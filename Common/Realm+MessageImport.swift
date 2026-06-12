//
//  Realm+MessageImport.swift
//  Bark
//
//  导入历史消息时的写库核心逻辑（过期过滤 + 覆盖 + 清理库内过期）。
//  与 AppDelegate.processPendingMessages() 的处理口径保持一致。
//

import Foundation
import RealmSwift

extension Realm {
    /// 导入历史消息：过滤掉已过期的、按主键覆盖已有记录、并清理库内既有的过期记录。
    ///
    /// 过期口径与 `AppDelegate.processPendingMessages()` 一致：`expireDate <= now` 视为过期，
    /// 既不导入此类条目，也会删除库内已存在的过期记录。
    ///
    /// 该方法自行管理写事务，调用方 **不要** 再包裹 `write {}`。
    ///
    /// - Parameters:
    ///   - messages: 待导入的未托管 `Message` 对象（通常由 `Message(json:)` 解析得到，必带主键 id）。
    ///   - now: 判定过期的基准时间，默认当前时间（测试可注入固定值）。
    /// - Returns: 是否实际发生了写入变更，供调用方决定是否触发刷新（小组件快照 / 列表通知）。
    @discardableResult
    func importMessages(_ messages: [Message], now: Date = Date()) -> Bool {
        // 过滤掉导入数据里已过期的消息
        let freshMessages = messages.filter { message in
            if let expireDate = message.expireDate, expireDate <= now {
                return false
            }
            return true
        }

        // 库内既有的过期记录（实时 Results，其内容在删除那一刻才求值）
        let expiredExisting = objects(Message.self)
            .filter("expireDate != nil AND expireDate <= %@", now)

        // 既没有可导入的新数据，也没有需要清理的过期记录时，不写库、不触发刷新
        guard !freshMessages.isEmpty || !expiredExisting.isEmpty else {
            return false
        }

        do {
            try write {
                // 先 add 后 delete：若某条导入消息的 id 命中库内某条过期记录，
                // add(update: .all) 会先把该行更新为（导入后的）未过期状态；随后 expiredExisting
                // 作为实时 Results 重新求值时已不再包含该行，因此不会被误删 —— 记录得以更新保留。
                for message in freshMessages {
                    add(message, update: .all)
                }
                if !expiredExisting.isEmpty {
                    delete(expiredExisting)
                }
            }
            return true
        } catch {
            // 写入失败：保持返回 false，避免在数据未落库的情况下误触发刷新或误报成功
            return false
        }
    }
}
