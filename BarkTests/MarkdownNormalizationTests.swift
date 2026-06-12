//
//  MarkdownNormalizationTests.swift
//  BarkTests
//
//  Markdown 正文归一化回归测试。
//
//  覆盖「通知处理 → 归档 → 小组件快照」整条正文链路的归一化契约：
//  1. Markdown 原文只保留在 `Message.body`（配合 `bodyType == .markdown`），供应用内列表富文本重渲染；
//  2. 通知横幅、小组件快照等展示链路统一使用 `MarkdownParser.displayPlainText` 产出的一致可读文本；
//  3. 普通文本消息全程原样透传，不被 Markdown 解析破坏；
//  4. 横幅链路与小组件链路对同一 Markdown 产出完全相同的纯文本（明文 / 密文同理，均走同一入口）。
//
//  说明：NotificationServiceExtension 中的 MarkdownProcessor / ArchiveProcessor 受 target 隔离
//  无法在主 App 测试 target 内直接实例化，但二者的归一化已收口到 `MarkdownParser.displayPlainText`，
//  归档写入的字段契约亦由 `Message(dict:)` 在此覆盖，因此核心行为在本测试中得到锁定。

@testable import Bark
import Testing
import UIKit

struct MarkdownNormalizationTests {

    // MARK: - 单一可信源：MarkdownParser.displayPlainText

    @Test("归一化为纯文本：去除粗体 / 斜体标记")
    func plainText_strips_emphasis() {
        let result = MarkdownParser.displayPlainText(fromMarkdown: "这是 **加粗** 和 *斜体* 文本")
        #expect(!result.contains("**"))
        #expect(!result.contains("*"))
        #expect(result.contains("加粗"))
        #expect(result.contains("斜体"))
    }

    @Test("归一化为纯文本：标题去除 # 标记")
    func plainText_strips_heading() {
        let result = MarkdownParser.displayPlainText(fromMarkdown: "# 标题\n正文")
        #expect(!result.contains("#"))
        #expect(result.contains("标题"))
        #expect(result.contains("正文"))
    }

    @Test("归一化为纯文本：链接只保留可读文本，去除 URL 与语法符号")
    func plainText_strips_link_syntax() {
        let result = MarkdownParser.displayPlainText(fromMarkdown: "点击 [这里](https://example.com) 查看")
        #expect(!result.contains("]("))
        #expect(!result.contains("https://example.com"))
        #expect(result.contains("这里"))
    }

    @Test("归一化为纯文本：行内代码去除反引号")
    func plainText_strips_inline_code() {
        let result = MarkdownParser.displayPlainText(fromMarkdown: "运行 `pod install` 命令")
        #expect(!result.contains("`"))
        #expect(result.contains("pod install"))
    }

    @Test("归一化为纯文本：无序列表不残留原始 - 标记")
    func plainText_strips_list_markers() {
        let result = MarkdownParser.displayPlainText(fromMarkdown: "- 第一项\n- 第二项")
        #expect(result.contains("第一项"))
        #expect(result.contains("第二项"))
        #expect(!result.contains("- 第一项"))
    }

    @Test("归一化为纯文本：多余空行折叠为单个换行")
    func plainText_collapses_blank_lines() {
        let result = MarkdownParser.displayPlainText(fromMarkdown: "第一段\n\n\n\n第二段")
        #expect(!result.contains("\n\n"))
        #expect(result.contains("第一段"))
        #expect(result.contains("第二段"))
    }

    // MARK: - 小组件快照归一化：WidgetHistoryMessage

    @Test("小组件快照：markdown 消息的 body 被归一化为纯文本")
    func widget_markdown_body_is_normalized() {
        let item = WidgetHistoryMessage(
            id: "m1", group: nil, title: "标题", subtitle: nil,
            body: "**重点**通知", bodyType: Message.BodyType.markdown.rawValue,
            image: nil, createDate: Date()
        )
        #expect(item.body == "重点通知")
        #expect(!(item.body ?? "").contains("**"))
    }

    @Test("小组件快照：bodyType 为 nil 的普通文本原样保留，不被 Markdown 解析破坏")
    func widget_plaintext_body_is_untouched() {
        // 含有会被 Markdown 误解析的字符（* _ #），普通文本必须原样保留
        let raw = "价格 *特惠* 5_000 元 #1"
        let item = WidgetHistoryMessage(
            id: "m2", group: nil, title: nil, subtitle: nil,
            body: raw, bodyType: nil,
            image: nil, createDate: Date()
        )
        #expect(item.body == raw)
    }

    @Test("小组件快照：bodyType 为 plainText 时同样原样保留")
    func widget_explicit_plaintext_is_untouched() {
        let raw = "**这不是加粗**"
        let item = WidgetHistoryMessage(
            id: "m3", group: nil, title: nil, subtitle: nil,
            body: raw, bodyType: Message.BodyType.plainText.rawValue,
            image: nil, createDate: Date()
        )
        #expect(item.body == raw)
    }

    @Test("小组件快照：从 Realm Message 构造时对 markdown 归一化")
    func widget_from_message_normalizes_markdown() {
        let message = Message()
        message.id = "m4"
        message.body = "**加粗**正文"
        message.bodyType = Message.BodyType.markdown.rawValue
        message.createDate = Date()

        let item = WidgetHistoryMessage(message: message)
        #expect(item.body == "加粗正文")
    }

    @Test("小组件快照：从普通文本 Message 构造时原样保留")
    func widget_from_message_keeps_plaintext() {
        let message = Message()
        message.id = "m5"
        message.body = "普通 *文本*"
        message.bodyType = nil
        message.createDate = Date()

        let item = WidgetHistoryMessage(message: message)
        #expect(item.body == "普通 *文本*")
    }

    // MARK: - 归档数据契约：原文只存 Realm.body，供富文本重渲染

    @Test("归档契约：markdown 消息在 Message 中保留原文 + bodyType")
    func archive_keeps_raw_markdown_in_message() {
        // 模拟 ArchiveProcessor 写入 plist 的字典：body 存原始 markdown，bodyType 标记为 markdown
        let dict: [String: Any] = [
            "id": "m6",
            "body": "**原始** markdown",
            "bodyType": "markdown",
            "createDate": Date().timeIntervalSince1970
        ]
        let message = Message(dict: dict)
        // 原文必须原样保留：应用内列表需要它重新渲染富文本
        #expect(message.body == "**原始** markdown")
        #expect(message.type == .markdown)
    }

    @Test("归档契约：未带 bodyType 的普通文本消息 type 为 plainText")
    func archive_plaintext_message_type() {
        let dict: [String: Any] = [
            "id": "m7",
            "body": "普通文本",
            "createDate": Date().timeIntervalSince1970
        ]
        let message = Message(dict: dict)
        #expect(message.type == .plainText)
        #expect(message.body == "普通文本")
    }

    // MARK: - 应用内列表：markdown 渲染为富文本（不含字面标记），普通文本原样

    @Test("应用内列表：markdown 消息渲染为富文本，纯文本里不含字面标记")
    func messageItem_markdown_rendered_without_literal_markup() {
        let message = Message()
        message.id = "m8"
        message.body = "**加粗**内容"
        message.bodyType = Message.BodyType.markdown.rawValue
        message.createDate = Date()

        let model = MessageItemModel(message: message)
        let plain = model.attributedText?.string ?? ""
        #expect(plain.contains("加粗"))
        #expect(!plain.contains("**"))
    }

    @Test("应用内列表：普通文本消息内容原样展示")
    func messageItem_plaintext_preserved() {
        let message = Message()
        message.id = "m9"
        message.body = "普通 **不渲染** 文本"
        message.bodyType = nil
        message.createDate = Date()

        let model = MessageItemModel(message: message)
        let plain = model.attributedText?.string ?? ""
        #expect(plain.contains("普通 **不渲染** 文本"))
    }

    // MARK: - 一致性：横幅链路与小组件链路得到完全相同的可读文本

    @Test("一致性：通知横幅与小组件快照对同一 markdown 产出相同纯文本")
    func banner_and_widget_produce_identical_plaintext() {
        // 单段落、首尾无空白，规避小组件 trimmedForWidget 的边界差异，专注验证标记去除逻辑一致
        let raw = "**加粗** 与 [链接](https://example.com) 和 `代码`"

        // 横幅链路：MarkdownProcessor 现在调用的同一归一化入口
        let bannerText = MarkdownParser.displayPlainText(fromMarkdown: raw)

        // 小组件链路：markdown body 经带 bodyType 的归一化构造器
        let widgetItem = WidgetHistoryMessage(
            id: "m10", group: nil, title: nil, subtitle: nil,
            body: raw, bodyType: Message.BodyType.markdown.rawValue,
            image: nil, createDate: Date()
        )

        #expect(widgetItem.body == bannerText)
        #expect(!bannerText.contains("**"))
    }
}
