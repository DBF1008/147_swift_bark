//
//  MessageImportServiceTests.swift
//  BarkTests
//
//  Created on 2026/6/12.
//

@testable import Bark
import Foundation
import RealmSwift
import SwiftyJSON
import Testing

struct MessageImportServiceTests {

    // MARK: - Helpers

    /// 配置内存 Realm 供测试使用
    private func setupInMemoryRealm() throws -> Realm {
        let config = Realm.Configuration(inMemoryIdentifier: "test-\(UUID().uuidString)")
        Realm.Configuration.defaultConfiguration = config
        return try Realm(configuration: config)
    }

    /// 构造一条消息的 JSON 字典
    private func makeMessageJSON(
        id: String = UUID().uuidString,
        title: String = "Test",
        createDate: Int64 = Int64(Date().timeIntervalSince1970),
        expireDate: Int64? = nil
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "title": title,
            "createDate": createDate
        ]
        if let expireDate {
            dict["expireDate"] = expireDate
        }
        return dict
    }

    /// 将消息字典数组编码为 JSON Data
    private func makeImportData(_ messages: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: messages)
    }

    // MARK: - Tests

    @Test("有效的未过期消息被正确导入")
    func importsValidMessages() throws {
        let realm = try setupInMemoryRealm()
        let futureDate = Int64(Date().addingTimeInterval(3600).timeIntervalSince1970)
        let data = makeImportData([
            makeMessageJSON(id: "msg-1", expireDate: futureDate),
            makeMessageJSON(id: "msg-2") // 无过期时间
        ])

        let result = MessageImportService.importMessages(from: data)

        #expect(result != nil)
        #expect(result?.importedCount == 2)
        #expect(result?.skippedExpiredCount == 0)
        #expect(realm.objects(Message.self).count == 2)
    }

    @Test("导入数据中的已过期消息被跳过")
    func skipsExpiredMessages() throws {
        let realm = try setupInMemoryRealm()
        let pastDate = Int64(Date().addingTimeInterval(-3600).timeIntervalSince1970)
        let futureDate = Int64(Date().addingTimeInterval(3600).timeIntervalSince1970)
        let data = makeImportData([
            makeMessageJSON(id: "valid", expireDate: futureDate),
            makeMessageJSON(id: "expired", expireDate: pastDate)
        ])

        let result = MessageImportService.importMessages(from: data)

        #expect(result?.importedCount == 1)
        #expect(result?.skippedExpiredCount == 1)
        #expect(realm.objects(Message.self).count == 1)
        #expect(realm.objects(Message.self).first?.id == "valid")
    }

    @Test("导入时 Realm 中已有的过期消息被清理")
    func deletesExistingExpiredMessages() throws {
        let realm = try setupInMemoryRealm()
        let pastDate = Date().addingTimeInterval(-3600)

        // 预置一条过期消息
        let expiredMsg = Message()
        expiredMsg.id = "old-expired"
        expiredMsg.createDate = Date()
        expiredMsg.expireDate = pastDate
        try realm.write { realm.add(expiredMsg) }
        #expect(realm.objects(Message.self).count == 1)

        // 导入一条有效消息
        let futureDate = Int64(Date().addingTimeInterval(3600).timeIntervalSince1970)
        let data = makeImportData([makeMessageJSON(id: "new-valid", expireDate: futureDate)])

        let result = MessageImportService.importMessages(from: data)

        #expect(result?.deletedExpiredCount == 1)
        #expect(result?.importedCount == 1)
        #expect(realm.objects(Message.self).count == 1)
        #expect(realm.objects(Message.self).first?.id == "new-valid")
    }

    @Test("已有消息被完全覆盖（update:.all 而非 .modified）")
    func overwritesExistingMessages() throws {
        let realm = try setupInMemoryRealm()

        // 预置一条消息
        let existing = Message()
        existing.id = "msg-1"
        existing.title = "Old Title"
        existing.body = "Old Body"
        existing.createDate = Date()
        try realm.write { realm.add(existing) }

        // 用相同 ID 但不同数据导入
        let data = makeImportData([
            makeMessageJSON(id: "msg-1", title: "New Title")
        ])

        _ = MessageImportService.importMessages(from: data)

        let updated = realm.objects(Message.self).first { $0.id == "msg-1" }
        #expect(updated?.title == "New Title")
        // update:.all 会将 body 覆盖为 nil，而非保留旧值
        #expect(updated?.body == nil)
    }

    @Test("无效 JSON 返回 nil")
    func rejectsInvalidJSON() throws {
        _ = try setupInMemoryRealm()
        let badData = "not json".data(using: .utf8)!

        let result = MessageImportService.importMessages(from: badData)

        #expect(result == nil)
    }

    @Test("空数组正常导入零条消息")
    func handlesEmptyArray() throws {
        let realm = try setupInMemoryRealm()
        let data = makeImportData([])

        let result = MessageImportService.importMessages(from: data)

        #expect(result != nil)
        #expect(result?.importedCount == 0)
        #expect(realm.objects(Message.self).count == 0)
    }

    @Test("导入成功后发送 kBarkMessagesDidChangeNotification 通知")
    func postsNotificationOnImport() throws {
        _ = try setupInMemoryRealm()
        let futureDate = Int64(Date().addingTimeInterval(3600).timeIntervalSince1970)
        let data = makeImportData([makeMessageJSON(expireDate: futureDate)])

        var notificationReceived = false
        let token = NotificationCenter.default.addObserver(
            forName: kBarkMessagesDidChangeNotification,
            object: nil,
            queue: nil
        ) { _ in
            notificationReceived = true
        }
        defer { NotificationCenter.default.removeObserver(token) }

        _ = MessageImportService.importMessages(from: data)

        // 通知通过 DispatchQueue.main.async 异步发送，需要运行主 RunLoop 处理
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        #expect(notificationReceived == true)
    }
}
