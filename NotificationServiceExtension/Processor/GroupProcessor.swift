//
//  GroupProcessor.swift
//  NotificationServiceExtension
//

import Foundation

/// 统一线程标识 (threadIdentifier)：将 group 同步到 threadIdentifier，
/// 供后续的通知分组、头像会话样式 (IconProcessor)、静音规则 (MuteProcessor) 按同一个组生效。
///
/// 需放在 CiphertextProcessor 之后（密文解密后 group 已写入 userInfo），
/// 且在 archive / mute / setIcon 之前。明文推送的顶层 group 与密文解密后的 group
/// 都经过这里，从而得到一致的线程标识。
class GroupProcessor: NotificationContentProcessor {
    func process(identifier: String, content bestAttemptContent: UNMutableNotificationContent) async throws -> UNMutableNotificationContent {
        bestAttemptContent.syncThreadIdentifierWithGroup()
        return bestAttemptContent
    }
}
