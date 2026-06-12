//
//  ImageFormatTests.swift
//  BarkTests
//
//  Created by huangfeng on 2026/6/12.
//  Copyright © 2026 Fin. All rights reserved.
//

import MobileCoreServices
import Testing
@testable import Bark

struct ImageFormatTests {
    private func makeData(_ bytes: [UInt8]) -> Data { Data(bytes) }

    @Test("PNG 文件头被正确识别")
    func png() {
        let format = ImageFormat.detect(from: makeData([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00]))
        #expect(format == .png)
        #expect(format.fileExtension == "png")
        #expect(format.isNotificationNativelySupported)
        #expect(format.notificationTypeHint.map { $0 as String } == (kUTTypePNG as String))
    }

    @Test("JPEG 文件头被正确识别，且不会被误判为 PNG")
    func jpeg() {
        let format = ImageFormat.detect(from: makeData([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]))
        #expect(format == .jpeg)
        // 回归：曾因把类型提示写死成 PNG，导致 JPEG 附件被系统拒绝（看不到大图）
        #expect(format != .png)
        #expect(format.fileExtension == "jpg")
        #expect(format.isNotificationNativelySupported)
        #expect(format.notificationTypeHint.map { $0 as String } == (kUTTypeJPEG as String))
    }

    @Test("GIF 文件头被正确识别，且不会被误判为 PNG")
    func gif() {
        let format = ImageFormat.detect(from: makeData([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00]))
        #expect(format == .gif)
        #expect(format != .png) // 同 JPEG 的回归点
        #expect(format.fileExtension == "gif")
        #expect(format.isNotificationNativelySupported)
        #expect(format.notificationTypeHint.map { $0 as String } == (kUTTypeGIF as String))
    }

    @Test("WebP 文件头被正确识别，归为需转码（非原生支持）")
    func webp() {
        let format = ImageFormat.detect(from: makeData([0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50]))
        #expect(format == .webp)
        #expect(format.fileExtension == "webp")
        #expect(format.isNotificationNativelySupported == false)
        #expect(format.notificationTypeHint == nil)
    }

    @Test("HEIC 文件头被正确识别，归为需转码（非原生支持）")
    func heic() {
        // box size + "ftyp" + brand "heic"
        let format = ImageFormat.detect(from: makeData([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63]))
        #expect(format == .heic)
        #expect(format.isNotificationNativelySupported == false)
        #expect(format.notificationTypeHint == nil)
    }

    @Test("BMP 文件头被正确识别，归为需转码（非原生支持）")
    func bmp() {
        let format = ImageFormat.detect(from: makeData([0x42, 0x4D, 0x00, 0x00]))
        #expect(format == .bmp)
        #expect(format.isNotificationNativelySupported == false)
    }

    @Test("TIFF 文件头（大小端）均被正确识别，归为需转码")
    func tiff() {
        let little = ImageFormat.detect(from: makeData([0x49, 0x49, 0x2A, 0x00]))
        let big = ImageFormat.detect(from: makeData([0x4D, 0x4D, 0x00, 0x2A]))
        #expect(little == .tiff)
        #expect(big == .tiff)
        #expect(little.isNotificationNativelySupported == false)
        #expect(big.isNotificationNativelySupported == false)
    }

    @Test("RIFF 容器但偏移 8 非 WEBP 时不应误判为图片")
    func riffButNotWebp() {
        // RIFF 同样是 WAV/AVI 容器头，偏移 8 为 "WAVE" 时不应识别为 webp
        let format = ImageFormat.detect(from: makeData([0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x41, 0x56, 0x45]))
        #expect(format == .unknown)
    }

    @Test("空数据与过短数据归为 unknown 且非原生支持")
    func emptyAndTooShort() {
        #expect(ImageFormat.detect(from: Data()) == .unknown)
        #expect(ImageFormat.detect(from: makeData([0x89, 0x50])) == .unknown) // PNG 头不完整
        #expect(ImageFormat.detect(from: makeData([0x52, 0x49, 0x46, 0x46])) == .unknown) // RIFF 但不足以判定 WEBP
        #expect(ImageFormat.detect(from: Data()).isNotificationNativelySupported == false)
    }
}
