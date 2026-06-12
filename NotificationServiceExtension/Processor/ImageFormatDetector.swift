//
//  ImageFormatDetector.swift
//  NotificationServiceExtension
//
//  Created on 2025/1/15.
//  Copyright © 2025 Fin. All rights reserved.
//

import Foundation

/// 通过文件头 Magic Bytes 检测图片格式，确保通知附件使用正确的文件扩展名和 UTI 类型。
///
/// Kingfisher 磁盘缓存的文件名是基于 URL hash 生成的，不带任何图片格式扩展名。
/// 如果直接使用缓存路径或随意加 `.tmp` 扩展名，`UNNotificationAttachment` 无法
/// 正确识别图片格式，导致大图显示失败或头像样式丢失。
///
/// 支持的格式：JPEG, PNG, GIF, WebP, HEIC/HEIF, TIFF, BMP
class ImageFormatDetector {

    /// 检测结果：包含文件扩展名和 UTI 类型标识符
    struct FormatInfo {
        /// 文件扩展名（不含点号），例如 "jpg"、"png"
        let fileExtension: String
        /// UTI 类型标识符，例如 "public.jpeg"、"public.png"
        /// 可直接用于 `UNNotificationAttachmentOptionsTypeHintKey`
        let utiIdentifier: String
    }

    // MARK: - 格式映射表

    /// 枚举所有支持的图片格式
    private enum Format {
        case jpeg, png, gif, webp, heic, heif, tiff, bmp, unknown

        var fileExtension: String {
            switch self {
            case .jpeg:    return "jpg"
            case .png:     return "png"
            case .gif:     return "gif"
            case .webp:    return "webp"
            case .heic:    return "heic"
            case .heif:    return "heif"
            case .tiff:    return "tiff"
            case .bmp:     return "bmp"
            case .unknown: return "png" // 无法识别时默认按 PNG 处理
            }
        }

        var utiIdentifier: String {
            switch self {
            case .jpeg:    return "public.jpeg"
            case .png:     return "public.png"
            case .gif:     return "com.compuserve.gif"
            case .webp:    return "org.webmproject.webp"
            case .heic:    return "public.heic"
            case .heif:    return "public.heif"
            case .tiff:    return "public.tiff"
            case .bmp:     return "com.microsoft.bmp"
            case .unknown: return "public.png"
            }
        }
    }

    // MARK: - Public API

    /// 从文件路径检测图片格式
    /// - Parameter filePath: 图片文件的绝对路径
    /// - Returns: 包含扩展名和 UTI 的 FormatInfo；文件不可读时返回 PNG 默认值
    class func detectFormat(fromFilePath filePath: String) -> FormatInfo {
        let data = readHeader(filePath: filePath, count: 16)
        return detectFormat(fromHeaderData: data)
    }

    /// 从 Data 的前 N 字节检测图片格式
    /// - Parameter data: 图片数据（只需要前 16 字节即可识别所有常见格式）
    /// - Returns: 包含扩展名和 UTI 的 FormatInfo
    class func detectFormat(fromHeaderData data: Data) -> FormatInfo {
        let format = identifyFormat(from: data)
        return FormatInfo(fileExtension: format.fileExtension,
                          utiIdentifier: format.utiIdentifier)
    }

    // MARK: - Magic Bytes 识别

    /// 根据文件头字节判断具体图片格式
    ///
    /// 各格式的 Magic Bytes 特征：
    /// - JPEG: `FF D8 FF`
    /// - PNG:  `89 50 4E 47 0D 0A 1A 0A`
    /// - GIF:  `47 49 46 38` ("GIF8")
    /// - WebP: `RIFF ?? ?? ?? ?? WEBP`
    /// - HEIC/HEIF: `?? ?? ?? ?? 66 74 79 70` + brand ("heic"/"heix"/"mif1" 等)
    /// - TIFF: `49 49 2A 00` (little-endian) 或 `4D 4D 00 2A` (big-endian)
    /// - BMP:  `42 4D` ("BM")
    private class func identifyFormat(from data: Data) -> Format {
        guard data.count >= 2 else { return .unknown }

        let bytes = Array(data)

        // ── JPEG: FF D8 FF ──
        if bytes.count >= 3,
           bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
            return .jpeg
        }

        // ── PNG: 89 50 4E 47 0D 0A 1A 0A ──
        if bytes.count >= 8,
           bytes[0] == 0x89, bytes[1] == 0x50,
           bytes[2] == 0x4E, bytes[3] == 0x47,
           bytes[4] == 0x0D, bytes[5] == 0x0A,
           bytes[6] == 0x1A, bytes[7] == 0x0A {
            return .png
        }

        // ── GIF: "GIF8" ──
        if bytes.count >= 4,
           bytes[0] == 0x47, bytes[1] == 0x49,
           bytes[2] == 0x46, bytes[3] == 0x38 {
            return .gif
        }

        // ── WebP: "RIFF" .... "WEBP" ──
        if bytes.count >= 12,
           bytes[0] == 0x52, bytes[1] == 0x49,
           bytes[2] == 0x46, bytes[3] == 0x46,
           bytes[8] == 0x57, bytes[9] == 0x45,
           bytes[10] == 0x42, bytes[11] == 0x50 {
            return .webp
        }

        // ── HEIC / HEIF: ftyp box ──
        // 结构: [4 bytes size] [ftyp] [brand]
        if bytes.count >= 12,
           bytes[4] == 0x66, bytes[5] == 0x74,
           bytes[6] == 0x79, bytes[7] == 0x70 {
            let brand = String(bytes: bytes[8..<12], encoding: .ascii) ?? ""
            if brand == "heic" || brand == "heix" || brand == "hevc" || brand == "hevx" {
                return .heic
            }
            if brand == "mif1" || brand == "msf1" {
                return .heif
            }
        }

        // ── TIFF: "II\x2A\x00" (LE) 或 "MM\x00\x2A" (BE) ──
        if bytes.count >= 4 {
            if (bytes[0] == 0x49 && bytes[1] == 0x49 &&
                bytes[2] == 0x2A && bytes[3] == 0x00) ||
               (bytes[0] == 0x4D && bytes[1] == 0x4D &&
                bytes[2] == 0x00 && bytes[3] == 0x2A) {
                return .tiff
            }
        }

        // ── BMP: "BM" ──
        if bytes[0] == 0x42 && bytes[1] == 0x4D {
            return .bmp
        }

        return .unknown
    }

    // MARK: - Helper

    /// 从文件头部读取指定字节数
    private class func readHeader(filePath: String, count: Int) -> Data {
        guard let handle = FileHandle(forReadingAtPath: filePath) else {
            return Data()
        }
        defer { handle.closeFile() }
        return handle.readData(ofLength: count)
    }
}
