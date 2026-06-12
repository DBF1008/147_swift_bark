//
//  IconProcessor.swift
//  NotificationServiceExtension
//
//  Created by huangfeng on 2024/5/29.
//  Copyright © 2024 Fin. All rights reserved.
//

import Foundation
import Intents
import UIKit

class IconProcessor: NotificationContentProcessor {
    func process(identifier: String, content bestAttemptContent: UNMutableNotificationContent) async throws -> UNMutableNotificationContent {
        if #available(iOSApplicationExtension 15.0, *) {
            let userInfo = bestAttemptContent.userInfo

            guard let imageUrl = userInfo["icon"] as? String,
                  let imageFileUrl = await ImageDownloader.downloadImage(imageUrl),
                  let imageData = try? Data(contentsOf: URL(fileURLWithPath: imageFileUrl))
            else {
                return bestAttemptContent
            }

            var personNameComponents = PersonNameComponents()
            personNameComponents.nickname = bestAttemptContent.title

            // 标准化图片数据：部分格式（动图 GIF / HEIC / WebP 等）直接喂给 INImage 会丢失头像样式，
            // 先用 UIImage 解码再以 PNG 重新编码可稳定生成头像；解码失败则回退原始数据，不退化既有行为。
            let avatarData = UIImage(data: imageData)?.pngData() ?? imageData
            let avatar = INImage(imageData: avatarData)
            let senderPerson = INPerson(
                personHandle: INPersonHandle(value: "", type: .unknown),
                nameComponents: personNameComponents,
                displayName: personNameComponents.nickname,
                image: avatar,
                contactIdentifier: nil,
                customIdentifier: nil,
                isMe: false,
                suggestionType: .none
            )
            let mePerson = INPerson(
                personHandle: INPersonHandle(value: "", type: .unknown),
                nameComponents: nil,
                displayName: nil,
                image: nil,
                contactIdentifier: nil,
                customIdentifier: nil,
                isMe: true,
                suggestionType: .none
            )

            // 必须两个接受者，才能显示 subtitle, 别问为什么
            let placeholderPerson = INPerson(
                personHandle: INPersonHandle(value: "", type: .unknown),
                nameComponents: personNameComponents,
                displayName: personNameComponents.nickname,
                image: avatar,
                contactIdentifier: nil,
                customIdentifier: nil
            )

            let intent = INSendMessageIntent(
                recipients: [mePerson, placeholderPerson],
                outgoingMessageType: .outgoingMessageText,
                content: bestAttemptContent.body,
                speakableGroupName: INSpeakableString(spokenPhrase: bestAttemptContent.subtitle),
                conversationIdentifier: bestAttemptContent.threadIdentifier,
                serviceName: nil,
                sender: senderPerson,
                attachments: nil
            )

            intent.setImage(avatar, forParameterNamed: \.speakableGroupName)

            let interaction = INInteraction(intent: intent, response: nil)
            interaction.direction = .incoming

            do {
                try await interaction.donate()
                let content = try bestAttemptContent.updating(from: intent) as! UNMutableNotificationContent
                return content
            } catch {
                return bestAttemptContent
            }
        } else {
            return bestAttemptContent
        }
    }
}
