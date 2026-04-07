import SwiftUI
import PhotosUI

// MARK: - ChatView
struct ChatView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool
    @State private var showScrollToBottom = false
    @State private var showIncognitoSheet = false
    @State private var suppressAutoScroll = false
    @State private var showDeleteConfirm = false
    @State private var showModelSelection = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    Spacer().frame(height: 12)

                    if viewModel.isDataLoading {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("正在整合本地海量存储...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 100)
                    } else {
                        if viewModel.currentMessages.isEmpty {
                            EmptyStateView()
                        }

                    ForEach(viewModel.currentMessages) { msg in
                        // Prevent duplicate display during streaming:
                        // If loading, hide the last message (which is the empty/partial AI message)
                        // because StreamingBubble handles the live display.
                        if viewModel.isLoading && msg.id == viewModel.currentMessages.last?.id && msg.role == .assistant {
                            EmptyView()
                        } else {
                            ChatBubble(message: msg, proxy: proxy, suppressAutoScroll: $suppressAutoScroll)
                                .id(msg.id)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 3)
                        }
                    }

                    // Streaming bubble
                    if viewModel.isLoading {
                        if !viewModel.streamingBlocks.isEmpty || !viewModel.streamingThinkingBlocks.isEmpty {
                            StreamingBubble(
                                blocks: viewModel.streamingBlocks,
                                thinkingBlocks: viewModel.streamingThinkingBlocks
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)
                            .id("streaming_bubble")
                        } else {
                            TypingIndicator()
                                .padding(.horizontal, 12)
                                .padding(.vertical, 3)
                        }
                    }




                    }

                    // The "bottom" anchor must be the absolute last element so that the
                    // scroll-to-bottom button always scrolls past the streaming bubble.
                    Spacer().frame(height: 20).id("bottom")
                }
            }
            .id(viewModel.currentSessionId)
            .scrollDismissesKeyboard(.immediately)
            .simultaneousGesture(TapGesture().onEnded { _ in
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            })
            .safeAreaInset(edge: .top) {
                // MARK: - Custom Header (Transparent, Glass Buttons)
                HStack(spacing: 12) {
                    // Sidebar toggle - no background
                    Button(action: { withAnimation(.spring(duration: 0.3)) { viewModel.isSidebarVisible.toggle() } }) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.primary)
                            .frame(width: 36, height: 36)
                    }

                    Spacer()

                    // Model selector menu - no background
                    Menu {
                        ForEach(viewModel.allFavoriteModels, id: \.id) { model in
                            Button {
                                viewModel.selectedGlobalModelID = model.id
                            } label: {
                                if viewModel.selectedGlobalModelID == model.id {
                                    Label(model.displayName, systemImage: "checkmark")
                                } else {
                                    Text(model.displayName)
                                }
                            }
                        }
                        Divider()
                        Button {
                            showModelSelection = true
                        } label: {
                            Label("更多模型...", systemImage: "ellipsis")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(viewModel.currentDisplayModelName)
                                .font(.headline)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: 200)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                    }

                    Spacer()

                    // Right Button: New Chat if not empty, Incognito if empty
                    if viewModel.currentMessages.isEmpty {
                        Button(action: { showIncognitoSheet = true }) {
                            DashedBubbleIcon(size: 18, color: .secondary)
                                .offset(y: 1)
                                .frame(width: 36, height: 36)
                        }
                    } else {
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                viewModel.createNewSession()
                            }
                        }) {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: 36, height: 36)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(UIColor.systemBackground), ignoresSafeAreaEdges: .top) // Solid background
                .overlay(Divider(), alignment: .bottom)
            }
            .overlay(alignment: .bottomTrailing) {
                // Scroll to bottom floating button
                if showScrollToBottom {
                    Button {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.white, Color.accentColor)
                            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 16) // Adaptive padding above InputArea
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Input Area
                InputArea(isInputFocused: _isInputFocused)
            }
            .defaultScrollAnchor(.bottom)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let distanceFromBottom = geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height
                // 提高被动判定阈值，防止文字生成过快时系统误判用户在“向上划”
                return distanceFromBottom > 350
            } action: { _, isScrolledUp in
                withAnimation(.easeInOut(duration: 0.2)) {
                    showScrollToBottom = isScrolledUp
                }
            }
            .onChange(of: viewModel.currentMessages.count) {
                if !showScrollToBottom {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
            }
            // v2.9: 还原基于字符级别的监听，配合 ViewModel 里的 50ms 节流，实现高刷丝滑滚动而不再弹跳起伏
            .onChange(of: viewModel.streamingText.count) {
                // Ignore showScrollToBottom lock when we are actively streaming text
                if !showScrollToBottom {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: viewModel.streamingThinkingText.count) {
                // Ignore showScrollToBottom lock when we are actively streaming thinking
                if !showScrollToBottom {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: viewModel.isLoading) {
                if viewModel.isLoading {
                    // Force the button to disappear and immediately sink to bottom when starting a new generation
                    showScrollToBottom = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                } else if !showScrollToBottom {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
            }
            .onAppear {
               proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showIncognitoSheet) {
            IncognitoChatView()
        }
        .sheet(isPresented: $showModelSelection) {
            NavigationStack {
                ModelSelectionRootView(viewModel: viewModel)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { showModelSelection = false }
                        }
                    }
            }
        }
        // v2.5: 待确认删除提示
        .onChange(of: viewModel.pendingMemoryDeletions.count) { newCount in
            if newCount > 0 { showDeleteConfirm = true }
        }
        .alert("确认删除记忆", isPresented: $showDeleteConfirm) {
            Button("确认删除", role: .destructive) {
                for pending in viewModel.pendingMemoryDeletions.sorted(by: { $0.index > $1.index }) {
                    if pending.index < viewModel.memories.count {
                        viewModel.softDeleteMemory(at: pending.index)
                        // 记录已确认的删除活动
                        var activity = viewModel.lastMemoryActivity ?? ChatViewModel.MemoryActivity()
                        activity.deletedMemories.append(pending.content)
                        viewModel.lastMemoryActivity = activity
                    }
                }
                viewModel.pendingMemoryDeletions.removeAll()
            }
            Button("取消", role: .cancel) {
                viewModel.pendingMemoryDeletions.removeAll()
            }
        } message: {
            let items = viewModel.pendingMemoryDeletions.map { $0.content }.joined(separator: "\n")
            Text("AI 建议删除以下记忆：\n\(items)")
        }
    }

}

// MARK: - Empty State
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: 56))
                .foregroundStyle(LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            Text("ChatBot")
                .font(.title.bold())
            Text("发送消息开始对话")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 350)
        .padding()
    }
}

// MARK: - Chat Bubble
struct ChatBubble: View {
    let message: ChatMessage
    let proxy: ScrollViewProxy?
    @Binding var suppressAutoScroll: Bool
    @EnvironmentObject var viewModel: ChatViewModel
    @AppStorage("lastThinkingExpandedState") private var thinkingExpanded = false
    @State private var memoryExpanded = false
    @State private var showCopied = false

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                // Image attachment
                if let data = message.imageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: 220, maxHeight: 220)
                        .cornerRadius(14)
                        .clipped()
                }

                // v2.5: 药丸标签行 + 思考平铺 + 记忆覆盖层
                if !isUser {
                    let hasThinking = message.thinkingContent.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
                    let thinkingBlocks = hasThinking ? (message.thinkingContent?.splitIntoMarkdownBlocks().filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? []) : []
                    let thinkingDuration: Double? = {
                        guard let send = message.sendTime, let first = message.firstTokenTime else { return nil }
                        return first.timeIntervalSince(send)
                    }()
                    let hasMemory = viewModel.lastMemoryActivity.map { !$0.retrievedMemories.isEmpty || !$0.addedMemories.isEmpty || !$0.deletedMemories.isEmpty } ?? false
                    let showBadgeRow = !thinkingBlocks.isEmpty || hasMemory
                    
                    if showBadgeRow {
                        VStack(alignment: .leading, spacing: 4) {
                            // 药丸行
                            HStack(spacing: 8) {
                                if !thinkingBlocks.isEmpty {
                                    ThinkingContentView(blocks: [], isExpanded: $thinkingExpanded, thinkingDuration: thinkingDuration)
                                }
                                if let activity = viewModel.lastMemoryActivity, hasMemory,
                                   message.id == viewModel.currentMessages.last(where: { $0.role == .assistant })?.id {
                                    MemoryBadge(activity: activity, isExpanded: $memoryExpanded)
                                }
                                Spacer()
                            }
                            
                            // 思考内容平铺 + 记忆覆盖层
                            if thinkingExpanded && !thinkingBlocks.isEmpty {
                                ZStack(alignment: .top) {
                                    // 底层：思考内容
                                    LazyVStack(alignment: .leading, spacing: 2) {
                                        ForEach(Array(thinkingBlocks.enumerated()), id: \.offset) { _, line in
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
                                    
                                    // 上层：记忆详情覆盖
                                    if memoryExpanded, let activity = viewModel.lastMemoryActivity {
                                        MemoryDetailOverlay(activity: activity)
                                    }
                                }
                                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                            } else if memoryExpanded, let activity = viewModel.lastMemoryActivity {
                                // 没有思考内容时，记忆直接展开
                                MemoryDetailOverlay(activity: activity)
                                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                            }
                        }
                    }
                }

                // Text bubble
                if !message.text.isEmpty {
                    if isUser {
                        MixedContentView(text: message.text, isStreaming: false)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(UIColor.secondarySystemBackground).opacity(0.5)) // User uses old AI style
                            .foregroundColor(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                            .contextMenu {
                                Button(action: {
                                    UIPasteboard.general.string = message.text
                                }) {
                                    Label("复制内容", systemImage: "doc.on.doc")
                                }
                            }
                    } else {
                        // AI Message - Plain Text
                        MixedContentView(text: message.text, isStreaming: false)
                            .padding(.horizontal, 10) // Reduced padding for plain text
                            .padding(.vertical, 6)
                            .foregroundColor(.primary)
                            .contextMenu {
                                Button(action: {
                                    UIPasteboard.general.string = message.text
                                }) {
                                    Label("复制内容", systemImage: "doc.on.doc")
                                }
                            }
                    }
                }

                // Timestamp
                if let sendTime = message.sendTime {
                    Text(sendTime, style: .time)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                }

                // Action buttons — last AI message
                if !isUser && !message.text.isEmpty && !viewModel.isLoading {
                    HStack(spacing: 8) {
                        // Copy Button (Always visible for AI messages)
                        Button(action: {
                            UIPasteboard.general.string = message.text
                            #if os(iOS)
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            #endif
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showCopied = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showCopied = false
                                }
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 13))
                                    .foregroundColor(showCopied ? .green : .secondary)
                                Text(showCopied ? "已复制" : "复制")
                                    .font(.system(size: 13))
                                    .foregroundColor(showCopied ? .green : .secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        // Regenerate Button (Only for last message)
                        if message.id == viewModel.currentMessages.last?.id {
                            Button(action: {
                                viewModel.regenerateLastMessage()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    proxy?.scrollTo("bottom", anchor: .bottom)
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 13))
                                    Text("重试")
                                        .font(.system(size: 13))
                                }
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    .padding(.top, 2)
                }

                // Action buttons — last user message
                if isUser &&
                   !viewModel.isLoading &&
                   message.id == viewModel.currentMessages.last(where: { $0.role == .user })?.id {
                    HStack(spacing: 8) {
                        Spacer()
                        Button(action: { withAnimation { viewModel.startEditing(message: message) } }) {
                            HStack(spacing: 4) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 13))
                                Text("编辑")
                                    .font(.system(size: 13))
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            viewModel.regenerateLastMessage()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                proxy?.scrollTo("bottom", anchor: .bottom)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 13))
                                Text("重试")
                                    .font(.system(size: 13))
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 2)
                }
            }

            if !isUser { Spacer(minLength: 0) } // Allow full width for AI
        }
    }
}


// MARK: - Streaming Bubble (注视点渲染 Foveated Rendering)
struct StreamingBubble: View {
    let blocks: [String]
    let thinkingBlocks: [String]

    @AppStorage("lastThinkingExpandedState") private var thinkingExpanded = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                // v2.4: Filter empty thinking blocks to prevent empty "思考过程" frame
                let filteredThinkingBlocks = thinkingBlocks.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                if !filteredThinkingBlocks.isEmpty {
                    ThinkingContentView(blocks: filteredThinkingBlocks, isExpanded: $thinkingExpanded)
                }
                if !blocks.isEmpty {
                    // AI Streaming - 流式按语义块切分注视点渲染防 OOM
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                            if block.isEmpty {
                                Spacer().frame(height: 4)
                            } else {
                                MixedContentView(text: block, isStreaming: true)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundColor(.primary)
                }
            }
            Spacer(minLength: 0) // Allow full width
        }
    }
}

// MARK: - Typing Indicator
struct TypingIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(width: 8, height: 8)
                        .offset(y: isAnimating ? -4 : 0)
                        .animation(
                            .easeInOut(duration: 0.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                            value: isAnimating
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(UIColor.secondarySystemBackground).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Spacer()
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Input Area
struct InputArea: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @FocusState var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Updated Input Area (No Divider, Material Background)
            if let data = viewModel.selectedImageData, let uiImage = UIImage(data: data) {
                HStack {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .cornerRadius(8)
                        .clipped()
                    Button(action: {
                        viewModel.selectedImageItem = nil
                        viewModel.selectedImageData = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            HStack(alignment: .center, spacing: 12) {
                // Photo picker (Plus Icon)
                PhotosPicker(selection: $viewModel.selectedImageItem, matching: .images) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(Circle())
                }
                .onChange(of: viewModel.selectedImageItem) {
                    Task {
                        await MainActor.run { viewModel.loadImage() }
                    }
                }
                
                // Web Search Toggle (Global)
                if viewModel.webSearchEnabled {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            viewModel.isSearchContextEnabled.toggle()
                        }
                    }) {
                        Image(systemName: "globe")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(viewModel.isSearchContextEnabled ? .blue : .secondary)
                            .frame(width: 36, height: 36)
                            .background(viewModel.isSearchContextEnabled ? Color.blue.opacity(0.15) : Color.clear)
                            .clipShape(Circle())
                    }
                }

                // Text input — grows vertically, centered
                TextField("发消息…", text: $viewModel.inputText, axis: .vertical)
                    .focused($isInputFocused)
                    .lineLimit(1...8)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(18)

                // Send / Stop button — fixed size, always same height
                Button(action: {
                    if viewModel.isLoading {
                        viewModel.stopGeneration()
                    } else {
                        viewModel.sendMessage()
                        isInputFocused = false
                    }
                }) {
                    Image(systemName: viewModel.isLoading ? "stop.fill" : "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            viewModel.isLoading ? Color.red :
                            (viewModel.inputText.isEmpty && viewModel.selectedImageData == nil) ? Color.secondary.opacity(0.3) : Color.blue
                        )
                        .clipShape(Circle())
                }
                .disabled(!viewModel.isLoading && viewModel.inputText.isEmpty && viewModel.selectedImageData == nil)
                .animation(.easeInOut(duration: 0.2), value: viewModel.isLoading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(
            Color(UIColor.systemBackground)
                .ignoresSafeArea(edges: .bottom)
        )
        // Add subtle shadow to separate from content if needed, mimicking a tab bar feel
        .shadow(color: .black.opacity(0.05), radius: 0, x: 0, y: -0.5)
    }
}

// MARK: - Incognito Chat View (Separate Sheet)
struct IncognitoChatView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var mainViewModel: ChatViewModel
    @StateObject private var incognitoVM = ChatViewModel()
    @FocusState private var isInputFocused: Bool
    @State private var suppressAutoScroll = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        Spacer().frame(height: 12)

                        // Incognito Banner
                        VStack(spacing: 8) {
                            DashedBubbleIcon(size: 44, color: .white.opacity(0.8))
                                .padding(.bottom, 4)
                            Text("暂存对话")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("关闭后聊天内容将被丢弃，不会保存到历史记录。")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(colors: [.purple.opacity(0.6), .indigo.opacity(0.4)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .cornerRadius(16)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)

                        ForEach(incognitoVM.currentMessages) { msg in
                            ChatBubble(message: msg, proxy: proxy, suppressAutoScroll: $suppressAutoScroll)
                                .id(msg.id)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 3)
                        }

                        if incognitoVM.isLoading {
                            if !incognitoVM.streamingBlocks.isEmpty || !incognitoVM.streamingThinkingBlocks.isEmpty {
                                StreamingBubble(
                                    blocks: incognitoVM.streamingBlocks,
                                    thinkingBlocks: incognitoVM.streamingThinkingBlocks
                                )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 3)
                                .id("streaming_bubble")
                            } else {
                                TypingIndicator()
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 3)
                            }
                        }

                        Spacer().frame(height: 8).id("bottom")
                    }
                }
                .scrollDismissesKeyboard(.immediately)
                .simultaneousGesture(TapGesture().onEnded { _ in
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                })
                .safeAreaInset(edge: .top) {
                    HStack(spacing: 12) {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                                .frame(width: 36, height: 36)
                                .background(.ultraThinMaterial, in: Circle())
                        }

                        Spacer()

                        Menu {
                            ForEach(incognitoVM.allFavoriteModels, id: \.id) { model in
                                Button {
                                    incognitoVM.selectedGlobalModelID = model.id
                                } label: {
                                    if incognitoVM.selectedGlobalModelID == model.id {
                                        Label(model.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(model.displayName)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                DashedBubbleIcon(size: 14, color: .primary)
                                    .offset(y: 1)
                                Text(incognitoVM.currentDisplayModelName)
                                    .font(.headline)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Image(systemName: "chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }
                            .foregroundColor(.primary)
                            .frame(maxWidth: 200)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.ultraThinMaterial, in: Capsule())
                        }

                        Spacer()

                        Color.clear.frame(width: 36, height: 36)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(UIColor.systemBackground), ignoresSafeAreaEdges: .top)
                    .overlay(Divider(), alignment: .bottom)
                }
                .safeAreaInset(edge: .bottom) {
                    InputArea(isInputFocused: _isInputFocused)
                }
                .onChange(of: incognitoVM.currentMessages.count) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: incognitoVM.streamingBlocks.count) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onChange(of: incognitoVM.isLoading) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .environmentObject(incognitoVM as ChatViewModel)
        .onAppear {
            incognitoVM.isIncognitoMode = true
            incognitoVM.selectedGlobalModelID = mainViewModel.selectedGlobalModelID
            if let data = try? JSONEncoder().encode(mainViewModel.providers) {
                incognitoVM.savedProvidersData = data
            }
            incognitoVM.customSystemPrompt = mainViewModel.customSystemPrompt
            incognitoVM.temperature = mainViewModel.temperature
            incognitoVM.thinkingModeRaw = mainViewModel.thinkingModeRaw
            incognitoVM.createNewSession()
        }
    }
}

// MARK: - Corner Radius Helper
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
