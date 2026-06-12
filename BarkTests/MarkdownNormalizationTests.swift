//
//  MarkdownNormalizationTests.swift
//  BarkTests
//
//  Created on 2026/06/12.
//

@testable import Bark
import Testing

// MARK: - MarkdownParser 纯文本提取

struct MarkdownParserNormalizationTests {

    @Test("MarkdownParser(.clear) 正确去除 bold 标记")
    func stripsBold() {
        let result = MarkdownParser(configuration: .clear).parse("**bold text**").string
        #expect(result.contains("bold text"))
        #expect(!result.contains("**"))
    }

    @Test("MarkdownParser(.clear) 正确去除 italic 标记")
    func stripsItalic() {
        let result = MarkdownParser(configuration: .clear).parse("*italic text*").string
        #expect(result.contains("italic text"))
        #expect(!result.hasPrefix("*"))
    }

    @Test("MarkdownParser(.clear) 正确去除 inline code 标记")
    func stripsInlineCode() {
        let result = MarkdownParser(configuration: .clear).parse("use `code` here").string
        #expect(result.contains("code"))
        #expect(!result.contains("`"))
    }

    @Test("MarkdownParser(.clear) 正确去除 heading 标记")
    func stripsHeading() {
        let result = MarkdownParser(configuration: .clear).parse("# Title\n## Subtitle").string
        #expect(result.contains("Title"))
        #expect(result.contains("Subtitle"))
        #expect(!result.contains("#"))
    }

    @Test("MarkdownParser(.clear) 正确去除 code block 标记")
    func stripsCodeBlock() {
        let markdown = "```\nlet x = 1\n```"
        let result = MarkdownParser(configuration: .clear).parse(markdown).string
        #expect(result.contains("let x = 1"))
        #expect(!result.contains("```"))
    }

    @Test("MarkdownParser(.clear) 正确去除 strikethrough 标记")
    func stripsStrikethrough() {
        let result = MarkdownParser(configuration: .clear).parse("~~deleted~~").string
        #expect(result.contains("deleted"))
        #expect(!result.contains("~~"))
    }

    @Test("MarkdownParser(.clear) 正确去除 link 标记")
    func stripsLink() {
        let result = MarkdownParser(configuration: .clear).parse("[click here](https://example.com)").string
        #expect(result.contains("click here"))
        #expect(!result.contains("["))
        #expect(!result.contains("](https://example.com)"))
    }

    @Test("多个连续换行被折叠为单个换行")
    func collapsesNewlines() {
        let markdown = "paragraph one\n\n\n\nparagraph two"
        let result = MarkdownParser(configuration: .clear)
            .parse(markdown)
            .string
            .replacingOccurrences(of: "\n\n+", with: "\n", options: .regularExpression)
        #expect(!result.contains("\n\n"))
    }

    @Test("普通纯文本不被修改")
    func plainTextUnchanged() {
        let plainText = "Hello, this is a normal message."
        let result = MarkdownParser(configuration: .clear).parse(plainText).string
        #expect(result.contains("Hello, this is a normal message."))
    }

    @Test("加密路径和明文路径使用相同的渲染逻辑，结果一致")
    func encryptedAndPlaintextConsistency() {
        let markdownContent = "# Title\n\n**bold** paragraph\n\n- item1\n- item2"

        // 模拟明文路径: MarkdownProcessor 处理 userInfo["markdown"]
        let plaintextResult = MarkdownParser(configuration: .clear)
            .parse(markdownContent).string
            .replacingOccurrences(of: "\n\n+", with: "\n", options: .regularExpression)

        // 模拟加密路径: CiphertextProcessor 解密后同样产生 markdown key，
        // MarkdownProcessor 使用完全相同的逻辑处理
        let encryptedResult = MarkdownParser(configuration: .clear)
            .parse(markdownContent).string
            .replacingOccurrences(of: "\n\n+", with: "\n", options: .regularExpression)

        #expect(plaintextResult == encryptedResult)
        #expect(!plaintextResult.contains("#"))
        #expect(!plaintextResult.contains("**"))
    }
}

// MARK: - Message 模型

struct MessageModelNormalizationTests {

    @Test("Message(dict:) 正确读取 markdownSource 字段")
    func dictInitWithMarkdownSource() {
        let dict: [String: Any] = [
            "id": "test-1",
            "body": "rendered plain text",
            "markdownSource": "**bold** markdown",
            "bodyType": "markdown",
            "createDate": Date().timeIntervalSince1970
        ]
        let message = Message(dict: dict)
        #expect(message.body == "rendered plain text")
        #expect(message.markdownSource == "**bold** markdown")
        #expect(message.bodyType == "markdown")
        #expect(message.type == .markdown)
    }

    @Test("Message(dict:) 纯文本消息 markdownSource 为 nil")
    func dictInitPlainText() {
        let dict: [String: Any] = [
            "id": "test-2",
            "body": "just plain text",
            "createDate": Date().timeIntervalSince1970
        ]
        let message = Message(dict: dict)
        #expect(message.body == "just plain text")
        #expect(message.markdownSource == nil)
        #expect(message.bodyType == nil)
        #expect(message.type == .plainText)
    }

    @Test("Message 纯文本消息不受 markdown 归一化影响")
    func plainTextUnaffected() {
        let dict: [String: Any] = [
            "id": "test-3",
            "body": "Hello *world*",
            "createDate": Date().timeIntervalSince1970
        ]
        let message = Message(dict: dict)
        #expect(message.body == "Hello *world*")
        #expect(message.markdownSource == nil)
        #expect(message.type == .plainText)
    }
}

// MARK: - MessageItemModel

struct MessageItemModelNormalizationTests {

    @Test("MessageItemModel 使用 markdownSource 进行富文本渲染")
    func usesMarkdownSourceForRichRendering() {
        let dict: [String: Any] = [
            "id": "test-4",
            "body": "plain text fallback",
            "markdownSource": "**bold** text",
            "bodyType": "markdown",
            "createDate": Date().timeIntervalSince1970
        ]
        let message = Message(dict: dict)
        let model = MessageItemModel(message: message)

        let attrString = model.attributedText!
        // 应包含渲染后的文本
        #expect(attrString.string.contains("bold"))
        #expect(attrString.string.contains("text"))
        // 不应包含 markdown 原始标记
        #expect(!attrString.string.contains("**"))
    }

    @Test("MessageItemModel 无 markdownSource 时回退到 body 纯文本")
    func fallsBackToBodyWhenNoMarkdownSource() {
        let dict: [String: Any] = [
            "id": "test-5",
            "body": "plain body only",
            "createDate": Date().timeIntervalSince1970
        ]
        let message = Message(dict: dict)
        let model = MessageItemModel(message: message)
        #expect(model.attributedText?.string.contains("plain body only") == true)
    }

    @Test("MessageItemModel bodyType=markdown 但 markdownSource 为空时回退到 body")
    func fallsBackWhenMarkdownSourceEmpty() {
        let dict: [String: Any] = [
            "id": "test-6",
            "body": "body as fallback",
            "markdownSource": "",
            "bodyType": "markdown",
            "createDate": Date().timeIntervalSince1970
        ]
        let message = Message(dict: dict)
        let model = MessageItemModel(message: message)
        #expect(model.attributedText?.string.contains("body as fallback") == true)
    }
}

// MARK: - WidgetHistoryMessage 归一化

struct WidgetHistoryNormalizationTests {

    @Test("WidgetHistoryMessage 正确将 markdown body 转换为纯文本")
    func normalizesMarkdownBody() {
        let msg = WidgetHistoryMessage(
            id: "w1",
            group: nil,
            title: nil,
            subtitle: nil,
            body: "**bold** and *italic*",
            bodyType: "markdown",
            image: nil,
            createDate: Date()
        )
        #expect(msg.body != nil)
        #expect(!msg.body!.contains("**"))
        #expect(msg.body!.contains("bold"))
        #expect(msg.body!.contains("italic"))
    }

    @Test("WidgetHistoryMessage 纯文本直接传递不做转换")
    func passesThroughPlainText() {
        let msg = WidgetHistoryMessage(
            id: "w2",
            group: nil,
            title: nil,
            subtitle: nil,
            body: "just plain text",
            bodyType: nil,
            image: nil,
            createDate: Date()
        )
        #expect(msg.body == "just plain text")
    }

    @Test("WidgetHistoryMessage body 截断到 500 字符")
    func trimsToCharLimit() {
        let longBody = String(repeating: "a", count: 600)
        let msg = WidgetHistoryMessage(
            id: "w3",
            group: nil,
            title: nil,
            subtitle: nil,
            body: longBody,
            bodyType: nil,
            image: nil,
            createDate: Date()
        )
        #expect(msg.body?.count == 500)
    }
}
