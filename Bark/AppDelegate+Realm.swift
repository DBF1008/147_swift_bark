//
//  AppDelegate+Realm.swift
//  Bark
//
//  Created by huangfeng on 12/18/25.
//  Copyright © 2025 Fin. All rights reserved.
//

import UIKit

private let pendingMessageProcessingQueue = DispatchQueue(label: "me.fin.bark.pending-message-processing", qos: .userInitiated)
let kBarkMessagesDidChangeNotification = Notification.Name("com.bark.messagesDidChange")

extension AppDelegate {
    /*
     之前数据库是放在App Groups 共享
     但由于Realm无法解决 0xdead10cc 闪退问题
     因此改为在主APP中存放数据库文件
     Notification Service Extension 使用 plist 文件保存消息，供主APP读取存放到数据库中
     */
    func setupRealm() {
        // 先执行数据库迁移
        migrateRealmDatabase()
        
        // Tell Realm to use this new configuration object for the default Realm
        Realm.Configuration.defaultConfiguration = kRealmDefaultConfiguration
    }

    func migrateRealmDatabase() {
        // 检查是否已经迁移过
        if UserDefaults.standard.bool(forKey: "hasRealmMigrated") {
            return
        }
        
        let fileManager = FileManager.default
        guard let oldGroupUrl = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.bark"),
              let newDocUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        else {
            return
        }
        
        let oldRealmUrl = oldGroupUrl.appendingPathComponent("bark.realm")
        let newRealmUrl = newDocUrl.appendingPathComponent("bark.realm")
        
        // 检查旧文件是否存在
        guard fileManager.fileExists(atPath: oldRealmUrl.path) else {
            // 旧文件不存在，标记为已迁移
            UserDefaults.standard.set(true, forKey: "hasRealmMigrated")
            return
        }
        
        do {
            // 复制主数据库文件
            try fileManager.copyItem(at: oldRealmUrl, to: newRealmUrl)
            
            // 复制相关文件
            let relatedFiles = ["bark.realm.lock", "bark.realm.management", "bark.realm.note"]
            for file in relatedFiles {
                let oldUrl = oldGroupUrl.appendingPathComponent(file)
                let newUrl = newDocUrl.appendingPathComponent(file)
                if fileManager.fileExists(atPath: oldUrl.path) {
                    try? fileManager.copyItem(at: oldUrl, to: newUrl)
                }
            }
            
            // 删除旧文件
            try fileManager.removeItem(at: oldRealmUrl)
            for file in relatedFiles {
                let oldUrl = oldGroupUrl.appendingPathComponent(file)
                try? fileManager.removeItem(at: oldUrl)
            }
            
            // 标记为已迁移
            UserDefaults.standard.set(true, forKey: "hasRealmMigrated")
        } catch {
            // 迁移失败，弹出提示
            DispatchQueue.main.async {
                let alert = UIAlertController(
                    title: "Migration Failed",
                    message: "Failed to migrate database file. Please contact support.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.window?.rootViewController?.present(alert, animated: true)
            }
        }
    }
    
    /// 处理 Notification Service Extension 保存的待处理消息, 将其存入 Realm 数据库
    ///
    /// 使用 `PendingMessageImporter` 进行容错导入:
    /// - 仅在消息成功入库后才删除对应的 plist 文件
    /// - 已过期消息的 plist 文件会被清理
    /// - 不可解析的文件在宽限期 (7天) 过后才会被清理，未超期的保留重试
    /// - 批量写入失败时自动回退为逐条写入，避免一条坏消息拖垮整批
    func processPendingMessages() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pendingMessageProcessingQueue.async {
                defer { continuation.resume() }

                guard let groupUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.bark") else {
                    return
                }

                let realm = try? Realm()
                let pendingDir = groupUrl.appendingPathComponent("pending_messages")

                let importer = PendingMessageImporter(
                    realm: realm,
                    pendingDir: pendingDir
                )
                let result = importer.process()

                if result.didChange {
                    WidgetHistorySnapshotStore.shared.refreshFromRealmAsync()
                    self.notifyMessagesDidChange()
                }
            }
        }
    }
    
    func notifyMessagesDidChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: kBarkMessagesDidChangeNotification, object: nil)
        }
    }
}
