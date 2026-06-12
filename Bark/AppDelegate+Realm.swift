//
//  AppDelegate+Realm.swift
//  Bark
//
//  Created by huangfeng on 12/18/25.
//  Copyright © 2025 Fin. All rights reserved.
//

import UIKit

private let pendingMessageProcessingQueue = DispatchQueue(label: "me.fin.bark.pending-message-processing", qos: .userInitiated)
let kBarkMessagesDidChangeNotification = Notification.Name("com.bark.messagesDidChange")

extension AppDelegate {
    /*
     之前数据库是放在App Groups 共享
     但由于Realm无法解决 0xdead10cc 闪退问题
     因此改为在主APP中存放数据库文件
     Notification Service Extension 使用 plist 文件保存消息，供主APP读取存放到数据库中
     */
    func setupRealm() {
        // 先执行数据库迁移
        migrateRealmDatabase()
        
        // Tell Realm to use this new configuration object for the default Realm
        Realm.Configuration.defaultConfiguration = kRealmDefaultConfiguration
    }

    func migrateRealmDatabase() {
        // 检查是否已经迁移过
        if UserDefaults.standard.bool(forKey: "hasRealmMigrated") {
            return
        }
        
        let fileManager = FileManager.default
        guard let oldGroupUrl = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.bark"),
              let newDocUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        else {
            return
        }
        
        let oldRealmUrl = oldGroupUrl.appendingPathComponent("bark.realm")
        let newRealmUrl = newDocUrl.appendingPathComponent("bark.realm")
        
        // 检查旧文件是否存在
        guard fileManager.fileExists(atPath: oldRealmUrl.path) else {
            // 旧文件不存在，标记为已迁移
            UserDefaults.standard.set(true, forKey: "hasRealmMigrated")
            return
        }
        
        do {
            // 复制主数据库文件
            try fileManager.copyItem(at: oldRealmUrl, to: newRealmUrl)
            
            // 复制相关文件
            let relatedFiles = ["bark.realm.lock", "bark.realm.management", "bark.realm.note"]
            for file in relatedFiles {
                let oldUrl = oldGroupUrl.appendingPathComponent(file)
                let newUrl = newDocUrl.appendingPathComponent(file)
                if fileManager.fileExists(atPath: oldUrl.path) {
                    try? fileManager.copyItem(at: oldUrl, to: newUrl)
                }
            }
            
            // 删除旧文件
            try fileManager.removeItem(at: oldRealmUrl)
            for file in relatedFiles {
                let oldUrl = oldGroupUrl.appendingPathComponent(file)
                try? fileManager.removeItem(at: oldUrl)
            }
            
            // 标记为已迁移
            UserDefaults.standard.set(true, forKey: "hasRealmMigrated")
        } catch {
            // 迁移失败，弹出提示
            DispatchQueue.main.async {
                let alert = UIAlertController(
                    title: "Migration Failed",
                    message: "Failed to migrate database file. Please contact support.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.window?.rootViewController?.present(alert, animated: true)
            }
        }
    }
    
    // 处理 Notification Service Extension 保存的待处理消息, 将其存入 Realm 数据库
    //
    // 容错约定（详见 PendingMessageImporter）：
    // - 只有成功入库后才删除对应文件；数据库短暂异常时保留文件，等待下次重试
    // - 无法解析的坏文件、已过期的消息按可预期方式清理（删除），且不拖累正常消息的清理节奏
    func processPendingMessages() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pendingMessageProcessingQueue.async {
                defer { continuation.resume() }

                guard let groupUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.bark") else {
                    return
                }

                // Realm 不可用时直接返回，不删除任何文件，待下次重试
                guard let realm = try? Realm() else {
                    return
                }

                let now = Date()
                let pendingMessagesDir = groupUrl.appendingPathComponent("pending_messages")

                let result = PendingMessageImporter.importPendingMessages(in: pendingMessagesDir, now: now) { messages in
                    let expiredMessages = realm.objects(Message.self)
                        .filter("expireDate != nil AND expireDate <= %@", now)
                    guard !messages.isEmpty || !expiredMessages.isEmpty else {
                        return false
                    }
                    try realm.write {
                        for message in messages {
                            realm.add(message, update: .all)
                        }
                        if !expiredMessages.isEmpty {
                            realm.delete(expiredMessages)
                        }
                    }
                    return true
                }

                if result.importedCount > 0 || result.didChangeStore {
                    WidgetHistorySnapshotStore.shared.refreshFromRealmAsync()
                    self.notifyMessagesDidChange()
                }
            }
        }
    }
    
    func notifyMessagesDidChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: kBarkMessagesDidChangeNotification, object: nil)
        }
    }
}

/// 把 Notification Service Extension 写入待处理目录(pending_messages)的 plist 消息导入存储。
///
/// 容错策略：每个文件根据自身状态获得**确定且独立**的结局，彼此互不拖累：
/// - 无法解析的坏文件：总是删除（不可重试，留着只会一直失败并拖慢清理节奏）
/// - 解析成功但已过期的消息：不入库，删除文件
/// - 解析成功且未过期的消息：入库**成功才删除**文件；入库失败则**保留**文件等待下次重试
///
/// 通过注入 `archive` 闭包隔离存储依赖，使核心逻辑无需真实数据库即可进行单元测试。
enum PendingMessageImporter {
    struct Result: Equatable {
        /// 成功入库的有效消息数量
        var importedCount = 0
        /// 删除的坏文件数量
        var deletedCorruptCount = 0
        /// 删除的已过期文件数量
        var deletedExpiredCount = 0
        /// 入库失败、保留等待重试的文件数量
        var retainedCount = 0
        /// archive 报告存储发生了变更（例如清理了存储内已过期消息）
        var didChangeStore = false
    }

    /// 把待处理目录中的消息导入存储。
    /// - Parameters:
    ///   - directory: 待处理消息目录（pending_messages）
    ///   - now: 当前时间，用于判定消息是否过期（注入以便测试）
    ///   - fileManager: 文件管理器（注入以便测试）
    ///   - archive: 把有效消息写入存储、并清理存储内已过期消息。
    ///     返回 `true` 表示存储发生变更；**抛出异常表示写入失败**，此时有效消息文件会被保留以便重试。
    /// - Returns: 各类文件处理数量的统计结果。
    @discardableResult
    static func importPendingMessages(
        in directory: URL,
        now: Date,
        fileManager: FileManager = .default,
        archive: (_ messages: [Message]) throws -> Bool
    ) -> Result {
        var result = Result()

        guard fileManager.fileExists(atPath: directory.path),
              let fileUrls = try? fileManager.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: nil,
                  options: [.skipsHiddenFiles]
              )
        else {
            return result
        }

        let plistFiles = fileUrls.filter { $0.pathExtension == "plist" }

        // 分类：坏文件 / 已过期 / 有效（有效消息与其文件一一对应）
        var corruptFiles: [URL] = []
        var expiredFiles: [URL] = []
        var validMessages: [Message] = []
        var validFiles: [URL] = []

        for plistUrl in plistFiles {
            guard let dict = NSDictionary(contentsOf: plistUrl) as? [String: Any] else {
                corruptFiles.append(plistUrl)
                continue
            }
            let message = Message(dict: dict)
            if let expireDate = message.expireDate, expireDate <= now {
                expiredFiles.append(plistUrl)
                continue
            }
            validMessages.append(message)
            validFiles.append(plistUrl)
        }

        // 坏文件、过期文件：按可预期方式清理，与入库成败无关，不拖累正常消息的清理节奏
        for url in corruptFiles {
            if (try? fileManager.removeItem(at: url)) != nil {
                result.deletedCorruptCount += 1
            }
        }
        for url in expiredFiles {
            if (try? fileManager.removeItem(at: url)) != nil {
                result.deletedExpiredCount += 1
            }
        }

        // 有效消息：入库成功才删除对应文件；失败则全部保留等待下次重试
        if validMessages.isEmpty {
            // 没有新消息，但仍尝试让 archive 清理存储内已过期消息；失败也无文件受影响
            if let changed = try? archive([]) {
                result.didChangeStore = changed
            }
        } else {
            do {
                let changed = try archive(validMessages)
                result.importedCount = validMessages.count
                result.didChangeStore = changed
                for url in validFiles {
                    try? fileManager.removeItem(at: url)
                }
            } catch {
                // 入库失败（如数据库短暂异常），保留有效文件等待下次重试
                result.retainedCount = validFiles.count
            }
        }

        return result
    }
}
