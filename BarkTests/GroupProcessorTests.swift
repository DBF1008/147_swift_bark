//
//  GroupProcessorTests.swift
//  BarkTests
//

import Testing
import UserNotifications

/// 验证 group 字段统一同步为 threadIdentifier 的逻辑。
///
/// 被测核心逻辑是 `UNMutableNotificationContent.syncThreadIdentifierWithGroup()`，
/// 它是 GroupProcessor 的唯一职责，明文与密文推送共用这一处逻辑，
/// 从而让通知分组、头像会话样式、静音规则都按同一个组生效。
struct GroupProcessorTests {
    @Test("明文带 group：group 同步为 threadIdentifier")
    func plaintextGroupSetsThreadIdentifier() {
        let content = UNMutableNotificationContent()
        content.userInfo = ["group": "groupA", "aps": ["alert": ["body": "hi"]]]

        content.syncThreadIdentifierWithGroup()

        #expect(content.threadIdentifier == "groupA")
    }

    @Test("无 group：保持既有 threadIdentifier 不变")
    func missingGroupKeepsThreadIdentifier() {
        let content = UNMutableNotificationContent()
        content.threadIdentifier = "existing"
        content.userInfo = ["aps": ["alert": ["body": "hi"]]]

        content.syncThreadIdentifierWithGroup()

        #expect(content.threadIdentifier == "existing")
    }

    @Test("空 group：不覆盖既有 threadIdentifier")
    func emptyGroupDoesNotOverride() {
        let content = UNMutableNotificationContent()
        content.threadIdentifier = "existing"
        content.userInfo = ["group": ""]

        content.syncThreadIdentifierWithGroup()

        #expect(content.threadIdentifier == "existing")
    }

    @Test("group 与服务端 thread-id 不一致：以 group 为准，统一线程标识")
    func groupOverridesServerThreadIdentifier() {
        let content = UNMutableNotificationContent()
        // 模拟系统从 aps.thread-id 预填充了一个不同的值
        content.threadIdentifier = "server-thread"
        content.userInfo = ["group": "groupA"]

        content.syncThreadIdentifierWithGroup()

        #expect(content.threadIdentifier == "groupA")
    }

    @Test("密文解密后状态：group 在 userInfo 中，同样得到一致 threadIdentifier")
    func decryptedCiphertextGroupIsApplied() {
        // 模拟 CiphertextProcessor 解密后 userInfo = map（含小写 group 与重建的 aps）
        let content = UNMutableNotificationContent()
        content.userInfo = [
            "group": "secret-group",
            "aps": ["alert": ["body": "decrypted"]]
        ]

        content.syncThreadIdentifierWithGroup()

        #expect(content.threadIdentifier == "secret-group")
    }

    @Test("明文与密文得到相同 threadIdentifier：同一逻辑，结果一致")
    func plaintextAndCiphertextProduceSameThreadIdentifier() {
        let plaintext = UNMutableNotificationContent()
        plaintext.userInfo = ["group": "team", "aps": ["alert": ["body": "from query"]]]
        plaintext.syncThreadIdentifierWithGroup()

        let ciphertext = UNMutableNotificationContent()
        ciphertext.userInfo = ["group": "team", "aps": ["alert": ["body": "from ciphertext"]]]
        ciphertext.syncThreadIdentifierWithGroup()

        #expect(plaintext.threadIdentifier == ciphertext.threadIdentifier)
        #expect(plaintext.threadIdentifier == "team")
    }
}
