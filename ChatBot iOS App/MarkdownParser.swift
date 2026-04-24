import SwiftUI

/// 极简 Markdown 解析器 - 纯文本转换
struct MarkdownParser {
    
    // Cached Regex Instances
    private static let titleRegex = try! NSRegularExpression(pattern: "(\\n|^)(#+\\s)(.*?)(\\n|$)", options: [])
    private static let quoteRegex = try! NSRegularExpression(pattern: "(\\n|^)(>\\s?)(.*?)(\\n|$)", options: [])
    private static let summaryRegex = try! NSRegularExpression(pattern: "<summary>(.*)", options: [.caseInsensitive])

    static func format(_ text: String) -> String {
        // 核心逻辑：先按 ``` 分割，奇数索引为代码块，偶数索引为普通文本
        // 只有普通文本才进行 Markdown 和 LaTeX 解析
        // 代码块保持原样
        
        let parts = text.components(separatedBy: "```")
        var result = ""
        
        for (index, part) in parts.enumerated() {
            if index % 2 == 1 {
                // --- 代码块部分 ---
                // 保留原样，或者简单美化
                // 移除可能的语言标识符 (如 ```swift\n -> \n)
                var codeContent = part
                if let firstLineEnd = codeContent.firstIndex(of: "\n") {
                    // 如果第一行很短且不包含空格，可能是语言 ID
                    let firstLine = codeContent[..<firstLineEnd]
                    if firstLine.count < 15 && !firstLine.contains(" ") {
                        codeContent.removeSubrange(..<firstLineEnd)
                    }
                }
                
                // 给代码块加一个视觉标记 (如果需要)
                result += "\n\(codeContent)\n"
            } else {
                // --- 普通文本部分 ---
                // 正常解析 LaTeX 和 Markdown
                result += cleanMarkdown(part)
            }
        }
        
        return result
    }
    
    // 公开：清洗 Markdown 格式 (表格、标题、列表等)，但不解析 LaTeX
    static func cleanMarkdown(_ text: String) -> String {
        var r = text
        
        // 表格处理
        if r.contains("|") {
            var lines = r.components(separatedBy: "\n")
            for i in 0..<lines.count {
                let line = lines[i].trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("|") || (line.contains("|") && line.contains("-")) {
                    
                    // 分割线处理：短分割线，防折行
                    if line.contains("---") {
                        lines[i] = "" 
                    } else {
                        // 内容行：恢复竖线分隔，用全角竖线或带空格的竖线
                        var formatted = line.replacingOccurrences(of: "|", with: " │ ")
                        // 清理首尾
                        if formatted.hasPrefix(" │ ") { formatted.removeFirst(3) }
                        if formatted.hasSuffix(" │ ") { formatted.removeLast(3) }
                        lines[i] = " " + formatted.trimmingCharacters(in: .whitespaces)
                    }
                }
            }
            r = lines.joined(separator: "\n")
        }
        
        // 标题简化 - 转换为加粗文本，以适应 inlineOnlyPreservingWhitespace 模式
        // 使用正则将 # Title 替换为 **Title**
        // 使用正则将 # Title 替换为 **Title**
        let range = NSRange(location: 0, length: (r as NSString).length)
        // 替换为：$1**$3**$4
        r = titleRegex.stringByReplacingMatches(in: r, options: [], range: range, withTemplate: "$1**$3**$4")
        
        // 列表符号
        r = r.replacingOccurrences(of: "\n- [ ] ", with: "\n☐ ")
        r = r.replacingOccurrences(of: "\n- [x] ", with: "\n☑ ")
        r = r.replacingOccurrences(of: "\n- [X] ", with: "\n☑ ")
        r = r.replacingOccurrences(of: "\n* ", with: "\n- ")
        // 引用块优化：使用竖线符号 + 斜体模拟引用样式
        // r = r.replacingOccurrences(of: "\n> ", with: "\n| ") // 旧逻辑
        do {
            let quoteRange = NSRange(location: 0, length: (r as NSString).length)
            // 替换为：$1▍ $3$4 (使用更粗的竖线 + 空格，不使用斜体以保持清晰)
            r = quoteRegex.stringByReplacingMatches(in: r, options: [], range: quoteRange, withTemplate: "$1▍ $3$4")
        }
        
        // 分割线：转换为文本型分割线，避免 AttributedString 解析为 Block 导致排版混乱
        r = r.replacingOccurrences(of: "\n---\n", with: "\n──────────\n")
        r = r.replacingOccurrences(of: "\n***\n", with: "\n──────────\n")
        
        // 行内格式 (简单移除标记)
        // 注意：SwiftUI Text 支持部分 Markdown，保留这些符号以进行渲染
        // r = r.replacingOccurrences(of: "**", with: "")
        // r = r.replacingOccurrences(of: "~~", with: "")
        // r = r.replacingOccurrences(of: "`", with: "") 
        
        // v1.8.2: 处理 HTML 标签 (details/summary)
        r = r.replacingOccurrences(of: "<details>", with: "", options: .caseInsensitive)
        r = r.replacingOccurrences(of: "</details>", with: "", options: .caseInsensitive)
        r = r.replacingOccurrences(of: "</summary>", with: "\n", options: .caseInsensitive)
        
        // <summary>文本</summary> -> ▼ 文本
        // <summary>文本</summary> -> ▼ 文本
        let summaryRange = NSRange(location: 0, length: (r as NSString).length)
        r = summaryRegex.stringByReplacingMatches(in: r, options: [], range: summaryRange, withTemplate: "▼ $1")
        
        return r
    }
}

/// 简单 Markdown 视图
struct MarkdownView: View {
    let text: String
    
    var body: some View {
        Text(MarkdownParser.format(text))
            .font(.system(size: 15))
    }
}
