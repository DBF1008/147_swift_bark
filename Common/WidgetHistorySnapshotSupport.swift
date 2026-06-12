//
//  WidgetHistorySnapshotSupport.swift
//  Bark
//
//  Created by OpenCode on 2026/3/23.
//

import Foundation
import RealmSwift

extension WidgetHistoryMessage {
    init(id: String,
         group: String?,
         title: String?,
         subtitle: String?,
         body: String?,
         bodyType: String?,
         image: String?,
         createDate: Date)
    {
        // markdown 消息：用与通知横幅完全相同的单一归一化入口转成纯文本（小组件不渲染富文本）。
        // 普通文本消息：原样透传，绝不经过 Markdown 解析，避免破坏含特殊字符的普通文本。
        let normalizedBody: String?
        if let body, bodyType == Message.BodyType.markdown.rawValue {
            normalizedBody = MarkdownParser.displayPlainText(fromMarkdown: body)
        } else {
            normalizedBody = body
        }

        self.init(id: id,
                  group: group,
                  title: title,
                  subtitle: subtitle,
                  body: normalizedBody,
                  image: image,
                  createDate: createDate)
    }

    init(message: Message) {
        self.init(id: message.id,
                  group: message.group,
                  title: message.title,
                  subtitle: message.subtitle,
                  body: message.body,
                  bodyType: message.bodyType,
                  image: message.image,
                  createDate: message.createDate ?? Date())
    }
}

extension Realm {
    func widgetSnapshotItems(limit: Int = WidgetHistoryConstants.snapshotRetentionLimit) -> [WidgetHistoryMessage] {
        let now = Date()
        return objects(Message.self)
            .filter("expireDate == nil OR expireDate > %@", now)
            .sorted(byKeyPath: "createDate", ascending: false)
            .prefix(limit)
            .map { WidgetHistoryMessage(message: $0) }
    }
}
