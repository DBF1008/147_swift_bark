//
//  MessageImportTests.swift
//  BarkTests
//
//  历史消息导入（restore）核心逻辑的回归测试：
//  覆盖过期过滤、已有记录覆盖、库内过期清理，以及返回值（是否触发刷新）的契约。
//
@testable import Bark
import RealmSwift
import Testing

struct MessageImportTests {
    /// 每个用例使用唯一 inMemoryIdentifier 隔离，并显式声明 objectTypes，避免与默认库 / schema 干扰。
    /// 返回的 Realm 必须由调用方全程持有强引用，否则内存库在无持有者时数据会被回收。
    private func makeRealm() throws -> Realm {
        let config = Realm.Configuration(
            inMemoryIdentifier: UUID().uuidString,
            objectTypes: [Message.self]
        )
        return try Realm(configuration: config)
    }

    /// 构造未托管的 Message（贴近 `Message(json:)` 解析得到的对象）。
    private func makeMessage(
        id: String,
        title: String? = nil,
        createDate: Date = Date(),
        expireDate: Date? = nil
    ) -> Message {
        let message = Message()
        message.id = id
        message.title = title
        message.createDate = createDate
        message.expireDate = expireDate
        return message
    }

    // 用例 1：空库导入多条未过期消息，全部入库，返回 true
    @Test("空库导入未过期消息全部入库并触发刷新")
    func importFreshMessagesIntoEmptyRealm() throws {
        let realm = try makeRealm()
        let now = Date()

        let changed = realm.importMessages([
            makeMessage(id: "a", createDate: now),
            makeMessage(id: "b", createDate: now, expireDate: now.addingTimeInterval(3600))
        ], now: now)

        #expect(changed == true)
        #expect(realm.objects(Message.self).count == 2)
    }

    // 用例 2：导入同 id 记录覆盖已有，条数不增、字段被更新
    @Test("导入同 id 记录覆盖已有且不增加条数")
    func importOverwritesExistingRecord() throws {
        let realm = try makeRealm()
        let now = Date()
        try realm.write {
            realm.add(makeMessage(id: "x", title: "old", createDate: now))
        }

        let changed = realm.importMessages([
            makeMessage(id: "x", title: "new", createDate: now)
        ], now: now)

        #expect(changed == true)
        #expect(realm.objects(Message.self).count == 1)
        #expect(realm.object(ofType: Message.self, forPrimaryKey: "x")?.title == "new")
    }

    // 用例 3：导入数据中已过期的条目不入库
    @Test("导入数据中已过期的消息被过滤不入库")
    func expiredMessagesAreFilteredOut() throws {
        let realm = try makeRealm()
        let now = Date()

        let changed = realm.importMessages([
            makeMessage(id: "fresh", createDate: now),
            makeMessage(id: "expired", createDate: now, expireDate: now.addingTimeInterval(-1))
        ], now: now)

        #expect(changed == true)
        #expect(realm.objects(Message.self).count == 1)
        #expect(realm.object(ofType: Message.self, forPrimaryKey: "fresh") != nil)
        #expect(realm.object(ofType: Message.self, forPrimaryKey: "expired") == nil)
    }

    // 用例 4：导入时清理库内既有的过期记录
    @Test("导入时清理库内既有的过期记录")
    func importPurgesExistingExpiredRecords() throws {
        let realm = try makeRealm()
        let now = Date()
        try realm.write {
            realm.add(makeMessage(id: "old-expired", createDate: now, expireDate: now.addingTimeInterval(-10)))
        }

        let changed = realm.importMessages([
            makeMessage(id: "new", createDate: now)
        ], now: now)

        #expect(changed == true)
        #expect(realm.objects(Message.self).count == 1)
        #expect(realm.object(ofType: Message.self, forPrimaryKey: "new") != nil)
        #expect(realm.object(ofType: Message.self, forPrimaryKey: "old-expired") == nil)
    }

    // 用例 5：没有新增但库内有过期需清理时，返回 true 并删除过期
    @Test("仅需清理过期时返回 true 并删除过期记录")
    func pureCleanupReturnsTrue() throws {
        let realm = try makeRealm()
        let now = Date()
        try realm.write {
            realm.add(makeMessage(id: "exp", createDate: now, expireDate: now.addingTimeInterval(-5)))
        }

        let changed = realm.importMessages([], now: now)

        #expect(changed == true)
        #expect(realm.objects(Message.self).count == 0)
    }

    // 用例 6：导入全为过期、库内也无过期可清理时，返回 false 且什么都不写
    @Test("全过期导入且无过期可清理时返回 false 不触发刷新")
    func noChangeReturnsFalse() throws {
        let realm = try makeRealm()
        let now = Date()
        try realm.write {
            realm.add(makeMessage(id: "keep", createDate: now))
        }

        let changed = realm.importMessages([
            makeMessage(id: "all-expired", createDate: now, expireDate: now.addingTimeInterval(-1))
        ], now: now)

        #expect(changed == false)
        #expect(realm.objects(Message.self).count == 1)
        #expect(realm.object(ofType: Message.self, forPrimaryKey: "keep") != nil)
    }

    // 用例 7：同一批内重复 id，最终只保留一条，取后者的值
    @Test("批内重复 id 最终只保留一条且取后者")
    func duplicateIdsInBatchKeepLast() throws {
        let realm = try makeRealm()
        let now = Date()

        let changed = realm.importMessages([
            makeMessage(id: "dup", title: "first", createDate: now),
            makeMessage(id: "dup", title: "second", createDate: now)
        ], now: now)

        #expect(changed == true)
        #expect(realm.objects(Message.self).count == 1)
        #expect(realm.object(ofType: Message.self, forPrimaryKey: "dup")?.title == "second")
    }

    // 用例 8（边界）：导入一条未过期记录覆盖库内同 id 的过期记录，
    // 验证“先 add 后 delete + 实时 Results”不会把这条已更新为未过期的记录误删。
    @Test("导入未过期记录覆盖库内同 id 过期记录时该记录被更新保留")
    func importRefreshesExistingExpiredWithSameId() throws {
        let realm = try makeRealm()
        let now = Date()
        try realm.write {
            realm.add(makeMessage(id: "x", title: "old", createDate: now, expireDate: now.addingTimeInterval(-100)))
        }

        let future = now.addingTimeInterval(3600)
        let changed = realm.importMessages([
            makeMessage(id: "x", title: "new", createDate: now, expireDate: future)
        ], now: now)

        #expect(changed == true)
        #expect(realm.objects(Message.self).count == 1)
        let object = realm.object(ofType: Message.self, forPrimaryKey: "x")
        #expect(object != nil)
        #expect(object?.title == "new")
        // 该记录现在应为未过期状态（不被误删，且 expireDate 已更新到未来）
        #expect((object?.expireDate ?? .distantPast) > now)
    }
}
