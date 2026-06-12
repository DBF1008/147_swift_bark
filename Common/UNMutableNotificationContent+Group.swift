//
//  UNMutableNotificationContent+Group.swift
//  Bark
//

import UserNotifications

extension UNMutableNotificationContent {
    /// 把推送中的 group 字段同步为系统线程标识 (threadIdentifier)。
    ///
    /// iOS 用 threadIdentifier 做通知分组；IconProcessor 的会话样式 (conversationIdentifier)、
    /// MuteProcessor 的静音查找、以及通知 UI 的静音都以 threadIdentifier 为准。
    /// 明文与密文推送统一调用此方法，从 userInfo["group"] 同步线程标识，
    /// 保证通知分组、头像会话样式、静音规则都按同一个组生效。
    ///
    /// 仅当 group 存在且非空时才覆盖，避免用空串清掉系统 (aps.thread-id) 已填充的线程标识。
    func syncThreadIdentifierWithGroup() {
        if let group = userInfo["group"] as? String, !group.isEmpty {
            threadIdentifier = group
        }
    }
}
