//
//  PendingMessageImporter.swift
//  Bark
//
//  Handles importing pending messages from the Notification Service Extension's
//  plist files into the Realm database, with fault-tolerant cleanup.
//

import Foundation
import RealmSwift

/// Imports pending messages written by the Notification Service Extension
/// into the Realm database.
///
/// Processing pipeline:
/// 1. Enumerate .plist files in the pending directory
/// 2. Classify each file: valid, expired, or unparsable (corrupt)
/// 3. Batch-write valid messages; fall back to per-file writes on failure
/// 4. Delete only files that were successfully imported, expired, or past the corrupt grace period
/// 5. Purge already-stored expired messages from Realm
final class PendingMessageImporter {

    /// Outcome of a single import run.
    struct Result {
        var importedCount: Int = 0
        var expiredCount: Int = 0
        var corruptCleanedCount: Int = 0
        var retryableCount: Int = 0
        /// Whether expired messages were actually purged from Realm
        /// (as opposed to just having expired plist files on disk).
        var expiredPurgedFromRealm: Bool = false

        /// Whether Realm contents actually changed (messages added or purged).
        var didChange: Bool {
            importedCount > 0 || expiredPurgedFromRealm
        }
    }

    // MARK: - Dependencies

    private let realm: Realm?
    private let pendingDir: URL
    private let fileManager: FileManager
    private let now: Date
    private let corruptGracePeriod: TimeInterval

    /// Creates an importer.
    ///
    /// - Parameters:
    ///   - realm: An opened Realm instance, or `nil` if Realm is unavailable.
    ///            When `nil`, all plist files are preserved for the next attempt.
    ///   - pendingDir: The directory containing pending `.plist` files.
    ///   - fileManager: File manager to use (default: `.default`).
    ///   - now: The reference "current time" (default: `Date()`).
    ///   - corruptGracePeriod: How long an unparsable file must exist before it is
    ///     considered permanently corrupt and eligible for deletion (default: 7 days).
    init(
        realm: Realm?,
        pendingDir: URL,
        fileManager: FileManager = .default,
        now: Date = Date(),
        corruptGracePeriod: TimeInterval = 7 * 24 * 3600
    ) {
        self.realm = realm
        self.pendingDir = pendingDir
        self.fileManager = fileManager
        self.now = now
        self.corruptGracePeriod = corruptGracePeriod
    }

    // MARK: - Classification

    /// How a single plist file was classified during the parse phase.
    private enum ClassifiedFile {
        /// File was readable and the message has not expired.
        case valid(URL, Message)
        /// File was readable but the message has already expired.
        case expired(URL)
        /// File could not be parsed. `isCorrupt` is true when the file has
        /// existed longer than the grace period.
        case unparsable(URL, isCorrupt: Bool)
    }

    // MARK: - Public API

    /// Process all pending messages in the configured directory.
    @discardableResult
    func process() -> Result {
        // Step 1: Enumerate plist files
        let plistFiles = enumeratePlistFiles()
        guard !plistFiles.isEmpty else { return Result() }

        // Step 2: Classify each file
        let classified = classifyFiles(plistFiles)

        // Step 3: Separate into categories
        var validEntries: [(url: URL, message: Message)] = []
        var expiredFiles: [URL] = []
        var corruptExpiredFiles: [URL] = []
        var retryableCount = 0

        for entry in classified {
            switch entry {
            case .valid(let url, let message):
                validEntries.append((url, message))
            case .expired(let url):
                expiredFiles.append(url)
            case .unparsable(let url, let isCorrupt):
                if isCorrupt {
                    corruptExpiredFiles.append(url)
                } else {
                    retryableCount += 1
                }
            }
        }

        // Step 4: Write valid messages to Realm and track which files succeeded
        var importedURLs = Set<String>()
        if !validEntries.isEmpty, let realm = realm {
            importedURLs = writeMessagesToRealm(realm, entries: validEntries)
        }

        // Step 5: Purge expired messages already in Realm
        var expiredPurged = false
        if let realm = realm {
            expiredPurged = purgeExpiredMessages(in: realm)
        }

        // Step 6: Delete only the files that are safe to remove
        var filesToDelete: [URL] = []

        // Delete files that were successfully imported
        for entry in validEntries {
            if importedURLs.contains(entry.url.path) {
                filesToDelete.append(entry.url)
            }
        }

        // Delete expired message files (they'll never be valid)
        filesToDelete.append(contentsOf: expiredFiles)

        // Delete corrupt files past the grace period
        filesToDelete.append(contentsOf: corruptExpiredFiles)

        for url in filesToDelete {
            try? fileManager.removeItem(at: url)
        }

        return Result(
            importedCount: importedURLs.count,
            expiredCount: expiredFiles.count,
            corruptCleanedCount: corruptExpiredFiles.count,
            retryableCount: retryableCount,
            expiredPurgedFromRealm: expiredPurged
        )
    }

    // MARK: - Private Helpers

    /// Enumerate all `.plist` files in the pending directory.
    private func enumeratePlistFiles() -> [URL] {
        guard fileManager.fileExists(atPath: pendingDir.path),
              let fileUrls = try? fileManager.contentsOfDirectory(
                  at: pendingDir,
                  includingPropertiesForKeys: [.contentModificationDateKey],
                  options: [.skipsHiddenFiles]
              )
        else { return [] }
        return fileUrls.filter { $0.pathExtension == "plist" }
    }

    /// Classify each plist file as valid, expired, or unparsable.
    private func classifyFiles(_ files: [URL]) -> [ClassifiedFile] {
        files.map { url -> ClassifiedFile in
            guard let dict = NSDictionary(contentsOf: url) as? [String: Any] else {
                let isCorrupt = isBeyondGracePeriod(url: url)
                return .unparsable(url, isCorrupt: isCorrupt)
            }
            let message = Message(dict: dict)
            if let expireDate = message.expireDate, expireDate <= now {
                return .expired(url)
            }
            return .valid(url, message)
        }
    }

    /// Write messages to Realm. Returns the set of file paths that were successfully imported.
    ///
    /// Tries a single batch transaction first. If that fails, falls back to
    /// per-message individual transactions so that one problematic message
    /// doesn't prevent the rest from being imported.
    private func writeMessagesToRealm(
        _ realm: Realm,
        entries: [(url: URL, message: Message)]
    ) -> Set<String> {
        // Attempt batch write
        do {
            try realm.write {
                for (_, message) in entries {
                    realm.add(message, update: .all)
                }
            }
            return Set(entries.map { $0.url.path })
        } catch {
            // Batch failed — fall back to per-message writes
            var succeeded = Set<String>()
            for entry in entries {
                do {
                    try realm.write {
                        realm.add(entry.message, update: .all)
                    }
                    succeeded.insert(entry.url.path)
                } catch {
                    // Individual message write failed; file will be preserved for retry
                }
            }
            return succeeded
        }
    }

    /// Delete messages from Realm whose expireDate has passed.
    /// Returns `true` if any messages were actually deleted.
    @discardableResult
    private func purgeExpiredMessages(in realm: Realm) -> Bool {
        let expiredMessages = realm.objects(Message.self)
            .filter("expireDate != nil AND expireDate <= %@", now)
        guard !expiredMessages.isEmpty else { return false }
        do {
            try realm.write {
                realm.delete(expiredMessages)
            }
            return true
        } catch {
            return false
        }
    }

    /// Check whether a file has existed longer than the corrupt grace period.
    private func isBeyondGracePeriod(url: URL) -> Bool {
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let modDate = attrs[.modificationDate] as? Date else {
            // Can't stat the file — treat as beyond grace period (safe to delete)
            return true
        }
        return now.timeIntervalSince(modDate) > corruptGracePeriod
    }
}
