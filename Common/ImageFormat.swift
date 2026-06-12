//
//  ImageFormat.swift
//  Bark
//
//  Created by huangfeng on 2026/6/12.
//  Copyright © 2026 Fin. All rights reserved.
//

import Foundation
import MobileCoreServices

/// 推送附件的图片格式判断。
///
/// 通知扩展从 Kingfisher 缓存拿到的文件名是无扩展名的裸 hash，
/// `UNNotificationAttachment` 只能依赖类型提示（typeHint）判定附件类型，
/// 因此必须按图片真实内容（文件头 magic bytes）判断格式，
/// 不能依赖文件名后缀、也不能写死成某一种类型。
enum ImageFormat {
    case png
    case jpeg
    case gif
    case heic
    case webp
    case bmp
    case tiff
    case unknown

    /// 按文件头 magic bytes 判断图片真实格式。
    /// - Parameter data: 图片原始数据（只读取文件头部分）。
    static func detect(from data: Data) -> ImageFormat {
        // 只需文件头，取前 16 字节即可覆盖所有签名（HEIC / WebP 的标识位于偏移 8）。
        let bytes = [UInt8](data.prefix(16))

        // PNG: 89 50 4E 47 0D 0A 1A 0A
        if matches(bytes, at: 0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return .png
        }
        // JPEG: FF D8 FF
        if matches(bytes, at: 0, [0xFF, 0xD8, 0xFF]) {
            return .jpeg
        }
        // GIF: "GIF8"（GIF87a / GIF89a）
        if matches(bytes, at: 0, [0x47, 0x49, 0x46, 0x38]) {
            return .gif
        }
        // BMP: "BM"
        if matches(bytes, at: 0, [0x42, 0x4D]) {
            return .bmp
        }
        // TIFF: little-endian "II*\0" 或 big-endian "MM\0*"
        if matches(bytes, at: 0, [0x49, 0x49, 0x2A, 0x00]) || matches(bytes, at: 0, [0x4D, 0x4D, 0x00, 0x2A]) {
            return .tiff
        }
        // WebP: "RIFF"????"WEBP"。RIFF 同样是 WAV/AVI 的容器头，
        // 必须再校验偏移 8 的 "WEBP" 才能确认是 WebP。
        if matches(bytes, at: 0, [0x52, 0x49, 0x46, 0x46]), matches(bytes, at: 8, [0x57, 0x45, 0x42, 0x50]) {
            return .webp
        }
        // HEIC / HEIF: ISOBMFF 容器，偏移 4 为 "ftyp"，偏移 8 为 major brand。
        // ftyp 也用于 MP4 等容器，需用 brand 区分。
        if matches(bytes, at: 4, [0x66, 0x74, 0x79, 0x70]), isHEIFBrand(bytes) {
            return .heic
        }
        return .unknown
    }

    /// 写本地文件时使用的扩展名。
    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .gif: return "gif"
        case .heic: return "heic"
        case .webp: return "webp"
        case .bmp: return "bmp"
        case .tiff: return "tiff"
        case .unknown: return "img"
        }
    }

    /// `UNNotificationAttachment` 可接受的类型提示。
    /// 通知附件原生只支持 PNG / JPEG / GIF，其余格式返回 nil（需转码为 PNG 后再附加）。
    var notificationTypeHint: CFString? {
        switch self {
        case .png: return kUTTypePNG
        case .jpeg: return kUTTypeJPEG
        case .gif: return kUTTypeGIF
        case .heic, .webp, .bmp, .tiff, .unknown: return nil
        }
    }

    /// 是否被通知附件原生接受（PNG / JPEG / GIF）。
    var isNotificationNativelySupported: Bool {
        notificationTypeHint != nil
    }

    // MARK: - Magic bytes helpers

    /// 比较 `bytes` 从 `offset` 起是否与 `pattern` 完全一致；越界时返回 false。
    private static func matches(_ bytes: [UInt8], at offset: Int, _ pattern: [UInt8]) -> Bool {
        guard bytes.count >= offset + pattern.count else { return false }
        for (index, value) in pattern.enumerated() {
            if bytes[offset + index] != value {
                return false
            }
        }
        return true
    }

    /// 偏移 8 处的 4 字节 brand 是否属于 HEIF 系列。
    private static func isHEIFBrand(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 12 else { return false }
        let heifBrands: Set<String> = ["heic", "heix", "hevc", "hevx", "heim", "heis", "hevm", "hevs", "mif1", "msf1"]
        guard let brand = String(bytes: bytes[8 ..< 12], encoding: .ascii) else { return false }
        return heifBrands.contains(brand)
    }
}
