//
//  ImageProcessor.swift
//  NotificationServiceExtension
//
//  Created by huangfeng on 2024/5/29.
//  Copyright © 2024 Fin. All rights reserved.
//

import Foundation
import MobileCoreServices
import UIKit

class ImageProcessor: NotificationContentProcessor {
    func process(identifier: String, content bestAttemptContent: UNMutableNotificationContent) async throws -> UNMutableNotificationContent {
        let userInfo = bestAttemptContent.userInfo
        guard let imageUrl = userInfo["image"] as? String,
              let imageFileUrl = await ImageDownloader.downloadImage(imageUrl)
        else {
            return bestAttemptContent
        }

        if let attachment = makeAttachment(imageFilePath: imageFileUrl) {
            bestAttemptContent.attachments = [attachment]
        }
        return bestAttemptContent
    }

    /// 根据缓存图片文件生成通知附件。
    ///
    /// Kingfisher 缓存文件名是无扩展名的裸 hash，`UNNotificationAttachment` 只能依赖类型提示判定类型。
    /// 因此这里按图片真实内容判断格式，生成带正确扩展名的临时副本并设置正确的类型提示，
    /// 否则非 PNG 图片会因类型提示与内容不符被系统拒绝（缓存命中时尤甚）。
    /// 非原生支持的格式统一转码为 PNG；无法解码时放弃附件，避免错误提示导致显示失败。
    private func makeAttachment(imageFilePath: String) -> UNNotificationAttachment? {
        let sourceUrl = URL(fileURLWithPath: imageFilePath)
        guard let data = try? Data(contentsOf: sourceUrl) else {
            return nil
        }

        let format = ImageFormat.detect(from: data)

        // 决定最终写入推送的数据、扩展名与类型提示
        let payload: Data
        let fileExtension: String
        let typeHint: CFString
        if format.isNotificationNativelySupported, let hint = format.notificationTypeHint {
            // 原生支持(PNG/JPEG/GIF)：原样使用，保留正确的扩展名与类型提示
            payload = data
            fileExtension = format.fileExtension
            typeHint = hint
        } else if let pngData = UIImage(data: data)?.pngData() {
            // 非原生(HEIC/WebP/BMP/TIFF/未知)：转码为 PNG 后再附加
            payload = pngData
            fileExtension = "png"
            typeHint = kUTTypePNG
        } else {
            // 既非原生格式又无法解码，放弃附件
            return nil
        }

        // 复制一份带正确扩展名的副本给推送使用（用完后系统会自动删除），原图片缓存留着以后在历史记录里查看
        let destUrl = sourceUrl.appendingPathExtension(fileExtension)
        try? FileManager.default.removeItem(at: destUrl)
        do {
            try payload.write(to: destUrl)
        } catch {
            return nil
        }

        return try? UNNotificationAttachment(
            identifier: "image",
            url: destUrl,
            options: [UNNotificationAttachmentOptionsTypeHintKey: typeHint]
        )
    }
}
