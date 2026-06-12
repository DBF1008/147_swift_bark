//
//  String+Extension.swift
//  Bark
//
//  Created by huangfeng on 2018/6/26.
//  Copyright © 2018 Fin. All rights reserved.
//

import UIKit

extension String {

    /// 将服务器地址规范化为统一格式，用于去重和比较。
    /// - 去除首尾空白和换行
    /// - 无 scheme 时默认补 `https://`
    /// - scheme 和 host 转小写
    /// - 去除末尾多余的 `/`
    /// - 去除默认端口（http :80, https :443）
    func normalizedServerAddress() -> String {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        // 如果没有 scheme，先补上 https:// 再解析
        var urlString = trimmed
        if !urlString.lowercased().hasPrefix("http://") && !urlString.lowercased().hasPrefix("https://") {
            urlString = "https://" + urlString
        }

        guard var components = URLComponents(string: urlString) else {
            return trimmed
        }

        // scheme 和 host 转小写
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()

        // 去除默认端口
        if let port = components.port {
            if (components.scheme == "https" && port == 443) ||
               (components.scheme == "http" && port == 80) {
                components.port = nil
            }
        }

        // 去除 path 末尾多余的 `/`，空 path 置为空字符串
        var path = components.path
        if !path.isEmpty {
            while path.count > 1 && path.hasSuffix("/") {
                path = String(path.dropLast())
            }
            if path == "/" {
                components.path = ""
            } else {
                components.path = path
            }
        }

        return components.string ?? trimmed
    }

    // 将原始的url编码为合法的url
    func urlEncoded() -> String {
        let encodeUrlString = self.addingPercentEncoding(withAllowedCharacters:
            .urlQueryAllowed)
        return encodeUrlString ?? ""
    }

    // 将编码后的url转换回原始的url
    func urlDecoded() -> String {
        return self.removingPercentEncoding ?? ""
    }
}

// MARK: - NSAttributedString

extension String {
    var bold: NSAttributedString {
        return NSMutableAttributedString(string: self, attributes: [.font: UIFont.boldSystemFont(ofSize: UIFont.systemFontSize)])
    }

    var underline: NSAttributedString {
        return NSAttributedString(string: self, attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue])
    }

    var strikethrough: NSAttributedString {
        return NSAttributedString(string: self, attributes: [.strikethroughStyle: NSNumber(value: NSUnderlineStyle.single.rawValue as Int)])
    }

    var italic: NSAttributedString {
        return NSMutableAttributedString(string: self, attributes: [.font: UIFont.italicSystemFont(ofSize: UIFont.systemFontSize)])
    }

    func colored(with color: UIColor) -> NSAttributedString {
        return NSMutableAttributedString(string: self, attributes: [.foregroundColor: color])
    }
}

// MARK: - Format

extension String {
    func format(_ arguments: any CVarArg...) -> String {
        return String(format: self, arguments)
    }
}

extension String {
    var localized: String {
        return NSLocalizedString(self, comment: "")
    }
    
    func localized(with arguments: CVarArg...) -> String {
        return String(format: NSLocalizedString(self, comment: ""), arguments: arguments)
    }
}
