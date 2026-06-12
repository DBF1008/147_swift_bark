//
//  ServerManager.swift
//  Bark
//
//  Created by huangfeng on 2018/3/21.
//  Copyright © 2018年 Fin. All rights reserved.
//

import RxSwift
import SwiftUI
import UIKit

let defaultServer = "https://api.day.app"

class Server: Codable {
    let id: String
    let address: String
    var key: String
    var state: Client.ClienState
    var name: String?
    
    var host: String {
        return URL(string: address)?.host ?? ""
    }
    
    init(id: String = UUID().uuidString, address: String, key: String, state: Client.ClienState = .ok) {
        self.id = id
        self.address = address
        self.key = key
        self.state = state
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case address
        case key
        case name
    }
    
    // 解码
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        address = try container.decode(String.self, forKey: .address)
        key = try container.decode(String.self, forKey: .key)
        name = try? container.decode(String?.self, forKey: .name)
        state = .ok
    }
}

extension Server {
    /// 规范化服务器地址：去除首尾空白、补全缺失的 scheme、将 scheme/host 转为小写、移除 path 末尾多余的斜杠。
    /// 用于新增与去重，保证同一服务的不同书写形式（末尾斜杠、大小写等）落到同一份配置。
    /// 保留 path 子路径、端口、query、fragment；解析不出 host 的非法地址返回 nil。
    static func normalize(address: String) -> String? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 缺少 scheme 时补全为 https，否则 host 会被 URLComponents 解析进 path。
        let withScheme = trimmed.range(of: "^[a-zA-Z][a-zA-Z0-9+.-]*://", options: .regularExpression) != nil
            ? trimmed
            : "https://" + trimmed

        guard var components = URLComponents(string: withScheme),
              let host = components.host, !host.isEmpty
        else {
            return nil
        }

        components.scheme = components.scheme?.lowercased()
        components.host = host.lowercased()

        // 移除 path 末尾多余的斜杠（根路径归为空），使 .../bark 与 .../bark/ 等价。
        var path = components.path
        while path.hasSuffix("/") {
            path.removeLast()
        }
        components.path = path

        return components.string
    }
}

class ServerManager: NSObject {
    static let shared = ServerManager()
    override private init() {
        if let servers: [Server] = Settings[.servers] {
            self.servers = servers
        }

        if servers.count <= 0 {
            servers = [Server(id: UUID().uuidString, address: defaultServer, key: "")]
        }
        self.currentServer = servers[0]

        super.init()

        // 将老版本数据转换成新版本
        if let key = Settings[.key] {
            let address = Settings[.currentServer] ?? defaultServer
            let server = Server(id: UUID().uuidString, address: address, key: key)

            self.servers = []
            self.addServer(server: server)

            Settings[.currentServerId] = server.id

            // 清空老版本数据
            Settings[.currentServer] = nil
            Settings[.key] = nil
        }

        if let currentServerId = Settings[.currentServerId] {
            self.setCurrentServer(serverId: currentServerId)
        }
    }

    /// 所有的 server
    var servers: [Server] = []
    /// 当前选中的 server ，在教程页显示。
    private(set) var currentServer: Server

    /// 更改当前选中的 server
    func setCurrentServer(serverId: String) {
        if let server = servers.first(where: { $0.id == serverId }) {
            currentServer = server
        } else {
            currentServer = servers.first!
        }
        Settings[.currentServerId] = serverId
    }

    /// 添加新的 server。
    /// 地址会先经过规范化；若已存在相同规范化地址的 server，则不重复添加，直接返回该已存在的 server
    /// （保留其 id / key / name）。这样手输、扫码、深链接三条录入路径都落在同一份去重后的配置上。
    /// - Returns: 实际生效的 server —— 新增的那个，或命中去重的已存在 server。
    @discardableResult
    func addServer(server: Server) -> Server {
        let normalizedAddress = Server.normalize(address: server.address) ?? server.address

        // 去重键为规范化地址（服务身份是地址，不含 key）。
        if let existing = self.servers.first(where: {
            (Server.normalize(address: $0.address) ?? $0.address) == normalizedAddress
        }) {
            return existing
        }

        // address 不可变，需用规范化后的地址新建对象，沿用原 id。
        let normalizedServer = Server(id: server.id, address: normalizedAddress, key: server.key, state: server.state)
        normalizedServer.name = server.name
        self.servers.append(normalizedServer)
        saveServers()
        return normalizedServer
    }

    func updateServerKey(server: Server) {
        let foundServer = self.servers.first { $0.id == server.id }
        foundServer?.key = server.key
        saveServers()
    }
    
    /// 移除 server，移除后如果 server 为`空`, `会新增一个默认server`
    func removeServer(server: Server) {
        self.servers.removeAll { $0.id == server.id }
        if self.servers.count <= 0 {
            self.servers.append(
                Server(id: UUID().uuidString, address: defaultServer, key: "")
            )
        }
        if self.currentServer.id == server.id {
            self.setCurrentServer(serverId: self.servers[0].id)
        }
        saveServers()
    }

    /// 保存 servers
    func saveServers() {
        Settings[.servers] = self.servers
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var dispose: Disposable?
    /// 同步所有 server
    func syncAllServers() {
        guard let token = Client.shared.deviceToken.value, token.count > 0 else {
            return
        }
        dispose?.dispose()

        let apis = servers.map { server in
            BarkApi.provider.request(
                .register(
                    address: server.address,
                    key: server.key,
                    devicetoken: token
                ))
                .filterResponseError()
                .map { result -> (Server, String, Client.ClienState) in

                    switch result {
                    case .success(let json):
                        if let key = json["data", "key"].rawString() {
                            return (server, key, .ok)
                        } else {
                            return (server, "", .serverError(error: .Error(info: "key not found")))
                        }
                    case .failure(let error):
                        return (server, "", .serverError(error: error))
                    }
                }.catch { error in
                    Observable.just((server, "", .serverError(error: .Error(info: error.localizedDescription))))
                }
        }

        dispose = Observable
            .merge(apis)
            .subscribe { result in
                // 更新所有的 server 状态
                if result.2 == .ok {
                    result.0.key = result.1
                }
                result.0.state = result.2

                // 通知客户端 当前 server 状态改变
                if result.0.id == self.currentServer.id {
                    Client.shared.state.accept(result.2)
                }
            } onError: { _ in

            } onCompleted: {
                self.saveServers()
            }
    }
    
    func setServerName(server: Server, name: String?) {
        server.name = name
        saveServers()
    }
}
