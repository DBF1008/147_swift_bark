//
//  MarkdownProcessor.swift
//  NotificationServiceExtension
//
//  Created by huangfeng on 11/21/25.
//  Copyright © 2025 Fin. All rights reserved.
//

import UIKit

class MarkdownProcessor: NotificationContentProcessor {
    func process(identifier: String, content bestAttemptContent: UNMutableNotificationContent) async throws -> UNMutableNotificationContent {
        let userInfo = bestAttemptContent.userInfo
        guard let markdown = userInfo["markdown"] as? String, !markdown.isEmpty else {
            return bestAttemptContent
        }
        // 统一走 MarkdownParser 的单一归一化入口，保证横幅与归档 / 小组件链路得到一致的可读文本。
        let body = MarkdownParser.displayPlainText(fromMarkdown: markdown)
        bestAttemptContent.body = body
        
        /// 更新 APS 字段, 供之后的 Porgressor 使用
        var aps = userInfo["aps"] as? [String: Any] ?? [:]
        var alert = aps["alert"] as? [String: Any] ?? [:]
        alert["body"] = body
        aps["alert"] = alert
        bestAttemptContent.userInfo["aps"] = aps

        return bestAttemptContent
    }
}
