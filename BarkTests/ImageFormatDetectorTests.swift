//
//  ImageFormatDetectorTests.swift
//  BarkTests
//
//  验证 ImageFormatDetector 的 Magic Bytes 格式检测逻辑。
//  覆盖 JPEG / PNG / GIF / WebP / HEIC / HEIF / TIFF / BMP 八种格式，
//  以及空数据、截断头、未知格式等边界情况。
//

import XCTest

class ImageFormatDetectorTests: XCTestCase {

    // MARK: - 辅助：写入临时文件

    /// 将 Data 写入临时文件，返回路径。测试结束后自动清理。
    private func writeTempFile(data: Data, ext: String = "") -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileName = ext.isEmpty ? "image" : "image.\(ext)"
        let path = dir.appendingPathComponent(fileName).path
        try? data.write(to: URL(fileURLWithPath: path))
        return path
    }

    // MARK: - JPEG

    func testDetectJPEG() {
        let header = Data([0xFF, 0xD8, 0xFF, 0xE0,
                           0x00, 0x10, 0x4A, 0x46,
                           0x49, 0x46, 0x00, 0x01,
                           0x01, 0x00, 0x00, 0x01])
        let info = ImageFormatDetector.detectFormat(fromHeaderData: header)
        XCTAssertEqual(info.fileExtension, "jpg")
        XCTAssertEqual(info.utiIdentifier, "public.jpeg")
    }

    func testDetectJPEG_ExifVariant() {
        // EXIF JPEG: FF D8 FF E1
        let header = Data([0xFF, 0xD8, 0xFF, 0xE1,
                           0x00, 0x10, 0x45, 0x78,
                           0x69, 0x66, 0x00, 0x00,
                           0x00, 0x00, 0x00, 0x00])
        let info = ImageFormatDetector.detectFormat(fromHeaderData: header)
        XCTAssertEqual(info.fileExtension, "jpg")
        XCTAssertEqual(info.utiIdentifier, "public.jpeg")
    }

    // MARK: - PNG

    func testDetectPNG() {
        let header = Data([0x89, 0x50, 0x4E, 0x47,
                           0x0D, 0x0A, 0x1A, 0x0A,
                           0x00, 0x00, 0x00, 0x0D,
                           0x49, 0x48, 0x44, 0x52])
        let info = ImageFormatDetector.detectFormat(fromHeaderData: header)
        XCTAssertEqual(info.fileExtension, "png")
        XCTAssertEqual(info.utiIdentifier, "public.png")
    }

    // MARK: - GIF

    func testDetectGIF87a() {
        // GIF87a
        let header = Data([0x47, 0x49, 0x46, 0x38,
                           0x37, 0x61, 0x01, 0x00,
                           0x01, 0x00, 0x80, 0x00,
                           0x00, 0x00, 0x00, 0x00])
        let info = ImageFormatDetector.detectFormat(fromHeaderData: header)
        XCTAssertEqual(info.fileExtension, "gif")
        XCTAssertEqual(info.utiIdentifier, "com.compuserve.gif")
    }

    func testDetectGIF89a() {
        // GIF89a (supports animation)
        let header = Data([0x47, 0x49, 0x46, 0x38,
                           0x39, 0x61, 0x01, 0x00,
                           0x01, 0x00, 0x80, 0x00,
                           0x00, 0x00, 0x00, 0x00])
        let info = ImageFormatDetector.detectFormat(fromHeaderData: header)
        XCTAssertEqual(info.fileExtension, "gif")
        XCTAssertEqual(info.utiIdentifier, "com.compuserve.gif")
    }

    // MARK: - WebP

    func testDetectWebP() {
        // RIFF .... WEBP
        let header = Data([0x52, 0x49, 0x46, 0x46,  // "RIFF"
                           0x24, 0x00, 0x00, 0x00,  // file size
                           0x57, 0x45, 0x42, 0x50,  // "WEBP"
                           0x56, 0x50, 0x38, 0x20])
        let info = ImageFormatDetector.detectFormat(fromHeaderData: header)
        XCTAssertEqual(info.fileExtension, "webp")
        XCTAssertEqual(info.utiIdentifier, "org.webmproject.webp")
    }

    // MARK: - HEIC

    func testDetectHEIC() {
        // ftyp box with "heic" brand
        let header = Data([0x00, 0x00, 0x00, 0x18,  // box size
                           0x66, 0x74, 0x79, 0x70,  // "ftyp"
                           0x68, 0x65, 0x69, 0x63,  // "heic"
                           0x00, 0x00, 0x00, 0x00])
        let info = ImageFormatDetector.detectFormat(fromHeaderData: header)
        XCTAssertEqual(info.fileExtension, "heic")
        XCTAssertEqual(info.utiIdentifier, "public.heic")
    }

    func testDetectHEIC_heixBrand() {
        // ftyp box with "heix" brand (10-bit HEIC)
        let header = Data([0x00, 0x00, 0x00, 0x18,
                           0x66, 0x74, 0x79, 0x70,
                           0x68, 0x65, 0x69, 0x78,  // "heix"
                           0x00, 0x00, 0x00, 0x00])
        let info = ImageFormatDetector.detectFormat(fromHeaderData: header)
        XCTAssertEqual(info.fileExtension, "heic")
        XCTAssertEqual(info.utiIdentifier, "public.heic")
    }

    // MARK: - HEIF

    func testDetectHEIF() {
        // ftyp box with "mif1" brand (HEIF image)
        let header = Data([0x00, 0x00, 0x00, 0x18,
                           0x66, 0x74, 0x79, 0x70,
                           0x6D, 0x69, 0x66, 0x31,  // "mif1"
                           0x00, 0x00, 0x00, 0x00])
        let info = ImageFormatDetector.detectFormat(fromHeaderData: header)
        XCTAssertEqual(info.fileExtension, "heif")
        XCTAssertEqual(info.utiIdentifier, "public.heif")
    }

    // MARK: - TIFF

    func testDetectTIFF_LittleEndian() {
        // "II\x2A\x00"
        let header = Data([0x49, 0x49, 0x2A, 0x00,
                           0x08, 0x00, 0x00, 0x00,
                           0x00, 0x00, 0x00, 0x00,
                           0x00, 0x00, 0x00, 0x00])
        let info = ImageFormatDetector.detectFormat(fromHeaderData: header)
        XCTAssertEqual(info.fileExtension, "tiff")
        XCTAssertEqual(info.utiIdentifier, "public.tiff")
    }

    func testDetectTIFF_BigEndian() {
        // "MM\x00\x2A"
        let header = Data([0x4D, 0x4D, 0x00, 0x2A,
                           0x00, 0x00, 0x00, 0x08,
                           0x00, 0x00, 0x00, 0x00,
                           0x00, 0x00, 0x00, 0x00])
        let info = ImageFormatDetector.detectFormat(fromHeaderData: header)
        XCTAssertEqual(info.fileExtension, "tiff")
        XCTAssertEqual(info.utiIdentifier, "public.tiff")
    }

    // MARK: - BMP

    func testDetectBMP() {
        let header = Data([0x42, 0x4D, 0x36, 0x00,
                           0x00, 0x00, 0x00, 0x00,
                           0x00, 0x00, 0x36, 0x00,
                           0x00, 0x00, 0x00, 0x00])
        let info = ImageFormatDetector.detectFormat(fromHeaderData: header)
        XCTAssertEqual(info.fileExtension, "bmp")
        XCTAssertEqual(info.utiIdentifier, "com.microsoft.bmp")
    }

    // MARK: - 边界情况

    func testEmptyData_DefaultsToPNG() {
        let info = ImageFormatDetector.detectFormat(fromHeaderData: Data())
        XCTAssertEqual(info.fileExtension, "png")
        XCTAssertEqual(info.utiIdentifier, "public.png")
    }

    func testSingleByte_DefaultsToPNG() {
        let info = ImageFormatDetector.detectFormat(fromHeaderData: Data([0x00]))
        XCTAssertEqual(info.fileExtension, "png")
        XCTAssertEqual(info.utiIdentifier, "public.png")
    }

    func testUnknownMagicBytes_DefaultsToPNG() {
        let header = Data([0x01, 0x02, 0x03, 0x04,
                           0x05, 0x06, 0x07, 0x08,
                           0x09, 0x0A, 0x0B, 0x0C,
                           0x0D, 0x0E, 0x0F, 0x10])
        let info = ImageFormatDetector.detectFormat(fromHeaderData: header)
        XCTAssertEqual(info.fileExtension, "png")
        XCTAssertEqual(info.utiIdentifier, "public.png")
    }

    func testPartialPNGHeader_DefaultsToPNG() {
        // 只有 PNG 签名的前 4 字节，不够完整的 8 字节签名
        let header = Data([0x89, 0x50, 0x4E, 0x47])
        let info = ImageFormatDetector.detectFormat(fromHeaderData: header)
        XCTAssertEqual(info.fileExtension, "png")
        XCTAssertEqual(info.utiIdentifier, "public.png")
    }

    func testPartialRIFF_NotWebP_DefaultsToPNG() {
        // "RIFF" 但后面不是 "WEBP"（可能是 WAV/AVI）
        let header = Data([0x52, 0x49, 0x46, 0x46,
                           0x24, 0x00, 0x00, 0x00,
                           0x57, 0x41, 0x56, 0x45,  // "WAVE" (音频)
                           0x00, 0x00, 0x00, 0x00])
        let info = ImageFormatDetector.detectFormat(fromHeaderData: header)
        XCTAssertEqual(info.fileExtension, "png")
        XCTAssertEqual(info.utiIdentifier, "public.png")
    }

    // MARK: - 文件路径检测

    func testDetectFromFilePath_JPEG() {
        let jpegData = Data([0xFF, 0xD8, 0xFF, 0xE0,
                             0x00, 0x10, 0x4A, 0x46,
                             0x49, 0x46, 0x00, 0x01,
                             0x01, 0x00, 0x00, 0x01])
        let path = writeTempFile(data: jpegData)
        defer {
            let dir = (path as NSString).deletingLastPathComponent
            try? FileManager.default.removeItem(atPath: dir)
        }

        let info = ImageFormatDetector.detectFormat(fromFilePath: path)
        XCTAssertEqual(info.fileExtension, "jpg")
        XCTAssertEqual(info.utiIdentifier, "public.jpeg")
    }

    func testDetectFromFilePath_PNG() {
        let pngData = Data([0x89, 0x50, 0x4E, 0x47,
                            0x0D, 0x0A, 0x1A, 0x0A,
                            0x00, 0x00, 0x00, 0x0D,
                            0x49, 0x48, 0x44, 0x52])
        let path = writeTempFile(data: pngData)
        defer {
            let dir = (path as NSString).deletingLastPathComponent
            try? FileManager.default.removeItem(atPath: dir)
        }

        let info = ImageFormatDetector.detectFormat(fromFilePath: path)
        XCTAssertEqual(info.fileExtension, "png")
        XCTAssertEqual(info.utiIdentifier, "public.png")
    }

    func testDetectFromFilePath_NoExtension() {
        // 模拟 Kingfisher 缓存命中：文件无扩展名，但内容是 JPEG
        let jpegData = Data([0xFF, 0xD8, 0xFF, 0xE0,
                             0x00, 0x10, 0x4A, 0x46,
                             0x49, 0x46, 0x00, 0x01])
        let path = writeTempFile(data: jpegData, ext: "") // 无扩展名
        defer {
            let dir = (path as NSString).deletingLastPathComponent
            try? FileManager.default.removeItem(atPath: dir)
        }

        let info = ImageFormatDetector.detectFormat(fromFilePath: path)
        XCTAssertEqual(info.fileExtension, "jpg",
                       "无扩展名的 JPEG 缓存文件应通过 Magic Bytes 正确识别")
    }

    func testDetectFromFilePath_WrongExtension() {
        // 模拟错误扩展名场景：文件实际是 GIF 但扩展名是 .png
        let gifData = Data([0x47, 0x49, 0x46, 0x38,
                            0x39, 0x61, 0x01, 0x00,
                            0x01, 0x00, 0x80, 0x00])
        let path = writeTempFile(data: gifData, ext: "png")
        defer {
            let dir = (path as NSString).deletingLastPathComponent
            try? FileManager.default.removeItem(atPath: dir)
        }

        let info = ImageFormatDetector.detectFormat(fromFilePath: path)
        XCTAssertEqual(info.fileExtension, "gif",
                       "扩展名与实际格式不符时，应以 Magic Bytes 为准")
    }

    func testDetectFromFilePath_NonExistentFile_DefaultsToPNG() {
        let info = ImageFormatDetector.detectFormat(fromFilePath: "/tmp/nonexistent_bark_test_12345")
        XCTAssertEqual(info.fileExtension, "png")
        XCTAssertEqual(info.utiIdentifier, "public.png")
    }

    // MARK: - 格式优先级（确保不会误判）

    func testJPEG_NotConfusedWithOtherFormats() {
        // JPEG 头不应被误判为其他格式
        let jpegMinimal = Data([0xFF, 0xD8, 0xFF])
        let info = ImageFormatDetector.detectFormat(fromHeaderData: jpegMinimal)
        XCTAssertEqual(info.fileExtension, "jpg")
    }

    func testWebP_NotConfusedWithRIFFAudio() {
        // RIFF+WAVE 不应被识别为 WebP
        let waveHeader = Data([0x52, 0x49, 0x46, 0x46,
                               0x00, 0x00, 0x00, 0x00,
                               0x57, 0x41, 0x56, 0x45])
        let info = ImageFormatDetector.detectFormat(fromHeaderData: waveHeader)
        XCTAssertNotEqual(info.fileExtension, "webp",
                          "RIFF WAVE 音频不应被识别为 WebP")
    }

    func testFtypBox_NonHEICBrand_DefaultsToPNG() {
        // ftyp 盒子但 brand 是 "isom"（MP4），不应被识别为 HEIC
        let mp4Header = Data([0x00, 0x00, 0x00, 0x20,
                              0x66, 0x74, 0x79, 0x70,
                              0x69, 0x73, 0x6F, 0x6D,  // "isom"
                              0x00, 0x00, 0x00, 0x00])
        let info = ImageFormatDetector.detectFormat(fromHeaderData: mp4Header)
        XCTAssertEqual(info.fileExtension, "png",
                       "非 HEIC/HEIF 品牌的 ftyp 盒子应默认为 PNG")
    }
}
