import SwiftUI
import PhotosUI

// MARK: - 主设置页
struct SettingsView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject private var watchManager = WatchSessionManager.shared
    @State private var showDeleteAlert = false
    @State private var pendingDeleteIndexSet: IndexSet?
    @State private var showAddProviderSheet = false
    @State private var selectedAvatarItem: PhotosPickerItem? = nil

    var body: some View {
        Form {
            // MARK: 模型选择
            Section(header: Text("当前对话模型")) {
                if viewModel.allFavoriteModels.isEmpty {
                    Text("暂无模型，请进入供应商添加").font(.subheadline).foregroundColor(.gray)
                } else {
                    NavigationLink {
                        ModelSelectionRootView(viewModel: viewModel)
                    } label: {
                        HStack {
                            Text("选择模型")
                            Spacer()
                            Text(viewModel.currentDisplayModelName)
                                .font(.subheadline).foregroundColor(.secondary)
                                .lineLimit(1).truncationMode(.tail)
                        }
                    }
                }
            }

            // MARK: 供应商
            Section(header: Text("供应商配置")) {
                ForEach($viewModel.providers) { $provider in
                    NavigationLink {
                        ProviderDetailView(config: $provider, viewModel: viewModel)
                    } label: {
                        HStack {
                            Image(systemName: provider.icon)
                                .frame(width: 20)
                                .foregroundColor(provider.isPreset ? .blue : .orange)
                            VStack(alignment: .leading) {
                                Text(provider.name)
                                if provider.isValidated {
                                    Text("已验证 • \(provider.savedModels.count) 模型").font(.footnote).foregroundColor(.green)
                                } else if !provider.apiKey.isEmpty {
                                    Text("未验证").font(.footnote).foregroundColor(.orange)
                                } else {
                                    Text("无 Key").font(.footnote).foregroundColor(.gray)
                                }
                            }
                        }
                    }
                }
                .onDelete { idx in
                    pendingDeleteIndexSet = idx
                    showDeleteAlert = true
                }
                Button { showAddProviderSheet = true } label: {
                    Label("添加自定义供应商", systemImage: "plus.circle").foregroundColor(.blue)
                }
            }

            // MARK: 子菜单导航
            Section {
                NavigationLink {
                    AppearanceSettingsView(viewModel: viewModel, selectedAvatarItem: $selectedAvatarItem)
                } label: {
                    Label("界面与显示", systemImage: "paintbrush")
                }
                
                NavigationLink {
                    ModelDialogSettingsView(viewModel: viewModel)
                } label: {
                    Label("模型与对话", systemImage: "slider.horizontal.3")
                }
                
                NavigationLink {
                    MemorySettingsView(viewModel: viewModel)
                } label: {
                    HStack {
                        Label("记忆与向量", systemImage: "brain.head.profile")
                        Spacer()
                        Text(viewModel.memoryEnabled ? "已启用" : "已禁用")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                }
            }
            
            // MARK: 联网搜索
            Section(header: Text("联网搜索")) {
                Toggle("启用全局搜索代理", isOn: $viewModel.webSearchEnabled)
                if viewModel.webSearchEnabled {
                    NavigationLink {
                        WebSearchURLEditView(url: $viewModel.webSearchWorkerURL)
                    } label: {
                        HStack {
                            Text("搜索代理地址")
                            Spacer()
                            Text(viewModel.webSearchWorkerURL.isEmpty ? "未配置" : viewModel.webSearchWorkerURL.replacingOccurrences(of: "https://", with: ""))
                                .font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                        }
                    }
                    NavigationLink {
                        WebSearchAuthKeyEditView(authKey: $viewModel.webSearchAuthKey)
                    } label: {
                        HStack {
                            Text("鉴权密钥")
                            Spacer()
                            Text(viewModel.webSearchAuthKey.isEmpty ? "未设置" : "••••••")
                                .font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // MARK: 高级与同步
            Section {
                NavigationLink {
                    AdvancedSyncSettingsView(viewModel: viewModel, watchManager: watchManager)
                } label: {
                    Label("高级与同步", systemImage: "gearshape.2")
                }
            }

            Section {
                Button(role: .destructive) { viewModel.clearCurrentChat() } label: {
                    Text("清空聊天记录").frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("设置")
        .alert("确认删除供应商？", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) { pendingDeleteIndexSet = nil }
            Button("删除", role: .destructive) {
                if let offsets = pendingDeleteIndexSet {
                    viewModel.providers.remove(atOffsets: offsets)
                    viewModel.saveProviders()
                }
                pendingDeleteIndexSet = nil
            }
        } message: { Text("此操作不可恢复。") }
        .sheet(isPresented: $showAddProviderSheet) {
            NavigationStack { AddProviderView(viewModel: viewModel) }
        }
    }
}

// MARK: - 界面与显示子页面
struct AppearanceSettingsView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var selectedAvatarItem: PhotosPickerItem?
    
    var body: some View {
        Form {
            Section(header: Text("界面设置")) {
                Toggle("显示模型名称", isOn: $viewModel.showModelNameInNavBar)
                Toggle("启用振动反馈", isOn: $viewModel.enableHapticFeedback)
                Toggle("消息气泡动画", isOn: $viewModel.enableMessageAnimation)
                
                Picker("显示模式", selection: $viewModel.preferredColorSchemeRaw) {
                    Text("跟随系统").tag("system")
                    Text("浅色模式").tag("light")
                    Text("深色模式").tag("dark")
                }
                
                Picker("主题配色", selection: $viewModel.currentTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        HStack(spacing: 6) {
                            Circle().fill(theme.userBubbleColor).frame(width: 10, height: 10)
                            Circle().fill(theme.botBubbleColor).frame(width: 10, height: 10)
                            Text(theme.rawValue)
                        }.tag(theme)
                    }
                }
            }
            
            Section(header: Text("个人资料")) {
                HStack {
                    Text("用户头像")
                    Spacer()
                    PhotosPicker(selection: $selectedAvatarItem, matching: .images, photoLibrary: .shared()) {
                        if !viewModel.userAvatarData.isEmpty, let uiImage = UIImage(data: viewModel.userAvatarData) {
                            Image(uiImage: uiImage)
                                .resizable().scaledToFill()
                                .frame(width: 40, height: 40).clipShape(Circle())
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable().frame(width: 40, height: 40).foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: selectedAvatarItem) { newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                if let downsampled = data.downsampled(to: 150) {
                                    // jpegData 返回 Optional，用 nil-coalescing 回退到原始 data
                                    await MainActor.run { viewModel.userAvatarData = downsampled.jpegData(compressionQuality: 0.8) ?? data }
                                } else {
                                    await MainActor.run { viewModel.userAvatarData = data }
                                }
                            }
                        }
                    }
                    if !viewModel.userAvatarData.isEmpty {
                        Button(role: .destructive) {
                            withAnimation { viewModel.userAvatarData = Data(); selectedAvatarItem = nil }
                        } label: { Image(systemName: "trash") }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
                HStack {
                    Text("显示名称"); Spacer()
                    TextField("用户", text: $viewModel.userName)
                        .multilineTextAlignment(.trailing).foregroundColor(.secondary)
                }
            }
            
            Section(header: Text("文本渲染")) {
                Picker("Markdown 渲染", selection: $viewModel.markdownRenderMode) {
                    ForEach(MarkdownRenderMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                Toggle("LaTeX 渲染", isOn: $viewModel.latexRenderingEnabled)
                if viewModel.latexRenderingEnabled {
                    Toggle("高级 LaTeX 模式", isOn: $viewModel.advancedLatexEnabled)
                }
            }
        }
        .navigationTitle("界面与显示")
    }
}

// MARK: - 模型与对话子页面
struct ModelDialogSettingsView: View {
    @ObservedObject var viewModel: ChatViewModel
    
    var body: some View {
        Form {
            Section(header: Text("模型参数")) {
                Picker("温度参数", selection: $viewModel.temperature) {
                    ForEach(0...20, id: \.self) { i in
                        let val = Double(i) / 10.0
                        Text(String(format: "%.1f", val)).tag(val)
                    }
                }
                HStack {
                    Text("历史消息数量"); Spacer()
                    TextField("10", value: $viewModel.historyMessageCount, format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        .frame(width: 44).textFieldStyle(.plain)
                    Text("条").foregroundColor(.secondary)
                }
                Picker("思考模式", selection: $viewModel.thinkingMode) {
                    ForEach(ThinkingMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                NavigationLink {
                    SystemPromptEditView(prompt: $viewModel.customSystemPrompt)
                } label: {
                    HStack {
                        Text("系统提示词"); Spacer()
                        Text(viewModel.customSystemPrompt.isEmpty ? "未设置" : "已设置")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                }
            }
            
            Section(header: Text("上下文信息")) {
                Toggle("向 AI 传递当前时间", isOn: $viewModel.sendTimeToAI)
                Toggle("向 AI 传递当前位置", isOn: $viewModel.sendLocationToAI)
            }
            
            Section(header: Text("辅助功能")) {
                NavigationLink {
                    HelperModelSelectionView(viewModel: viewModel)
                } label: {
                    HStack {
                        Text("辅助模型"); Spacer()
                        Text(viewModel.helperGlobalModelID.isEmpty ? "未设置" : "已设置")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                }
                Toggle("自动重试失败请求", isOn: $viewModel.autoRetryEnabled)
                if viewModel.autoRetryEnabled {
                    HStack {
                        Text("最大重试次数"); Spacer()
                        Stepper("\(viewModel.maxRetries) 次", value: $viewModel.maxRetries, in: 1...10)
                    }
                }
            }
        }
        .navigationTitle("模型与对话")
    }
}

// MARK: - 高级与同步子页面
struct AdvancedSyncSettingsView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var watchManager: WatchSessionManager
    @State private var isValidating = false
    @State private var validationResult: String? = nil
    
    var body: some View {
        Form {
            Section(header: Text("诊断")) {
                Button {
                    isValidating = true
                    Task {
                        let result = await viewModel.validateAllProviders()
                        await MainActor.run {
                            isValidating = false
                            validationResult = "✅ \(result.success) 成功, ❌ \(result.failed) 失败"
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "checkmark.shield"); Text("批量验证供应商"); Spacer()
                        if isValidating { ProgressView() }
                        else if let r = validationResult { Text(r).font(.subheadline).foregroundColor(.secondary) }
                    }
                }.disabled(isValidating)
                if let progress = viewModel.migrationProgress {
                    HStack { ProgressView(); Text(progress).font(.subheadline).foregroundColor(.secondary) }
                }
            }
            
            Section(header: Text("云端数据")) {
                NavigationLink {
                    CloudDataView(viewModel: viewModel)
                } label: {
                    Label("云端数据管理", systemImage: "icloud")
                }
            }
            
            Section(header: Text("Watch 同步"), footer: Text("所有配置、聊天记录和记忆会自动同步到手表。")) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(.blue).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("自动双向同步")
                        Text("配置 + 聊天记录 + 记忆").font(.system(size: 10)).foregroundColor(.secondary)
                    }
                    Spacer()
                    if watchManager.isWatchReachable {
                        HStack(spacing: 4) {
                            Circle().fill(.green).frame(width: 8, height: 8)
                            Text("已连接").font(.system(size: 10)).foregroundColor(.green)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Circle().fill(.secondary.opacity(0.3)).frame(width: 8, height: 8)
                            Text("离线").font(.system(size: 10)).foregroundColor(.secondary)
                        }
                    }
                }
                Button {
                    watchManager.isSyncing = true
                    watchManager.lastSyncStatus = "⏳ 正在推送..."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.watchManager.pushConfigToWatch(force: true)
                        self.watchManager.pushFullDataToWatch(force: true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.watchManager.isSyncing = false
                            if self.watchManager.lastSyncStatus?.contains("❌") != true {
                                self.watchManager.lastSyncStatus = "✅ 已推送 (\(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)))"
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        if watchManager.isSyncing { ProgressView().frame(width: 20, height: 20) }
                        else { Image(systemName: "arrow.clockwise").foregroundColor(.blue).frame(width: 20) }
                        Text(watchManager.isSyncing ? "同步中..." : "立即同步到 Watch")
                    }
                }.disabled(watchManager.isSyncing)
                if let status = watchManager.lastSyncStatus {
                    HStack(spacing: 6) {
                        if status.contains("✅") { Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.subheadline) }
                        else if status.contains("❌") { Image(systemName: "xmark.circle.fill").foregroundColor(.red).font(.subheadline) }
                        else if status.contains("⏳") { Image(systemName: "arrow.triangle.2.circlepath").foregroundColor(.blue).font(.subheadline) }
                        else { Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange).font(.subheadline) }
                        Text(status).font(.system(size: 12)).foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("高级与同步")
    }
}

// MARK: - 记忆与向量设置
struct MemorySettingsView: View {
    @ObservedObject var viewModel: ChatViewModel

    var embeddingModels: [AIModelInfo] {
        guard !viewModel.embeddingProviderID.isEmpty,
              let uuid = UUID(uuidString: viewModel.embeddingProviderID),
              let provider = viewModel.providers.first(where: { $0.id == uuid }) else { return [] }
        return provider.availableModels.filter { $0.id.localizedCaseInsensitiveContains("embed") }.sorted { $0.id < $1.id }
    }

    var body: some View {
        Form {
            Section(header: Text("记忆系统")) {
                Toggle("启用记忆功能", isOn: $viewModel.memoryEnabled)
                if viewModel.memoryEnabled {
                    Toggle("删除记忆需确认", isOn: $viewModel.memoryDeleteConfirm)
                        .font(.subheadline)
                    NavigationLink {
                        MemoryListView(viewModel: viewModel)
                    } label: {
                        HStack {
                            Text("记忆管理")
                            Spacer()
                            Text("\(viewModel.memories.count) 条").font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                    NavigationLink {
                        MemoryRecycleBinView(viewModel: viewModel)
                    } label: {
                        HStack {
                            Text("记忆回收站")
                            Spacer()
                            if !viewModel.deletedMemoriesBin.isEmpty {
                                Text("\(viewModel.deletedMemoriesBin.count) 条").font(.subheadline).foregroundColor(.red)
                            }
                        }
                    }
                }
            }
            
            if viewModel.memoryEnabled {
                Section(header: Text("记忆检索"), footer: Text("注入对话上下文的相关记忆最大数量（1-20）")) {
                    Stepper("最大检索记忆数: \(viewModel.memoryMaxRetrievalCount)", value: $viewModel.memoryMaxRetrievalCount, in: 1...20)
                }
                Section(footer: Text("检索记忆所需的最低相似度分数。值越高，匹配越严格。")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("相似度阈值: \(Int(viewModel.memoryRetrievalThreshold * 100))%")
                        HStack {
                            Text("宽松").font(.caption2).foregroundColor(.secondary)
                            Slider(value: $viewModel.memoryRetrievalThreshold, in: 0...1, step: 0.05)
                            Text("严格").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }


                Section(header: Text("向量配置 (Embedding)")) {
                    Picker("向量供应商", selection: $viewModel.embeddingProviderID) {
                        Text("未配置").tag("")
                        Text("Workers AI ☁️").tag("workersAI")
                        ForEach(viewModel.providers) { p in
                            Text(p.name).tag(p.id.uuidString)
                        }
                    }

                    if viewModel.embeddingProviderID == "workersAI" {
                        NavigationLink {
                            WorkersAIURLEditView(url: $viewModel.workersAIEmbeddingURL)
                        } label: {
                            HStack {
                                Text("端点 URL")
                                Spacer()
                                Text(viewModel.workersAIEmbeddingURL.replacingOccurrences(of: "https://", with: ""))
                                    .font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                            }
                        }
                    } else if !viewModel.embeddingProviderID.isEmpty {
                        if embeddingModels.isEmpty {
                            NavigationLink {
                                EmbeddingModelEditView(modelID: $viewModel.embeddingModelID)
                            } label: {
                                HStack {
                                    Text("模型 ID")
                                    Spacer()
                                    Text(viewModel.embeddingModelID.isEmpty ? "手动输入" : viewModel.embeddingModelID)
                                        .font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                                }
                            }
                        } else {
                            Picker("选择模型", selection: $viewModel.embeddingModelID) {
                                Text("未选择").tag("")
                                ForEach(embeddingModels) { m in
                                    Text(m.displayName ?? m.id).tag(m.id)
                                }
                            }
                        }
                    }

                    if !viewModel.embeddingProviderID.isEmpty {
                        Button {
                            Task {
                                await viewModel.probeEmbeddingDimension()
                                await viewModel.checkAndAutoMigrate()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("同步维度")
                                Spacer()
                                if viewModel.detectedEmbeddingDim > 0 {
                                    Text("\(viewModel.detectedEmbeddingDim)d").font(.subheadline).foregroundColor(.secondary)
                                }
                            }
                        }
                        if let progress = viewModel.migrationProgress {
                            HStack { ProgressView(); Text(progress).font(.subheadline).foregroundColor(.secondary) }
                        }
                    }
                }
            }
        }
        .navigationTitle("记忆设置")
    }
}

// MARK: - Workers AI URL 编辑
struct WorkersAIURLEditView: View {
    @Binding var url: String
    @State private var draft: String = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            Section(header: Text("Workers AI 向量端点")) {
                TextField("", text: $draft, prompt: Text("https://your-domain.com").foregroundColor(.gray))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }
            Section(footer: Text("部署在 Cloudflare Workers 上的向量嵌入服务地址。")) {
                Button("保存") {
                    url = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    dismiss()
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("端点 URL")
        .onAppear { draft = url }
    }
}

// MARK: - Web Search URL 编辑 (v2.5)
struct WebSearchURLEditView: View {
    @Binding var url: String
    @State private var draft: String = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            Section(header: Text("搜索代理地址")) {
                TextField("", text: $draft, prompt: Text("https://your-worker.workers.dev").foregroundColor(.gray))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }
            Section(footer: Text("部署在 Cloudflare Workers 上的联网搜索代理服务。请求格式为 Serper API 兼容。")) {
                Button("保存") {
                    url = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    dismiss()
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("搜索代理")
        .onAppear { draft = url }
    }
}

// MARK: - Web Search Auth Key 编辑 (v2.5)
struct WebSearchAuthKeyEditView: View {
    @Binding var authKey: String
    @State private var draft: String = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            Section(header: Text("鉴权密钥"), footer: Text("在 Cloudflare Worker 环境变量中设置 AUTH_KEY，此处填写相同的值。留空则不鉴权。")) {
                SecureField("", text: $draft, prompt: Text("输入密钥").foregroundColor(.gray))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section {
                Button("保存") {
                    authKey = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    dismiss()
                }
            }
        }
        .navigationTitle("鉴权密钥")
        .onAppear { draft = authKey }
    }
}

// MARK: - Embedding 模型编辑
struct EmbeddingModelEditView: View {
    @Binding var modelID: String
    @State private var draft: String = ""
    @Environment(\.dismiss) var dismiss

    private let examples = ["gemini-embedding-001", "text-embedding-3-small", "text-embedding-ada-002", "BAAI/bge-large-zh-v1.5"]

    var body: some View {
        Form {
            Section(header: Text("Embedding 模型名称")) {
                TextField("模型 ID", text: $draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section(header: Text("常用模型")) {
                ForEach(examples, id: \.self) { ex in
                    Button(ex) { draft = ex }.font(.subheadline)
                }
            }
            Section {
                Button("保存") {
                    modelID = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    dismiss()
                }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("Embedding 模型")
        .onAppear { draft = modelID }
    }
}

// MARK: - 辅助模型选择
struct HelperModelSelectionView: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        List {
            Section(footer: Text("辅助模型用于标题生成、记忆提取等后台任务，不影响主对话。")) {
                Button {
                    viewModel.helperGlobalModelID = ""
                } label: {
                    HStack {
                        Text("跟随当前模型")
                        Spacer()
                        if viewModel.helperGlobalModelID.isEmpty {
                            Image(systemName: "checkmark").foregroundColor(.blue)
                        }
                    }
                }
            }
            Section(header: Text("收藏模型")) {
                ForEach(viewModel.allFavoriteModels, id: \.id) { item in
                    Button {
                        viewModel.helperGlobalModelID = item.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.displayName)
                                Text(item.providerName).font(.footnote).foregroundColor(.gray)
                            }
                            Spacer()
                            if viewModel.helperGlobalModelID == item.id {
                                Image(systemName: "checkmark").foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("辅助模型")
    }
}

// MARK: - 云端数据管理
struct CloudDataView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var showOverwriteAlert = false
    @State private var isUploading = false

    private var lastSyncText: String? {
        guard viewModel.lastCloudSyncTime > 0 else { return nil }
        let date = Date(timeIntervalSince1970: viewModel.lastCloudSyncTime)
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }

    var body: some View {
        List {
            if let syncTime = lastSyncText {
                Section {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath").font(.footnote)
                        Text("上次同步 \(syncTime)").font(.footnote)
                    }.foregroundColor(.secondary)
                }
            }

            // 上传
            Section(footer: Text("将当前全部配置、记忆和聊天记录上传到云端。Workers 会自动保留历史版本。")) {
                Button {
                    guard !isUploading else { return }
                    isUploading = true
                    Task { await viewModel.uploadConfigToCloud(); isUploading = false }
                } label: {
                    HStack {
                        if isUploading {
                            ProgressView().frame(width: 20, height: 20)
                            Text("正在上传...").foregroundColor(.secondary)
                        } else {
                            Image(systemName: "icloud.and.arrow.up.fill").foregroundColor(.blue).frame(width: 20)
                            Text("上传到云端")
                        }
                    }
                }.disabled(isUploading || viewModel.cloudBackupURL.isEmpty)
            }

            if let status = viewModel.cloudUploadStatus {
                Section {
                    HStack(spacing: 8) {
                        if status.contains("✅") { Image(systemName: "checkmark.circle.fill").foregroundColor(.green) }
                        else if status.contains("❌") { Image(systemName: "xmark.circle.fill").foregroundColor(.red) }
                        Text(status).font(.subheadline).foregroundColor(.secondary)
                    }
                }
            }

            // 恢复
            Section(header: Text("从云端恢复")) {
                // 增量合并
                NavigationLink {
                    CloudImportSelectionView(viewModel: viewModel)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.triangle.merge").foregroundColor(.cyan).frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("增量合并")
                            Text("选择要合并的数据项，保留本地已有数据").font(.system(size: 10)).foregroundColor(.secondary)
                        }
                    }
                }

                NavigationLink {
                    CloudVersionListView(viewModel: viewModel)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath").foregroundColor(.indigo).frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("历史版本")
                            Text("浏览和恢复 Workers 保留的历史备份").font(.system(size: 10)).foregroundColor(.secondary)
                        }
                    }
                }

                Button(role: .destructive) { showOverwriteAlert = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.counterclockwise.circle.fill").foregroundColor(.red).frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("完整覆盖").foregroundColor(.red)
                            Text("清空本地，完全恢复云端状态").font(.system(size: 10)).foregroundColor(.secondary)
                        }
                    }
                }
            }

            // 设置
            Section {
                NavigationLink {
                    CloudBackupSettingsView(viewModel: viewModel)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "gearshape.fill").foregroundColor(.gray).frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("云备份设置")
                            if !viewModel.cloudBackupURL.isEmpty {
                                Text(viewModel.cloudBackupURL.replacingOccurrences(of: "https://", with: ""))
                                    .font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("云端数据")
        .alert("确定要完整覆盖吗？", isPresented: $showOverwriteAlert) {
            Button("取消", role: .cancel) {}
            Button("覆盖本地数据", role: .destructive) {
                Task {
                    do {
                        try await viewModel.downloadConfigFromCloud(mode: .overwrite)
                        viewModel.cloudUploadStatus = "✅ 完整恢复成功"
                        viewModel.lastCloudSyncTime = Date().timeIntervalSince1970
                    } catch {
                        viewModel.cloudUploadStatus = "❌ 恢复失败: \(error.localizedDescription)"
                    }
                }
            }
        } message: { Text("所有本地配置、聊天记录和记忆都将被替换为云端版本。此操作无法撤销。") }
    }
}

// MARK: - 云备份设置
struct CloudBackupSettingsView: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        Form {
            Section(header: Text("云端配置")) {
                TextField("备份 URL", text: $viewModel.cloudBackupURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField("Auth Key", text: $viewModel.cloudBackupAuthKey)
                Toggle("自动备份", isOn: $viewModel.autoBackupEnabled)
            }
            Section(footer: Text("备份 URL 为 Cloudflare R2 的 Workers 端点，Auth Key 用于鉴权。")) {
                EmptyView()
            }
        }
        .navigationTitle("云备份设置")
    }
}

// MARK: - 历史版本列表
struct CloudVersionListView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var versions: [ChatViewModel.BackupVersion] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var operationStatus: String? = nil
    @State private var isDeduplicating = false

    var body: some View {
        List {
            if isLoading {
                Section { HStack { ProgressView(); Text("加载中...").foregroundColor(.secondary) } }
            } else if let error = errorMessage {
                Section {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        Text(error).font(.subheadline).foregroundColor(.secondary)
                    }
                    Button { Task { await loadVersions() } } label: { Label("重试", systemImage: "arrow.clockwise") }
                }
            } else if versions.isEmpty {
                Section { Text("暂无历史版本").foregroundColor(.secondary) }
            } else {
                if let current = versions.first(where: { $0.version == 0 }) {
                    Section(header: Text("当前版本")) { versionRow(current) }
                }
                let history = versions.filter { $0.version > 0 }
                if !history.isEmpty {
                    Section(header: Text("历史版本 (\(history.count))")) {
                        ForEach(history) { v in versionRow(v) }
                    }
                }
            }

            if !versions.isEmpty {
                Section(header: Text("工具")) {
                    Button {
                        guard !isDeduplicating else { return }
                        isDeduplicating = true
                        Task {
                            do {
                                let result = try await viewModel.deduplicateBackups()
                                operationStatus = result.removed > 0 ? "✅ \(result.message)" : "ℹ️ \(result.message)"
                                await loadVersions(forceRefresh: true)
                            } catch {
                                operationStatus = "❌ 去重失败: \(error.localizedDescription)"
                            }
                            isDeduplicating = false
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isDeduplicating { ProgressView().frame(width: 18, height: 18); Text("去重中...").foregroundColor(.secondary) }
                            else { Image(systemName: "wand.and.stars").foregroundColor(.purple).frame(width: 18); Text("一键去重") }
                        }
                    }.disabled(isDeduplicating)

                    Button { Task { await loadVersions(forceRefresh: true) } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise").foregroundColor(.blue).frame(width: 18)
                            Text("刷新列表")
                        }
                    }
                }
            }

            if let status = operationStatus {
                Section {
                    HStack(spacing: 6) {
                        if status.contains("✅") { Image(systemName: "checkmark.circle.fill").foregroundColor(.green) }
                        else if status.contains("❌") { Image(systemName: "xmark.circle.fill").foregroundColor(.red) }
                        else { Image(systemName: "info.circle.fill").foregroundColor(.blue) }
                        Text(status).font(.subheadline).foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("历史版本")
        .task { await loadVersions() }
    }

    private func loadVersions(forceRefresh: Bool = false) async {
        isLoading = true; errorMessage = nil
        do {
            versions = try await viewModel.fetchBackupVersions(forceRefresh: forceRefresh)
            isLoading = false
        } catch {
            if let cached = viewModel.loadCachedVersions() {
                versions = cached; operationStatus = "⚠️ 已使用本地缓存"; isLoading = false
            } else { errorMessage = error.localizedDescription; isLoading = false }
        }
    }

    @ViewBuilder
    private func versionRow(_ version: ChatViewModel.BackupVersion) -> some View {
        NavigationLink {
            BackupPreviewView(viewModel: viewModel, version: version)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: version.version == 0 ? "doc.fill" : "clock")
                            .font(.subheadline)
                            .foregroundColor(version.version == 0 ? .blue : .secondary)
                        Text(version.displayName)
                    }
                    Text(version.displaySubtitle).font(.system(size: 10)).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "eye").font(.subheadline).foregroundColor(.cyan)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task {
                    do {
                        try await viewModel.restoreBackupVersion(key: version.key, mode: .overwrite)
                        operationStatus = "✅ 已恢复 \(version.label)"
                    } catch { operationStatus = "❌ 恢复失败: \(error.localizedDescription)" }
                }
            } label: { Label("恢复", systemImage: "arrow.counterclockwise") }.tint(.blue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if version.version > 0 {
                Button(role: .destructive) {
                    Task {
                        do {
                            try await viewModel.deleteBackupVersion(key: version.key)
                            await MainActor.run { viewModel.cachedVersions = nil }
                            await loadVersions(forceRefresh: true)
                            operationStatus = "✅ 已删除 \(version.label)"
                        } catch { operationStatus = "❌ 删除失败: \(error.localizedDescription)" }
                    }
                } label: { Label("删除", systemImage: "trash") }
            }
        }
        .contextMenu {
            Button {
                Task {
                    do {
                        try await viewModel.restoreBackupVersion(key: version.key, mode: .overwrite)
                        operationStatus = "✅ 已恢复 \(version.label)"
                    } catch { operationStatus = "❌ 恢复失败: \(error.localizedDescription)" }
                }
            } label: { Label("恢复", systemImage: "arrow.counterclockwise") }
            if version.version > 0 {
                Divider()
                Button(role: .destructive) {
                    Task {
                        do {
                            try await viewModel.deleteBackupVersion(key: version.key)
                            await MainActor.run { viewModel.cachedVersions = nil }
                            await loadVersions(forceRefresh: true)
                            operationStatus = "✅ 已删除 \(version.label)"
                        } catch { operationStatus = "❌ 删除失败: \(error.localizedDescription)" }
                    }
                } label: { Label("删除", systemImage: "trash") }
            }
        }
    }
}

// MARK: - 备份版本预览
struct BackupPreviewView: View {
    @ObservedObject var viewModel: ChatViewModel
    let version: ChatViewModel.BackupVersion
    @State private var preview: ChatViewModel.BackupPreview? = nil
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var showRestoreAlert = false
    @State private var restoreStatus: String? = nil

    var body: some View {
        List {
            if isLoading {
                Section { HStack { ProgressView(); Text("加载预览...").foregroundColor(.secondary) } }
            } else if let error = errorMessage {
                Section {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        Text(error).font(.subheadline).foregroundColor(.secondary)
                    }
                }
            } else if let p = preview {
                Section(header: Text("概览")) {
                    infoRow("大小", value: p.sizeText)
                    infoRow("供应商", value: "\(p.providers ?? 0) 个")
                    infoRow("记忆", value: "\(p.memories ?? 0) 条")
                    infoRow("会话", value: "\(p.sessions ?? 0) 个")
                }
                if let d = p.details {
                    Section(header: Text("配置详情")) {
                        if let model = d.selectedModel, !model.isEmpty { infoRow("当前模型", value: model) }
                        if let temp = d.temperature { infoRow("温度", value: String(format: "%.1f", temp)) }
                        if let count = d.historyCount { infoRow("历史条数", value: "\(count)") }
                    }
                }
                Section(header: Text("恢复方式")) {
                    Button {
                        restoreWithMode(.merge)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.triangle.merge").foregroundColor(.cyan).frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("增量合并")
                                Text("保留本地数据，仅合并云端新内容").font(.system(size: 10)).foregroundColor(.secondary)
                            }
                        }
                    }
                    Button(role: .destructive) { showRestoreAlert = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.counterclockwise.circle.fill").foregroundColor(.red).frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("完整覆盖").foregroundColor(.red)
                                Text("清空本地，完全恢复此版本").font(.system(size: 10)).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            if let status = restoreStatus {
                Section {
                    HStack(spacing: 6) {
                        if status.contains("✅") { Image(systemName: "checkmark.circle.fill").foregroundColor(.green) }
                        else if status.contains("❌") { Image(systemName: "xmark.circle.fill").foregroundColor(.red) }
                        Text(status).font(.subheadline).foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle(version.displayName)
        .task {
            do {
                preview = try await viewModel.previewBackupVersion(key: version.key, uuid: version.uuid)
                isLoading = false
            } catch { errorMessage = error.localizedDescription; isLoading = false }
        }
        .alert("确认完整覆盖？", isPresented: $showRestoreAlert) {
            Button("取消", role: .cancel) {}
            Button("覆盖本地数据", role: .destructive) {
                restoreWithMode(.overwrite)
            }
        } message: { Text("所有本地数据将被此版本替换，无法撤销。") }
    }

    private func restoreWithMode(_ mode: ChatViewModel.ImportMode) {
        Task {
            do {
                try await viewModel.restoreBackupVersion(key: version.key, mode: mode)
                restoreStatus = mode == .merge ? "✅ 增量合并成功" : "✅ 覆盖恢复成功"
            } catch {
                restoreStatus = "❌ 恢复失败: \(error.localizedDescription)"
            }
        }
    }

    @ViewBuilder
    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
    }
}

// MARK: - 模型选择层级视图
struct ModelSelectionRootView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var searchText = ""

    var filteredFavorites: [(id: String, displayName: String, providerName: String)] {
        if searchText.isEmpty { return viewModel.allFavoriteModels }
        return viewModel.allFavoriteModels.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.providerName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var filteredRecent: [(id: String, displayName: String, providerName: String)] {
        if searchText.isEmpty { return viewModel.recentlyUsedModels }
        return viewModel.recentlyUsedModels.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.providerName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            TextField("搜索模型...", text: $searchText).textInputAutocapitalization(.never)

            if !filteredRecent.isEmpty {
                Section(header: Text("🕐 最近使用")) {
                    ForEach(filteredRecent, id: \.id) { item in
                        let isSelected = viewModel.selectedGlobalModelID == item.id
                        Button { viewModel.selectedGlobalModelID = item.id } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.displayName).foregroundColor(isSelected ? .blue : .primary)
                                    Text(item.providerName).font(.footnote).foregroundColor(.gray)
                                }
                                Spacer()
                                if isSelected { Image(systemName: "checkmark").foregroundColor(.blue) }
                            }
                        }
                    }
                }
            }

            if !filteredFavorites.isEmpty {
                Section(header: Text("⭐ 收藏模型")) {
                    ForEach(filteredFavorites, id: \.id) { item in
                        let isSelected = viewModel.selectedGlobalModelID == item.id
                        Button { viewModel.selectedGlobalModelID = item.id } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.displayName).foregroundColor(isSelected ? .blue : .primary)
                                    Text(item.providerName).font(.footnote).foregroundColor(.gray)
                                }
                                Spacer()
                                if isSelected { Image(systemName: "checkmark").foregroundColor(.blue) }
                            }
                        }
                    }
                }
            }

            if searchText.isEmpty {
                Section(header: Text("所有模型")) {
                    ForEach(viewModel.providers) { provider in
                        if !provider.availableModels.isEmpty {
                            NavigationLink {
                                ModelListForProviderView(viewModel: viewModel, provider: provider)
                            } label: {
                                HStack {
                                    Image(systemName: provider.icon).frame(width: 20)
                                    Text(provider.name)
                                    Spacer()
                                    Text("\(provider.availableModels.count)").font(.subheadline).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("选择模型")
    }
}

struct ModelListForProviderView: View {
    @ObservedObject var viewModel: ChatViewModel
    let provider: ProviderConfig
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""

    var filteredModels: [AIModelInfo] {
        if searchText.isEmpty { return provider.availableModels }
        return provider.availableModels.filter {
            $0.id.localizedCaseInsensitiveContains(searchText) ||
            ($0.displayName?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        List {
            TextField("搜索模型...", text: $searchText).textInputAutocapitalization(.never)
            ForEach(filteredModels) { model in
                let compositeID = "\(provider.id.uuidString)|\(model.id)"
                let isSelected = viewModel.selectedGlobalModelID == compositeID
                Button {
                    viewModel.selectedGlobalModelID = compositeID
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(model.displayName ?? model.id).foregroundColor(isSelected ? .blue : .primary)
                            if model.displayName != nil { Text(model.id).font(.footnote).foregroundColor(.gray) }
                        }
                        Spacer()
                        if isSelected { Image(systemName: "checkmark").foregroundColor(.blue) }
                    }
                }
            }
        }
        .navigationTitle(provider.name)
    }
}

// MARK: - 供应商详情 (完整版，支持多 Key)
struct ProviderDetailView: View {
    @Binding var config: ProviderConfig
    @ObservedObject var viewModel: ChatViewModel
    @State private var isFetching = false
    @State private var fetchError: String? = nil
    @State private var fetchedOnlineModels: [AIModelInfo] = []
    @State private var modelSearchText = ""
    @State private var draftConfig: ProviderConfig = ProviderConfig(name: "", baseURL: "", apiKey: "", isPreset: false, icon: "")
    @State private var modelToConfigure: AIModelInfo?
    @State private var showAddKeySheet = false
    @State private var editingKeyIndex: Int? = nil  // 正在编辑的 Key 索引

    var body: some View {
        Form {
            connectionSection
            apiKeysSection
            modelManagementSection
            availableModelsSection
        }
        .navigationTitle(config.name.isEmpty ? "供应商配置" : config.name)
        .onAppear { draftConfig = config }
        .onDisappear {
            // 合并 viewModel 中可能已通过子页面直接添加的自定义模型，防止被旧快照覆盖
            if let latestFromVM = viewModel.providers.first(where: { $0.id == draftConfig.id }) {
                for model in latestFromVM.availableModels where model.isCustom == true {
                    if !draftConfig.availableModels.contains(where: { $0.id == model.id }) {
                        draftConfig.availableModels.insert(model, at: 0)
                        if latestFromVM.isModelFavorited(model.id) && !draftConfig.isModelFavorited(model.id) {
                            draftConfig.favoriteModelIds.append(model.id)
                        }
                    }
                }
            }
            viewModel.updateProvider(draftConfig)
        }
        .sheet(item: $modelToConfigure) { model in
            let compositeID = "\(draftConfig.id.uuidString)|\(model.id)"
            let settings = viewModel.modelSettings[compositeID] ?? ModelSettings()
            ModelCapabilityConfigView(viewModel: viewModel, modelID: compositeID, settings: settings)
        }
        .sheet(isPresented: $showAddKeySheet) {
            NavigationStack { AddAPIKeyView(apiKeys: $draftConfig.apiKeys) }
        }
        .sheet(item: Binding(
            get: { editingKeyIndex.map { EditKeyTarget(index: $0) } },
            set: { editingKeyIndex = $0?.index }
        )) { target in
            NavigationStack {
                EditAPIKeyView(key: Binding(
                    get: { draftConfig.apiKeys.indices.contains(target.index) ? draftConfig.apiKeys[target.index] : "" },
                    set: { if draftConfig.apiKeys.indices.contains(target.index) { draftConfig.apiKeys[target.index] = $0 } }
                ))
            }
        }
    }

    @ViewBuilder
    private var connectionSection: some View {
        Section(header: Text("连接信息")) {
            TextField("名称", text: $draftConfig.name)
            Picker("类型", selection: $draftConfig.apiType) {
                ForEach(APIType.allCases) { t in Text(t.rawValue).tag(t) }
            }
            VStack(alignment: .leading) {
                Text("Base URL").font(.subheadline).foregroundColor(.gray)
                TextField("https://...", text: $draftConfig.baseURL)
                    .textInputAutocapitalization(.never).disableAutocorrection(true)
            }
        }
    }

    @ViewBuilder
    private var apiKeysSection: some View {
        Section(header: Text("API Keys (\(draftConfig.apiKeys.count)个)")) {
            ForEach(Array(draftConfig.apiKeys.enumerated()), id: \.offset) { index, key in
                Button {
                    editingKeyIndex = index
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text("Key \(index + 1)").font(.footnote).foregroundColor(.gray)
                                if index == draftConfig.currentKeyIndex {
                                    Text("当前使用")
                                        .font(.system(size: 10))
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Color.green.opacity(0.15))
                                        .foregroundColor(.green)
                                        .cornerRadius(4)
                                }
                            }
                            Text(maskAPIKey(key)).font(.subheadline).foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote).foregroundColor(.gray)
                    }
                }
                .foregroundColor(.primary)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        draftConfig.apiKeys.remove(at: index)
                        if draftConfig.currentKeyIndex >= draftConfig.apiKeys.count {
                            draftConfig.currentKeyIndex = max(0, draftConfig.apiKeys.count - 1)
                        }
                    } label: { Label("删除", systemImage: "trash") }
                    Button {
                        editingKeyIndex = index
                    } label: { Label("编辑", systemImage: "pencil") }.tint(.blue)
                }
                .contextMenu {
                    if draftConfig.apiKeys.count > 1 {
                        Button {
                            draftConfig.currentKeyIndex = index
                        } label: { Label("设为当前使用", systemImage: "checkmark.circle") }
                    }
                    Button { editingKeyIndex = index } label: { Label("编辑 Key", systemImage: "pencil") }
                    Divider()
                    Button(role: .destructive) {
                        draftConfig.apiKeys.remove(at: index)
                        if draftConfig.currentKeyIndex >= draftConfig.apiKeys.count {
                            draftConfig.currentKeyIndex = max(0, draftConfig.apiKeys.count - 1)
                        }
                    } label: { Label("删除", systemImage: "trash") }
                }
            }
            Button { showAddKeySheet = true } label: {
                Label("添加新 Key", systemImage: "plus.circle").foregroundColor(.blue)
            }
        }
    }

    @ViewBuilder
    private var modelManagementSection: some View {
        Section(header: Text("模型管理")) {
            if draftConfig.apiKey.isEmpty {
                Text("请先填写 API Key").font(.subheadline).foregroundColor(.gray)
            } else {
                Button { validateAndFetch() } label: {
                    HStack {
                        Text(isFetching ? "正在获取..." : "获取在线模型列表")
                        if draftConfig.isValidated && !isFetching {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        }
                    }
                }.disabled(isFetching)
                if let err = fetchError { Text(err).font(.footnote).foregroundColor(.red) }
            }
        }
    }

    @ViewBuilder
    private var availableModelsSection: some View {
        if !fetchedOnlineModels.isEmpty || !draftConfig.availableModels.isEmpty {
            Section(header: Text("可用模型")) {
                TextField("搜索模型...", text: $modelSearchText).textInputAutocapitalization(.never)
                ForEach(computedDisplayModels) { model in
                    Button { toggleDraftModelFavorite(model: model) } label: {
                        HStack {
                            Text(model.id).font(.subheadline)
                            Spacer()
                            Image(systemName: draftConfig.isModelFavorited(model.id) ? "star.fill" : "star")
                                .foregroundColor(draftConfig.isModelFavorited(model.id) ? .yellow : .gray)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button { modelToConfigure = model } label: { Label("能力配置", systemImage: "slider.horizontal.3") }.tint(.orange)
                    }
                    .contextMenu {
                        Button { modelToConfigure = model } label: { Label("能力配置", systemImage: "slider.horizontal.3") }
                        Button { toggleDraftModelFavorite(model: model) } label: {
                            Label(draftConfig.isModelFavorited(model.id) ? "取消收藏" : "收藏", systemImage: draftConfig.isModelFavorited(model.id) ? "star.slash" : "star.fill")
                        }
                    }
                }
            }
        }
    }

    func toggleDraftModelFavorite(model: AIModelInfo) {
        draftConfig.toggleFavorite(model.id)
        if !draftConfig.availableModels.contains(where: { $0.id == model.id }) {
            draftConfig.availableModels.append(model)
        }
    }

    func mergeModels() -> [AIModelInfo] {
        var set = Set<String>()
        var result = draftConfig.availableModels
        for m in result { set.insert(m.id) }
        for m in fetchedOnlineModels { if !set.contains(m.id) { result.append(m) } }
        return result.sorted { $0.id < $1.id }
    }

    func validateAndFetch() {
        guard !draftConfig.apiKey.isEmpty else { return }
        isFetching = true; fetchError = nil
        let service = LLMService(); let cfg = draftConfig
        Task {
            do {
                let models = try await service.fetchModels(config: cfg)
                await MainActor.run {
                    fetchedOnlineModels = models
                    draftConfig.isValidated = true
                    draftConfig.availableModels = mergeModels()
                    draftConfig.modelsLastFetched = Date()
                    isFetching = false
                }
            } catch {
                await MainActor.run {
                    fetchError = "失败: \(error.localizedDescription)"
                    draftConfig.isValidated = false
                    isFetching = false
                }
            }
        }
    }

    var computedDisplayModels: [AIModelInfo] {
        mergeModels().filter { model in
            modelSearchText.isEmpty ||
            model.id.localizedCaseInsensitiveContains(modelSearchText) ||
            (model.displayName?.localizedCaseInsensitiveContains(modelSearchText) ?? false)
        }.sorted { m1, m2 in
            let f1 = draftConfig.isModelFavorited(m1.id)
            let f2 = draftConfig.isModelFavorited(m2.id)
            if f1 != f2 { return f1 }
            return m1.id < m2.id
        }
    }
}

// MARK: - 模型能力配置
struct ModelCapabilityConfigView: View {
    @ObservedObject var viewModel: ChatViewModel
    let modelID: String
    @State var settings: ModelSettings
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            Section(header: Text("模型 ID")) {
                Text(modelID).font(.subheadline).foregroundColor(.secondary)
            }
            Section(header: Text("思考能力 (Thinking)"), footer: Text("强制开启可能导致不支持思考的模型产生幻觉。")) {
                Picker("状态", selection: $settings.thinking) {
                    ForEach(CapabilityState.allCases) { s in Text(s.rawValue).tag(s) }
                }.onChange(of: settings.thinking) { _ in save() }
            }
            Section(header: Text("视觉能力 (Vision)"), footer: Text("开启后允许上传图片。")) {
                Picker("状态", selection: $settings.vision) {
                    ForEach(CapabilityState.allCases) { s in Text(s.rawValue).tag(s) }
                }.onChange(of: settings.vision) { _ in save() }
            }
        }
        .navigationTitle("能力配置")
        .onDisappear { save() }
    }

    func save() { viewModel.updateModelSettings(modelId: modelID, thinking: settings.thinking, vision: settings.vision) }
}

// MARK: - 编辑 API Key 辅助类型
struct EditKeyTarget: Identifiable {
    var id: Int { index }
    let index: Int
}

struct EditAPIKeyView: View {
    @Binding var key: String
    @State private var draft: String = ""
    @State private var isRevealed: Bool = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            Section(header: Text("编辑 API Key"), footer: Text("修改后点击保存生效。")) {
                HStack {
                    if isRevealed {
                        TextField("sk-...", text: $draft)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("sk-...", text: $draft)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                    }
                    Button {
                        isRevealed.toggle()
                    } label: {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("编辑 Key")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") {
                    key = draft.trimmingCharacters(in: .whitespaces)
                    dismiss()
                }
                .fontWeight(.semibold)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear { draft = key }
    }
}

// MARK: - 添加供应商
struct AddProviderView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var newConfig = ProviderConfig(name: "", baseURL: "", apiKey: "", isPreset: false, icon: "server.rack")
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            Section {
                TextField("名称", text: $newConfig.name)
                Picker("类型", selection: $newConfig.apiType) {
                    ForEach(APIType.allCases) { t in Text(t.rawValue).tag(t) }
                }
                TextField("Base URL", text: $newConfig.baseURL).textInputAutocapitalization(.never).disableAutocorrection(true)
                SecureField("API Key", text: $newConfig.apiKey)
            }
            Button("保存") {
                if !newConfig.baseURL.hasPrefix("http") && !newConfig.baseURL.isEmpty { newConfig.baseURL = "https://" + newConfig.baseURL }
                viewModel.providers.append(newConfig)
                viewModel.saveProviders()
                dismiss()
            }.disabled(newConfig.baseURL.isEmpty)
        }
        .navigationTitle("添加供应商")
    }
}

// MARK: - 添加 API Key
struct AddAPIKeyView: View {
    @Binding var apiKeys: [String]
    @State private var newKey: String = ""
    @Environment(\.dismiss) var dismiss

    var isDisabled: Bool { newKey.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Form {
            Section(header: Text("输入 API Key")) {
                SecureField("sk-...", text: $newKey)
            }
            Section(footer: Text("添加多个 Key 可实现自动轮询，避免单 Key 限流。")) {
                Button("添加") {
                    if !isDisabled { apiKeys.append(newKey.trimmingCharacters(in: .whitespaces)); dismiss() }
                }.disabled(isDisabled)
            }
        }
        .navigationTitle("添加 Key")
    }
}

// MARK: - 系统提示词编辑
struct SystemPromptEditView: View {
    @Binding var prompt: String
    @State private var draftPrompt: String = ""
    @Environment(\.dismiss) var dismiss

    private let examples = ["请用简洁的中文回复", "你是一个专业的编程助手", "回答问题时请列出要点"]

    var body: some View {
        Form {
            Section(header: Text("自定义提示词")) {
                TextField("输入系统提示词...", text: $draftPrompt, axis: .vertical)
                    .lineLimit(3...8)
            }
            if draftPrompt.isEmpty {
                Section(header: Text("示例")) {
                    ForEach(examples, id: \.self) { ex in Button(ex) { draftPrompt = ex } }
                }
            }
            Section {
                Button("保存") { prompt = draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines); dismiss() }
                    .disabled(draftPrompt == prompt)
                if !draftPrompt.isEmpty {
                    Button("清空", role: .destructive) { draftPrompt = "" }
                }
            }
        }
        .navigationTitle("系统提示词")
        .onAppear { draftPrompt = prompt }
    }
}

// MARK: - 记忆列表
struct MemoryListView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var searchText = ""
    @State private var showAddSheet = false

    var filteredMemories: [MemoryItem] {
        if searchText.isEmpty { return viewModel.memories }
        return viewModel.memories.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List {
            if viewModel.memories.isEmpty && searchText.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "brain").font(.system(size: 40)).foregroundColor(.secondary)
                    Text("暂无记忆").foregroundColor(.secondary)
                    Text("点击右上角 + 手动添加").font(.subheadline).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40).listRowBackground(Color.clear)
            } else {
                ForEach(filteredMemories) { memory in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(memory.type == .longTerm ? "长期" : "临时")
                                .font(.footnote).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(memory.type == .longTerm ? Color.blue.opacity(0.15) : Color.orange.opacity(0.15))
                                .foregroundColor(memory.type == .longTerm ? .blue : .orange).cornerRadius(4)
                            Spacer()
                            Text(memory.createdAt, style: .date).font(.footnote).foregroundColor(.secondary)
                        }
                        Text(memory.content).font(.body)
                        if let source = memory.source {
                            Text("来源：\(source)").font(.subheadline).foregroundColor(.secondary)
                        }
                        HStack(spacing: 6) {
                            Text("重要性").font(.footnote).foregroundColor(.secondary)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.2))
                                    RoundedRectangle(cornerRadius: 2).fill(Color.blue)
                                        .frame(width: geo.size.width * CGFloat(memory.importance))
                                }
                            }.frame(height: 4)
                            Text(String(format: "%.0f%%", memory.importance * 100))
                                .font(.footnote).foregroundColor(.secondary).frame(width: 32, alignment: .trailing)
                        }
                    }.padding(.vertical, 4)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = memory.content
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        Divider()
                        Button(role: .destructive) {
                            if let idx = viewModel.memories.firstIndex(where: { $0.id == memory.id }) {
                                viewModel.softDeleteMemory(at: idx)
                            }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
                .onDelete { offsets in
                    let sortedOffsets = offsets.sorted(by: >)
                    for offset in sortedOffsets {
                        let targetId = filteredMemories[offset].id
                        if let realIdx = viewModel.memories.firstIndex(where: { $0.id == targetId }) {
                            viewModel.softDeleteMemory(at: realIdx)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "搜索记忆")
        .navigationTitle("记忆库 (\(viewModel.memories.count))")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) { EditButton() }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAddSheet = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAddSheet) { AddMemorySheet(viewModel: viewModel) }
    }
}

// MARK: - 记忆回收站 (v2.5)
struct MemoryRecycleBinView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var showEmptyConfirm = false
    
    var body: some View {
        List {
            if viewModel.deletedMemoriesBin.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "trash").font(.system(size: 40)).foregroundColor(.secondary)
                    Text("回收站为空").foregroundColor(.secondary)
                    Text("删除的记忆会先移到这里").font(.subheadline).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40).listRowBackground(Color.clear)
            } else {
                ForEach(Array(viewModel.deletedMemoriesBin.enumerated()), id: \.element.id) { idx, memory in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(memory.content).font(.body).strikethrough(color: .red.opacity(0.5))
                        HStack {
                            Text(memory.type == .longTerm ? "长期" : "临时")
                                .font(.footnote).foregroundColor(.secondary)
                            Spacer()
                            Text(memory.createdAt, style: .date).font(.footnote).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .swipeActions(edge: .leading) {
                        Button {
                            viewModel.restoreMemory(at: idx)
                        } label: {
                            Label("恢复", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.green)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            viewModel.permanentlyDeleteMemory(at: idx)
                        } label: {
                            Label("永久删除", systemImage: "trash.fill")
                        }
                    }
                    .contextMenu {
                        Button {
                            viewModel.restoreMemory(at: idx)
                        } label: {
                            Label("恢复", systemImage: "arrow.uturn.backward")
                        }
                        Divider()
                        Button(role: .destructive) {
                            viewModel.permanentlyDeleteMemory(at: idx)
                        } label: {
                            Label("永久删除", systemImage: "trash.fill")
                        }
                    }
                }
            }
        }
        .navigationTitle("回收站 (\(viewModel.deletedMemoriesBin.count))")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !viewModel.deletedMemoriesBin.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("清空") { showEmptyConfirm = true }
                        .foregroundColor(.red)
                }
            }
        }
        .alert("清空回收站", isPresented: $showEmptyConfirm) {
            Button("清空", role: .destructive) { viewModel.emptyRecycleBin() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作不可撤销，确定永久删除所有 \(viewModel.deletedMemoriesBin.count) 条记忆？")
        }
    }
}

// MARK: - 手动添加记忆
struct AddMemorySheet: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) var dismiss
    @State private var content = ""
    @State private var source = ""
    @State private var memoryType: MemoryType = .longTerm
    @State private var importance: Double = 0.7
    @State private var expireDays: Int = 7

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Label("记忆内容", systemImage: "text.quote")) {
                    TextEditor(text: $content).frame(minHeight: 100).scrollContentBackground(.hidden)
                }
                Section(header: Label("来源（可选）", systemImage: "tag")) {
                    TextField("例：手动添加、某次对话", text: $source)
                }
                Section(header: Label("类型", systemImage: "clock")) {
                    Picker("记忆类型", selection: $memoryType) {
                        ForEach(MemoryType.allCases) { t in Text(t.rawValue).tag(t) }
                    }.pickerStyle(.segmented)
                    if memoryType == .shortTerm {
                        Stepper("有效期 \(expireDays) 天", value: $expireDays, in: 1...365)
                    }
                }
                Section(header: Label("重要性 \(Int(importance * 100))%", systemImage: "star.leadinghalf.filled")) {
                    Slider(value: $importance, in: 0...1, step: 0.05)
                        .tint(importance < 0.4 ? .green : importance < 0.7 ? .orange : .red)
                }
            }
            .navigationTitle("添加记忆").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { saveMemory(); dismiss() }
                        .fontWeight(.semibold)
                        .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    func saveMemory() {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let expiration = memoryType == .shortTerm ? Calendar.current.date(byAdding: .day, value: expireDays, to: Date()) : nil
        let memory = MemoryItem(content: trimmed, createdAt: Date(), source: source.isEmpty ? "手动添加" : source,
                                importance: Float(importance), type: memoryType, expiration: expiration, lastUpdated: Date())
        viewModel.memories.insert(memory, at: 0)
    }
}

// MARK: - 辅助函数
func maskAPIKey(_ key: String) -> String {
    guard key.count > 8 else { return String(repeating: "•", count: key.count) }
    return "\(key.prefix(4))\(String(repeating: "•", count: min(8, key.count - 8)))\(key.suffix(4))"
}
