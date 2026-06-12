//
//  IconProcessor.swift
//  NotificationServiceExtension
//
//  Created by huangfeng on 2024/5/29.
//  Copyright © 2024 Fin. All rights reserved.
//

import Foundation
import Intents

class IconProcessor: NotificationContentProcessor {
    func process(identifier: String, content bestAttemptContent: UNMutableNotificationContent) async throws -> UNMutableNotificationContent {
        if #available(iOSApplicationExtension 15.0, *) {
            let userInfo = bestAttemptContent.userInfo
            
            guard let imageUrl = userInfo["icon"] as? String,
                  let imageFileUrl = await ImageDownloader.downloadImage(imageUrl)
            else {
                return bestAttemptContent
            }

            // 检测图片真实格式，复制到带正确扩展名的临时文件
            // 这确保 INImage 能正确识别图片格式，尤其是缓存命中时 Kingfisher 缓存文件无扩展名的情况
            let formatInfo = ImageFormatDetector.detectFormat(fromFilePath: imageFileUrl)
            let sourceUrl = URL(fileURLWithPath: imageFileUrl)
            let tmpUrl = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(formatInfo.fileExtension)
            try? FileManager.default.copyItem(at: sourceUrl, to: tmpUrl)

            // 优先从带正确扩展名的临时文件加载 INImage，回退到 imageData 方式
            let avatar: INImage
            if let fileAvatar = INImage(contentsOfFile: tmpUrl.path) {
                avatar = fileAvatar
            } else if let imageData = try? Data(contentsOf: sourceUrl) {
                avatar = INImage(imageData: imageData)
            } else {
                return bestAttemptContent
            }
            
            var personNameComponents = PersonNameComponents()
            personNameComponents.nickname = bestAttemptContent.title

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
