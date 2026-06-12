//
//  ServerManagerTests.swift
//  BarkTests
//
//  地址规范化与去重的回归测试：保证同一服务的不同书写形式（末尾斜杠、大小写、缺 scheme）
//  落到同一份配置，且新增后「当前服务」与实际注册地址一致。
//

@testable import Bark
import XCTest

class ServerManagerTests: XCTestCase {
    // 保存测试前的全局状态，结束后恢复，避免污染真实存储（ServerManager 为单例 + 读写 UserDefaults）。
    private var savedServers: [Server]?
    private var savedCurrentServerId: String?

    override func setUpWithError() throws {
        savedServers = Settings[.servers]
        savedCurrentServerId = Settings[.currentServerId]
        ServerManager.shared.servers = []
    }

    override func tearDownWithError() throws {
        Settings[.servers] = savedServers
        Settings[.currentServerId] = savedCurrentServerId
        ServerManager.shared.servers = savedServers ?? []
    }

    // MARK: - Server.normalize（纯函数）

    func testNormalizeTrailingSlashIsEquivalent() {
        XCTAssertEqual(
            Server.normalize(address: "https://example.com/"),
            Server.normalize(address: "https://example.com")
        )
        XCTAssertEqual(Server.normalize(address: "https://example.com/"), "https://example.com")
    }

    func testNormalizeLowercasesSchemeAndHost() {
        XCTAssertEqual(Server.normalize(address: "HTTPS://Example.COM"), "https://example.com")
    }

    func testNormalizePreservesSubPathButTrimsTrailingSlash() {
        XCTAssertEqual(Server.normalize(address: "https://example.com/bark/"), "https://example.com/bark")
        // 不同子路径不能被视为同一服务（不过度去重）
        XCTAssertNotEqual(
            Server.normalize(address: "https://example.com/bark"),
            Server.normalize(address: "https://example.com/api")
        )
    }

    func testNormalizeAddsMissingScheme() {
        XCTAssertEqual(Server.normalize(address: "example.com"), "https://example.com")
    }

    func testNormalizePreservesPort() {
        XCTAssertEqual(Server.normalize(address: "https://example.com:8080/"), "https://example.com:8080")
    }

    func testNormalizeTrimsWhitespace() {
        XCTAssertEqual(Server.normalize(address: "  https://example.com/  "), "https://example.com")
    }

    func testNormalizeReturnsNilForInvalidInput() {
        XCTAssertNil(Server.normalize(address: ""))
        XCTAssertNil(Server.normalize(address: "   "))
    }

    // MARK: - addServer 去重

    func testAddServerDeduplicatesEquivalentAddresses() {
        let first = ServerManager.shared.addServer(server: Server(address: "https://example.com", key: ""))
        let second = ServerManager.shared.addServer(server: Server(address: "https://example.com/", key: ""))

        XCTAssertEqual(ServerManager.shared.servers.count, 1, "等价地址不应产生第二条记录")
        XCTAssertEqual(first.id, second.id, "命中去重时应返回已存在的同一 server")
        XCTAssertTrue(first === second)
    }

    func testAddServerStoresNormalizedAddress() {
        let saved = ServerManager.shared.addServer(server: Server(address: "HTTPS://Example.COM/", key: ""))
        XCTAssertEqual(saved.address, "https://example.com")
        // 返回的对象与列表中的对象是同一引用，保证展示/列表/注册读到同一份配置
        XCTAssertTrue(ServerManager.shared.servers.first === saved)
    }

    func testAddServerKeepsDistinctSubPaths() {
        ServerManager.shared.addServer(server: Server(address: "https://example.com/bark", key: ""))
        ServerManager.shared.addServer(server: Server(address: "https://example.com/api", key: ""))
        XCTAssertEqual(ServerManager.shared.servers.count, 2, "不同子路径应保留为两条记录")
    }

    // MARK: - 当前服务一致性（id 陷阱回归）

    /// 复现并验证修复：录入链路在 addServer 后必须用「返回值的 id」切换当前服务。
    /// 若去重命中已存在记录而仍用本地新建对象的 id，setCurrentServer 会回退到 servers.first，
    /// 导致「当前服务」与实际注册目标对不上。
    func testCurrentServerConsistentAfterDedup() {
        let first = ServerManager.shared.addServer(server: Server(address: "https://example.com/", key: ""))
        ServerManager.shared.setCurrentServer(serverId: first.id)

        let second = ServerManager.shared.addServer(server: Server(address: "https://example.com", key: ""))
        ServerManager.shared.setCurrentServer(serverId: second.id)

        XCTAssertEqual(ServerManager.shared.servers.count, 1)
        XCTAssertEqual(ServerManager.shared.currentServer.id, first.id)
        XCTAssertEqual(ServerManager.shared.currentServer.address, "https://example.com")
        XCTAssertTrue(ServerManager.shared.currentServer === ServerManager.shared.servers.first)
    }
}
