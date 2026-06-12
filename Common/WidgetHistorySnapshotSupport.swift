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
        let normalizedBody: String?
        if let body, bodyType == "markdown" {
            normalizedBody = MarkdownParser(configuration: MarkdownParser.Configuration.clear)
                .parse(body)
                .string
                .replacingOccurrences(of: "\n\n+", with: "\n", options: .regularExpression)
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
        // message.body 已经是归一化后的纯文本，无需再次转换
        self.init(id: message.id,
                  group: message.group,
                  title: message.title,
                  subtitle: message.subtitle,
                  body: message.body,
                  bodyType: nil,
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
