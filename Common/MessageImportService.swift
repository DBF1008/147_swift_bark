//
//  MessageImportService.swift
//  Bark
//
//  Created on 2026/6/12.
//

import Foundation
import RealmSwift
import SwiftyJSON

/// 历史消息导入服务
/// 负责将 JSON 数据导入 Realm，行为与 `AppDelegate.processPendingMessages()` 保持一致：
/// - 过滤已过期消息（expireDate <= now）
/// - 清理 Realm 中已有的过期消息
/// - 使用 `update: .all` 进行 upsert（完全覆盖）
/// - 刷新小组件快照
/// - 发送消息变更通知以刷新消息列表
enum MessageImportService {

    struct ImportResult {
        let importedCount: Int
        let skippedExpiredCount: Int
        let deletedExpiredCount: Int
    }

    /// 从 JSON 数据导入消息
    /// - Parameter jsonData: JSON 数组数据，每个元素为一条消息的字典
    /// - Returns: 导入结果，如果 JSON 解析失败或 Realm 不可用则返回 nil
    @discardableResult
    static func importMessages(from jsonData: Data) -> ImportResult? {
        guard let json = try? JSON(data: jsonData), let arr = json.array else {
            return nil
        }
        guard let realm = try? Realm() else {
            return nil
        }

        let now = Date()
        var messagesToAdd: [Message] = []
        var skippedExpired = 0

        for messageJSON in arr {
            guard let messageObject = Message(json: messageJSON) else {
                continue
            }
            // 过滤已过期消息，与 processPendingMessages 行为一致
            if let expireDate = messageObject.expireDate, expireDate <= now {
                skippedExpired += 1
                continue
            }
            messagesToAdd.append(messageObject)
        }

        // 查找 Realm 中已有的过期消息
        let expiredMessages = realm.objects(Message.self)
            .filter("expireDate != nil AND expireDate <= %@", now)

        var didChange = false
        do {
            try realm.write {
                if !messagesToAdd.isEmpty {
                    didChange = true
                    for message in messagesToAdd {
                        realm.add(message, update: .all)
                    }
                }
                if !expiredMessages.isEmpty {
                    didChange = true
                    realm.delete(expiredMessages)
                }
            }
        } catch {
            return nil
        }

        let result = ImportResult(
            importedCount: messagesToAdd.count,
            skippedExpiredCount: skippedExpired,
            deletedExpiredCount: expiredMessages.count
        )

        if didChange {
            // 刷新小组件快照（内部异步执行）
            WidgetHistorySnapshotStore.shared.refreshFromRealmAsync()

            // 通知消息列表刷新（必须在主线程投递）
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: kBarkMessagesDidChangeNotification,
                    object: nil
                )
            }
        }

        return result
    }
}
