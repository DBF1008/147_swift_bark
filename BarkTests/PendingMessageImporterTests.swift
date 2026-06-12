//
//  PendingMessageImporterTests.swift
//  BarkTests
//
//  Created by Claude on 6/12/26.
//  Copyright © 2026 Fin. All rights reserved.
//
//  回归测试：保证待处理消息导入的容错语义
//  - 只有成功入库后才删除对应文件
//  - 坏数据、已过期数据按可预期方式清理（删除）
//  - 可重试的数据（解析成功但入库失败）不会被提前吞掉
//  - 坏/过期文件不会拖累正常消息的清理节奏
//
//  注入 archive 闭包以隔离存储依赖，整套测试无需真实 Realm 数据库。

@testable import Bark
import Foundation
import Testing

struct PendingMessageImporterTests {
    private enum TestError: Error {
        case archiveFailed
        case writeFailed
    }

    // MARK: - 单类文件

    @Test("导入有效消息后删除文件，并把消息交给 archive")
    func importsValidMessageAndDeletesFile() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let now = Date()
        let url = try writeValidPlist(in: dir, id: "msg-1", body: "hello", expireDate: nil)

        var received: [Message] = []
        let result = PendingMessageImporter.importPendingMessages(in: dir, now: now) { messages in
            received = messages
            return true
        }

        #expect(result.importedCount == 1)
        #expect(result.retainedCount == 0)
        #expect(!FileManager.default.fileExists(atPath: url.path), "成功入库后文件应被删除")
        #expect(received.count == 1)
        #expect(received.first?.id == "msg-1")
        #expect(received.first?.body == "hello")
    }

    @Test("坏文件被删除且不进入 archive")
    func corruptFileIsDeletedAndNotArchived() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let url = try writeCorruptPlist(in: dir, name: "broken")

        var received: [Message] = []
        let result = PendingMessageImporter.importPendingMessages(in: dir, now: Date()) { messages in
            received = messages
            return false
        }

        #expect(result.deletedCorruptCount == 1)
        #expect(result.importedCount == 0)
        #expect(!FileManager.default.fileExists(atPath: url.path), "坏文件应被删除")
        #expect(received.isEmpty, "坏文件不应作为有效消息进入 archive")
    }

    @Test("已过期的消息不入库但删除文件")
    func expiredMessageIsDeletedNotArchived() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let now = Date()
        let url = try writeValidPlist(in: dir, id: "old", body: "x", expireDate: now.addingTimeInterval(-100))

        var received: [Message] = []
        let result = PendingMessageImporter.importPendingMessages(in: dir, now: now) { messages in
            received = messages
            return false
        }

        #expect(result.deletedExpiredCount == 1)
        #expect(result.importedCount == 0)
        #expect(!FileManager.default.fileExists(atPath: url.path), "过期文件应被删除")
        #expect(received.isEmpty, "过期消息不应入库")
    }

    // MARK: - 核心回归：可重试数据不被提前吞掉

    @Test("入库失败时可重试文件不被吞掉")
    func retryableFileIsKeptWhenArchiveFails() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let now = Date()
        let url = try writeValidPlist(in: dir, id: "retry", body: "keep me", expireDate: nil)

        let result = PendingMessageImporter.importPendingMessages(in: dir, now: now) { _ in
            throw TestError.archiveFailed
        }

        #expect(result.importedCount == 0)
        #expect(result.retainedCount == 1)
        #expect(FileManager.default.fileExists(atPath: url.path), "数据库异常时有效文件必须保留以便重试")
    }

    // MARK: - 混合批次：三类文件结局相互独立

    @Test("混合批次入库失败：坏/过期文件清理，有效文件保留")
    func mixedBatchKeepsValidWhenArchiveFails() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let now = Date()
        let validUrl = try writeValidPlist(in: dir, id: "v", body: "v", expireDate: nil)
        let expiredUrl = try writeValidPlist(in: dir, id: "e", body: "e", expireDate: now.addingTimeInterval(-10))
        let corruptUrl = try writeCorruptPlist(in: dir, name: "c")

        let result = PendingMessageImporter.importPendingMessages(in: dir, now: now) { _ in
            throw TestError.archiveFailed
        }

        #expect(result.deletedCorruptCount == 1)
        #expect(result.deletedExpiredCount == 1)
        #expect(result.retainedCount == 1)
        #expect(result.importedCount == 0)
        // 坏/过期清理不依赖入库成败，有效文件保留待重试 —— 三者结局相互独立
        #expect(FileManager.default.fileExists(atPath: validUrl.path), "有效文件应保留")
        #expect(!FileManager.default.fileExists(atPath: expiredUrl.path), "过期文件应删除")
        #expect(!FileManager.default.fileExists(atPath: corruptUrl.path), "坏文件应删除")
    }

    @Test("混合批次入库成功：全部文件清理，有效消息入库")
    func mixedBatchSucceeds() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let now = Date()
        let validUrl = try writeValidPlist(in: dir, id: "v", body: "v", expireDate: nil)
        let expiredUrl = try writeValidPlist(in: dir, id: "e", body: "e", expireDate: now.addingTimeInterval(-10))
        let corruptUrl = try writeCorruptPlist(in: dir, name: "c")

        var received: [Message] = []
        let result = PendingMessageImporter.importPendingMessages(in: dir, now: now) { messages in
            received = messages
            return true
        }

        #expect(result.importedCount == 1)
        #expect(result.deletedCorruptCount == 1)
        #expect(result.deletedExpiredCount == 1)
        #expect(result.retainedCount == 0)
        #expect(received.count == 1)
        #expect(received.first?.id == "v")
        #expect(!FileManager.default.fileExists(atPath: validUrl.path))
        #expect(!FileManager.default.fileExists(atPath: expiredUrl.path))
        #expect(!FileManager.default.fileExists(atPath: corruptUrl.path))
    }

    // MARK: - 边界

    @Test("目录不存在时安全返回空结果且不调用 archive")
    func nonexistentDirectoryReturnsEmpty() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString)")
        var archiveCalled = false
        let result = PendingMessageImporter.importPendingMessages(in: dir, now: Date()) { _ in
            archiveCalled = true
            return true
        }

        #expect(result == PendingMessageImporter.Result())
        #expect(archiveCalled == false)
    }

    @Test("空目录返回空结果")
    func emptyDirectoryReturnsEmpty() {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let result = PendingMessageImporter.importPendingMessages(in: dir, now: Date()) { _ in true }

        #expect(result.importedCount == 0)
        #expect(result.deletedCorruptCount == 0)
        #expect(result.deletedExpiredCount == 0)
        #expect(result.retainedCount == 0)
    }

    // MARK: - Helpers

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-import-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    /// 写入一个合法的消息 plist（字段与 ArchiveProcessor 写入端一致）。
    @discardableResult
    private func writeValidPlist(in dir: URL, id: String, body: String, expireDate: Date?) throws -> URL {
        var dict: [String: Any] = [
            "id": id,
            "body": body,
            "createDate": Date().timeIntervalSince1970,
        ]
        if let expireDate {
            dict["expireDate"] = expireDate.timeIntervalSince1970
        }
        let url = dir.appendingPathComponent("\(id).plist")
        guard NSDictionary(dictionary: dict).write(to: url, atomically: true) else {
            throw TestError.writeFailed
        }
        return url
    }

    /// 写入一个扩展名为 .plist 但内容损坏的文件，使 NSDictionary(contentsOf:) 返回 nil。
    @discardableResult
    private func writeCorruptPlist(in dir: URL, name: String) throws -> URL {
        let url = dir.appendingPathComponent("\(name).plist")
        try Data("this is not a valid plist".utf8).write(to: url)
        return url
    }
}
