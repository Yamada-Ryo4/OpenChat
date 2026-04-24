import Foundation
import SwiftUI

// MARK: - AST Nodes
enum LatexNode: Identifiable, Hashable {
    // v2.1: 使用稳定的 hash-based ID，避免每次访问创建新 UUID 导致 SwiftUI 全量重绘。
    // 注意：hashValue 碰撞概率极低（Int64 范围），配合 ForEach index 不会丢节点。
    var id: Int { hashValue }
    
    case text(String)
    case inlineMath(String)
    case mathFunction(String)
    case symbol(String)
    case fraction(num: [LatexNode], den: [LatexNode])
    case root(content: [LatexNode], power: [LatexNode]?)
    case script(base: [LatexNode]?, super: [LatexNode]?, sub: [LatexNode]?)
    case group([LatexNode])
    case accent(type: String, content: [LatexNode]) // bar, vec, hat
    case binom(n: [LatexNode], k: [LatexNode]) // binom
}

// MARK: - Parser Engine
struct LaTeXParser {
    
    // 公开入口
    static func parseToNodes(_ text: String) -> [LatexNode] {
        let tokens = LatexLexer.tokenize(text)
        return LatexParser.parse(tokens)
    }
}

// MARK: - Lexer
private enum Token: Equatable {
    case char(Character)
    case command(String)
    case lBrace, rBrace      // { }
    case lBracket, rBracket  // [ ]
    case dollar              // $
    case caret, underscore   // ^, _
    case pipe                // |
}

private struct LatexLexer {
    static func tokenize(_ input: String) -> [Token] {
        var tokens: [Token] = []
        var i = input.startIndex
        
        while i < input.endIndex {
            let c = input[i]
            
            switch c {
            case "\\":
                i = input.index(after: i)
                guard i < input.endIndex else { break }
                let start = i
                // 读取命令名
                if input[i].isLetter {
                    while i < input.endIndex && input[i].isLetter {
                        i = input.index(after: i)
                    }
                    let name = String(input[start..<i])
                    tokens.append(.command(name))
                    continue // 已移动 i
                } else {
                    // 单字符命令 (如 \, \%, \$)
                    tokens.append(.command(String(input[i])))
                    i = input.index(after: i)
                    continue
                }
            case "{": tokens.append(.lBrace)
            case "}": tokens.append(.rBrace)
            case "[": tokens.append(.lBracket)
            case "]": tokens.append(.rBracket)
            case "$": tokens.append(.dollar)
            case "^": tokens.append(.caret)
            case "_": tokens.append(.underscore)
            case "|": tokens.append(.pipe)
            default:
                tokens.append(.char(c))
            }
            
            // 如果没在 case 里处理 i 的移动，这里默认 +1
            if c != "\\" { 
                i = input.index(after: i)
            }
        }
        return tokens
    }
}

// MARK: - Parser Logic
private struct LatexParser {
    
    static func parse(_ tokens: [Token]) -> [LatexNode] {
        var cursor = 0
        return parseBlock(tokens, cursor: &cursor, until: nil)
    }
    
    // 解析一个块 (直到 endToken 或 结束)
    private static func parseBlock(_ tokens: [Token], cursor: inout Int, until endToken: Token?) -> [LatexNode] {
        var nodes: [LatexNode] = []
        var textBuffer = ""
        
        func commitText() {
            if !textBuffer.isEmpty {
                // 智能识别：文本是否包含数学内容？
                // 这里我们按 "单词" 粒度并在 Token 级别做过简单的 char，
                // 但为了保持 FlowLayout 高效，我们尽量合并纯文本。
                // 这里的策略：先生成 .text，后续渲染时 ChatView 会再次 smartTokenize。
                // 或者我们在这里就直接做好分类？
                // 既然 ChatView 已经有 smartTokenize，这里直接给 text 比较好。
                // 但是！我们需要处理 "隐式数学" (sin x)。
                // 暂时方案：这里全部当 .text，让 ChatView 决定是否要转为 math。
                // 或者：如果 textBuffer 全是数学符号/数字，转为 .inlineMath。
                
                nodes.append(.text(textBuffer))
                textBuffer = ""
            }
        }
        
        while cursor < tokens.count {
            let token = tokens[cursor]
            
            if let end = endToken, token == end {
                cursor += 1 // consume end token
                commitText()
                return nodes
            }
            
            // 特殊处理：如果遇到 $，进入 Explicit Math Mode
            if token == .dollar {
                commitText()
                cursor += 1
                // 解析直到下一个 $
                let mathNodes = parseBlock(tokens, cursor: &cursor, until: .dollar)
                // 标记为 Explicit Group，或者平铺但赋予 Math 属性?
                // 为了简单，我们用 .group 但 ChatView 渲染时会知道它是 math
                // 我们在 LatexNode 加一个 group 类型? 或者复用 .group
                // 不如直接解析 mathNodes，然后把它们全部标记为 .inlineMath (除非是 command)
                // 这一步转换可以在 post-process 做。
                // 这里我们简单地把 mathNodes 包装一下，或者直接 append。
                // 更好的方式：引入 .mathBlock
                // 但是上面定义里没有 mathBlock。
                // 我们用 group 并假设 ChatView 会处理。
                // 或者，我们把 parseBlock 拆分为 "parseTextMode" 和 "parseMathMode"。
                // 这里简化处理：内容保持原样，但在 Explicit Math 里的 Text 也是 Math Font。
                // 我们新增一个 .group([LatexNode])，渲染时统一处理。
                // 为适应现有 ChatView 结构，我们尝试把 mathNodes 里的 .text 转为 .inlineMath
                let convertedNodes = convertToMathNodes(mathNodes)
                nodes.append(contentsOf: convertedNodes)
                continue
            }
            
            switch token {
            case .char(let c):
                textBuffer.append(c)
                cursor += 1
                
            case .command(let name):
                commitText()
                cursor += 1
                nodes.append(parseCommand(name, tokens: tokens, cursor: &cursor))
                
            case .caret, .underscore:
                // 上下标 (如果出现在 text 模式，通常也是数学)
                commitText()
                let isSuper = (token == .caret)
                cursor += 1
                let scriptArg = parseArg(tokens, cursor: &cursor)
                if isSuper {
                    nodes.append(.script(base: nil, super: scriptArg, sub: nil))
                } else {
                    nodes.append(.script(base: nil, super: nil, sub: scriptArg))
                }
                
            case .lBrace:
                commitText()
                cursor += 1
                let groupNodes = parseBlock(tokens, cursor: &cursor, until: .rBrace)
                // { ... } 只是分组，展平它
                nodes.append(contentsOf: groupNodes)
                
            default:
                // 其他符号如 [ ] | 等，视为文本
                if case .char(let c) = token { textBuffer.append(c) }
                else if token == .lBracket { textBuffer.append("[") }
                else if token == .rBracket { textBuffer.append("]") }
                else if token == .pipe { textBuffer.append("|") }
                cursor += 1
            }
        }
        
        commitText()
        return nodes
    }
    
    // 解析单个参数 (可以是 {group} 或 单个 token)
    private static func parseArg(_ tokens: [Token], cursor: inout Int) -> [LatexNode] {
        if cursor >= tokens.count { return [] }
        
        if tokens[cursor] == .lBrace {
            cursor += 1
            return parseBlock(tokens, cursor: &cursor, until: .rBrace)
        } else {
            // 单个 token
            // 如果是 command, 解析 command
            if case .command(let name) = tokens[cursor] {
                cursor += 1
                return [parseCommand(name, tokens: tokens, cursor: &cursor)]
            } else if case .char(let c) = tokens[cursor] {
                cursor += 1
                return [.inlineMath(String(c))] // 参数通常默认是 math
            } else if case .dollar = tokens[cursor] {
                 cursor += 1 // 忽略 $
                 return [] // 应该不会发生
            }
            cursor += 1
            return []
        }
    }
    
    private static func parseCommand(_ name: String, tokens: [Token], cursor: inout Int) -> LatexNode {
        // 1. 结构化命令
        if name == "frac" {
            let num = parseArg(tokens, cursor: &cursor)
            let den = parseArg(tokens, cursor: &cursor)
            return .fraction(num: num, den: den)
        } else if name == "binom" {
            let n = parseArg(tokens, cursor: &cursor)
            let k = parseArg(tokens, cursor: &cursor)
            return .binom(n: n, k: k)
        } else if name == "sqrt" {
            var power: [LatexNode]? = nil
            if cursor < tokens.count && tokens[cursor] == .lBracket {
                cursor += 1
                power = parseBlock(tokens, cursor: &cursor, until: .rBracket)
            }
            let content = parseArg(tokens, cursor: &cursor)
            return .root(content: content, power: power)
        } else if ["bar", "vec", "hat", "overline", "dot", "ddot", "tilde", "widehat", "widetilde"].contains(name) {
            let content = parseArg(tokens, cursor: &cursor)
            return .accent(type: name, content: content)
        } else if name == "text" || name == "mathrm" || name == "mathbf" {
            let content = parseArg(tokens, cursor: &cursor)
            let str = flattenText(content)
            return .text(str)
        }
        
        // 2. 符号与函数
        if let symbol = Constants.symbolMap[name] {
            return .symbol(symbol)
        } else if Constants.mathFunctions.contains(name) {
            return .mathFunction(name)
        }
        
        // 3. 忽略的命令
        if ["left", "right"].contains(name) {
            return .group([])
        }
        
        // 4. 未知命令
        return .text("\\" + name)
    }
    
    static func flattenText(_ nodes: [LatexNode]) -> String {
        var res = ""
        for node in nodes {
            switch node {
            case .text(let s), .inlineMath(let s), .symbol(let s), .mathFunction(let s):
                res += s
            case .group(let ns):
                res += flattenText(ns)
            default: break
            }
        }
        return res
    }
    
    static func convertToMathNodes(_ nodes: [LatexNode]) -> [LatexNode] {
        return nodes.map { node in
            if case .text(let str) = node {
                return .inlineMath(str)
            }
            return node
        }
    }
}

// MARK: - Constants
private struct Constants {
    static let mathFunctions: Set<String> = [
        "sin", "cos", "tan", "cot", "sec", "csc",
        "arcsin", "arccos", "arctan",
        "sinh", "cosh", "tanh",
        "log", "ln", "lg", "lim", "exp",
        "min", "max", "sup", "inf", "det", "dim"
    ]
    
    static let symbolMap: [String: String] = [
        // Greek
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε",
        "zeta": "ζ", "eta": "η", "theta": "θ", "iota": "ι", "kappa": "κ",
        "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "pi": "π",
        "rho": "ρ", "sigma": "σ", "tau": "τ", "upsilon": "υ", "phi": "φ",
        "chi": "χ", "psi": "ψ", "omega": "ω",
        "Alpha": "Α", "Beta": "Β", "Gamma": "Γ", "Delta": "Δ",
        "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ", "Pi": "Π",
        "Sigma": "Σ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
        // Operators
        "times": "×", "div": "÷", "pm": "±", "mp": "∓", "cdot": "·",
        "leq": "≤", "le": "≤", "geq": "≥", "ge": "≥",
        "neq": "≠", "ne": "≠", "approx": "≈", "equiv": "≡",
        "infty": "∞", "propto": "∝",
        "sum": "∑", "prod": "∏", "int": "∫", "oint": "∮",
        "partial": "∂", "nabla": "∇", "forall": "∀", "exists": "∃",
        "in": "∈", "notin": "∉", "subset": "⊂", "supset": "⊃",
        "subseteq": "⊆", "supseteq": "⊇", "cup": "∪", "cap": "∩",
        "emptyset": "∅", "varnothing": "∅",
        "rightarrow": "→", "to": "→", "Rightarrow": "⇒", "implies": "⟹",
        "leftarrow": "←", "Leftarrow": "⇐", "impliedby": "⟸",
        "leftrightarrow": "↔", "Leftrightarrow": "⇔", "iff": "⟺",
        "uparrow": "↑", "downarrow": "↓",
        "because": "∵", "therefore": "∴",
        "angle": "∠", "perp": "⊥", "parallel": "∥",
        "triangle": "△", "circ": "°"
    ]
}
