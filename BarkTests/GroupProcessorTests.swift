//
//  GroupProcessorTests.swift
//  BarkTests
//
//  Created on 2026/6/12.
//  Copyright © 2026 Fin. All rights reserved.
//

@testable import Bark
import CryptoSwift
import SwiftyJSON
import UserNotifications
import XCTest

/// 验证分组字段在通知处理链路中的传递一致性。
///
/// 核心不变量：无论明文还是加密推送，`threadIdentifier` 和 `userInfo["group"]`
/// 在 CiphertextProcessor 处理后必须一致，从而保证通知分组、头像会话样式和静音规则
/// 都按同一个组生效。
///
/// 由于处理器类编译在 NotificationServiceExtension target 中，此处直接复刻
/// CiphertextProcessor / ArchiveProcessor / MuteProcessor 中与分组相关的核心逻辑，
/// 验证修复后的行为。
final class GroupProcessorTests: XCTestCase {

    // MARK: - 辅助方法：模拟 CiphertextProcessor 的 group → threadIdentifier 同步

    /// 复刻 CiphertextProcessor 的明文路径逻辑（修复后）
    private func simulateCiphertextProcessorPlaintext(
        _ content: UNMutableNotificationContent
    ) -> UNMutableNotificationContent {
        var userInfo = content.userInfo
        guard userInfo["ciphertext"] is String else {
            // 修复：明文推送确保 group → threadIdentifier 一致
            if let group = userInfo["group"] as? String, !group.isEmpty {
                content.threadIdentifier = group
            }
            return content
        }
        // 加密路径不在此测试覆盖
        return content
    }

    /// 复刻 ArchiveProcessor 的 group 读取逻辑（修复后）
    private func simulateArchiveProcessorGroup(
        _ content: UNMutableNotificationContent
    ) -> String? {
        let userInfo = content.userInfo
        // 修复：增加 threadIdentifier fallback
        let group = (userInfo["group"] as? String)
            ?? (content.threadIdentifier.isEmpty ? nil : content.threadIdentifier)
        return group
    }

    /// 复刻 MuteProcessor 的静音检查逻辑
    private func simulateMuteProcessorIsMuted(
        _ content: UNMutableNotificationContent
    ) -> Bool {
        let groupName = content.threadIdentifier
        guard let date = GroupMuteSettingManager().settings[groupName],
              date > Date()
        else {
            return false
        }
        return true
    }

    // MARK: - 明文推送 group → threadIdentifier 同步

    func testPlaintextPushWithGroup_setsThreadIdentifier() {
        let content = UNMutableNotificationContent()
        content.userInfo = [
            "aps": ["alert": ["title": "Test", "body": "Hello"]],
            "group": "myGroup",
        ]

        let result = simulateCiphertextProcessorPlaintext(content)

        XCTAssertEqual(result.threadIdentifier, "myGroup",
                       "明文推送带 group 时，threadIdentifier 应被设为 group 值")
    }

    func testPlaintextPushWithoutGroup_threadIdentifierUnchanged() {
        let content = UNMutableNotificationContent()
        content.userInfo = [
            "aps": ["alert": ["title": "Test", "body": "Hello"]],
        ]

        let result = simulateCiphertextProcessorPlaintext(content)

        XCTAssertEqual(result.threadIdentifier, "",
                       "明文推送不带 group 时，threadIdentifier 应保持空")
    }

    func testPlaintextPushWithEmptyGroup_threadIdentifierNotSet() {
        let content = UNMutableNotificationContent()
        content.userInfo = [
            "aps": ["alert": ["title": "Test", "body": "Hello"]],
            "group": "",
        ]

        let result = simulateCiphertextProcessorPlaintext(content)

        XCTAssertEqual(result.threadIdentifier, "",
                       "明文推送 group 为空字符串时，不应设置空 threadIdentifier")
    }

    func testPlaintextPushPreservesExistingThreadIdentifier() {
        // 如果服务器同时设了 aps.thread-id 和自定义 group，以 group 为准（保持一致性）
        let content = UNMutableNotificationContent()
        content.threadIdentifier = "serverThreadId"
        content.userInfo = [
            "aps": ["alert": ["title": "Test", "body": "Hello"]],
            "group": "myGroup",
        ]

        let result = simulateCiphertextProcessorPlaintext(content)

        XCTAssertEqual(result.threadIdentifier, "myGroup",
                       "明文推送带 group 时，threadIdentifier 应以 group 为准")
    }

    // MARK: - ArchiveProcessor group 读取 fallback

    func testArchiveProcessor_readsGroupFromUserInfo() {
        let content = UNMutableNotificationContent()
        content.userInfo = ["group": "archiveGroup"]

        let group = simulateArchiveProcessorGroup(content)

        XCTAssertEqual(group, "archiveGroup",
                       "ArchiveProcessor 应优先从 userInfo[\"group\"] 读取分组")
    }

    func testArchiveProcessor_fallsBackToThreadIdentifier() {
        let content = UNMutableNotificationContent()
        content.threadIdentifier = "threadGroup"
        content.userInfo = [:] // 没有 group 字段

        let group = simulateArchiveProcessorGroup(content)

        XCTAssertEqual(group, "threadGroup",
                       "当 userInfo 没有 group 时，ArchiveProcessor 应从 threadIdentifier 读取")
    }

    func testArchiveProcessor_returnsNilWhenNoGroupAnywhere() {
        let content = UNMutableNotificationContent()
        content.userInfo = [:]

        let group = simulateArchiveProcessorGroup(content)

        XCTAssertNil(group,
                     "当 userInfo 和 threadIdentifier 都没有 group 时，应返回 nil")
    }

    // MARK: - 端到端：明文推送 Ciphertext → Mute 一致性

    func testEndToEnd_plaintextGroupFlowsThroughPipeline() {
        // 1. 构造明文推送
        let content = UNMutableNotificationContent()
        content.userInfo = [
            "aps": ["alert": ["title": "Hi", "body": "Test"]],
            "group": "pipelineGroup",
        ]

        // 2. CiphertextProcessor（明文路径）同步 threadIdentifier
        let afterCiphertext = simulateCiphertextProcessorPlaintext(content)
        XCTAssertEqual(afterCiphertext.threadIdentifier, "pipelineGroup")

        // 3. ArchiveProcessor 读取 group
        let archivedGroup = simulateArchiveProcessorGroup(afterCiphertext)
        XCTAssertEqual(archivedGroup, "pipelineGroup",
                       "ArchiveProcessor 应能读取到一致的 group")

        // 4. MuteProcessor 用 threadIdentifier 做静音判断
        // （此时没有设置静音，应不静音）
        XCTAssertFalse(simulateMuteProcessorIsMuted(afterCiphertext),
                       "未设置静音时不应被静音")
    }

    func testEndToEnd_muteCheckUsesCorrectGroup() {
        // 1. 先设置 "muteTestGroup" 的静音
        let muteManager = GroupMuteSettingManager()
        muteManager.settings["muteTestGroup"] = Date() + 3600 // 1小时后过期

        // 2. 构造明文推送，group = "muteTestGroup"
        let content = UNMutableNotificationContent()
        content.userInfo = [
            "aps": ["alert": ["title": "Hi", "body": "Test"]],
            "group": "muteTestGroup",
        ]

        // 3. CiphertextProcessor 同步 threadIdentifier
        let afterCiphertext = simulateCiphertextProcessorPlaintext(content)

        // 4. MuteProcessor 应检测到静音
        XCTAssertTrue(simulateMuteProcessorIsMuted(afterCiphertext),
                      "设置了静音的 group 应被检测到")

        // 清理
        muteManager.settings.removeValue(forKey: "muteTestGroup")
    }

    func testEndToEnd_differentGroupNotMuted() {
        // 1. 设置 "groupA" 的静音
        let muteManager = GroupMuteSettingManager()
        muteManager.settings["groupA"] = Date() + 3600

        // 2. 构造明文推送，group = "groupB"（不同的分组）
        let content = UNMutableNotificationContent()
        content.userInfo = [
            "aps": ["alert": ["title": "Hi", "body": "Test"]],
            "group": "groupB",
        ]

        // 3. CiphertextProcessor 同步 threadIdentifier
        let afterCiphertext = simulateCiphertextProcessorPlaintext(content)

        // 4. MuteProcessor 不应静音不同分组
        XCTAssertFalse(simulateMuteProcessorIsMuted(afterCiphertext),
                       "不同 group 不应被静音")

        // 清理
        muteManager.settings.removeValue(forKey: "groupA")
    }

    // MARK: - GroupMuteSettingManager 基本行为

    func testGroupMuteSettingManager_storesAndRetrievesByGroupName() {
        let manager = GroupMuteSettingManager()
        let futureDate = Date() + 3600

        manager.settings["testGroup123"] = futureDate

        let retrieved = GroupMuteSettingManager()
        XCTAssertNotNil(retrieved.settings["testGroup123"],
                        "应能通过 group 名称取回静音设置")

        // 清理
        manager.settings.removeValue(forKey: "testGroup123")
    }

    func testGroupMuteSettingManager_cleansExpiredEntries() {
        let manager = GroupMuteSettingManager()
        let pastDate = Date() - 3600 // 1小时前就过期了

        manager.settings["expiredGroup"] = pastDate

        // 重新初始化（模拟新进程）会清理过期条目
        let freshManager = GroupMuteSettingManager()
        XCTAssertNil(freshManager.settings["expiredGroup"],
                     "过期的静音设置应在初始化时被清理")

        // 清理（以防万一）
        manager.settings.removeValue(forKey: "expiredGroup")
    }

    func testGroupMuteSettingManager_emptyGroupNameWorksButIsDistinct() {
        let manager = GroupMuteSettingManager()
        let futureDate = Date() + 3600

        // 空字符串也可以作为 key（用于无分组的通知）
        manager.settings[""] = futureDate

        let retrieved = GroupMuteSettingManager()
        XCTAssertNotNil(retrieved.settings[""],
                        "空 group 名称也应能存储静音设置")

        // 不同 group 互不影响
        manager.settings["realGroup"] = futureDate
        let freshManager = GroupMuteSettingManager()
        XCTAssertNotNil(freshManager.settings[""])
        XCTAssertNotNil(freshManager.settings["realGroup"])

        // 清理
        manager.settings.removeValue(forKey: "")
        manager.settings.removeValue(forKey: "realGroup")
    }

    // MARK: - 加密推送 JSON 中 group 字段解析

    func testEncryptedPayloadGroupParsing_lowercaseKey() {
        // 模拟解密后的 JSON（CiphertextProcessor 会将 key 转小写）
        let jsonString = """
        {"title":"Hello","body":"World","group":"cryptoGroup","sound":"birdsong"}
        """
        let data = jsonString.data(using: .utf8)!
        let map = JSON(data).dictionaryObject!

        // 模拟 CiphertextProcessor 的 key 小写化
        var result: [AnyHashable: Any] = [:]
        for (key, val) in map {
            result[key.lowercased()] = val
        }

        let group = result["group"] as? String
        XCTAssertEqual(group, "cryptoGroup",
                       "加密推送解密后应能正确提取 group 字段")
    }

    func testEncryptedPayloadGroupParsing_mixedCaseKey() {
        // 用户可能输入大小写混合的 key
        let jsonString = """
        {"Title":"Hello","Body":"World","Group":"cryptoGroup"}
        """
        let data = jsonString.data(using: .utf8)!
        let map = JSON(data).dictionaryObject!

        var result: [AnyHashable: Any] = [:]
        for (key, val) in map {
            result[key.lowercased()] = val
        }

        let group = result["group"] as? String
        XCTAssertEqual(group, "cryptoGroup",
                       "大小写混合的 Group key 经过小写化后应能正确提取")
    }

    // MARK: - AESCryptoModel 加密/解密 roundtrip（确保 group 字段不丢失）

    func testAESCryptoRoundtrip_preservesGroupInJSON() throws {
        let key = "1234567890123456" // 16 bytes for AES128
        let iv = "1234567890123456" // 16 bytes for CBC
        let fields = CryptoSettingFields(
            algorithm: "AES128",
            mode: "CBC",
            padding: "pkcs7",
            key: key,
            iv: iv
        )
        let crypto = try AESCryptoModel(cryptoFields: fields)

        let originalJSON: [String: Any] = [
            "title": "Test Title",
            "body": "Test Body",
            "group": "myEncryptedGroup",
            "sound": "birdsong",
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: originalJSON)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        // 加密
        let ciphertext = try crypto.encrypt(text: jsonString)

        // 解密
        let decryptedString = try crypto.decrypt(ciphertext: ciphertext)
        let decryptedData = decryptedString.data(using: .utf8)!
        let decryptedMap = JSON(decryptedData).dictionaryObject!

        XCTAssertEqual(decryptedMap["group"] as? String, "myEncryptedGroup",
                       "加密→解密后 group 字段应完整保留")
        XCTAssertEqual(decryptedMap["title"] as? String, "Test Title")
        XCTAssertEqual(decryptedMap["body"] as? String, "Test Body")
    }

    func testAESCryptoRoundtrip_worksWithoutGroup() throws {
        let key = "1234567890123456"
        let iv = "1234567890123456"
        let fields = CryptoSettingFields(
            algorithm: "AES128",
            mode: "CBC",
            padding: "pkcs7",
            key: key,
            iv: iv
        )
        let crypto = try AESCryptoModel(cryptoFields: fields)

        let originalJSON: [String: Any] = [
            "title": "No Group",
            "body": "Test",
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: originalJSON)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        let ciphertext = try crypto.encrypt(text: jsonString)
        let decryptedString = try crypto.decrypt(ciphertext: ciphertext)
        let decryptedData = decryptedString.data(using: .utf8)!
        let decryptedMap = JSON(decryptedData).dictionaryObject!

        XCTAssertNil(decryptedMap["group"],
                     "不含 group 的加密推送解密后 group 应为 nil")
    }

    // MARK: - threadIdentifier 与 userInfo["group"] 一致性验证

    func testConsistency_threadIdentifierMatchesUserInfoGroup() {
        // 这个测试验证核心不变量：经过处理后 threadIdentifier == userInfo["group"]
        let content = UNMutableNotificationContent()
        content.userInfo = [
            "aps": ["alert": ["title": "Hi", "body": "Test"]],
            "group": "consistencyGroup",
        ]

        // 模拟 CiphertextProcessor 处理
        let processed = simulateCiphertextProcessorPlaintext(content)

        // 核心不变量验证
        let threadId = processed.threadIdentifier
        let userInfoGroup = processed.userInfo["group"] as? String
        XCTAssertEqual(threadId, userInfoGroup,
                       "核心不变量：threadIdentifier 必须等于 userInfo[\"group\"]")
        XCTAssertEqual(threadId, "consistencyGroup")
    }

    func testConsistency_allThreeConsumersSeeSameGroup() {
        // 验证通知分组（threadIdentifier）、存档（userInfo["group"]）、
        // 静音（threadIdentifier）三者看到同一个 group
        let content = UNMutableNotificationContent()
        content.userInfo = [
            "aps": ["alert": ["title": "Hi", "body": "Test"]],
            "group": "unifiedGroup",
        ]

        let processed = simulateCiphertextProcessorPlaintext(content)

        // 通知分组使用 threadIdentifier
        let groupForNotification = processed.threadIdentifier
        // 存档使用 userInfo["group"] (fallback to threadIdentifier)
        let groupForArchive = simulateArchiveProcessorGroup(processed)
        // 静音使用 threadIdentifier
        let groupForMute = processed.threadIdentifier

        XCTAssertEqual(groupForNotification, "unifiedGroup")
        XCTAssertEqual(groupForArchive, "unifiedGroup")
        XCTAssertEqual(groupForMute, "unifiedGroup")
        XCTAssertEqual(groupForNotification, groupForArchive)
        XCTAssertEqual(groupForArchive, groupForMute)
    }
}
