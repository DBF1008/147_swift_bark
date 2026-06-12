//
//  ImageProcessor.swift
//  NotificationServiceExtension
//
//  Created by huangfeng on 2024/5/29.
//  Copyright © 2024 Fin. All rights reserved.
//

import Foundation
import UserNotifications

class ImageProcessor: NotificationContentProcessor {
    func process(identifier: String, content bestAttemptContent: UNMutableNotificationContent) async throws -> UNMutableNotificationContent {
        let userInfo = bestAttemptContent.userInfo
        guard let imageUrl = userInfo["image"] as? String,
              let imageFileUrl = await ImageDownloader.downloadImage(imageUrl)
        else {
            return bestAttemptContent
        }

        let sourceUrl = URL(fileURLWithPath: imageFileUrl)

        // 通过 Magic Bytes 检测图片真实格式，确保扩展名和 UTI 类型匹配
        let formatInfo = ImageFormatDetector.detectFormat(fromFilePath: imageFileUrl)

        // 用正确的扩展名生成临时文件路径
        // 推送使用完后会自动删除临时文件，但 Kingfisher 缓存需要保留以供历史记录查看
        let tmpDir = FileManager.default.temporaryDirectory
        let copyDestUrl = tmpDir
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(formatInfo.fileExtension)

        try? FileManager.default.copyItem(at: sourceUrl, to: copyDestUrl)

        // 使用检测到的真实 UTI 类型创建附件，避免硬编码 kUTTypePNG 导致格式不匹配
        if let attachment = try? UNNotificationAttachment(
            identifier: "image",
            url: copyDestUrl,
            options: [UNNotificationAttachmentOptionsTypeHintKey: formatInfo.utiIdentifier]
        ) {
            bestAttemptContent.attachments = [attachment]
        }
        return bestAttemptContent
    }
}
