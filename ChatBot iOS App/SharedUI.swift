import SwiftUI

// MARK: - 共享 UI 组件 (iOS 移植版)

// MARK: - MathText
// 智能数学文本组件：自动处理变量斜体、函数正体
struct MathText: View {
    let text: String
    let size: CGFloat
    
    // 已知数学函数 (需要保持正体)
    private let mathFunctions: Set<String> = [
        "sin", "cos", "tan", "cot", "sec", "csc",
        "arcsin", "arccos", "arctan",
        "sinh", "cosh", "tanh",
        "log", "ln", "lg", "lim", "exp",
        "min", "max", "sup", "inf", "det", "dim"
    ]
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(splitMathParts(text), id: \.self) { part in
                if isNumber(part) || mathFunctions.contains(part) || isSymbol(part) {
                    Text(part)
                        .font(.system(size: size, weight: .regular, design: .serif))
                } else {
                    Text(part)
                        .font(.system(size: size, weight: .regular, design: .serif))
                        .italic()
                }
            }
        }
    }
    
    func splitMathParts(_ str: String) -> [String] {
        var result: [String] = []
        var currentBuffer = ""
        
        for char in str {
            if char.isNumber {
                if !currentBuffer.isEmpty && !currentBuffer.last!.isNumber {
                    result.append(currentBuffer); currentBuffer = ""
                }
                currentBuffer.append(char)
            } else if char.isLetter {
                if !currentBuffer.isEmpty && !currentBuffer.last!.isLetter {
                    result.append(currentBuffer); currentBuffer = ""
                }
                currentBuffer.append(char)
            } else {
                if !currentBuffer.isEmpty {
                    result.append(currentBuffer); currentBuffer = ""
                }
                result.append(String(char))
            }
        }
        if !currentBuffer.isEmpty { result.append(currentBuffer) }
        return result
    }
    
    func isNumber(_ str: String) -> Bool { Double(str) != nil }
    func isSymbol(_ str: String) -> Bool {
        guard let first = str.first else { return false }
        return !first.isLetter && !first.isNumber
    }
}

// MARK: - MessageContentView
// MARK: - MessageContentView (Optimized)
struct MessageContentView: View {
    let text: String
    let isStreaming: Bool // v1.8.2: 流式输出标记
    @EnvironmentObject var viewModel: ChatViewModel // Only used for config
    
    init(text: String, isStreaming: Bool = false) {
        self.text = text
        self.isStreaming = isStreaming
    }
    
    var body: some View {
        OptimizedMessageContent(
            text: text,
            isStreaming: isStreaming,
            renderMode: viewModel.markdownRenderMode,
            latexEnabled: viewModel.latexRenderingEnabled,
            advancedLatexEnabled: viewModel.advancedLatexEnabled
        )
    }
}

// Optimized Equatable Content View to prevent re-rendering when viewModel changes (but text/config is same)
struct OptimizedMessageContent: View, Equatable {
    let text: String
    let isStreaming: Bool
    let renderMode: MarkdownRenderMode
    let latexEnabled: Bool
    let advancedLatexEnabled: Bool
    
    // Custom Equality Check
    static func == (lhs: OptimizedMessageContent, rhs: OptimizedMessageContent) -> Bool {
        return lhs.text == rhs.text &&
               lhs.isStreaming == rhs.isStreaming &&
               lhs.renderMode == rhs.renderMode &&
               lhs.latexEnabled == rhs.latexEnabled &&
               lhs.advancedLatexEnabled == rhs.advancedLatexEnabled
    }
    
    var body: some View {
        // v1.8.6: 根据三种渲染模式判断如何显示
        let shouldRender: Bool = {
            switch renderMode {
            case .realtime:
                return true  // 总是渲染
            case .onComplete:
                return !isStreaming  // 完成后才渲染
            case .manual:
                return !isStreaming  // 流式时显示纯文本（通过按钮切换）
            }
        }()
        
        if shouldRender {
            // 渲染 Markdown (使用缓存正则)
            let markdownProcessed = MarkdownParser.cleanMarkdown(text)
            
            if !latexEnabled {
                // 关闭 LaTeX 渲染：只应用 Markdown 格式化，不转换数学符号
                Text(toMarkdown(markdownProcessed))
                    .font(.system(size: 16))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else {
                // 简单模式/高级模式：Markdown + LaTeX 符号替换
                let converted = SimpleLatexConverter.convertLatexOnly(markdownProcessed)
                Text(toMarkdown(converted))
                    .font(.system(size: 16))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        } else {
            // 显示纯文本（流式中）
            Text(text)
                .font(.system(size: 16))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
    
    // 辅助函数
    private func toMarkdown(_ text: String) -> AttributedString {
        return autoreleasepool {
            do {
                var options = AttributedString.MarkdownParsingOptions()
                options.interpretedSyntax = .inlineOnlyPreservingWhitespace
                return try AttributedString(markdown: text, options: options)
            } catch {
                return AttributedString(text)
            }
        }
    }
}
    


// MARK: - Dashed Bubble Icon (Incognito)
struct DashedBubbleIcon: View {
    var size: CGFloat = 24
    var color: Color = .primary
    
    var body: some View {
        ZStack {
            ManualDashedBubbleShape()
                .stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .foregroundColor(color)
                .frame(width: size, height: size)
        }
    }
}

struct ManualDashedBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let cx = w / 2
        let cy = h / 2
        let r = min(w, h) / 2 * 0.7 // Main radius
        let tipR = min(w, h) / 2 * 0.95 // Tail tip radius
        
        let segmentCount = 6
        let tailIndex = 2 // Bottom-Left (approx 135 degrees)
        // Base angles: 15, 75, 135, 195, 255, 315
        let baseAngleOffset: Double = 15
        let arcSpan: Double = 38 // Degrees per segment (visual length)
        
        for i in 0..<segmentCount {
            let centerAngle = Double(i * 60) + baseAngleOffset
            let startA = centerAngle - arcSpan/2
            let endA = centerAngle + arcSpan/2
            
            if i == tailIndex {
                // Draw Tail Segment (V-shape ticking out)
                let pStart = pointOnCircle(cx: cx, cy: cy, r: r, angle: startA)
                let pEnd = pointOnCircle(cx: cx, cy: cy, r: r, angle: endA)
                let pTip = pointOnCircle(cx: cx, cy: cy, r: tipR, angle: centerAngle)
                
                path.move(to: pStart)
                path.addLine(to: pTip)
                path.addLine(to: pEnd)
            } else {
                // Draw Arc Segment
                path.move(to: pointOnCircle(cx: cx, cy: cy, r: r, angle: startA))
                path.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                            startAngle: .degrees(startA), endAngle: .degrees(endA),
                            clockwise: false)
            }
        }
        return path
    }
    
    func pointOnCircle(cx: CGFloat, cy: CGFloat, r: CGFloat, angle: Double) -> CGPoint {
        let rad = angle * .pi / 180
        return CGPoint(x: cx + r * CGFloat(cos(rad)), y: cy + r * CGFloat(sin(rad)))
    }
}

// MARK: - AdvancedLatexView
struct AdvancedLatexView: View {
    let text: String
    
    var body: some View {
        let nodes = LaTeXParser.parseToNodes(text)
        
        FlowLayout(spacing: 0, lineSpacing: 6) {
            ForEach(nodes) { node in
                LatexNodeView(node: node)
            }
        }
    }
}

// MARK: - LatexNodeView
struct LatexNodeView: View {
    let node: LatexNode
    
    var body: some View {
        switch node {
        case .text(let str):
            ForEach(Array(smartTokenize(str).enumerated()), id: \.offset) { item in
                let token = item.element
                if token == "\n" {
                     Color.clear.frame(maxWidth: .infinity, minHeight: 1)
                } else if token == " " {
                     Text("").frame(width: 4) // iOS 稍宽
                } else {
                     Text(token).font(.system(size: 16))
                }
            }
            
        case .inlineMath(let str):
             MathText(text: str, size: 16)
             
        case .mathFunction(let name):
             MathText(text: name, size: 16)
             
        case .symbol(let sym):
             MathText(text: sym, size: 16)
             
        case .fraction(let num, let den):
             FractionView(numNodes: num, denNodes: den)
                 .padding(.horizontal, 2)
                 
        case .root(let content, let power):
            rootView(content: content, power: power)
            
        case .script(let base, let sup, let sub):
             scriptView(base: base, sup: sup, sub: sub)
             
        case .accent(let type, let content):
             AccentView(type: type, content: content)
             
        case .binom(let n, let k):
             BinomView(nNodes: n, kNodes: k)
                 .padding(.horizontal, 2)
                 
        case .group(let nodes):
             ForEach(nodes) { n in LatexNodeView(node: n) }
        }
    }
    
    // 根号视图构建 (使用 overlay 确保横线与内容同宽)
    @ViewBuilder
    func rootView(content: [LatexNode], power: [LatexNode]?) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            // 可选的指数 (如 ³√)
            if let p = power {
                HStack(spacing: 0) {
                    ForEach(p) { n in LatexNodeView(node: n).scaleEffect(0.6) }
                }
                .offset(y: -8)
            }
            
            // 根号符号
            Text("√")
                .font(.system(size: 18))
            
            // 内容 + 顶部横线
            HStack(spacing: 0) {
                ForEach(content) { n in LatexNodeView(node: n) }
            }
            .overlay(alignment: .top) {
                // 横线紧贴内容顶部，宽度自动匹配
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(.primary) // iOS adapt
                    .offset(y: -2)
            }
        }
        .fixedSize()
    }
    
    // 上下标视图构建
    @ViewBuilder
    func scriptView(base: [LatexNode]?, sup: [LatexNode]?, sub: [LatexNode]?) -> some View {
        HStack(spacing: 0) {
            if let b = base {
                ForEach(b) { n in LatexNodeView(node: n) }
            }
            VStack(spacing: 0) {
                if let s = sup {
                    HStack(spacing:0) {
                        ForEach(s) { n in LatexNodeView(node: n).scaleEffect(0.75) }
                    }
                    .offset(y: -6)
                }
                if let s = sub {
                    HStack(spacing:0) {
                        ForEach(s) { n in LatexNodeView(node: n).scaleEffect(0.75) }
                    }
                    .offset(y: 6)
                }
            }
        }
    }
}

// 支持装饰符号 (bar, vec, hat, dot)
struct AccentView: View {
    let type: String
    let content: [LatexNode]
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部符号 - 使用 overlay 确保与内容同宽
            ZStack {
                // 占位，确保宽度
                HStack(spacing: 0) {
                    ForEach(content) { n in LatexNodeView(node: n) }
                }
                .opacity(0) // 隐藏，只占位
                
                // 真正的装饰符号
                if type == "vec" {
                    Image(systemName: "arrow.right").font(.system(size: 10))
                } else if type == "bar" || type == "overline" {
                    Rectangle().frame(height: 1).foregroundColor(.primary)
                } else if type == "hat" {
                    Text("^").font(.system(size: 12))
                } else if type == "dot" {
                    Text("·").font(.system(size: 12))
                } else if type == "tilde" || type == "widetilde" {
                    Text("~").font(.system(size: 12))
                }
            }
            .frame(height: 10) // 固定装饰符号高度
            
            // 实际内容
            HStack(spacing: 0) {
                ForEach(content) { n in LatexNodeView(node: n) }
            }
        }
        .fixedSize() // 关键：防止 VStack 扩展到无限宽
    }
}

// 二项式系数视图
struct BinomView: View {
    let nNodes: [LatexNode]
    let kNodes: [LatexNode]
    
    var body: some View {
        HStack(spacing: 0) {
            Text("(").font(.system(size: 16)).scaleEffect(y: 2.0)
            VStack(spacing: 2) {
                HStack(spacing: 0) {
                     ForEach(nNodes) { n in LatexNodeView(node: n).scaleEffect(0.9) }
                }
                HStack(spacing: 0) {
                     ForEach(kNodes) { n in LatexNodeView(node: n).scaleEffect(0.9) }
                }
            }
            Text(")").font(.system(size: 16)).scaleEffect(y: 2.0)
        }
    }
}

// FractionView
struct FractionView: View {
    let numNodes: [LatexNode]
    let denNodes: [LatexNode]
    
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                ForEach(numNodes) { n in LatexNodeView(node: n).scaleEffect(0.9) }
            }
            Rectangle().frame(height: 1).foregroundColor(.primary)
            HStack(spacing: 0) {
                ForEach(denNodes) { n in LatexNodeView(node: n).scaleEffect(0.9) }
            }
        }
        .fixedSize()
    }
}

// MARK: - CodeBlockView (v2.5: 语言标识 + 复制确认动画)
struct CodeBlockView: View {
    let language: String
    let code: String
    @State private var showCopied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 头部：语言标识 + 复制按钮
            HStack {
                Text(language)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    #if os(iOS)
                    UIPasteboard.general.string = code
                    #endif
                    withAnimation(.easeInOut(duration: 0.2)) { showCopied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.easeInOut(duration: 0.2)) { showCopied = false }
                    }
                } label: {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(showCopied ? .green : .secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.1))
            
            // 代码正文（不含语言标识）
            Text(code)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.green.opacity(0.8))
                .padding(12)
                .textSelection(.enabled)
        }
        .background(Color.black.opacity(0.8))
        .cornerRadius(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - MixedContentView
struct MixedContentView: View {
    let text: String
    let isStreaming: Bool // v1.8.2: 流式输出标记
    
    init(text: String, isStreaming: Bool = false) {
        self.text = text
        self.isStreaming = isStreaming
    }
    
    var body: some View {
        let parts = text.components(separatedBy: "```")
        VStack(alignment: .leading, spacing: 8) {
             ForEach(parts.indices, id: \.self) { i in
                 if i % 2 == 1 {
                     // 代码块：提取语言标识和纯代码
                     let raw = parts[i]
                     let firstNewline = raw.firstIndex(of: "\n")
                     let langLine = firstNewline != nil ? String(raw[raw.startIndex..<firstNewline!]).trimmingCharacters(in: .whitespaces) : ""
                     let lang = langLine.isEmpty ? "Code" : langLine
                     let codeBody = firstNewline != nil ? String(raw[raw.index(after: firstNewline!)...]).trimmingCharacters(in: .whitespacesAndNewlines) : raw.trimmingCharacters(in: .whitespacesAndNewlines)
                     
                     CodeBlockView(language: lang, code: codeBody)
                 } else {
                     // v1.8.2: 普通文本 (支持公式)，传递流式标志
                     let part = parts[i]
                     if !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                         MessageContentView(text: part, isStreaming: isStreaming)
                     }
                 }
             }
        }
    }
}

// MARK: - 思考内容 (v2.5: 紧凑药丸标签设计)
struct ThinkingContentView: View {
    let blocks: [String]
    @Binding var isExpanded: Bool
    var thinkingDuration: Double? = nil  // 思考时长（秒）
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "brain.head.profile.fill" : "brain.head.profile")
                        .font(.system(size: 11))
                    if let duration = thinkingDuration {
                        Text("思考了 \(String(format: "%.1f", duration)) 秒")
                            .font(.system(size: 12, weight: .medium))
                    } else {
                        Text("思考过程")
                            .font(.system(size: 12, weight: .medium))
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.08))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            
            if isExpanded && !blocks.isEmpty {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, line in
                        if line.isEmpty {
                            Spacer().frame(height: 4)
                        } else {
                            Text(line)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(8)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
    }
}

// MARK: - 记忆药丸标签 (v2.5: 蓝色 + 覆盖层)
struct MemoryBadge: View {
    let activity: ChatViewModel.MemoryActivity
    @Binding var isExpanded: Bool
    
    var body: some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
            HStack(spacing: 4) {
                Image(systemName: "brain")
                    .font(.system(size: 11))
                Text("\(activity.retrievedMemories.count) 条记忆")
                    .font(.system(size: 12, weight: .medium))
                if !activity.addedMemories.isEmpty {
                    Text("+ \(activity.addedMemories.count)")
                        .font(.system(size: 11))
                }
                if !activity.deletedMemories.isEmpty {
                    Text("- \(activity.deletedMemories.count)")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(.blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.blue.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 记忆详情面板（作为覆盖层使用）
struct MemoryDetailOverlay: View {
    let activity: ChatViewModel.MemoryActivity
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !activity.retrievedMemories.isEmpty {
                Text("检索到的记忆")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                ForEach(Array(activity.retrievedMemories.enumerated()), id: \.offset) { _, mem in
                    HStack(alignment: .top, spacing: 4) {
                        Text("•")
                            .font(.system(size: 11))
                            .foregroundColor(.blue.opacity(0.7))
                        Text(mem)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            if !activity.addedMemories.isEmpty {
                if !activity.retrievedMemories.isEmpty { Divider() }
                Text("新增的记忆")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                ForEach(Array(activity.addedMemories.enumerated()), id: \.offset) { _, mem in
                    HStack(alignment: .top, spacing: 4) {
                        Text("+")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.green.opacity(0.8))
                        Text(mem)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            if !activity.deletedMemories.isEmpty {
                if !activity.retrievedMemories.isEmpty || !activity.addedMemories.isEmpty { Divider() }
                Text("已删除的记忆")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.red.opacity(0.7))
                ForEach(Array(activity.deletedMemories.enumerated()), id: \.offset) { _, mem in
                    HStack(alignment: .top, spacing: 4) {
                        Text("×")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.red.opacity(0.7))
                        Text(mem)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .strikethrough(color: .red.opacity(0.5))
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

// MARK: - FlowLayout (Copy from Watch)
struct FlowLayout: Layout {
    var spacing: CGFloat = 0
    var lineSpacing: CGFloat = 4
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrangeSubviews(proposal: proposal, subviews: subviews)
        if rows.isEmpty { return .zero }
        
        var width: CGFloat = 0
        var height: CGFloat = 0
        
        for row in rows {
            width = max(width, row.width)
            height += row.height + lineSpacing
        }
        height -= lineSpacing
        
        return CGSize(width: width, height: height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrangeSubviews(proposal: proposal, subviews: subviews)
        
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            let centerY = y + row.height / 2
            
            for item in row.items {
                let size = item.size
                let itemY = centerY - size.height / 2
                item.view.place(at: CGPoint(x: x, y: itemY), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }
    
    struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }
    
    struct Item {
        var view: LayoutSubview
        var size: CGSize
    }
    
    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let proposed = proposal.width ?? .infinity
        let maxWidth = proposed 
        
        var rows: [Row] = []
        var currentRow = Row()
        
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            
            if currentRow.width + size.width + spacing > maxWidth && !currentRow.items.isEmpty {
                 rows.append(currentRow)
                 currentRow = Row()
            }
            
            currentRow.items.append(Item(view: subview, size: size))
            currentRow.width += size.width + (currentRow.items.count > 1 ? spacing : 0)
            currentRow.height = max(currentRow.height, size.height)
        }
        
        if !currentRow.items.isEmpty {
            rows.append(currentRow)
        }
        
        return rows
    }
}

// MARK: - LaTeX 符号转换器 (简单模式)
struct SimpleLatexConverter {
    
    // 静态常量：希腊字母映射
    private static let greekLetters: [String: String] = [
        "\\alpha": "α", "\\beta": "β", "\\gamma": "γ", "\\delta": "δ",
        "\\epsilon": "ε", "\\zeta": "ζ", "\\eta": "η", "\\theta": "θ",
        "\\iota": "ι", "\\kappa": "κ", "\\lambda": "λ", "\\mu": "μ",
        "\\nu": "ν", "\\xi": "ξ", "\\pi": "π", "\\rho": "ρ",
        "\\sigma": "σ", "\\tau": "τ", "\\upsilon": "υ", "\\phi": "φ",
        "\\chi": "χ", "\\psi": "ψ", "\\omega": "ω",
        "\\Gamma": "Γ", "\\Delta": "Δ", "\\Theta": "Θ", "\\Lambda": "Λ",
        "\\Xi": "Ξ", "\\Pi": "Π", "\\Sigma": "Σ", "\\Phi": "Φ",
        "\\Psi": "Ψ", "\\Omega": "Ω"
    ]
    
    // 静态常量：数学运算符映射
    private static let mathSymbols: [String: String] = [
        "\\times": "×", "\\div": "÷", "\\pm": "±", "\\mp": "∓",
        "\\cdot": "·", "\\leq": "≤", "\\le": "≤", "\\geq": "≥", "\\ge": "≥",
        "\\neq": "≠", "\\ne": "≠", "\\approx": "≈", "\\equiv": "≡",
        "\\infty": "∞", "\\propto": "∝",
        "\\sum": "Σ", "\\prod": "Π", "\\int": "∫", "\\oint": "∮",
        "\\partial": "∂", "\\nabla": "∇", "\\forall": "∀", "\\exists": "∃",
        "\\in": "∈", "\\notin": "∉", "\\subset": "⊂", "\\supset": "⊃",
        "\\subseteq": "⊆", "\\supseteq": "⊇", "\\cup": "∪", "\\cap": "∩",
        "\\emptyset": "∅", "\\varnothing": "∅",
        "\\rightarrow": "→", "\\to": "→", "\\Rightarrow": "⇒", "\\implies": "⟹",
        "\\leftarrow": "←", "\\Leftarrow": "⇐",
        "\\leftrightarrow": "↔", "\\Leftrightarrow": "⇔", "\\iff": "⟺",
        "\\because": "∵", "\\therefore": "∴",
        "\\angle": "∠", "\\perp": "⊥", "\\parallel": "∥",
        "\\triangle": "△", "\\circ": "°", "\\sqrt": "√"
    ]
    
    // 静态常量：上标映射
    private static let superscripts: [String: String] = [
        "^{0}": "⁰", "^{1}": "¹", "^{2}": "²", "^{3}": "³", "^{n}": "ⁿ",
        "^0": "⁰", "^1": "¹", "^2": "²", "^3": "³", "^n": "ⁿ", "^m": "ᵐ"
    ]
    
    // 静态常量：下标映射
    private static let subscripts: [String: String] = [
        "_{0}": "₀", "_{1}": "₁", "_{2}": "₂", "_{n}": "ₙ", "_{m}": "ₘ", "_{i}": "ᵢ",
        "_0": "₀", "_1": "₁", "_2": "₂", "_n": "ₙ", "_m": "ₘ", "_i": "ᵢ", "_a": "ₐ", "_b": "ᵦ"
    ]
    
    // 缓存的正则表达式
    private static let commandRegex = try? NSRegularExpression(pattern: "\\\\([a-zA-Z]+)")
    
    /// 转换 LaTeX 数学符号（不处理 Markdown）
    static func convertLatexOnly(_ text: String) -> String {
        var result = text
        
        // 1. 移除数学模式标记
        result = result.replacingOccurrences(of: "$$", with: "")
        result = result.replacingOccurrences(of: "$", with: "")
        
        // 2. 预处理：\text{内容} -> [内容]
        let textPattern = "\\\\text\\s*\\{([^{}]*)\\}"
        if let regex = try? NSRegularExpression(pattern: textPattern) {
            for _ in 0..<5 {
                let newResult = regex.stringByReplacingMatches(
                    in: result, range: NSRange(result.startIndex..., in: result),
                    withTemplate: "[$1]"
                )
                if newResult == result { break }
                result = newResult
            }
        }
        
        // 3. \sqrt{} -> √()
        let sqrtPattern = "\\\\sqrt\\s*\\{([^{}]*)\\}"
        if let regex = try? NSRegularExpression(pattern: sqrtPattern) {
            for _ in 0..<20 {
                let newResult = regex.stringByReplacingMatches(
                    in: result, range: NSRange(result.startIndex..., in: result),
                    withTemplate: "√($1)"
                )
                if newResult == result { break }
                result = newResult
            }
        }
        
        // 4. \boxed{} -> ⟦内容⟧
        let boxedPattern = "\\\\boxed\\s*\\{([^{}]*)\\}"
        if let regex = try? NSRegularExpression(pattern: boxedPattern) {
            for _ in 0..<20 {
                let newResult = regex.stringByReplacingMatches(
                    in: result, range: NSRange(result.startIndex..., in: result),
                    withTemplate: "⟦$1⟧"
                )
                if newResult == result { break }
                result = newResult
            }
        }
        
        // 5. \frac{a}{b} -> (a)/(b)
        let fracPattern = "\\\\frac\\s*\\{([^{}]*)\\}\\s*\\{([^{}]*)\\}"
        if let regex = try? NSRegularExpression(pattern: fracPattern) {
            for _ in 0..<30 {
                let newResult = regex.stringByReplacingMatches(
                    in: result, range: NSRange(result.startIndex..., in: result),
                    withTemplate: "($1)/($2)"
                )
                if newResult == result { break }
                result = newResult
            }
        }
        
        // 6. \bar{x} -> x̄
        let barPattern = "\\\\bar\\s*\\{([^{}]*)\\}"
        if let regex = try? NSRegularExpression(pattern: barPattern) {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result),
                withTemplate: "$1̄"
            )
        }
        
        // 7. \vec{x} -> x⃗
        let vecPattern = "\\\\vec\\s*\\{([^{}]*)\\}"
        if let regex = try? NSRegularExpression(pattern: vecPattern) {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result),
                withTemplate: "$1⃗"
            )
        }
        
        // 8. \binom{n}{k} -> C(n,k)
        let binomPattern = "\\\\binom\\s*\\{([^{}]*)\\}\\s*\\{([^{}]*)\\}"
        if let regex = try? NSRegularExpression(pattern: binomPattern) {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result),
                withTemplate: "C($1,$2)"
            )
        }
        
        // 9. 希腊字母
        for (latex, symbol) in greekLetters {
            result = result.replacingOccurrences(of: latex, with: symbol)
        }
        
        // 10. 数学运算符
        for (latex, symbol) in mathSymbols {
            result = result.replacingOccurrences(of: latex, with: symbol)
        }
        
        // 11. 上下标
        for (latex, symbol) in superscripts {
            result = result.replacingOccurrences(of: latex, with: symbol)
        }
        for (latex, symbol) in subscripts {
            result = result.replacingOccurrences(of: latex, with: symbol)
        }
        
        // 12. 移除剩余的 LaTeX 命令
        if let regex = commandRegex {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result),
                withTemplate: "$1"
            )
        }
        
        // 13. 清理花括号
        result = result.replacingOccurrences(of: "{", with: "")
        result = result.replacingOccurrences(of: "}", with: "")
        
        // 14. 恢复 \text 的方括号
        result = result.replacingOccurrences(of: "[", with: "")
        result = result.replacingOccurrences(of: "]", with: "")
        
        return result
    }
}

// 辅助：智能分词
private func smartTokenize(_ str: String) -> [String] {
    var tokens: [String] = []
    var currentToken = ""
    for char in str {
        if char == " " {
            if !currentToken.isEmpty { tokens.append(currentToken); currentToken = "" }
            tokens.append(" ")
        } else if isCJK(char) {
            if !currentToken.isEmpty { tokens.append(currentToken); currentToken = "" }
            tokens.append(String(char))
        } else {
            currentToken.append(char)
        }
    }
    if !currentToken.isEmpty { tokens.append(currentToken) }
    return tokens
}

private func isCJK(_ char: Character) -> Bool {
    guard let scalar = char.unicodeScalars.first else { return false }
    return scalar.value >= 0x4E00 && scalar.value <= 0x9FFF
}
