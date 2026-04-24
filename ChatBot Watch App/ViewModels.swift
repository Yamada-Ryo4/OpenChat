import SwiftUI
import PhotosUI
import Combine
import WatchKit
import ClockKit
import ImageIO
import Accelerate
@MainActor
class ChatViewModel: ObservableObject {
    @AppStorage("savedProviders_v3") var savedProvidersData: Data = Data()
    @AppStorage("selectedGlobalModelID") var selectedGlobalModelID: String = ""
    @AppStorage("showModelNameInNavBar") var showModelNameInNavBar: Bool = true  // 显示顶部模型名称
    @AppStorage("showScrollToBottomButton") var showScrollToBottomButton: Bool = true  // 显示回到底部按钮
    @AppStorage("enableHapticFeedback") var enableHapticFeedback: Bool = true  // 启用振动反馈
    @AppStorage("historyMessageCount") var historyMessageCount: Int = 10  // 携带的对话历史数量
    @AppStorage("customSystemPrompt") var customSystemPrompt: String = ""  // 自定义系统提示词
    @AppStorage("temperature") var temperature: Double = 0.7  // 温度参数 (0.0-2.0)
    @AppStorage("latexRenderingEnabled") var latexRenderingEnabled: Bool = true  // 启用 LaTeX 数学格式渲染
    @AppStorage("markdownRenderMode") var markdownRenderModeRaw: String = MarkdownRenderMode.realtime.rawValue  // v1.8.6: Markdown 渲染模式
    @AppStorage("advancedLatexEnabled") var advancedLatexEnabled: Bool = false  // v1.7: 启用高级 LaTeX 渲染模式（可能导致排版问题）
    @AppStorage("thinkingMode") var thinkingModeRaw: String = ThinkingMode.auto.rawValue // v1.6: 思考模式
    @AppStorage("enableMessageAnimation") var enableMessageAnimation: Bool = true  // v1.6: 消息气泡动画
    @AppStorage("appThemeRaw") var appThemeRaw: String = AppTheme.classic.rawValue  // v1.6: 主题配色
    @AppStorage("memoryEnabled") var memoryEnabled: Bool = true  // v1.7: 记忆功能开关
    @AppStorage("embeddingProviderID") var embeddingProviderID: String = ""  // v1.7: Embedding 供应商 ID
    @AppStorage("embeddingModelID") var embeddingModelID: String = ""  // v1.7: Embedding 模型 ID
    @AppStorage("helperGlobalModelID") var helperGlobalModelID: String = "" // v1.7: 辅助模型 ID
    @AppStorage("detectedEmbeddingDim") var detectedEmbeddingDim: Int = 0  // v1.8: 探测到的向量维度
    @AppStorage("sendTimeToAI") var sendTimeToAI: Bool = true  // 向 AI 传递当前时间
    @AppStorage("sendLocationToAI") var sendLocationToAI: Bool = true  // 向 AI 传递当前位置
    
    // --- 极客配置 (Cloudflare Workers AI 专属) ---
    @AppStorage("workersAIEmbeddingURL") var workersAIEmbeddingURL: String = ""
    @AppStorage("cloudBackupURL") var cloudBackupURL: String = ""
    @AppStorage("cloudBackupAuthKey") var cloudBackupAuthKey: String = ""

    // --- v2.1+：与 iOS 同步的用户偏好（之前缺失，导致同步值写入磁盘但 Watch 端从不读取）---
    @AppStorage("userName") var userName: String = ""
    @AppStorage("preferredColorSchemeRaw") var preferredColorSchemeRaw: String = "dark"
    /// 用户头像数据（空 Data 表示未设置）。watchOS @AppStorage 不支持 Optional<Data>，用空值作哨兵
    @AppStorage("userAvatarData") var userAvatarData: Data = Data()
    @AppStorage("memoryDeleteConfirm") var memoryDeleteConfirm: Bool = true
    @AppStorage("memoryMaxRetrievalCount") var memoryMaxRetrievalCount: Int = 5
    @AppStorage("memoryRetrievalThreshold") var memoryRetrievalThreshold: Double = 0.1
    @AppStorage("autoRetryEnabled") var autoRetryEnabled: Bool = false
    @AppStorage("maxRetries") var maxRetries: Int = 3
    // v2.6: 全局最近使用模型历史
    @AppStorage("recentModelHistory_v1") var recentModelHistoryData: String = "[]"
    @AppStorage("webSearchEnabled") var webSearchEnabled: Bool = false
    @AppStorage("webSearchWorkerURL") var webSearchWorkerURL: String = ""
    @AppStorage("webSearchAuthKey") var webSearchAuthKey: String = ""

    @Published var memories: [MemoryItem] = []  // v1.7: 记忆列表
    @Published var memoryTrash: [MemoryItem] = []  // v2.1: 记忆回收站
    @Published var migrationProgress: String? = nil  // v1.8: 迁移进度提示
    @Published var cloudUploadStatus: String? = nil  // v1.10: 云上传状态
    @AppStorage("lastCloudSyncTime") var lastCloudSyncTime: Double = 0  // v1.12: 最后同步时间戳
    @AppStorage("autoBackupEnabled") var autoBackupEnabled: Bool = false  // v1.12: 自动备份开关
    @Published var cachedVersions: [BackupVersion]? = nil  // v1.12: 本地缓存的版本列表
    var previewCache: [String: BackupPreview] = [:]  // v1.12: UUID->预览 缓存
    
    // v1.10: 导入模式
    enum ImportMode {
        case overwrite  // 全量覆盖（清空本地，使用云端）
        case merge      // 增量合并（保留本地，添加云端新增）
    }
    
    // v1.6: 主题计算属性
    var currentTheme: AppTheme {
        get { AppTheme(rawValue: appThemeRaw) ?? .classic }
        set { appThemeRaw = newValue.rawValue }
    }
    
    // v1.8.6: 渲染模式计算属性
    var markdownRenderMode: MarkdownRenderMode {
        get { MarkdownRenderMode(rawValue: markdownRenderModeRaw) ?? .realtime }
        set { markdownRenderModeRaw = newValue.rawValue }
    }
    
    // v1.7: 模型能力配置 (JSON 存储)
    @AppStorage("modelSettings") var modelSettingsData: Data = Data()
    @Published var modelSettings: [String: ModelSettings] = [:] {
        didSet { saveModelSettings() }
    }
    
    var thinkingMode: ThinkingMode {
        get { ThinkingMode(rawValue: thinkingModeRaw) ?? .auto }
        set { thinkingModeRaw = newValue.rawValue }
    }
    
    @Published var providers: [ProviderConfig] = []
    @Published var sessions: [ChatSession] = []
    @Published var currentSessionId: UUID?
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var isDataLoading: Bool = true // 防止大数据解析阻塞主线程，控制 UI Loading 状态
    @Published var streamingText: String = ""          // v1.6: 流式输出专用（避免全量重渲染）
    @Published var streamingThinkingText: String = ""   // v1.6: 流式思考内容
    @Published var isInputVisible: Bool = true  // 输入框是否可见（用于显示回到底部按钮）
    @Published var selectedImageItem: PhotosPickerItem? = nil
    @Published var selectedImageData: Data? = nil
    private let service = LLMService()
    private var currentTask: Task<Void, Never>?
    
    /// 停止当前生成
    func stopGeneration() {
        currentTask?.cancel()
        currentTask = nil
        isLoading = false
        // v1.6: 清空流式状态
        streamingText = ""
        streamingThinkingText = ""
    }
    private var observers: [Any] = []

    init() {
        // 核心：WatchOS watchdog 严格限制时间，不要在主线程 decode 庞大的 JSON (chatSessions, userMemories)
        
        // 启动定位以备用 (由于不需要强制等，可放主线程立刻去申请)
        LocationService.shared.requestPermission()
        LocationService.shared.updateLocation()
        
        // 监听云端数据变更
        observers.append(NotificationCenter.default.addObserver(forName: .init("CloudDataDidUpdate"), object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in self.loadFromCloud() }
        })
        
        // 监听 iPhone WatchConnectivity 配置推送
        observers.append(NotificationCenter.default.addObserver(forName: WatchSessionManager.configDidUpdateNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in self.reloadFromWatchConnectivity() }
        })
        
        // 监听 iPhone WatchConnectivity 大文件传输（聊天记录+记忆）完成
        observers.append(NotificationCenter.default.addObserver(forName: .init("WatchConnectivityDidReceiveFullData"), object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in self.reloadFromWatchConnectivity() }
        })
        
        Task { [weak self] in
            await self?.loadAllDataOffMainThread()
        }
    }
    
    // v2.1 性能优化：剥离体积庞大的解码逻辑到后台线程，避免 WatchOS APP 开启卡死转圈后闪退
    private func loadAllDataOffMainThread() async {
        // 定义最新的预设供应商
        let latestPresets: [ProviderConfig] = [
            ProviderConfig(name: "智谱AI", baseURL: "https://open.bigmodel.cn/api/paas/v4", apiKey: "", isPreset: true, icon: "sparkles"),
            ProviderConfig(name: "OpenAI", baseURL: "https://api.openai.com/v1", apiKey: "", isPreset: true, icon: "globe"),
            ProviderConfig(name: "Anthropic", baseURL: "https://api.anthropic.com", apiKey: "", isPreset: true, icon: "a.circle.fill", apiType: .anthropic),
            ProviderConfig(name: "DeepSeek", baseURL: "https://api.deepseek.com", apiKey: "", isPreset: true, icon: "brain"),
            ProviderConfig(name: "Nvidia", baseURL: "https://integrate.api.nvidia.com/v1", apiKey: "", isPreset: true, icon: "bolt.horizontal.fill"),
            ProviderConfig(name: "硅基流动", baseURL: "https://api.siliconflow.cn/v1", apiKey: "", isPreset: true, icon: "cpu"),
            ProviderConfig(name: "阿里云百炼", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", apiKey: "", isPreset: true, icon: "cloud"),
            ProviderConfig(name: "ModelScope", baseURL: "https://api-inference.modelscope.cn/v1", apiKey: "", isPreset: true, icon: "cube"),
            ProviderConfig(name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", apiKey: "", isPreset: true, icon: "network"),
            ProviderConfig(name: "Gemini", baseURL: "https://generativelanguage.googleapis.com/v1beta", apiKey: "", isPreset: true, icon: "sparkle", apiType: .gemini),
            ProviderConfig(name: "OpenCode Zen", baseURL: "https://opencode.ai/zen/v1", apiKey: "", isPreset: true, icon: "bolt.fill", apiType: .openAI)
        ]
        
        let result = await Task.detached(priority: .userInitiated) { () -> (
            providers: [ProviderConfig],
            sessions: [ChatSession],
            settings: [String: ModelSettings],
            memories: [MemoryItem],
            trash: [MemoryItem]
        ) in
            // 1. 在完全独立的后台线程中执行 I/O 读取 (避免主线程 plist 解析卡顿)
            let defaults = UserDefaults.standard
            let providersData = defaults.data(forKey: "savedProviders_v3")
            let sessionsData = defaults.data(forKey: "chatSessions_v1")
            let settingsData = defaults.data(forKey: "modelSettings")
            let memoriesData = defaults.data(forKey: "userMemories_v1")
            let trashData = defaults.data(forKey: "memoryTrash_v1")
            
            // providers 解析逻辑
            var pFinal: [ProviderConfig] = latestPresets
            if let data = providersData, let decoded = try? JSONDecoder().decode([ProviderConfig].self, from: data), !decoded.isEmpty {
                var merged: [ProviderConfig] = []
                for preset in latestPresets {
                    if let existing = decoded.first(where: { $0.name == preset.name && $0.isPreset }) {
                        var updated = preset
                        updated.id = existing.id
                        updated.availableModels = existing.availableModels
                        updated.favoriteModelIds = existing.favoriteModelIds
                        updated.isValidated = existing.isValidated
                        updated.lastUsedModelId = existing.lastUsedModelId
                        if !existing.apiKeys.isEmpty {
                            updated.apiKeys = existing.apiKeys
                            updated.currentKeyIndex = existing.currentKeyIndex
                        }
                        merged.append(updated)
                    } else {
                        merged.append(preset)
                    }
                }
                for custom in decoded where !custom.isPreset { merged.append(custom) }
                for old in decoded where old.isPreset {
                    if !latestPresets.contains(where: { $0.name == old.name }) {
                        if !old.apiKeys.isEmpty || !old.favoriteModelIds.isEmpty {
                            var demoted = old
                            demoted.isPreset = false
                            merged.append(demoted)
                        }
                    }
                }
                pFinal = merged
            }
            
            // sessions 解析
            var sFinal: [ChatSession] = []
            if let data = sessionsData, let decoded = try? JSONDecoder().decode([ChatSession].self, from: data) {
                sFinal = decoded.sorted(by: { $0.lastModified > $1.lastModified })
            }
            
            // settings 解析
            var stFinal: [String: ModelSettings] = [:]
            if let data = settingsData, let decoded = try? JSONDecoder().decode([String: ModelSettings].self, from: data) {
                stFinal = decoded
            }
            
            // memories 解析
            var mFinal: [MemoryItem] = []
            if let data = memoriesData, let decoded = try? JSONDecoder().decode([MemoryItem].self, from: data) {
                mFinal = decoded
            }
            
            // trash 解析
            var tFinal: [MemoryItem] = []
            if let data = trashData, let decoded = try? JSONDecoder().decode([MemoryItem].self, from: data) {
                tFinal = decoded
            }
            
            return (pFinal, sFinal, stFinal, mFinal, tFinal)
        }.value
        
        // 2. 将后台解析好的大型对象写回主线程 @Published
        self.providers = result.providers
        self.saveProviders()
        
        self.sessions = result.sessions
        if self.sessions.isEmpty { self.createNewSession() }
        else if self.currentSessionId == nil { self.currentSessionId = self.sessions.first?.id }
        
        self.modelSettings = result.settings
        self.memories = result.memories
        self.memoryTrash = result.trash
        
        // 数据准备就绪，关闭遮罩
        self.isDataLoading = false
        
        // 3. 自动验证（后台静默进行）
        Task {
            for i in 0..<self.providers.count {
                if !self.providers[i].apiKey.isEmpty && !self.providers[i].isValidated {
                    await self.autoValidateProvider(index: i)
                }
            }
        }
    }
    
    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        NotificationCenter.default.removeObserver(self)
    }
    
    // 从云端/本地重新加载配置 (静默同步)
    func loadFromCloud() {
        let data = UserDefaults.standard.data(forKey: "savedProviders_v3")
        Task { [weak self] in
            let decoded = await Task.detached(priority: .background) { () -> [ProviderConfig]? in
                if let d = data, let p = try? JSONDecoder().decode([ProviderConfig].self, from: d), !p.isEmpty {
                    return p
                }
                return nil
            }.value
            if let p = decoded {
                self?.providers = p
                print("☁️ [ViewModel] UI refreshed from Cloud Data")
            }
        }
    }
    
    /// 从 WatchConnectivity 推送重新加载所有同步的配置
    func reloadFromWatchConnectivity() {
        let defaults = UserDefaults.standard
        let pData = defaults.data(forKey: "savedProviders_v3")
        let sData = defaults.data(forKey: "chatSessions_v1")
        let settingsData = defaults.data(forKey: "modelSettings")
        let memData = defaults.data(forKey: "userMemories_v1")
        let trashData = defaults.data(forKey: "memoryTrash_v1")
        
        Task { [weak self] in
            let result = await Task.detached(priority: .background) { () -> (
                providers: [ProviderConfig]?,
                sessions: [ChatSession]?,
                settings: [String: ModelSettings]?,
                memories: [MemoryItem]?,
                trash: [MemoryItem]?
            ) in
                var p: [ProviderConfig]? = nil
                if let d = pData, let decoded = try? JSONDecoder().decode([ProviderConfig].self, from: d), !decoded.isEmpty { p = decoded }
                
                var s: [ChatSession]? = nil
                if let d = sData, let decoded = try? JSONDecoder().decode([ChatSession].self, from: d) { s = decoded }
                
                var st: [String: ModelSettings]? = nil
                if let d = settingsData, let decoded = try? JSONDecoder().decode([String: ModelSettings].self, from: d) { st = decoded }
                
                var m: [MemoryItem]? = nil
                if let d = memData, let decoded = try? JSONDecoder().decode([MemoryItem].self, from: d) { m = decoded }
                
                var t: [MemoryItem]? = nil
                if let d = trashData, let decoded = try? JSONDecoder().decode([MemoryItem].self, from: d) { t = decoded }
                
                return (p, s, st, m, t)
            }.value
            
            if let p = result.providers { self?.providers = p }
            if let s = result.sessions { self?.sessions = s }
            if let st = result.settings { self?.modelSettings = st }
            if let m = result.memories { self?.memories = m }
            if let t = result.trash { self?.memoryTrash = t }
            
            self?.objectWillChange.send()
            print("📱 [ViewModel] 已从 iPhone 同步刷新全部数据")
        }
    }
    
    // MARK: - 会话管理
    func createNewSession() {
        let newSession = ChatSession(title: "新对话", messages: [], lastModified: Date())
        sessions.insert(newSession, at: 0)
        currentSessionId = newSession.id
        saveSessions()
    }
    func selectSession(_ session: ChatSession) { currentSessionId = session.id }
    func deleteSession(at offsets: IndexSet) {
        let idsToDelete = offsets.map { sessions[$0].id }
        sessions.remove(atOffsets: offsets)
        if let current = currentSessionId, idsToDelete.contains(current) { if let first = sessions.first { currentSessionId = first.id } else { createNewSession() } }
        saveSessions()
    }
    func saveSessions() {
        // BUG-2 fix: persist currentSessionId
        if let id = currentSessionId {
            UserDefaults.standard.set(id.uuidString, forKey: "currentSessionId_v1")
        }
        
        // BUG-3 / OOM fix: move heavy JSON encoding off the main thread
        let sessionsCopy = self.sessions
        Task.detached(priority: .background) { [sessionsCopy] in
            guard let encoded = try? JSONEncoder().encode(sessionsCopy) else { return }
            UserDefaults.standard.set(encoded, forKey: "chatSessions_v1")
            
            // 轻量级 Widget 数据
            if let first = sessionsCopy.first {
                var msg = "No messages"
                if let lastM = first.messages.last(where: { $0.role != .system }) {
                    msg = String(lastM.text.prefix(80)) // 限制长度防止过大
                }
                let widgetData: [String: String] = ["title": first.title, "lastMessage": msg]
                UserDefaults.standard.set(widgetData, forKey: "widget_tiny_data")
            } else {
                UserDefaults.standard.set(["title": "OpenChat", "lastMessage": "No conversations"], forKey: "widget_tiny_data")
            }

            // 刷新表盘组件（必须在主线程）
            await MainActor.run {
                let server = CLKComplicationServer.sharedInstance()
                for complication in server.activeComplications ?? [] {
                    server.reloadTimeline(for: complication)
                }
            }
        }
    }
    
    var currentMessages: [ChatMessage] {
        guard let sessionId = currentSessionId, let session = sessions.first(where: { $0.id == sessionId }) else { return [] }
        return session.messages
    }
    
    /// 更新消息并保存到磁盘（用于非频繁操作）
    private func updateCurrentSessionMessages(_ newMessages: [ChatMessage]) {
        updateCurrentSessionMessagesInMemory(newMessages)
        saveSessions()
    }
    
    /// 仅更新内存中的消息（不写磁盘，用于流式输出）
    private func updateCurrentSessionMessagesInMemory(_ newMessages: [ChatMessage]) {
        guard let index = sessions.firstIndex(where: { $0.id == currentSessionId }) else { return }
        sessions[index].messages = newMessages
        sessions[index].lastModified = Date()
        
        // 改进标题生成：使用用户首条消息的前 15 字符
        if sessions[index].title == "新对话" || sessions[index].title.isEmpty {
            if let firstUserMsg = newMessages.first(where: { $0.role == .user }), !firstUserMsg.text.isEmpty {
                let cleanText = firstUserMsg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                sessions[index].title = String(cleanText.prefix(15)) + (cleanText.count > 15 ? "..." : "")
            }
        }
        // OOM fix: 移除 sessions.sort() 热路径调用。
        // sort 会导致 Swift COW 对整个 sessions 数组做内存拷贝，在流式输出期间每 150ms 距矩执行一次容易 OOM。
        // 排序只在对话切换/删除/保存时才需要（由 selectSession, deleteSession, saveSessions 负责）。
    }
    
    // MARK: - 供应商与模型逻辑
    func saveProviders() {
        if let encoded = try? JSONEncoder().encode(providers) {
            savedProvidersData = encoded
            // 自动推送到 iPhone（防止同步循环）
            if !WatchSessionManager.shared.isSyncingFromRemote {
                WatchSessionManager.shared.pushConfigToPhone()
            }
        }
    }
    
    // v2.6: 记录一次模型使用，插入到历史头部，去重，截断为 3 条
    func recordRecentModel(providerID: UUID, modelID: String) {
        var arr: [[String: String]] = []
        if let data = recentModelHistoryData.data(using: .utf8) {
            arr = (try? JSONDecoder().decode([[String: String]].self, from: data)) ?? []
        }
        arr.removeAll { $0["providerID"] == providerID.uuidString && $0["modelID"] == modelID }
        arr.insert(["providerID": providerID.uuidString, "modelID": modelID], at: 0)
        if arr.count > 3 { arr = Array(arr.prefix(3)) }
        if let encoded = try? JSONEncoder().encode(arr), let str = String(data: encoded, encoding: .utf8) {
            recentModelHistoryData = str
        }
    }

    
    // 自动验证供应商（首次启动时调用）
    @MainActor
    private func autoValidateProvider(index: Int) async {
        guard index < providers.count else { return }
        let provider = providers[index]
        guard !provider.apiKey.isEmpty else { return }
        do {
            let models = try await service.fetchModels(config: provider)
            await MainActor.run {
                self.providers[index].mergeModels(fetchedModels: models)
                self.providers[index].isValidated = true
                self.saveProviders()
            }
            print("✅ 自动验证成功: \(provider.name)")
        } catch {
            print("⚠️ 自动验证失败: \(provider.name) - \(error.localizedDescription)")
        }
    }
    
    @MainActor
    func fetchModelsForProvider(providerID: UUID, forceRefresh: Bool = false) async {
        guard let index = providers.firstIndex(where: { $0.id == providerID }) else { return }
        let provider = providers[index]
        guard !provider.apiKey.isEmpty else { return }
        
        // 缓存逻辑：1小时内不重复获取（除非强制刷新）
        if !forceRefresh,
           let lastFetch = provider.modelsLastFetched,
           Date().timeIntervalSince(lastFetch) < 3600,
           !provider.availableModels.isEmpty {
            return
        }
        
        do {
            let models = try await service.fetchModels(config: provider)
            self.providers[index].mergeModels(fetchedModels: models)
            self.providers[index].isValidated = true
            self.providers[index].modelsLastFetched = Date()
            saveProviders()
        } catch {
            self.providers[index].isValidated = false
            // 如果是认证错误且有多个 Key，尝试轮换
            if provider.apiKeys.count > 1 {
                self.providers[index].rotateKey()
                saveProviders()
            }
        }
    }
    
    // 批量验证所有有 API Key 的供应商
    @MainActor
    func validateAllProviders() async -> (success: Int, failed: Int) {
        var success = 0
        var failed = 0
        for i in 0..<providers.count {
            guard !providers[i].apiKey.isEmpty else { continue }
            do {
                let models = try await service.fetchModels(config: providers[i])
                await MainActor.run {
                    self.providers[i].mergeModels(fetchedModels: models)
                    self.providers[i].isValidated = true
                    self.providers[i].modelsLastFetched = Date()
                }
                success += 1
            } catch {
                await MainActor.run {
                    self.providers[i].isValidated = false
                }
                failed += 1
            }
        }
        await MainActor.run { saveProviders() }
        return (success, failed)
    }
    
    func updateProvider(_ updated: ProviderConfig) {
        if let index = providers.firstIndex(where: { $0.id == updated.id }) {
            providers[index] = updated
            saveProviders()
        }
    }
    
    func toggleModelFavorite(providerID: UUID, model: AIModelInfo) {
        guard let index = providers.firstIndex(where: { $0.id == providerID }) else { return }
        providers[index].toggleFavorite(model.id)
        saveProviders()
    }
    
    func addCustomModel(providerID: UUID, modelID: String, displayName: String) {
        guard let index = providers.firstIndex(where: { $0.id == providerID }) else { return }
        let newModel = AIModelInfo(id: modelID, displayName: displayName.isEmpty ? nil : displayName, isCustom: true)
        var currentSaved = providers[index].savedModels
        if let existIndex = currentSaved.firstIndex(where: { $0.id == modelID }) { currentSaved.remove(at: existIndex) }
        currentSaved.insert(newModel, at: 0)
        providers[index].savedModels = currentSaved
        saveProviders()
    }
    
    // 获取所有收藏的模型
    var allFavoriteModels: [(id: String, displayName: String, providerName: String)] {
        var list: [(String, String, String)] = []
        for provider in providers {
            for model in provider.availableModels where provider.isModelFavorited(model.id) {
                let compositeID = "\(provider.id.uuidString)|\(model.id)"
                let nameToShow = model.displayName ?? model.id
                list.append((compositeID, nameToShow, provider.name))
            }
        }
        return list
    }
    
    // 获取所有可用模型（按供应商分组）
    var allAvailableModels: [(provider: ProviderConfig, models: [AIModelInfo])] {
        providers.filter { !$0.availableModels.isEmpty }.map { ($0, $0.availableModels) }
    }
    
    // 获取最近使用的模型（每个供应商一个）
    var recentlyUsedModels: [(id: String, displayName: String, providerName: String)] {
        var list: [(String, String, String)] = []
        for provider in providers {
            guard let lastModelId = provider.lastUsedModelId,
                  let model = provider.availableModels.first(where: { $0.id == lastModelId }) else { continue }
            let compositeID = "\(provider.id.uuidString)|\(model.id)"
            let nameToShow = model.displayName ?? model.id
            list.append((compositeID, nameToShow, provider.name))
        }
        return list
    }
    
    // MARK: - 配置导出/导入 (v1.9: S7 文件优化版)
    
    private func saveToTempFile(data: Data, filename: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("Export file write error: \(error)")
            return nil
        }
    }
    
    /// 导出配置为文件（去除向量以减小体积）
    func exportConfigURL() -> URL? {
        // 去除 vector 数据，大幅减小体积防止 Watch 卡死
        let strippedMemories = memories.map { var m = $0; m.embedding = nil; return m }
        let exportData = ExportableConfig(
            providers: providers,
            selectedGlobalModelID: selectedGlobalModelID,
            temperature: temperature,
            historyMessageCount: historyMessageCount,
            customSystemPrompt: customSystemPrompt,
            thinkingMode: thinkingMode,
            modelSettings: modelSettings,
            memories: strippedMemories,
            sessions: sessions,
            helperGlobalModelID: helperGlobalModelID,
            embeddingDimension: detectedEmbeddingDim > 0 ? detectedEmbeddingDim : nil,
            embeddingProviderID: embeddingProviderID.isEmpty ? nil : embeddingProviderID,
            embeddingModelID: embeddingModelID.isEmpty ? nil : embeddingModelID,
            workersAIEmbeddingURL: workersAIEmbeddingURL.isEmpty ? nil : workersAIEmbeddingURL,
            cloudBackupURL: cloudBackupURL.isEmpty ? nil : cloudBackupURL,
            cloudBackupAuthKey: cloudBackupAuthKey.isEmpty ? nil : cloudBackupAuthKey,
            memoryEnabled: memoryEnabled
        )
        guard let data = try? JSONEncoder().encode(exportData) else { return nil }
        let dateStr = Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")
        return saveToTempFile(data: data, filename: "OpenChat_Config_\(dateStr).json")
    }
    
    /// 单独导出记忆（文件URL，无向量）
    func exportMemoriesURL() -> URL? {
        let stripped = memories.map { var m = $0; m.embedding = nil; return m }
        guard let data = try? JSONEncoder().encode(stripped) else { return nil }
        let dateStr = Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")
        return saveToTempFile(data: data, filename: "OpenChat_Memories_\(dateStr).json")
    }
    
    /// 单独导出聊天记录（文件URL）
    func exportSessionsURL() -> URL? {
        guard let data = try? JSONEncoder().encode(sessions) else { return nil }
        let dateStr = Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")
        return saveToTempFile(data: data, filename: "OpenChat_Chats_\(dateStr).json")
    }
    
    // MARK: - 云备份 (v1.10: R2 直传)
    
    /// 上传配置到云端
    func uploadConfigToCloud() async {
        await MainActor.run { cloudUploadStatus = "⬆️ 正在上传..." }
        
        let url = cloudBackupURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let authKey = cloudBackupAuthKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, let requestURL = URL(string: url) else {
            await MainActor.run { cloudUploadStatus = "❌ URL 无效" }
            return
        }
        
        // v2.6: 先尝试获取现有云端配置，以保留手机专用字段
        var existingConfig: ExportableConfig? = nil
        if let (data, _) = try? await URLSession.shared.data(for: {
            var req = URLRequest(url: requestURL)
            req.httpMethod = "GET"
            if !authKey.isEmpty { req.setValue(authKey, forHTTPHeaderField: "X-Auth-Key") }
            return req
        }()) {
            existingConfig = try? JSONDecoder().decode(ExportableConfig.self, from: data)
        }

        let strippedMemories = memories.map { var m = $0; m.embedding = nil; return m }
        var exportData = ExportableConfig(
            providers: providers,
            selectedGlobalModelID: existingConfig?.selectedGlobalModelID ?? selectedGlobalModelID,
            temperature: temperature,
            historyMessageCount: historyMessageCount,
            customSystemPrompt: customSystemPrompt,
            thinkingMode: thinkingMode,
            modelSettings: modelSettings,
            memories: strippedMemories,
            sessions: sessions,
            helperGlobalModelID: existingConfig?.helperGlobalModelID ?? helperGlobalModelID,
            embeddingDimension: detectedEmbeddingDim > 0 ? detectedEmbeddingDim : nil,
            embeddingProviderID: embeddingProviderID.isEmpty ? nil : embeddingProviderID,
            embeddingModelID: embeddingModelID.isEmpty ? nil : embeddingModelID,
            workersAIEmbeddingURL: workersAIEmbeddingURL.isEmpty ? nil : workersAIEmbeddingURL,
            cloudBackupURL: cloudBackupURL.isEmpty ? nil : cloudBackupURL,
            cloudBackupAuthKey: cloudBackupAuthKey.isEmpty ? nil : cloudBackupAuthKey,
            memoryEnabled: memoryEnabled
        )
        
        // 注入差异化字段
        exportData.watchSelectedGlobalModelID = selectedGlobalModelID
        exportData.watchHelperGlobalModelID = helperGlobalModelID
        exportData.watchRecentModelHistory = recentModelHistoryData
        
        if let existing = existingConfig {
            exportData.iphoneRecentModelHistory = existing.iphoneRecentModelHistory
        }
        
        guard let jsonData = try? JSONEncoder().encode(exportData) else {
            await MainActor.run { cloudUploadStatus = "❌ JSON 编码失败" }
            return
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !authKey.isEmpty {
            request.setValue(authKey, forHTTPHeaderField: "X-Auth-Key")
        }
        
        do {
            let (responseData, response) = try await URLSession.shared.upload(for: request, from: jsonData)
            let httpResponse = response as? HTTPURLResponse
            let statusCode = httpResponse?.statusCode ?? 0
            let sizeKB = String(format: "%.1f", Double(jsonData.count) / 1024.0)
            
            // v1.12: 解析 Workers 返回的 JSON 响应
            var serverMessage = ""
            if let resData = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               let msg = resData["message"] as? String {
                serverMessage = msg
            }
            
            await MainActor.run {
                if (200...299).contains(statusCode) {
                    if serverMessage.contains("跳过") || serverMessage.contains("无变化") {
                        cloudUploadStatus = "⏭️ 内容无变化，已跳过"
                    } else {
                        cloudUploadStatus = "✅ 上传成功 (\(sizeKB)KB)"
                        // 自动刷新列表 (异步)
                        Task { try? await self.fetchBackupVersions(forceRefresh: true) }
                    }
                    lastCloudSyncTime = Date().timeIntervalSince1970
                } else {
                    cloudUploadStatus = "❌ 服务器返回 \(statusCode)"
                }
            }
        } catch {
            await MainActor.run {
                cloudUploadStatus = "❌ 上传失败: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - v1.12: 重命名备份
    func renameBackup(key: String, name: String) async -> (success: Bool, message: String) {
        let url = cloudBackupURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, let baseURL = URL(string: url) else {
            return (false, "URL 无效")
        }
        
        let filename = baseURL.lastPathComponent
        let baseString = baseURL.deletingLastPathComponent().absoluteString
        guard let renameURL = URL(string: "\(baseString)rename/\(key)") else {
            return (false, "URL 构造失败")
        }
        
        var request = URLRequest(url: renameURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let authKey = cloudBackupAuthKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !authKey.isEmpty {
            request.setValue(authKey, forHTTPHeaderField: "X-Auth-Key")
        }
        
        do {
            let body = ["name": name]
            request.httpBody = try JSONEncoder().encode(body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            let statusCode = httpResponse?.statusCode ?? 0
            
            if (200...299).contains(statusCode) {
                // 重命名成功后刷新列表
                Task { try? await self.fetchBackupVersions(forceRefresh: true) }
                return (true, "重命名成功")
            } else {
                return (false, "HTTP \(statusCode)")
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }
    
    /// 从云端下载并恢复配置
    func downloadConfigFromCloud(mode: ImportMode) async throws {
        let url = cloudBackupURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, let requestURL = URL(string: url) else {
            throw NSError(domain: "CloudBackup", code: -1, userInfo: [NSLocalizedDescriptionKey: "URL 无效"])
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        let authKey = cloudBackupAuthKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !authKey.isEmpty {
            request.setValue(authKey, forHTTPHeaderField: "X-Auth-Key")
        }
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        switch mode {
        case .overwrite:
            try importFullConfig(from: data)
        case .merge:
            try mergeConfig(from: data)
        }
    }
    

    
    /// v1.10: 增量合并配置
    // v1.12: 导入选项（细化为 8 项）
    enum ImportOption: String, CaseIterable, Identifiable, Hashable {
        case providers = "供应商配置"
        case memories = "记忆库"
        case sessions = "聊天记录"
        case modelParams = "模型参数"
        case embeddingConfig = "向量配置"
        case cloudConfig = "云备份配置"
        case helperModel = "辅助模型"
        case modelSettings = "模型级设置"
        var id: String { rawValue }
    }
    
    /// v1.12: 从云端获取配置对象（不立即导入）
    func fetchConfigFromCloud() async throws -> ExportableConfig {
        let url = cloudBackupURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, let requestURL = URL(string: url) else {
            throw NSError(domain: "CloudBackup", code: -1, userInfo: [NSLocalizedDescriptionKey: "URL 无效"])
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        let authKey = cloudBackupAuthKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !authKey.isEmpty {
            request.setValue(authKey, forHTTPHeaderField: "X-Auth-Key")
        }
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(ExportableConfig.self, from: data)
    }
    
    /// v1.12: 测试云端连接
    func testCloudConnection() async -> (success: Bool, message: String) {
        let url = cloudBackupURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, let requestURL = URL(string: url) else {
            return (false, "URL 无效")
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        let authKey = cloudBackupAuthKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !authKey.isEmpty {
            request.setValue(authKey, forHTTPHeaderField: "X-Auth-Key")
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            let statusCode = httpResponse?.statusCode ?? 0
            
            if statusCode == 401 {
                return (false, "认证失败 (401)")
            } else if statusCode == 404 {
                return (true, "连接正常，暂无备份")
            } else if (200...299).contains(statusCode) {
                let sizeKB = String(format: "%.1f", Double(data.count) / 1024.0)
                // 尝试解析并返回摘要
                if let config = try? JSONDecoder().decode(ExportableConfig.self, from: data) {
                    return (true, "连接正常 · \(sizeKB)KB · \(config.providers.count)供应商 · \(config.memories?.count ?? 0)记忆 · \(config.sessions?.count ?? 0)会话")
                }
                return (true, "连接正常 (\(sizeKB)KB)")
            } else {
                return (false, "HTTP \(statusCode)")
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }
    
    // MARK: - v1.12: 历史版本管理 (Workers 新 API)
    
    /// 历史版本信息（支持 Codable 以便本地缓存）
    struct BackupVersion: Identifiable, Codable {
        let key: String
        let version: Int
        let label: String
        let size: Int
        let uploaded: String?
        let uuid: String?
        let customName: String?
        
        var id: String { uuid ?? key }
        
        /// 主标题（优先显示自定义名称）
        var displayName: String {
            if let name = customName, !name.isEmpty, name != "null" { return name }
            if version == 0 { return "当前配置" }
            return "备份 \(version)"
        }
        
        /// 副标题（大小 + 时间）
        var displaySubtitle: String {
            var timeStr = ""
            if let uploaded = uploaded {
                let isoFormatter = ISO8601DateFormatter()
                // 优先尝试带毫秒的格式 (Workers通常返回这种)
                isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                var date = isoFormatter.date(from: uploaded)
                
                // 如果失败，尝试标准格式
                if date == nil {
                    isoFormatter.formatOptions = [.withInternetDateTime]
                    date = isoFormatter.date(from: uploaded)
                }
                
                if let d = date {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd HH:mm"
                    timeStr = formatter.string(from: d)
                }
            }
            return "\(sizeText)  \(timeStr)"
        }
        
        /// 格式化大小
        var sizeText: String {
            if size > 1024 * 1024 {
                return String(format: "%.1fMB", Double(size) / 1024.0 / 1024.0)
            }
            return String(format: "%.1fKB", Double(size) / 1024.0)
        }
        
        /// 容错解码（自动转换本地时间）
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            key = try c.decode(String.self, forKey: .key)
            version = (try? c.decode(Int.self, forKey: .version)) ?? 0
            size = (try? c.decode(Int.self, forKey: .size)) ?? 0
            uploaded = try? c.decodeIfPresent(String.self, forKey: .uploaded)
            uuid = try? c.decodeIfPresent(String.self, forKey: .uuid)
            customName = try? c.decodeIfPresent(String.self, forKey: .customName)
            
            // label 字段保留用于兼容（虽然 UI 可能不再直接使用它）
            label = (try? c.decode(String.self, forKey: .label)) ?? key
        }

        
        init(key: String, version: Int, label: String, size: Int, uploaded: String?, uuid: String?, customName: String? = nil) {
            self.key = key; self.version = version; self.label = label
            self.size = size; self.uploaded = uploaded; self.uuid = uuid
            self.customName = customName
        }
    }
    
    /// 获取历史版本列表（自动缓存）
    func fetchBackupVersions(forceRefresh: Bool = false) async throws -> [BackupVersion] {
        // 如果有缓存且不强制刷新，直接返回
        if !forceRefresh, let cached = cachedVersions {
            return cached
        }
        
        let url = cloudBackupURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, let baseURL = URL(string: url) else {
            throw NSError(domain: "CloudBackup", code: -1, userInfo: [NSLocalizedDescriptionKey: "URL 无效"])
        }
        
        let filename = baseURL.lastPathComponent
        let baseString = baseURL.deletingLastPathComponent().absoluteString
        guard let listURL = URL(string: "\(baseString)list/\(filename)") else {
            throw NSError(domain: "CloudBackup", code: -1, userInfo: [NSLocalizedDescriptionKey: "URL 构造失败"])
        }
        
        var request = URLRequest(url: listURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        let authKey = cloudBackupAuthKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !authKey.isEmpty {
            request.setValue(authKey, forHTTPHeaderField: "X-Auth-Key")
        }
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct ListResponse: Decodable {
            let status: String
            let versions: [BackupVersion]
        }
        
        let response = try JSONDecoder().decode(ListResponse.self, from: data)
        let versions = response.versions
        
        // 保存到本地缓存
        await MainActor.run {
            cachedVersions = versions
        }
        // 持久化到 UserDefaults
        if let encoded = try? JSONEncoder().encode(versions) {
            UserDefaults.standard.set(encoded, forKey: "cachedBackupVersions")
        }
        
        return versions
    }
    
    /// 从本地缓存加载版本列表
    func loadCachedVersions() -> [BackupVersion]? {
        guard let data = UserDefaults.standard.data(forKey: "cachedBackupVersions"),
              let versions = try? JSONDecoder().decode([BackupVersion].self, from: data) else {
            return nil
        }
        return versions
    }
    
    /// 恢复指定历史版本
    func restoreBackupVersion(key: String, mode: ImportMode) async throws {
        let url = cloudBackupURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, let baseURL = URL(string: url) else {
            throw NSError(domain: "CloudBackup", code: -1, userInfo: [NSLocalizedDescriptionKey: "URL 无效"])
        }
        
        // 构造历史版本 URL：替换最后的文件名部分
        let versionURL = baseURL.deletingLastPathComponent().appendingPathComponent(key)
        
        var request = URLRequest(url: versionURL)
        request.httpMethod = "GET"
        let authKey = cloudBackupAuthKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !authKey.isEmpty {
            request.setValue(authKey, forHTTPHeaderField: "X-Auth-Key")
        }
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        switch mode {
        case .overwrite:
            try importFullConfig(from: data)
        case .merge:
            try mergeConfig(from: data)
        }
        
        lastCloudSyncTime = Date().timeIntervalSince1970
    }
    
    /// 删除指定历史版本
    func deleteBackupVersion(key: String) async throws {
        let url = cloudBackupURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, let baseURL = URL(string: url) else {
            throw NSError(domain: "CloudBackup", code: -1, userInfo: [NSLocalizedDescriptionKey: "URL 无效"])
        }
        
        let versionURL = baseURL.deletingLastPathComponent().appendingPathComponent(key)
        
        var request = URLRequest(url: versionURL)
        request.httpMethod = "DELETE"
        let authKey = cloudBackupAuthKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !authKey.isEmpty {
            request.setValue(authKey, forHTTPHeaderField: "X-Auth-Key")
        }
        
        let (_, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        if let statusCode = httpResponse?.statusCode, !(200...299).contains(statusCode) {
            throw NSError(domain: "CloudBackup", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "删除失败 (HTTP \(statusCode))"])
        }
    }
    
    /// 配置预览信息（Workers /preview/ 响应）
    struct BackupPreview: Decodable {
        let status: String
        let key: String
        let size: Int
        let uploaded: String?
        let providers: Int?
        let memories: Int?
        let sessions: Int?
        let details: PreviewDetails?
        
        struct PreviewDetails: Decodable {
            let providerNames: [String]?
            let selectedModel: String?
            let temperature: Double?
            let historyCount: Int?
            let thinkingMode: Bool?
            let memoryEnabled: Bool?
            let hasCustomPrompt: Bool?
            
            /// 容错解码：任何字段类型不匹配都不会导致整体失败
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                providerNames = try? c.decodeIfPresent([String].self, forKey: .providerNames)
                selectedModel = try? c.decodeIfPresent(String.self, forKey: .selectedModel)
                temperature = try? c.decodeIfPresent(Double.self, forKey: .temperature)
                historyCount = try? c.decodeIfPresent(Int.self, forKey: .historyCount)
                thinkingMode = try? c.decodeIfPresent(Bool.self, forKey: .thinkingMode)
                memoryEnabled = try? c.decodeIfPresent(Bool.self, forKey: .memoryEnabled)
                hasCustomPrompt = try? c.decodeIfPresent(Bool.self, forKey: .hasCustomPrompt)
            }
            
            private enum CodingKeys: String, CodingKey {
                case providerNames, selectedModel, temperature, historyCount
                case thinkingMode, memoryEnabled, hasCustomPrompt
            }
        }
        
        /// 容错解码：key/size 必须有，其余都可选
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            status = (try? c.decode(String.self, forKey: .status)) ?? "unknown"
            key = try c.decode(String.self, forKey: .key)
            size = try c.decode(Int.self, forKey: .size)
            uploaded = try? c.decodeIfPresent(String.self, forKey: .uploaded)
            providers = try? c.decodeIfPresent(Int.self, forKey: .providers)
            memories = try? c.decodeIfPresent(Int.self, forKey: .memories)
            sessions = try? c.decodeIfPresent(Int.self, forKey: .sessions)
            details = try? c.decodeIfPresent(PreviewDetails.self, forKey: .details)
        }
        
        private enum CodingKeys: String, CodingKey {
            case status, key, size, uploaded, providers, memories, sessions, details
        }
        
        var sizeText: String {
            if size > 1024 * 1024 {
                return String(format: "%.1fMB", Double(size) / 1024.0 / 1024.0)
            }
            return String(format: "%.1fKB", Double(size) / 1024.0)
        }
    }
    
    /// 预览指定版本的配置摘要（带 UUID 缓存）
    func previewBackupVersion(key: String, uuid: String? = nil) async throws -> BackupPreview {
        // 有 UUID 且已缓存 → 直接返回
        if let uuid = uuid, let cached = previewCache[uuid] {
            return cached
        }
        
        let url = cloudBackupURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, let baseURL = URL(string: url) else {
            throw NSError(domain: "CloudBackup", code: -1, userInfo: [NSLocalizedDescriptionKey: "URL 无效"])
        }
        
        // 构造 /preview/{key} URL
        // appendingPathComponent 会将 / 编码为 %2F，需用字符串拼接
        let baseString = baseURL.deletingLastPathComponent().absoluteString
        guard let previewURL = URL(string: "\(baseString)preview/\(key)") else {
            throw NSError(domain: "CloudBackup", code: -1, userInfo: [NSLocalizedDescriptionKey: "URL 构造失败"])
        }
        
        var request = URLRequest(url: previewURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        let authKey = cloudBackupAuthKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !authKey.isEmpty {
            request.setValue(authKey, forHTTPHeaderField: "X-Auth-Key")
        }
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let preview = try JSONDecoder().decode(BackupPreview.self, from: data)
        
        // 缓存结果
        if let uuid = uuid {
            previewCache[uuid] = preview
        }
        
        return preview
    }
    
    /// 一键去重历史备份
    func deduplicateBackups() async throws -> (removed: Int, remaining: Int, message: String) {
        let url = cloudBackupURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, let baseURL = URL(string: url) else {
            throw NSError(domain: "CloudBackup", code: -1, userInfo: [NSLocalizedDescriptionKey: "URL 无效"])
        }
        
        let filename = baseURL.lastPathComponent
        let baseString = baseURL.deletingLastPathComponent().absoluteString
        guard let dedupURL = URL(string: "\(baseString)dedup/\(filename)") else {
            throw NSError(domain: "CloudBackup", code: -1, userInfo: [NSLocalizedDescriptionKey: "URL 构造失败"])
        }
        
        var request = URLRequest(url: dedupURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30  // 去重可能耗时较长
        let authKey = cloudBackupAuthKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !authKey.isEmpty {
            request.setValue(authKey, forHTTPHeaderField: "X-Auth-Key")
        }
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct DedupResponse: Decodable {
            let status: String
            let message: String
            let removed: Int?
            let remaining: Int?
        }
        
        let response = try JSONDecoder().decode(DedupResponse.self, from: data)
        
        // 去重后清除缓存，下次列表强制刷新
        await MainActor.run { cachedVersions = nil }
        previewCache.removeAll()
        
        return (removed: response.removed ?? 0, remaining: response.remaining ?? 0, message: response.message)
    }
    
    /// App 启动时自动静默备份（不影响 UI）
    func performAutoBackupIfNeeded() {
        guard autoBackupEnabled,
              !cloudBackupURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        Task {
            await uploadConfigToCloud()
            print("☁️ 自动备份完成")
        }
    }

    /// v1.10: 增量合并配置 (默认全选)
    func mergeConfig(from data: Data) throws {
        let config = try JSONDecoder().decode(ExportableConfig.self, from: data)
        try mergeConfig(from: config, options: Set(ImportOption.allCases))
    }
    
    /// v1.12: 增量合并配置 (带选项，8 项细粒度)
    func mergeConfig(from config: ExportableConfig, options: Set<ImportOption>) throws {
        // 1. 供应商配置 (ID 不存在才添加)
        if options.contains(.providers) {
            for p in config.providers {
                if !providers.contains(where: { $0.id == p.id }) {
                    providers.append(p)
                }
            }
            saveProviders()
        }
        
        // 2. 记忆库 (内容不重复才添加)
        if options.contains(.memories), let importedMemories = config.memories {
            for mem in importedMemories {
                if !memories.contains(where: { $0.content == mem.content }) {
                    memories.append(mem)
                }
            }
            saveMemories()
        }
        
        // 3. 聊天记录 (ID 不重复才添加)
        if options.contains(.sessions), let importedSessions = config.sessions {
            for session in importedSessions {
                if !sessions.contains(where: { $0.id == session.id }) {
                    sessions.append(session)
                }
            }
            saveSessions()
        }
        
        // 4. 模型参数 (温度、历史、提示词、思考模式)
        if options.contains(.modelParams) {
            self.temperature = config.temperature
            self.historyMessageCount = config.historyMessageCount
            self.customSystemPrompt = config.customSystemPrompt
            self.thinkingModeRaw = config.thinkingMode.rawValue
            // v2.6: 应用手表专属模型历史
            if let watchHistory = config.watchRecentModelHistory {
                self.recentModelHistoryData = watchHistory
            }
        }
        
        // 5. 向量配置 (供应商、模型、URL、维度)
        if options.contains(.embeddingConfig) {
            if let pid = config.embeddingProviderID { self.embeddingProviderID = pid }
            if let mid = config.embeddingModelID { self.embeddingModelID = mid }
            if let wurl = config.workersAIEmbeddingURL { self.workersAIEmbeddingURL = wurl }
            if let dim = config.embeddingDimension, dim > 0 { self.detectedEmbeddingDim = dim }
            if let enabled = config.memoryEnabled { self.memoryEnabled = enabled }
        }
        
        // 6. 云备份配置 (URL、认证密钥)
        if options.contains(.cloudConfig) {
            if let curl = config.cloudBackupURL { self.cloudBackupURL = curl }
            if let ckey = config.cloudBackupAuthKey { self.cloudBackupAuthKey = ckey }
        }
        
        // 7. 辅助模型
        if options.contains(.helperModel) {
            if let hid = config.helperGlobalModelID { self.helperGlobalModelID = hid }
        }
        
        // 8. 模型级设置 (能力开关等)
        if options.contains(.modelSettings) {
            for (key, value) in config.modelSettings {
                self.modelSettings[key] = value
            }
            saveModelSettings()
        }
    }
    
    /// 从 JSON 数据导入配置
    func importConfig(from data: Data) throws {
        let config = try JSONDecoder().decode(ExportableConfig.self, from: data)
        self.providers = config.providers
        self.selectedGlobalModelID = config.selectedGlobalModelID
        self.temperature = config.temperature
        self.historyMessageCount = config.historyMessageCount
        self.customSystemPrompt = config.customSystemPrompt
        saveProviders()
        
        // v1.7: 导入记忆（合并，不覆盖）
        if let importedMemories = config.memories {
            for mem in importedMemories {
                if !memories.contains(where: { $0.content == mem.content }) {
                    memories.append(mem)
                }
            }
            if memories.count > maxMemoryCount {
                memories = Array(memories.prefix(maxMemoryCount))
            }
            saveMemories()
        }
        
        // v1.7: 导入聊天记录（合并）
        if let importedSessions = config.sessions {
            for session in importedSessions {
                if !sessions.contains(where: { $0.id == session.id }) {
                    sessions.append(session)
                }
            }
            saveSessions()
        }
        
        // v1.7: 导入辅助模型设置
        if let helperID = config.helperGlobalModelID {
            self.helperGlobalModelID = helperID
        }
        // v1.8: 导入维度信息
        if let dim = config.embeddingDimension, dim > 0 {
            self.detectedEmbeddingDim = dim
        }
        
        // v1.12: 导入向量配置
        if let pid = config.embeddingProviderID { self.embeddingProviderID = pid }
        if let mid = config.embeddingModelID { self.embeddingModelID = mid }
        if let wurl = config.workersAIEmbeddingURL { self.workersAIEmbeddingURL = wurl }
        if let enabled = config.memoryEnabled { self.memoryEnabled = enabled }
        
        // v1.12: 导入云备份配置
        if let curl = config.cloudBackupURL { self.cloudBackupURL = curl }
        if let ckey = config.cloudBackupAuthKey { self.cloudBackupAuthKey = ckey }
        
        // v1.12: 导入思考模式和模型级设置
        self.thinkingModeRaw = config.thinkingMode.rawValue
        for (key, value) in config.modelSettings {
            self.modelSettings[key] = value
        }
        saveModelSettings()
        // v2.6: 应用手表专属模型历史
        if let watchHistory = config.watchRecentModelHistory {
            self.recentModelHistoryData = watchHistory
        }
    }
    
    /// v1.10: 从 URL 下载并导入配置 (R2 方案)
    func importConfigFromURL(_ url: URL) async throws {
        let (data, _) = try await URLSession.shared.data(from: url)
        try importFullConfig(from: data)
    }
    
    /// 兼容旧版：从一般字符串导入
    func importFullConfig(from jsonString: String) throws {
        guard let data = jsonString.data(using: .utf8) else {
            throw NSError(domain: "Import", code: -1, userInfo: [NSLocalizedDescriptionKey: "JSON 解析失败"])
        }
        try importFullConfig(from: data)
    }
    
    /// v1.8: 全量覆盖导入（用于设备迁移/重装恢复）
    func importFullConfig(from data: Data) throws {
        let config = try JSONDecoder().decode(ExportableConfig.self, from: data)
        
        // 全量覆盖 providers
        self.providers = config.providers
        self.temperature = config.temperature
        self.historyMessageCount = config.historyMessageCount
        self.customSystemPrompt = config.customSystemPrompt
        self.thinkingModeRaw = config.thinkingMode.rawValue  // v1.12: 恢复思考模式
        saveProviders()
        
        // v2.6: 优先恢复手表专用模型设置
        let importedID = config.watchSelectedGlobalModelID ?? config.selectedGlobalModelID
        let idComponents = importedID.split(separator: "|")
        if idComponents.count == 2,
           let providerUUID = UUID(uuidString: String(idComponents[0])),
           providers.contains(where: { $0.id == providerUUID }) {
            self.selectedGlobalModelID = importedID
        }
        
        if let watchHelper = config.watchHelperGlobalModelID {
            self.helperGlobalModelID = watchHelper
        } else if let helperID = config.helperGlobalModelID {
            self.helperGlobalModelID = helperID
        }
        
        // v2.6: 恢复手表专用历史
        if let watchHistory = config.watchRecentModelHistory {
            self.recentModelHistoryData = watchHistory
        }
        
        // 全量覆盖记忆
        if let importedMemories = config.memories {
            self.memories = importedMemories
            saveMemories()
        }
        
        // 全量覆盖会话
        if let importedSessions = config.sessions {
            self.sessions = importedSessions
            saveSessions()
        }
        if let dim = config.embeddingDimension, dim > 0 {
            self.detectedEmbeddingDim = dim
        }
        
        // v1.12: 恢复向量配置
        if let pid = config.embeddingProviderID { self.embeddingProviderID = pid }
        if let mid = config.embeddingModelID { self.embeddingModelID = mid }
        if let wurl = config.workersAIEmbeddingURL { self.workersAIEmbeddingURL = wurl }
        if let enabled = config.memoryEnabled { self.memoryEnabled = enabled }
        
        // v1.12: 恢复云备份配置
        if let curl = config.cloudBackupURL { self.cloudBackupURL = curl }
        if let ckey = config.cloudBackupAuthKey { self.cloudBackupAuthKey = ckey }
        
        // 重新加载模型设置
        for (key, value) in config.modelSettings {
            modelSettings[key] = value
        }
        saveModelSettings()
    }
    
    // 缓存模型名称，避免重复计算
    private var _cachedModelName: String?
    private var _cachedModelID: String?
    
    var currentDisplayModelName: String {
        // 检查缓存是否有效
        if _cachedModelID == selectedGlobalModelID, let cached = _cachedModelName {
            return cached
        }
        
        // 计算新值
        let result: String
        if selectedGlobalModelID.isEmpty {
            result = "OpenChat"
        } else {
            let components = selectedGlobalModelID.split(separator: "|")
            if components.count == 2 {
                if let found = allFavoriteModels.first(where: { $0.id == selectedGlobalModelID }) {
                    let parts = found.displayName.split(separator: "/")
                    if parts.count >= 2 { result = String(parts.last!).trimmingCharacters(in: .whitespaces) }
                    else { result = found.displayName }
                } else {
                    result = String(components[1])
                }
            } else {
                result = "OpenChat"
            }
        }
        
        // 更新缓存
        _cachedModelID = selectedGlobalModelID
        _cachedModelName = result
        return result
    }
    

    func sendMessage() {
        guard (!inputText.isEmpty || selectedImageData != nil) else { return }
        let components = selectedGlobalModelID.split(separator: "|")
        guard components.count == 2, let providerID = UUID(uuidString: String(components[0])), let modelID = String(components[1]) as String? else {
            appendSystemMessage("⚠️ 请先在设置中选择一个模型"); return
        }
        guard let providerIndex = providers.firstIndex(where: { $0.id == providerID }) else {
            appendSystemMessage("⚠️ 找不到供应商配置"); return
        }
        let provider = providers[providerIndex]
        if provider.apiKey.isEmpty { appendSystemMessage("⚠️ \(provider.name) 未配置 API Key"); return }
        
        // v2.6: 记录最近使用的模型（全局时间倒序列表）
        recordRecentModel(providerID: providerID, modelID: modelID)
        providers[providerIndex].lastUsedModelId = modelID  // 兼容旧逻辑
        saveProviders()
        
        if currentSessionId == nil { createNewSession() }
        var msgs = currentMessages
        
        // v1.5: 记录发送时间
        let sendTime = Date()
        var userMsg = ChatMessage(role: .user, text: inputText, imageData: selectedImageData)
        userMsg.sendTime = sendTime
        msgs.append(userMsg)
        updateCurrentSessionMessages(msgs)
        
        inputText = ""; selectedImageItem = nil; selectedImageData = nil; isLoading = true
        if enableHapticFeedback { WKInterfaceDevice.current().play(.click) } // 开始生成震动

        // v1.6: 初始化流式输出状态
        streamingText = ""
        streamingThinkingText = ""
        
        // v1.5: AI 消息也记录发送时间
        var assistantMsg = ChatMessage(role: .assistant, text: "")
        assistantMsg.sendTime = sendTime
        msgs.append(assistantMsg)
        updateCurrentSessionMessages(msgs)
        let botIndex = msgs.count - 1
        
        // v1.12: 首 Token 时间跟踪
        var firstTokenReceived = false
        var localFirstTokenTime: Date? = nil
        
        // v2.5 fix: 自动重试计数器（使 autoRetryEnabled 在 Watch 上真正生效）
        var retryCount = 0

        currentTask = Task {
            let history = await buildHistoryWithContext(from: msgs)

            var responseText = ""
            var thinkingText = ""
            
            // v1.8.1: 流式解析状态机 (优化性能)
            var isThinking = false
            var pendingBuffer = ""
            var hasSeenFirstThink = false
            var responseTextBeforeThink = ""
            
            // v1.6: 性能优化 - 200ms 节流（只更新 streamingText，不触发全量 diff）
            var lastUIUpdateTime = Date()
            let uiUpdateInterval: TimeInterval = 0.15  // 150ms 平衡流畅度和性能
            var pendingUpdate = false
            
            do {
                let stream = service.streamChat(messages: history, modelId: modelID, config: provider, temperature: temperature)
                for try await chunk in stream {
                    // 检查是否被取消
                    if Task.isCancelled { break }
                    
                    // v1.12: 记录首 Token 时间
                    if !firstTokenReceived {
                        firstTokenReceived = true
                        localFirstTokenTime = Date()
                        if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                            currentMsgs[botIndex].firstTokenTime = localFirstTokenTime
                            updateCurrentSessionMessagesInMemory(currentMsgs)
                        }
                    }
                    
                    // 2. 直接将网络层的 chunk 送入缓冲
                    // 底层 LLMService 会原生利用 reasoning_content 并添加外层 <think> 标签包裹
                    // 此处的 buffer 现在仅作为流式状态机控制 UI 卡片
                    pendingBuffer += chunk
                    
                    // 3. 状态机解析：基于不可逆状态的标记点引擎
                    let startTag = "<think>"
                    let endTag = "</think>"
                    
                    while true {
                        // 寻找的目标：如果还没完成思考闭环且不在思考中，找 startTag。
                        // 如果在思考中，找 endTag。
                        // 如果已经完成思考闭环 (hasSeenFirstThink == true && !isThinking)，就不再找任何 Tag。
                        let currentTag: String? = {
                            if isThinking { return endTag }
                            if !hasSeenFirstThink { return startTag }
                            return nil
                        }()
                        
                        if let target = currentTag, let range = pendingBuffer.range(of: target, options: .caseInsensitive) {
                            // 找到了目标标签
                            let textBefore = String(pendingBuffer[..<range.lowerBound])
                            
                            if isThinking {
                                // 闭合思考区
                                thinkingText += textBefore
                                isThinking = false
                                hasSeenFirstThink = true // 永久锁定！之后不管是正文探讨格式还是引用代码里的 <think>，通通当作文本！
                                
                                responseTextBeforeThink = responseText
                                responseText = ""
                            } else {
                                // 开启首次思考区
                                responseText += textBefore
                                isThinking = true
                            }
                            
                            pendingBuffer = String(pendingBuffer[range.upperBound...])
                        } else {
                            // 没找到完整标签，检查缓冲末尾是否有当前寻找标签的前缀
                            var safeLength = pendingBuffer.count
                            
                            if let target = currentTag {
                                let maxPrefixLen = target.count - 1
                                if maxPrefixLen > 0 {
                                    for i in (1...maxPrefixLen).reversed() { // 从长到短检查
                                        if pendingBuffer.count >= i {
                                            let suffix = String(pendingBuffer.suffix(i))
                                            if target.lowercased().hasPrefix(suffix.lowercased()) {
                                                safeLength = pendingBuffer.count - i
                                                break
                                            }
                                        }
                                    }
                                }
                            }
                            
                            if safeLength > 0 {
                                let safeContent = String(pendingBuffer.prefix(safeLength))
                                if isThinking { thinkingText += safeContent }
                                else { responseText += safeContent }
                                pendingBuffer = String(pendingBuffer.suffix(from: pendingBuffer.index(pendingBuffer.startIndex, offsetBy: safeLength)))
                            }
                            break // 退出循环，等待下一个 chunk
                        }
                    }
                    
                    // v1.6: 高性能流式更新 — 只更新 streamingText，不碰 sessions
                    let now = Date()
                    if now.timeIntervalSince(lastUIUpdateTime) >= uiUpdateInterval {
                        let finalContent = (responseTextBeforeThink + responseText).trimmingCharacters(in: .whitespacesAndNewlines)
                        streamingText = finalContent
                        if thinkingMode != .disabled {
                            streamingThinkingText = thinkingText
                        }
                        lastUIUpdateTime = now
                        pendingUpdate = false
                    } else {
                        pendingUpdate = true
                    }
                }
                
                // 循环结束，处理剩余 Buffer
                if !pendingBuffer.isEmpty {
                    if isThinking {
                         thinkingText += pendingBuffer
                    } else {
                         responseText += pendingBuffer
                    }
                }
                
                // v1.6: 流式完成 — 一次性写入 sessions（触发完整 Markdown 渲染）
                let finalContent = (responseTextBeforeThink + responseText).trimmingCharacters(in: .whitespacesAndNewlines)
                let finalThinking = thinkingText
                
                if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                    currentMsgs[botIndex].text = finalContent
                    
                    if thinkingMode == .disabled {
                        currentMsgs[botIndex].thinkingContent = nil
                    } else {
                        currentMsgs[botIndex].thinkingContent = finalThinking.isEmpty ? nil : finalThinking
                    }
                    
                    // v1.12: 记录完成时间
                    currentMsgs[botIndex].completeTime = Date()
                    if let t = localFirstTokenTime { currentMsgs[botIndex].firstTokenTime = t }
                    
                    // 先清空流式状态，再写入 sessions
                    streamingText = ""
                    streamingThinkingText = ""
                    updateCurrentSessionMessagesInMemory(currentMsgs)
                }
                
                // 流式输出完成后，一次性保存到磁盘
                saveSessions()
                // 生成完成：成功震动
                if enableHapticFeedback { WKInterfaceDevice.current().play(.success) }
                
                // v1.7: 后台提取记忆（非阻塞）
                if self.memoryEnabled {
                    Task { [weak self] in
                        await self?.extractMemories()
                    }
                }
                
                // v1.7: 自动生成会话标题（首次对话时）
                if let session = self.sessions.first(where: { $0.id == self.currentSessionId }),
                   session.title == "新对话",
                   let firstUserMsg = session.messages.first(where: { $0.role == .user }) {
                    Task { [weak self] in
                        await self?.generateSessionTitle(from: firstUserMsg.text)
                    }
                }
            } catch {
                // v1.6: 先清空流式状态
                streamingText = ""
                streamingThinkingText = ""
                
                // 如果是取消错误，标记为用户停止
                if Task.isCancelled {
                    if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                        // 写入已积累的文本
                        let finalContent = (responseTextBeforeThink + responseText).trimmingCharacters(in: .whitespacesAndNewlines)
                        currentMsgs[botIndex].text = finalContent.isEmpty ? "" : finalContent + "\n[已停止]"
                        if thinkingMode != .disabled && !thinkingText.isEmpty {
                            currentMsgs[botIndex].thinkingContent = thinkingText
                        }
                        updateCurrentSessionMessagesInMemory(currentMsgs)
                    }
                    saveSessions()
                    if enableHapticFeedback { WKInterfaceDevice.current().play(.directionDown) }
                } else if autoRetryEnabled && retryCount < maxRetries {
                    // v2.5 fix: 自动重试（与 iOS 端行为对齐）
                    retryCount += 1
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 等待 1 秒
                    if Task.isCancelled { isLoading = false; currentTask = nil; return }

                    // 重试时更新消息气泡提示
                    if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                        currentMsgs[botIndex].text = "正在重试 (\(retryCount)/\(maxRetries))..."
                        updateCurrentSessionMessagesInMemory(currentMsgs)
                    }

                    // 重置流式状态并重新发起请求（注意：此处复用同一 Task，不创建新 Task）
                    responseText = ""
                    thinkingText = ""
                    isThinking = false
                    pendingBuffer = ""
                    hasSeenFirstThink = false
                    responseTextBeforeThink = ""
                    firstTokenReceived = false

                    let retryStream = service.streamChat(messages: history, modelId: modelID, config: provider, temperature: temperature)
                    do {
                        for try await chunk in retryStream {
                            if Task.isCancelled { break }
                            pendingBuffer += chunk
                            let startTag = "<think>"; let endTag = "</think>"
                            while true {
                                let currentTag: String? = { if isThinking { return endTag }; if !hasSeenFirstThink { return startTag }; return nil }()
                                if let target = currentTag, let range = pendingBuffer.range(of: target, options: .caseInsensitive) {
                                    let textBefore = String(pendingBuffer[..<range.lowerBound])
                                    if isThinking { thinkingText += textBefore; isThinking = false; hasSeenFirstThink = true; responseTextBeforeThink = responseText; responseText = "" }
                                    else { responseText += textBefore; isThinking = true }
                                    pendingBuffer = String(pendingBuffer[range.upperBound...])
                                } else {
                                    if let target = currentTag {
                                        let maxPrefixLen = target.count - 1
                                        var safeLength = pendingBuffer.count
                                        if maxPrefixLen > 0 {
                                            for i in (1...maxPrefixLen).reversed() {
                                                if pendingBuffer.count >= i {
                                                    let suffix = String(pendingBuffer.suffix(i))
                                                    if target.lowercased().hasPrefix(suffix.lowercased()) { safeLength = pendingBuffer.count - i; break }
                                                }
                                            }
                                        }
                                        if safeLength > 0 { let safe = String(pendingBuffer.prefix(safeLength)); if isThinking { thinkingText += safe } else { responseText += safe }; pendingBuffer = String(pendingBuffer.suffix(from: pendingBuffer.index(pendingBuffer.startIndex, offsetBy: safeLength))) }
                                    }
                                    break
                                }
                            }
                            let now = Date()
                            if now.timeIntervalSince(lastUIUpdateTime) >= uiUpdateInterval {
                                let finalContent = (responseTextBeforeThink + responseText).trimmingCharacters(in: .whitespacesAndNewlines)
                                streamingText = finalContent
                                if thinkingMode != .disabled { streamingThinkingText = thinkingText }
                                lastUIUpdateTime = now; pendingUpdate = false
                            } else { pendingUpdate = true }
                        }
                        if !pendingBuffer.isEmpty { if isThinking { thinkingText += pendingBuffer } else { responseText += pendingBuffer } }
                        let finalContent = (responseTextBeforeThink + responseText).trimmingCharacters(in: .whitespacesAndNewlines)
                        let finalThinking = thinkingText
                        if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                            currentMsgs[botIndex].text = finalContent
                            if thinkingMode == .disabled { currentMsgs[botIndex].thinkingContent = nil } else { currentMsgs[botIndex].thinkingContent = finalThinking.isEmpty ? nil : finalThinking }
                            currentMsgs[botIndex].completeTime = Date()
                            if let t = localFirstTokenTime { currentMsgs[botIndex].firstTokenTime = t }
                            streamingText = ""; streamingThinkingText = ""
                            updateCurrentSessionMessagesInMemory(currentMsgs)
                        }
                        saveSessions()
                        if enableHapticFeedback { WKInterfaceDevice.current().play(.success) }
                        if self.memoryEnabled { Task { [weak self] in await self?.extractMemories() } }
                    } catch {
                        streamingText = ""; streamingThinkingText = ""
                        if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                            currentMsgs[botIndex].text = "❌ [已重试 \(retryCount) 次] \(error.localizedDescription)"
                            updateCurrentSessionMessagesInMemory(currentMsgs)
                            saveSessions()
                            if enableHapticFeedback { WKInterfaceDevice.current().play(.failure) }
                        }
                    }
                } else if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                    let finalContent = (responseTextBeforeThink + responseText).trimmingCharacters(in: .whitespacesAndNewlines)
                    var errorMsg = "❌ \(error.localizedDescription)"
                    if retryCount > 0 { errorMsg = "❌ [已重试 \(retryCount) 次] \(error.localizedDescription)" }
                    if finalContent.isEmpty { currentMsgs[botIndex].text = errorMsg }
                    else { currentMsgs[botIndex].text = finalContent + "\n[中断]" }
                    if thinkingMode != .disabled && !thinkingText.isEmpty {
                        currentMsgs[botIndex].thinkingContent = thinkingText
                    }
                    updateCurrentSessionMessagesInMemory(currentMsgs)
                    saveSessions()
                    if enableHapticFeedback { WKInterfaceDevice.current().play(.failure) }
                }
            }
            isLoading = false
            currentTask = nil
        }
    }
    
    /// 构建带系统上下文的历史消息列表（注入记忆、时间、位置等）
    private func buildHistoryWithContext(from msgs: [ChatMessage]) async -> [ChatMessage] {
        var history = msgs.dropLast(1).suffix(max(historyMessageCount, 1)).map { $0 }
        
        // 构造系统上下文
        var systemParts: [String] = []
        
        // 1. 用户自定义提示词（优先级最高）
        if !customSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            systemParts.append(customSystemPrompt)
        }
        
        // 2. v1.7: 注入长期记忆（全量回退模式）
        if memoryEnabled && !memories.isEmpty {
            // 从最后一条用户消息提取查询
            let userQuery = msgs.last(where: { $0.role == .user })?.text ?? ""
            let relevantMemories: [MemoryItem]
            
            // 检查是否有带 embedding 的记忆且已配置 Embedding 提供商
            let hasEmbeddings = memories.contains(where: { $0.embedding != nil })
            if hasEmbeddings, let (embConfig, embModel) = getEmbeddingProvider(), !userQuery.isEmpty {
                // 向量检索 Top-5（综合相似度 + 重要性）
                if let queryEmb = try? await service.fetchEmbedding(text: userQuery, modelId: embModel, config: embConfig) {
                    var scored: [(MemoryItem, Float)] = memories.map { m in
                        let similarity = m.embedding.map { cosineSimilarity(queryEmb, $0) } ?? 0.3
                        let finalScore = similarity * 0.7 + m.importance * 0.3
                        return (m, finalScore)
                    }
                    scored.sort { $0.1 > $1.1 }
                    relevantMemories = scored.prefix(5).map { $0.0 }
                } else {
                    relevantMemories = Array(memories.sorted { $0.importance > $1.importance }.prefix(10))
                }
            } else {
                // 无 Embedding，按重要性排序注入（最多 10 条）
                relevantMemories = Array(memories.sorted { $0.importance > $1.importance }.prefix(10))
            }
            
            if !relevantMemories.isEmpty {
                let memoryLines = relevantMemories.map { "- \($0.content)" }.joined(separator: "\n")
                systemParts.append("你知道以下关于用户的信息（长期记忆）：\n\(memoryLines)")
            }
        }
        
        // 3. 时间和位置信息（可由用户关闭）
        var contextInfo = ""
        if sendTimeToAI {
            contextInfo = "Current Time: \(Date().formatted(date: .numeric, time: .standard))"
        }
        if sendLocationToAI, let location = LocationService.shared.locationInfo {
            let cleanLoc = location.replacingOccurrences(of: "Location: ", with: "")
            contextInfo += contextInfo.isEmpty ? "Location: \(cleanLoc)" : "; Location: \(cleanLoc)"
        }
        if !contextInfo.isEmpty {
            systemParts.append(contextInfo)
        }
        
        // 合并系统消息
        let systemMsg = ChatMessage(role: .system, text: systemParts.joined(separator: "\n\n"))
        history.insert(systemMsg, at: 0)
        
        return history
    }

    // parseThinkTags 已移除 — 所有路径统一使用状态机解析器 (v1.12)
    
    func appendSystemMessage(_ text: String) {
        if currentSessionId == nil { createNewSession() }
        var msgs = currentMessages
        msgs.append(ChatMessage(role: .assistant, text: text))
        updateCurrentSessionMessages(msgs)
    }
    func clearCurrentChat() { updateCurrentSessionMessages([]) }
    
    // MARK: - 记忆系统 (v1.7)
    
    private let maxMemoryCount = 200  // v1.8: 扩容
    
    func saveMemories() {
        if let encoded = try? JSONEncoder().encode(memories) {
            UserDefaults.standard.set(encoded, forKey: "userMemories_v1")
        }
    }
    
    func loadMemories() {
        if let data = UserDefaults.standard.data(forKey: "userMemories_v1"),
           let decoded = try? JSONDecoder().decode([MemoryItem].self, from: data) {
            memories = decoded
        }
    }
    
    // v2.1: 回收站存取
    func saveMemoryTrash() {
        if let encoded = try? JSONEncoder().encode(memoryTrash) {
            UserDefaults.standard.set(encoded, forKey: "memoryTrash_v1")
        }
    }
    
    func loadMemoryTrash() {
        if let data = UserDefaults.standard.data(forKey: "memoryTrash_v1"),
           let decoded = try? JSONDecoder().decode([MemoryItem].self, from: data) {
            memoryTrash = decoded
        }
    }
    
    // iCloud 记忆相关代码已移除 — 备份/恢复走 R2 (v1.12)
    
    func addMemory(_ content: String, embedding: [Float]? = nil, importance: Float = 0.5, type: MemoryType = .longTerm, expiration: Date? = nil) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // v1.8: 语义去重 — 用向量相似度检测近义记忆
        if let newEmb = embedding {
            for i in memories.indices {
                if let existingEmb = memories[i].embedding {
                    let sim = cosineSimilarity(newEmb, existingEmb)
                    if sim > 0.85 {
                        // 语义高度相似，更新内容而非重复添加
                        print("🔄 语义去重：\(trimmed) ≈ \(memories[i].content)（相似度 \(String(format: "%.2f", sim))）")
                        memories[i].content = trimmed  // 用更新的表述替换
                        memories[i].lastUpdated = Date()
                        if memories[i].type == .shortTerm && type == .longTerm {
                            memories[i].type = .longTerm
                            memories[i].expiration = nil
                        }
                        if importance > memories[i].importance { memories[i].importance = importance }
                        saveMemories()
                        return
                    }
                }
            }
        }
        
        // v2.0: 模糊文本去重 + 子集检测 — 当向量不可用时，用关键词重叠度检测相似记忆
        let newTokens = Set(trimmed.components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: "\u{4e00}"..."\u{9fff}")).inverted).filter { $0.count > 1 })
        if newTokens.count >= 2 {
            for i in memories.indices {
                let existTokens = Set(memories[i].content.components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: "\u{4e00}"..."\u{9fff}")).inverted).filter { $0.count > 1 })
                guard !existTokens.isEmpty else { continue }
                let intersection = newTokens.intersection(existTokens)
                let union = newTokens.union(existTokens)
                let jaccard = Float(intersection.count) / Float(union.count)
                // 检测1: Jaccard 相似度超阈值
                // 检测2: 已有记忆的关键词是新记忆的子集（即新记忆是多条旧记忆的合并）
                let isSubset = existTokens.isSubset(of: newTokens)
                if jaccard > 0.6 || (isSubset && existTokens.count >= 2) {
                    print("🔄 模糊去重：\(trimmed) ≈ \(memories[i].content)（Jaccard \(String(format: "%.2f", jaccard)), subset=\(isSubset)）")
                    memories[i].content = trimmed
                    memories[i].lastUpdated = Date()
                    if memories[i].type == .shortTerm && type == .longTerm {
                        memories[i].type = .longTerm
                        memories[i].expiration = nil
                    }
                    if importance > memories[i].importance { memories[i].importance = importance }
                    saveMemories()
                    return
                }
            }
        }
        
        // 精确去重：相同文本只更新时间戳
        if let existingIdx = memories.firstIndex(where: { $0.content == trimmed }) {
            memories[existingIdx].lastUpdated = Date()
            if memories[existingIdx].type == .shortTerm && type == .longTerm {
                memories[existingIdx].type = .longTerm
                memories[existingIdx].expiration = nil
            }
            saveMemories()
            return
        }
        
        let sessionTitle = sessions.first(where: { $0.id == currentSessionId })?.title
        let item = MemoryItem(
            content: trimmed, createdAt: Date(), source: sessionTitle,
            embedding: embedding, importance: importance,
            type: type, expiration: expiration, lastUpdated: Date()
        )
        memories.insert(item, at: 0)
        
        // v1.8: 智能淘汰 — 200 条上限仅计长期记忆，临时记忆不占名额
        // 1. 先清理过期临时记忆
        memories.removeAll { $0.type == .shortTerm && $0.isExpired }
        
        // 2. 长期记忆超过上限时，拒绝新增（不自动删）
        let longTermCount = memories.filter { $0.type == .longTerm }.count
        if longTermCount > maxMemoryCount && type == .longTerm {
            print("⚠️ 长期记忆已满（\(maxMemoryCount)条），无法添加")
            memories.removeFirst() // 移除刚插入的
        }
        
        // 3. 临时记忆超 200 条时，淘汰最旧的临时记忆
        let shortTermMems = memories.enumerated().filter { $0.element.type == .shortTerm && !$0.element.isExpired }
        if shortTermMems.count > 200 {
            if let oldestIdx = shortTermMems
                .min(by: { ($0.element.lastUpdated ?? $0.element.createdAt) < ($1.element.lastUpdated ?? $1.element.createdAt) })
                .map({ $0.offset }) {
                memories.remove(at: oldestIdx)
            }
        }
        saveMemories()
    }
    
    // v2.5: 软删除（移到回收站），与 iOS 端对称；extractMemories 的自动删除路径会调用此方法
    func softDeleteMemory(at index: Int) {
        guard index < memories.count else { return }
        var item = memories.remove(at: index)
        item.deletedAt = Date()
        memoryTrash.insert(item, at: 0)
        saveMemories()
        saveMemoryTrash()
        WatchSessionManager.shared.pushFullDataToPhone() // 同步到 iPhone
    }

    func deleteMemory(id: UUID) {
        if let idx = memories.firstIndex(where: { $0.id == id }) {
            softDeleteMemory(at: idx)
        }
    }
    
    func deleteMemories(at offsets: IndexSet) {
        let deleted = offsets.map { memories[$0] }
        memories.remove(atOffsets: offsets)
        let now = Date()
        for var item in deleted {
            item.deletedAt = now
            memoryTrash.insert(item, at: 0)
        }
        saveMemories()
        saveMemoryTrash()
        WatchSessionManager.shared.pushFullDataToPhone() // 同步到 iPhone
    }
    
    func clearAllMemories() {
        let now = Date()
        for var item in memories {
            item.deletedAt = now
            memoryTrash.insert(item, at: 0)
        }
        memories.removeAll()
        saveMemories()
        saveMemoryTrash()
        WatchSessionManager.shared.pushFullDataToPhone() // 同步到 iPhone
    }

    // v2.1: 从回收站恢复记忆
    func restoreMemoryFromTrash(at index: Int) {
        guard index < memoryTrash.count else { return }
        var item = memoryTrash.remove(at: index)
        item.deletedAt = nil
        memories.insert(item, at: 0)
        saveMemories()
        saveMemoryTrash()
        WatchSessionManager.shared.pushFullDataToPhone()
    }

    // v2.1: 从回收站永久删除（不可恢复）
    func permanentlyDeleteFromTrash(at index: Int) {
        guard index < memoryTrash.count else { return }
        memoryTrash.remove(at: index)
        saveMemoryTrash()
        WatchSessionManager.shared.pushFullDataToPhone()
    }

    // v2.1: 清空回收站
    func emptyMemoryTrash() {
        memoryTrash.removeAll()
        saveMemoryTrash()
        WatchSessionManager.shared.pushFullDataToPhone()
    }

    /// v1.8: 利用 LLM 从当前对话中提取记忆（双轨模式 + 反幻觉）
    func extractMemories() async {
        guard memoryEnabled else { return }
        
        let msgs = currentMessages
        guard msgs.count >= 2 else { return }
        
        // 取最近 6 条用户消息（只分析用户说的话，不看 AI 回复）
        // 根因修复：AI 回复中引用已有记忆、提建议等内容不应被提取模型看到
        let recentUserMsgs = msgs.suffix(min(12, msgs.count))
            .filter { $0.role == .user }
            .suffix(6)
        let conversationText = recentUserMsgs.map { "用户: \($0.text)" }.joined(separator: "\n")
        
        guard !conversationText.isEmpty else { return }
        
        // v2.0: 只分析用户消息，提取用户侧写
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy.M.d"
        let todayStr = dateFormatter.string(from: Date())
        
        var existingMemoryNote = ""
        if !memories.isEmpty {
            let existingLines = memories.prefix(30).map { "• \($0.content)" }.joined(separator: "\n")
            existingMemoryNote = """
            
            ━━━ 已有记忆（不要重复） ━━━
            \(existingLines)
            以上已记录，不要重复提取。仅当用户更新或纠正了某条时，输出更新版。
            
            """
        }
        
        let extractionPrompt = """
        你是用户侧写分析师。从用户的发言中提取值得长期记住的信息。

        ━━━ 当前时间 ━━━
        \(todayStr)

        ━━━ 提取类别 ━━━

        [临时] 当下的情绪、心情、短期打算（24h后自动失效）
          → 必须带日期，记录具体原因
          → 例：[临时] 2026.3.6 心情低落，数学考砸了只有65分

        [长期] 用户的身份、事实、关系
          → 例：[长期] 用户是高二学生 / 用户有个姐姐在读大学

        [长期] 用户的喜好、兴趣、习惯
          → 例：[长期] 用户喜欢看动漫，最近在追《芙莉莲》

        [长期] 用户经历的事件（必须带日期或时间线索）
          → 例：[长期] 2026.3.1 用户去了东京旅行
          → 例：[长期] 用户最近在准备高考

        [!] 用户明确说"帮我记住"的信息
          → 例：[!] 用户生日是3月15号

        ━━━ 核心规则 ━━━
        1. 只提取用户亲口说的，禁止推测
        2. 同一件事的所有细节必须合并成一条，绝对不要拆成多条
           例：心情差+原因+当天打算 → 合并为一条 [临时]
        3. 不要记录"用户要求记住"这个动作，直接记事实
        4. "今天""昨天""上周"等相对时间 → 转换为具体日期
        5. 第三人称描述，每条≤40字
        6. 没有新信息就回复"无"

        ━━━ 示例 ━━━
        输入：
        用户: 今天心情好差啊考试没考好
        用户: 晚上打算吃点好的缓缓

        正确输出：
        - [临时] \(todayStr) 用户心情差，考试失利，晚上打算吃点好的缓解

        错误输出（拆分了）：
        - [临时] 用户今天心情差
        - [临时] 用户考试没考好
        - [临时] 用户晚上打算吃好的
        \(existingMemoryNote)
        ━━━ 用户消息 ━━━
        \(conversationText)
        """
        
        // 优先使用辅助模型
        let targetModelID = helperGlobalModelID.isEmpty ? selectedGlobalModelID : helperGlobalModelID
        let components = targetModelID.split(separator: "|")
        guard components.count == 2,
              let providerID = UUID(uuidString: String(components[0])),
              let provider = providers.first(where: { $0.id == providerID }),
              !provider.apiKey.isEmpty else { return }
        let modelID = String(components[1])
        
        let extractionMsg = ChatMessage(role: .user, text: extractionPrompt)
        let stream = service.streamChat(
            messages: [extractionMsg],
            modelId: modelID,
            config: provider,
            temperature: 0.05,  // 极低温度
            disableReasoning: true
        )
        
        var result = ""
        do {
            for try await chunk in stream {
                result += chunk
            }
        } catch {
            print("⚠️ 记忆提取失败: \(error.localizedDescription)")
            return
        }
        
        // v2.1: 即使模型强行输出思考过程（如 Qwen/DeepSeek 等），也通过正则将其移除，确保严格提取
        var finalResult = result
        if finalResult.contains("<think>") {
            finalResult = finalResult.replacingOccurrences(of: "<think>[\\s\\S]*?</think>", with: "", options: .regularExpression)
            finalResult = finalResult.replacingOccurrences(of: "<think>[\\s\\S]*", with: "", options: .regularExpression)
        }
        let trimmed = finalResult.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "无", !trimmed.hasPrefix("无") else { return }
        
        let embProvider = getEmbeddingProvider()
        
        // v1.8: 解析双轨前缀（包含 v2.5 新增的 [删除] 路径，与 iOS 端对称）
        let allLines = trimmed.components(separatedBy: "\n")
        let lines = Array(allLines.prefix(20))
        let maxDeletionsPerExtraction = 3  // 安全阀：每次提取最多删除 3 条
        var deletionCount = 0

        for line in lines {
            var cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
            var memType: MemoryType = .longTerm
            var memExpiration: Date? = nil
            var isHighPriority = false
            var isDelete = false

            // 解析前缀（优先匹配 [删除]）
            if cleaned.hasPrefix("[删除]") || cleaned.hasPrefix("- [删除]") {
                cleaned = cleaned.replacingOccurrences(of: "[删除]", with: "")
                cleaned = cleaned.hasPrefix("- ") ? String(cleaned.dropFirst(2)) : cleaned
                isDelete = true
            } else if cleaned.hasPrefix("[!] ") || cleaned.hasPrefix("- [!] ") {
                cleaned = cleaned.replacingOccurrences(of: "[!] ", with: "")
                cleaned = cleaned.hasPrefix("- ") ? String(cleaned.dropFirst(2)) : cleaned
                isHighPriority = true
                memType = .longTerm
            } else if cleaned.hasPrefix("[临时]") || cleaned.hasPrefix("- [临时]") {
                cleaned = cleaned.replacingOccurrences(of: "[临时]", with: "")
                cleaned = cleaned.hasPrefix("- ") ? String(cleaned.dropFirst(2)) : cleaned
                memType = .shortTerm
                memExpiration = Date().addingTimeInterval(24 * 3600) // 24h 过期
            } else if cleaned.hasPrefix("[长期]") || cleaned.hasPrefix("- [长期]") {
                cleaned = cleaned.replacingOccurrences(of: "[长期]", with: "")
                cleaned = cleaned.hasPrefix("- ") ? String(cleaned.dropFirst(2)) : cleaned
                memType = .longTerm
            } else if cleaned.hasPrefix("- ") {
                cleaned = String(cleaned.dropFirst(2))
            } else if cleaned.hasPrefix("* ") {
                cleaned = String(cleaned.dropFirst(2))
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, cleaned.count > 2 else { continue }

            // v2.5: [删除] 路径 — 文本包含匹配（Watch 上无需 Embedding 也能删除）
            if isDelete {
                guard deletionCount < maxDeletionsPerExtraction else {
                    print("⚠️ 已达最大删除数 \(maxDeletionsPerExtraction)，跳过: \(cleaned.prefix(30))")
                    continue
                }
                let lowered = cleaned.lowercased()
                await MainActor.run {
                    if let idx = self.memories.firstIndex(where: {
                        $0.content.lowercased().contains(lowered) || lowered.contains($0.content.lowercased())
                    }) {
                        self.softDeleteMemory(at: idx)
                        print("🗑️ Watch 自动删除记忆: \(self.memoryTrash.first?.content ?? cleaned)")
                    } else {
                        print("⚠️ 删除失败：找不到与 '\(cleaned.prefix(30))' 匹配的记忆")
                    }
                }
                deletionCount += 1
                continue
            }

            // 生成向量嵌入
            var emb: [Float]? = nil
            if let (embConfig, embModel) = embProvider {
                do {
                    emb = try await service.fetchEmbedding(text: cleaned, modelId: embModel, config: embConfig)
                } catch {
                    print("⚠️ Embedding 生成失败: \(error.localizedDescription)")
                }
            }

            await MainActor.run {
                addMemory(cleaned, embedding: emb, importance: isHighPriority ? 0.9 : 0.5, type: memType, expiration: memExpiration)
            }
        }

        // 提取完成后推送到 iPhone
        await MainActor.run {
            if !WatchSessionManager.shared.isSyncingFromRemote {
                WatchSessionManager.shared.pushFullDataToPhone()
            }
        }

        print("✅ 记忆提取完成，当前共 \(memories.count) 条记忆")
    }
    
    /// 获取 Embedding 提供商配置
    func getEmbeddingProvider() -> (ProviderConfig, String)? {
        // v1.8: Workers AI 特殊处理
        if embeddingProviderID == "workersAI" {
            let url = workersAIEmbeddingURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { return nil }
            let virtualConfig = ProviderConfig(
                name: "Workers AI", baseURL: url, apiKey: "none",
                isPreset: false, icon: "☁️", apiType: .workersAI
            )
            return (virtualConfig, "workers-ai-embedding")
        }
        guard !embeddingProviderID.isEmpty, !embeddingModelID.isEmpty,
              let providerUUID = UUID(uuidString: embeddingProviderID),
              let provider = providers.first(where: { $0.id == providerUUID }),
              !provider.apiKey.isEmpty else { return nil }
        return (provider, embeddingModelID)
    }
    
    /// v1.8: 探测 Embedding 模型的输出维度
    func probeEmbeddingDimension() async {
        guard let (config, modelId) = getEmbeddingProvider() else { return }
        do {
            let testEmb = try await service.fetchEmbedding(text: "test", modelId: modelId, config: config)
            let dim = testEmb.count
            await MainActor.run {
                if dim > 0 {
                    self.detectedEmbeddingDim = dim
                    print("✅ 探测到 Embedding 维度: \(dim)")
                }
            }
        } catch {
            print("⚠️ 维度探测失败: \(error.localizedDescription)")
        }
    }
    
    /// v1.8: 检查并自动迁移记忆向量（维度不匹配时）
    func checkAndAutoMigrate() async {
        guard detectedEmbeddingDim > 0 else { return }
        guard let (config, modelId) = getEmbeddingProvider() else { return }
        
        // 找出维度不匹配或缺失向量的记忆
        let mismatchedIndices = memories.enumerated().compactMap { (idx, mem) -> Int? in
            guard let emb = mem.embedding else { return idx } // 缺失向量，需要补全
            return emb.count != detectedEmbeddingDim ? idx : nil // 维度不匹配，需要重新生成
        }
        
        guard !mismatchedIndices.isEmpty else { return }
        
        await MainActor.run {
            migrationProgress = "迁移中 0/\(mismatchedIndices.count)"
        }
        
        var successCount = 0
        for (i, memIdx) in mismatchedIndices.enumerated() {
            do {
                let newEmb = try await service.fetchEmbedding(
                    text: memories[memIdx].content,
                    modelId: modelId,
                    config: config
                )
                await MainActor.run {
                    if memIdx < memories.count {
                        memories[memIdx].embedding = newEmb
                        memories[memIdx].lastUpdated = Date()
                    }
                    migrationProgress = "迁移中 \(i + 1)/\(mismatchedIndices.count)"
                }
                successCount += 1
                // 每 10 条保存一次
                if successCount % 10 == 0 {
                    await MainActor.run { saveMemories() }
                }
            } catch {
                print("⚠️ 迁移第 \(i+1) 条失败: \(error.localizedDescription)")
                // 继续处理其他的，不中断
            }
        }
        
        await MainActor.run {
            saveMemories()
            migrationProgress = nil
            print("✅ 记忆迁移完成，成功 \(successCount)/\(mismatchedIndices.count)")
        }
    }
    
    /// 余弦相似度 (v1.8: Accelerate 优化)
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        vDSP_dotpr(a, 1, a, 1, &normA, vDSP_Length(a.count))
        vDSP_dotpr(b, 1, b, 1, &normB, vDSP_Length(b.count))
        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 0 else { return 0 }
        return dot / denom
    }
    
    /// 检索与查询最相关的 Top-K 记忆 (v1.8: 过滤过期记忆)
    func retrieveRelevantMemories(for query: String, topK: Int = 5) async -> [MemoryItem] {
        // v1.8: 先过滤过期的临时记忆
        let activeMemories = memories.filter { !$0.isExpired }
        guard !activeMemories.isEmpty else { return [] }
        
        // 如果没有配置 Embedding，返回全部活跃记忆
        guard let (embConfig, embModel) = getEmbeddingProvider() else {
            return Array(activeMemories.prefix(topK))
        }
        
        let memoriesWithEmbedding = activeMemories.filter { $0.embedding != nil }
        guard !memoriesWithEmbedding.isEmpty else {
            return Array(activeMemories.prefix(topK))
        }
        
        do {
            let queryEmbedding = try await service.fetchEmbedding(text: query, modelId: embModel, config: embConfig)
            
            var scored: [(memory: MemoryItem, score: Float)] = []
            for memory in activeMemories {
                if let emb = memory.embedding {
                    let score = cosineSimilarity(queryEmbedding, emb)
                    scored.append((memory, score))
                } else {
                    scored.append((memory, 0.3))
                }
            }
            
            scored.sort { $0.score > $1.score }
            return scored.prefix(topK).map { $0.memory }
        } catch {
            print("⚠️ 查询 Embedding 失败: \(error.localizedDescription)，回退全量注入")
            return Array(activeMemories.prefix(topK))
        }
    }
    
    /// v1.7: 自动生成会话标题
    func generateSessionTitle(from firstMessage: String) async {
        // 优先使用辅助模型，若未设置则使用当前模型
        let targetModelID = helperGlobalModelID.isEmpty ? selectedGlobalModelID : helperGlobalModelID
        
        let components = targetModelID.split(separator: "|")
        guard components.count == 2,
              let providerID = UUID(uuidString: String(components[0])),
              let provider = providers.first(where: { $0.id == providerID }),
              !provider.apiKey.isEmpty else { return }
        let modelID = String(components[1])
        
        let titlePrompt = "用不超过10个字总结以下内容的主题，只输出标题本身，不要加引号或标点：\n\(firstMessage.prefix(200))"
        let titleMsg = ChatMessage(role: .user, text: titlePrompt)
        let stream = service.streamChat(
            messages: [titleMsg],
            modelId: modelID,
            config: provider,
            temperature: 0.3
        )
        
        var result = ""
        do {
            for try await chunk in stream {
                result += chunk
            }
        } catch {
            print("⚠️ 标题生成失败: \(error.localizedDescription)")
            return
        }
        
        let title = result.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "《", with: "")
            .replacingOccurrences(of: "》", with: "")
        guard !title.isEmpty, title.count <= 20 else { return }
        
        await MainActor.run {
            if let idx = self.sessions.firstIndex(where: { $0.id == self.currentSessionId }) {
                self.sessions[idx].title = title
                self.saveSessions()
                print("✅ 自动标题: \(title)")
            }
        }
    }
    
    /// 重新生成最后一条回复
    func regenerateLastMessage() {
        guard !isLoading else { return }
        var msgs = currentMessages
        
        // 移除最后一条 assistant 消息
        while let last = msgs.last, last.role == .assistant {
            msgs.removeLast()
        }
        
        // 找到最后一条 user 消息
        guard let lastUserMsg = msgs.last, lastUserMsg.role == .user else { return }
        
        // 重新发送
        let components = selectedGlobalModelID.split(separator: "|")
        guard components.count == 2,
              let providerID = UUID(uuidString: String(components[0])),
              let modelID = String(components[1]) as String?,
              let provider = providers.first(where: { $0.id == providerID }),
              !provider.apiKey.isEmpty else { return }
        
        updateCurrentSessionMessages(msgs)
        isLoading = true
        
        // v1.6: 初始化流式输出状态
        streamingText = ""
        streamingThinkingText = ""
        
        msgs.append(ChatMessage(role: .assistant, text: ""))
        updateCurrentSessionMessagesInMemory(msgs) // 只更新内存，不写磁盘
        let botIndex = msgs.count - 1
        
        currentTask = Task {
            let history = await buildHistoryWithContext(from: msgs)
            var responseText = ""
            var thinkingText = ""
            
            // v1.12: 统一状态机解析器（与 sendMessage 一致）
            var isThinking = false
            var pendingBuffer = ""
            
            // v1.12: 统一节流间隔 150ms
            var lastUIUpdateTime = Date()
            let uiUpdateInterval: TimeInterval = 0.15
            var pendingUpdate = false
            
            do {
                let stream = service.streamChat(messages: history, modelId: modelID, config: provider, temperature: temperature)
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    
                    // 2. 追加到缓冲
                    pendingBuffer += chunk
                    
                    // 3. 状态机解析循环
                    while true {
                        let tag = isThinking ? "</think>" : "<think>"
                        if let range = pendingBuffer.range(of: tag, options: .caseInsensitive) {
                            let contentBefore = String(pendingBuffer[..<range.lowerBound])
                            if isThinking {
                                thinkingText += contentBefore
                                isThinking = false
                            } else {
                                responseText += contentBefore
                                isThinking = true
                            }
                            pendingBuffer = String(pendingBuffer[range.upperBound...])
                        } else {
                            let keepLength = tag.count - 1
                            if pendingBuffer.count > keepLength {
                                let safeIndex = pendingBuffer.index(pendingBuffer.endIndex, offsetBy: -keepLength)
                                let safeContent = String(pendingBuffer[..<safeIndex])
                                if isThinking { thinkingText += safeContent }
                                else { responseText += safeContent }
                                pendingBuffer = String(pendingBuffer[safeIndex...])
                            }
                            break
                        }
                    }
                    
                    // 4. 节流更新 streamingText
                    let now = Date()
                    if now.timeIntervalSince(lastUIUpdateTime) >= uiUpdateInterval {
                        let finalContent = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                        streamingText = finalContent
                        if thinkingMode != .disabled {
                            streamingThinkingText = thinkingText
                        }
                        lastUIUpdateTime = now
                        pendingUpdate = false
                    } else {
                        pendingUpdate = true
                    }
                }
                
                // 循环结束，处理剩余 Buffer
                if !pendingBuffer.isEmpty {
                    if isThinking { thinkingText += pendingBuffer }
                    else { responseText += pendingBuffer }
                }
                
                // 流式完成 — 一次性写入 sessions
                let finalContent = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                let finalThinking = thinkingText
                if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                    currentMsgs[botIndex].text = finalContent
                    if thinkingMode == .disabled {
                        currentMsgs[botIndex].thinkingContent = nil
                    } else {
                        currentMsgs[botIndex].thinkingContent = finalThinking.isEmpty ? nil : finalThinking
                    }
                    streamingText = ""
                    streamingThinkingText = ""
                    updateCurrentSessionMessagesInMemory(currentMsgs)
                }
                saveSessions()
                if enableHapticFeedback { WKInterfaceDevice.current().play(.success) } // v1.12: 成功震动
                
                // v1.8: 重新生成后也提取记忆
                if self.memoryEnabled {
                    Task { [weak self] in
                        await self?.extractMemories()
                    }
                }
                
            } catch {
                streamingText = ""
                streamingThinkingText = ""
                
                if Task.isCancelled {
                    if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                        let finalContent = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                        currentMsgs[botIndex].text = finalContent.isEmpty ? "" : finalContent + "\n[已停止]"
                        if thinkingMode != .disabled && !thinkingText.isEmpty {
                            currentMsgs[botIndex].thinkingContent = thinkingText
                        }
                        updateCurrentSessionMessagesInMemory(currentMsgs)
                    }
                    saveSessions()
                    if enableHapticFeedback { WKInterfaceDevice.current().play(.directionDown) }
                } else if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                    let finalContent = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if finalContent.isEmpty { currentMsgs[botIndex].text = "❌ \(error.localizedDescription)" }
                    else { currentMsgs[botIndex].text = finalContent + "\n[中断]" }
                    if thinkingMode != .disabled && !thinkingText.isEmpty {
                        currentMsgs[botIndex].thinkingContent = thinkingText
                    }
                    updateCurrentSessionMessagesInMemory(currentMsgs)
                    saveSessions()
                    if enableHapticFeedback { WKInterfaceDevice.current().play(.failure) }
                }
            }
            isLoading = false
            currentTask = nil
        }
    }
    
    func loadImage() {
        Task {
            if let data = try? await selectedImageItem?.loadTransferable(type: Data.self) {
                // 使用 ImageIO 直接从 Data 下采样，避免解码全图导致 Watch 内存溢出 (OOM)
                // 提升分辨率至 1200px 以确保试卷/文档清晰可读
                if let downsampled = data.downsampled(to: 1200) {
                     // 0.6 质量通常在体积和清晰度之间有很好的平衡
                     self.selectedImageData = downsampled.jpegData(compressionQuality: 0.6)
                } else {
                     self.selectedImageData = data
                }
            }
        }
    }
    
    // MARK: - 消息编辑逻辑
    @Published var editingMessageID: UUID?
    @Published var editingText: String = ""
    
    // MARK: - 模型能力检查 (v1.7)
    
    enum ThinkingSupportStatus {
        case supported      // 原生支持 (e.g. DeepSeek-R1)
        case unsupported    // 原生不支持 (e.g. GPT-3.5)
        case unknown        // 未知 / 无法判断
    }
    
    /// 获取当前模型的思考能力状态
    /// 优先级：模型专属设置 > 全局思考模式 > 自动判断
    func checkThinkingSupport(modelId: String = "") -> ThinkingSupportStatus {
        let targetId = modelId.isEmpty ? resolveCurrentModelID() : modelId
        let lower = targetId.lowercased()
        
        // 1. 检查模型专属设置
        if let settings = modelSettings[targetId] {
            switch settings.thinking {
            case .enabled: return .supported
            case .disabled: return .unsupported
            case .auto: break // 继续检查
            }
        }
        
        // 2. 检查全局模式
        // 注意：全局模式控制的是“是否显示”，这里返回的是“是否支持”
        // 如果全局强制开启，则视为支持；强制关闭不影响支持状态判断，但会影响显示逻辑
        if thinkingMode == .enabled { return .supported }
        
        // 3. 查表逻辑 (ModelRegistry)
        if let info = ModelRegistry.shared.getCapability(modelId: targetId) {
            if info.supportsThinking { return .supported }
        }
        
        // 4. 兜底/旧逻辑
        if lower.contains("deepseek-r1") || 
           lower.contains("deepseek-reasoner") {
            return .supported
        }
        
        // v1.12: 精确匹配不支持思考的模型（避免误判 o1/o3/claude-3.5-sonnet 等）
        if lower.contains("gpt-3") ||
           (lower.contains("gpt-4") && !lower.contains("4o")) || // gpt-4-turbo 不支持，gpt-4o 交给 ModelRegistry
           lower.contains("gemini") ||
           lower.contains("deepseek-chat") || // V3 非 R1
           lower.contains("deepseek-v3") {
            return .unsupported
        }
        
        return .unknown
    }
    
    /// 获取当前模型的视觉能力状态
    /// 优先级：模型专属设置 > 自动判断
    func checkVisionSupport(modelId: String = "") -> ThinkingSupportStatus {
        let targetId = modelId.isEmpty ? resolveCurrentModelID() : modelId
        let lower = targetId.lowercased()
        
        // 1. 检查模型专属设置
        if let settings = modelSettings[targetId] {
            switch settings.vision {
            case .enabled: return .supported
            case .disabled: return .unsupported
            case .auto: break 
            }
        }
        
        // 2. 查表逻辑 (ModelRegistry)
        if let info = ModelRegistry.shared.getCapability(modelId: targetId) {
            if info.supportsVision { return .supported }
        }
        
        // 3. 兜底逻辑
        if lower.contains("vision") || 
           lower.contains("gpt-4o") || 
           lower.contains("gemini-1.5") || 
           lower.contains("claude-3") ||
           lower.contains("vl") { // Qwen-VL, DeepSeek-VL
            return .supported
        }
        
        if lower.contains("gpt-3") || 
           lower.contains("deepseek-r1") { // R1 目前主要是文本
            return .unsupported
        }
        
        return .unknown
    }
    
    /// 解析当前选中的模型 ID (去除 Provider 前缀)
    func resolveCurrentModelID() -> String {
        let components = selectedGlobalModelID.split(separator: "|")
        if components.count >= 2 {
            return String(components[1])
        }
        return selectedGlobalModelID
    }
    
    // 保存模型设置
    func saveModelSettings() {
        if let data = try? JSONEncoder().encode(modelSettings) {
            modelSettingsData = data
        }
    }
    
    // 加载模型设置 (在 init 中调用)
    func loadModelSettings() {
        if let decoded = try? JSONDecoder().decode([String: ModelSettings].self, from: modelSettingsData) {
            modelSettings = decoded
        }
    }
    
    // 更新特定模型的能力设置
    func updateModelSettings(modelId: String, thinking: CapabilityState? = nil, vision: CapabilityState? = nil) {
        var settings = modelSettings[modelId] ?? ModelSettings()
        if let t = thinking { settings.thinking = t }
        if let v = vision { settings.vision = v }
        modelSettings[modelId] = settings
    }
    
    func startEditing(message: ChatMessage) {
        stopGeneration() // 假如正在生成，先停止
        editingMessageID = message.id
        editingText = message.text
    }
    
    func cancelEditing() {
        editingMessageID = nil
        editingText = ""
    }
    
    func submitEdit() {
        guard let editingID = editingMessageID, !editingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        var msgs = currentMessages
        guard let index = msgs.firstIndex(where: { $0.id == editingID }) else { return }
        
        // 1. 更新该条消息文本
        msgs[index].text = editingText
        
        // 2. 移除该条消息之后的所有消息（清除旧的上下文和回复）
        if index < msgs.count - 1 {
            msgs.removeSubrange((index + 1)...)
        }
        
        // 3. 准备重新生成
        updateCurrentSessionMessages(msgs)
        cancelEditing() // 退出编辑模式
        
        // 4. 触发生成逻辑
        let components = selectedGlobalModelID.split(separator: "|")
        guard components.count == 2,
              let providerID = UUID(uuidString: String(components[0])),
              let modelID = String(components[1]) as String?,
              let provider = providers.first(where: { $0.id == providerID }),
              !provider.apiKey.isEmpty else { return }
        
        isLoading = true
        // v1.8: 记录重新生成的时间
        let sendTime = Date()
        var assistantMsg = ChatMessage(role: .assistant, text: "")
        assistantMsg.sendTime = sendTime
        msgs.append(assistantMsg)
        
        updateCurrentSessionMessages(msgs)
        let botIndex = msgs.count - 1
        
        currentTask = Task {
            let history = await buildHistoryWithContext(from: msgs)
            var responseText = ""
            var thinkingText = ""
            var firstTokenReceived = false
            var localFirstTokenTime: Date? = nil // v1.8: 本地暂存首 Token 时间
            
            // v1.8.1: 流式解析状态机 (优化性能)
            var isThinking = false
            var pendingBuffer = ""
            
            // v1.12: 统一节流间隔 150ms（与 sendMessage 一致）
            var lastUIUpdateTime = Date()
            let uiUpdateInterval: TimeInterval = 0.15
            var pendingUpdate = false
            
            do {
                let stream = service.streamChat(messages: history, modelId: modelID, config: provider, temperature: temperature)
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    
                    // v1.8: 记录首 Token 时间
                    if !firstTokenReceived {
                        firstTokenReceived = true
                        localFirstTokenTime = Date()
                        if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                            currentMsgs[botIndex].firstTokenTime = localFirstTokenTime
                            updateCurrentSessionMessagesInMemory(currentMsgs)
                        }
                    }
                    
                    // 2. 追加到缓冲
                    pendingBuffer += chunk
                    
                    // 3. 状态机解析
                    let startTag = "<think>"
                    let endTag = "</think>"
                    
                    while true {
                        // 动态计算当前是否在 Markdown 代码块中 (计算 ``` 的对数)
                        let totalFences = (responseText + pendingBuffer).components(separatedBy: "```").count - 1
                        let isInCodeBlock = totalFences % 2 != 0
                        // 只有处于外部正文且在代码块内时，才免疫 `<think>` 标签拦截（保护演示代码的效果）。如果是寻找 </think> 则无视代码块。
                        let ignoreTag = !isThinking && isInCodeBlock
                        
                        let currentTag = isThinking ? endTag : startTag
                        
                        if !ignoreTag, let range = pendingBuffer.range(of: currentTag, options: .caseInsensitive) {
                            // 找到完整标签
                            let textBefore = String(pendingBuffer[..<range.lowerBound])
                            if isThinking {
                                thinkingText += textBefore
                                isThinking = false
                                // 移除原先的 thinkingBlockClosed 封印：允许多次 <think> 出现合并折叠
                            } else {
                                responseText += textBefore
                                isThinking = true
                            }
                            
                            pendingBuffer = String(pendingBuffer[range.upperBound...])
                        } else {
                            // 没找到完整标签，检查缓冲末尾是否有当前标签的前缀
                            var safeLength = pendingBuffer.count
                            
                            if !ignoreTag {
                                // 暴力检查末尾是否有当前标签的前缀（例如 "<", "<t", "<th", etc.）
                                let maxPrefixLen = currentTag.count - 1
                                if maxPrefixLen > 0 {
                                    for i in (1...maxPrefixLen).reversed() { // 从长到短检查
                                        if pendingBuffer.count >= i {
                                            let suffix = String(pendingBuffer.suffix(i))
                                            if currentTag.lowercased().hasPrefix(suffix.lowercased()) {
                                                // 找到了前缀，保留在 buffer 里
                                                safeLength = pendingBuffer.count - i
                                                break
                                            }
                                        }
                                    }
                                }
                            }
                            
                            if safeLength > 0 {
                                let safeContent = String(pendingBuffer.prefix(safeLength))
                                if isThinking { thinkingText += safeContent }
                                else { responseText += safeContent }
                                pendingBuffer = String(pendingBuffer.suffix(from: pendingBuffer.index(pendingBuffer.startIndex, offsetBy: safeLength)))
                            }
                            break // 退出循环，等待下一个 chunk
                        }
                    }
                    
                    // 4. 节流 UI 更新（流式输出时禁用动画，减少Watch卡顿）
                    let now = Date()
                    if now.timeIntervalSince(lastUIUpdateTime) >= uiUpdateInterval {
                        let finalThinking = thinkingText
                        var finalContent = responseText
                        finalContent = finalContent.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        // v1.8.4: 流式输出时禁用动画，只做数据更新
                        if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                            currentMsgs[botIndex].text = finalContent
                            if thinkingMode == .disabled {
                                currentMsgs[botIndex].thinkingContent = nil
                            } else {
                                currentMsgs[botIndex].thinkingContent = finalThinking.isEmpty ? nil : finalThinking
                            }
                            updateCurrentSessionMessagesInMemory(currentMsgs)
                        }
                        lastUIUpdateTime = now
                        pendingUpdate = false
                    } else {
                        pendingUpdate = true
                    }
                }
                
                // 结束处理剩余 Buffer
                if !pendingBuffer.isEmpty {
                    if isThinking { thinkingText += pendingBuffer }
                    else { responseText += pendingBuffer }
                }
                
                // v1.12: 完成记录
                let finalThinking = thinkingText
                let finalContent = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                    currentMsgs[botIndex].text = finalContent
                    if thinkingMode == .disabled {
                        currentMsgs[botIndex].thinkingContent = nil
                    } else {
                        currentMsgs[botIndex].thinkingContent = finalThinking.isEmpty ? nil : finalThinking
                    }
                    currentMsgs[botIndex].completeTime = Date()
                    if let t = localFirstTokenTime { currentMsgs[botIndex].firstTokenTime = t }
                    updateCurrentSessionMessagesInMemory(currentMsgs)
                }
                
                saveSessions() // 最终保存
                if enableHapticFeedback { WKInterfaceDevice.current().play(.success) }
                
                // v1.8: 编辑重发后也提取记忆
                if self.memoryEnabled {
                    Task { [weak self] in
                        await self?.extractMemories()
                    }
                }
                
            } catch {
                if Task.isCancelled {
                    if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                        if !currentMsgs[botIndex].text.isEmpty {
                            currentMsgs[botIndex].text += "\n[已停止]"
                        }
                        if let t = localFirstTokenTime { currentMsgs[botIndex].firstTokenTime = t }
                        updateCurrentSessionMessagesInMemory(currentMsgs)
                    }
                    saveSessions()
                    if enableHapticFeedback { WKInterfaceDevice.current().play(.directionDown) }
                } else if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                    if responseText.isEmpty { currentMsgs[botIndex].text = "❌ \(error.localizedDescription)" }
                    else { currentMsgs[botIndex].text += "\n[中断]" }
                    if let t = localFirstTokenTime { currentMsgs[botIndex].firstTokenTime = t }
                    updateCurrentSessionMessagesInMemory(currentMsgs)
                    saveSessions()
                    if enableHapticFeedback { WKInterfaceDevice.current().play(.failure) }
                }
            }
            isLoading = false
            currentTask = nil
        }
    }
}

extension Data {
    /// 使用 ImageIO 进行高效下采样，避免内存峰值
    func downsampled(to maxDimension: CGFloat) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(self as CFData, options) else { return nil }
        
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as CFDictionary
        
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
