//
//  RealmConfiguration.swift
//  NotificationServiceExtension
//
//  Created by huangfeng on 2024/5/29.
//  Copyright © 2024 Fin. All rights reserved.
//

@_exported import RealmSwift
import UIKit

let kRealmDefaultConfiguration = {
    let fileUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("bark.realm")
    let config = Realm.Configuration(
        fileURL: fileUrl,
        schemaVersion: 19,
        migrationBlock: { migration, oldSchemaVersion in
            switch oldSchemaVersion {
            case 0...13:
                migration.enumerateObjects(ofType: Message.className()) { oldObject, newObject in
                    guard let obj = oldObject else {
                        return
                    }
                    guard let isDeleted = obj["isDeleted"] as? Bool else {
                        return
                    }
                    // 旧版软删除的数据，迁移到新版时硬删除掉，新版不再过滤 isDeleted 字段
                    if isDeleted, let newObject {
                        migration.delete(newObject)
                    }
                }
            default:
                break
            }

            // schema 18 → 19: 将 markdown 消息的 body 从原始标记文本归一化为纯文本，
            // 原始 markdown 源文本迁移到 markdownSource 字段
            if oldSchemaVersion < 19 {
                migration.enumerateObjects(ofType: Message.className()) { oldObject, newObject in
                    guard let oldObject, let newObject else { return }
                    guard let bodyType = oldObject["bodyType"] as? String,
                          bodyType == "markdown",
                          let body = oldObject["body"] as? String
                    else {
                        return
                    }
                    // 原始 markdown 源文本存入 markdownSource
                    newObject["markdownSource"] = body
                    // body 替换为渲染后的纯文本
                    let plainText = MarkdownParser(configuration: MarkdownParser.Configuration.clear)
                        .parse(body)
                        .string
                        .replacingOccurrences(of: "\n\n+", with: "\n", options: .regularExpression)
                    newObject["body"] = plainText
                }
            }
        },
        objectTypes: [Message.self]
    )
    return config
}()
