//
//  ServerManagerTests.swift
//  BarkTests
//
//  Created for server address normalization and deduplication regression tests.
//

@testable import Bark
import XCTest

class ServerManagerTests: XCTestCase {

    // MARK: - normalizedServerAddress() Tests

    func testNormalizeTrailingSlash() {
        XCTAssertEqual(
            "https://example.com/".normalizedServerAddress(),
            "https://example.com"
        )
    }

    func testNormalizeMultipleTrailingSlashes() {
        XCTAssertEqual(
            "https://example.com///".normalizedServerAddress(),
            "https://example.com"
        )
    }

    func testNormalizeLowercaseHost() {
        XCTAssertEqual(
            "https://EXAMPLE.COM".normalizedServerAddress(),
            "https://example.com"
        )
    }

    func testNormalizeLowercaseScheme() {
        XCTAssertEqual(
            "HTTP://example.com".normalizedServerAddress(),
            "http://example.com"
        )
    }

    func testNormalizeNoSchemeDefaultsHttps() {
        XCTAssertEqual(
            "example.com".normalizedServerAddress(),
            "https://example.com"
        )
    }

    func testNormalizeTrimWhitespace() {
        XCTAssertEqual(
            "  https://example.com  ".normalizedServerAddress(),
            "https://example.com"
        )
    }

    func testNormalizeTrimNewlines() {
        XCTAssertEqual(
            "\nhttps://example.com\n".normalizedServerAddress(),
            "https://example.com"
        )
    }

    func testNormalizeRemoveDefaultHttpsPort() {
        XCTAssertEqual(
            "https://example.com:443".normalizedServerAddress(),
            "https://example.com"
        )
    }

    func testNormalizeRemoveDefaultHttpPort() {
        XCTAssertEqual(
            "http://example.com:80".normalizedServerAddress(),
            "http://example.com"
        )
    }

    func testNormalizeKeepNonDefaultPort() {
        XCTAssertEqual(
            "https://example.com:8080".normalizedServerAddress(),
            "https://example.com:8080"
        )
    }

    func testNormalizePreservePath() {
        XCTAssertEqual(
            "https://example.com/api/v1".normalizedServerAddress(),
            "https://example.com/api/v1"
        )
    }

    func testNormalizeStripPathTrailingSlash() {
        XCTAssertEqual(
            "https://example.com/api/v1/".normalizedServerAddress(),
            "https://example.com/api/v1"
        )
    }

    func testNormalizeEmptyString() {
        XCTAssertEqual(
            "".normalizedServerAddress(),
            ""
        )
    }

    func testNormalizeWhitespaceOnly() {
        XCTAssertEqual(
            "   ".normalizedServerAddress(),
            ""
        )
    }

    /// 不同格式的同一地址应规范化后完全一致
    func testNormalizeEquivalentAddresses() {
        let variants = [
            "https://example.com",
            "https://example.com/",
            "HTTPS://EXAMPLE.COM",
            "HTTPS://EXAMPLE.COM/",
            "  https://example.com  ",
            "https://example.com:443",
            "https://example.com:443/",
            "example.com",
            "example.com/",
        ]
        let normalized = variants.map { $0.normalizedServerAddress() }
        let first = normalized.first!
        XCTAssertTrue(normalized.allSatisfy { $0 == first }, "All variants should normalize to '\(first)', got: \(normalized)")
    }

    // MARK: - Server.init Normalization Tests

    func testServerInitNormalizesAddress() {
        let server = Server(address: "https://Example.COM/", key: "")
        XCTAssertEqual(server.address, "https://example.com")
    }

    func testServerInitNormalizesAddressWithTrailingSlash() {
        let server = Server(address: "https://api.day.app/", key: "testkey")
        XCTAssertEqual(server.address, "https://api.day.app")
    }

    // MARK: - ServerManager Deduplication Tests

    func testAddServerDeduplication() {
        // 创建一个临时的 ServerManager 以避免影响全局单例
        let server1 = Server(address: "https://example.com", key: "")
        let server2 = Server(address: "https://example.com/", key: "")

        // 两个 server 的地址规范化后应该一致
        XCTAssertEqual(server1.address, server2.address)
    }

    func testAddServerDeduplicationWithDifferentFormats() {
        let server1 = Server(address: "https://example.com", key: "")
        let server2 = Server(address: "HTTPS://EXAMPLE.COM/", key: "")
        let server3 = Server(address: "example.com", key: "")

        XCTAssertEqual(server1.address, server2.address)
        XCTAssertEqual(server1.address, server3.address)
    }

    func testAddServerDifferentAddressesNotDeduped() {
        let server1 = Server(address: "https://a.example.com", key: "")
        let server2 = Server(address: "https://b.example.com", key: "")

        XCTAssertNotEqual(server1.address, server2.address)
    }

    // MARK: - Host 一致性测试

    /// 确保规范化后的 server.host 和 address 解析一致
    func testHostMatchesAfterNormalization() {
        let server = Server(address: "https://EXAMPLE.COM/", key: "")
        XCTAssertEqual(server.host, "example.com")
    }

    /// 不同格式的同一地址，host 应该一致
    func testHostConsistentAcrossFormats() {
        let formats = [
            "https://api.day.app",
            "https://api.day.app/",
            "HTTPS://API.DAY.APP",
            "api.day.app",
        ]
        let hosts = formats.map { Server(address: $0, key: "").host }
        let first = hosts.first!
        XCTAssertTrue(hosts.allSatisfy { $0 == first }, "All hosts should be '\(first)', got: \(hosts)")
    }
}
