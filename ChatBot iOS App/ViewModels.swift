import SwiftUI
import PhotosUI
import Combine
#if os(watchOS)
import WatchKit
import ClockKit
#endif
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
    
    // v2.0: 导航路径控制 (用于首页直达聊天)
    @Published var navigationPath = NavigationPath()
    @AppStorage("appThemeRaw") var appThemeRaw: String = AppTheme.classic.rawValue  // v1.6: 主题配色
    @AppStorage("preferredColorSchemeRaw") var preferredColorSchemeRaw: String = "dark"  // v2.1: 浅色/深色模式 ("system", "light", "dark")
    @AppStorage("userName") var userName: String = ""  // v2.1: 用户自定义名称
    @AppStorage("userAvatarData") var userAvatarData: Data = Data() // v2.2: 自定义用户头像（空 Data 表示未设置，与 Watch 端对称）
    @AppStorage("memoryEnabled") var memoryEnabled: Bool = true  // v1.7: 记忆功能开关
    @AppStorage("embeddingProviderID") var embeddingProviderID: String = ""  // v1.7: Embedding 供应商 ID
    @AppStorage("embeddingModelID") var embeddingModelID: String = ""  // v1.7: Embedding 模型 ID
    @AppStorage("helperGlobalModelID") var helperGlobalModelID: String = "" // v1.7: 辅助模型 ID
    @AppStorage("detectedEmbeddingDim") var detectedEmbeddingDim: Int = 0  // v1.8: 探测到的向量维度
    @AppStorage("sendTimeToAI") var sendTimeToAI: Bool = true  // 向 AI 传递当前时间
    @AppStorage("sendLocationToAI") var sendLocationToAI: Bool = true  // 向 AI 传递当前位置
    @AppStorage("workersAIEmbeddingURL") var workersAIEmbeddingURL: String = ""  // v1.8: Workers AI 向量端点
    @AppStorage("cloudBackupURL") var cloudBackupURL: String = ""  // v1.10: 云备份端点
    @AppStorage("cloudBackupAuthKey") var cloudBackupAuthKey: String = ""  // v1.10: 云备份认证
    @AppStorage("memoryDeleteConfirm") var memoryDeleteConfirm: Bool = true  // v2.5: 删除记忆需确认
    @AppStorage("memoryMaxRetrievalCount") var memoryMaxRetrievalCount: Int = 5  // v2.5: 最大检索记忆数
    @AppStorage("memoryRetrievalThreshold") var memoryRetrievalThreshold: Double = 0.1  // v2.5: 相似度阈值
    @Published var memories: [MemoryItem] = []  // v1.7: 记忆列表
    @Published var deletedMemoriesBin: [MemoryItem] = []  // v2.5: 记忆回收站
    @Published var pendingMemoryDeletions: [(content: String, index: Int)] = []  // v2.5: 待确认删除
    @Published var migrationProgress: String? = nil  // v1.8: 迁移进度提示
    @Published var cloudUploadStatus: String? = nil  // v1.10: 云上传状态
    @AppStorage("lastCloudSyncTime") var lastCloudSyncTime: Double = 0  // v1.12: 最后同步时间戳
    @AppStorage("autoBackupEnabled") var autoBackupEnabled: Bool = false  // v1.12: 自动备份开关
    @Published var cachedVersions: [BackupVersion]? = nil  // v1.12: 本地缓存的版本列表
    
    @AppStorage("autoRetryEnabled") var autoRetryEnabled: Bool = false
    @AppStorage("maxRetries") var maxRetries: Int = 3
    // v2.6: 全局最近使用模型历史（按时间倒序排列，最多保留 3 条）
    // 格式: JSON 数组 [{"providerID": "...", "modelID": "..."}]
    @AppStorage("recentModelHistory_v1") var recentModelHistoryData: String = "[]"
    
    // v2.3: 联网搜索 (Web Search Proxy)
    @AppStorage("webSearchEnabled") var webSearchEnabled: Bool = false
    @AppStorage("webSearchWorkerURL") var webSearchWorkerURL: String = ""
    @AppStorage("webSearchAuthKey") var webSearchAuthKey: String = ""  // v2.5: 搜索鉴权密钥
    @Published var isSearchContextEnabled: Bool = false // 本次对话是否启用搜索
    
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
    @Published var streamingText: String = ""          // v1.6: 流式输出专用（避免全量重渲染）
    @Published var streamingThinkingText: String = ""   // v1.6: 流式思考内容
    @Published var streamingBlocks: [String] = []       // 防 OOM 分块优化
    @Published var streamingThinkingBlocks: [String] = []
    @Published var isInputVisible: Bool = true  // 输入框是否可见（用于显示回到底部按钮）
    @Published var selectedImageItem: PhotosPickerItem? = nil
    @Published var selectedImageData: Data? = nil
    
    // v2.4: 记忆活动跟踪
    struct MemoryActivity {
        var retrievedMemories: [String] = []  // 本轮调用的记忆内容
        var addedMemories: [String] = []      // 本轮新增的记忆
        var deletedMemories: [String] = []    // 本轮删除的记忆
    }
    @Published var lastMemoryActivity: MemoryActivity? = nil
    
    // v2.1: UI Redesign State
    @Published var isSidebarVisible: Bool = false
    @Published var searchText: String = ""
    @Published var isIncognitoMode: Bool = false
    
    @Published var isDataLoading: Bool = true // 防止大数据解析阻塞主线程，控制 UI Loading 状态
    
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
        streamingBlocks = []
        streamingThinkingBlocks = []
    }
    private var observers: [Any] = []
    
    init() {
        // v2.1 性能优化：剥离体积庞大的解码逻辑到后台线程，避免占用主线程导致启动卡顿
        
        // 启动定位以备用 (可以在主线程立刻启动)
        LocationService.shared.requestPermission()
        LocationService.shared.updateLocation()
        
        // 监听云端数据变更
        observers.append(NotificationCenter.default.addObserver(forName: .init("CloudDataDidUpdate"), object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in self.loadFromCloud() }
        })
        
        // 监听 Watch WatchConnectivity 配置推送
        observers.append(NotificationCenter.default.addObserver(forName: WatchSessionManager.configDidUpdateNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in self.reloadFromWatchConnectivity() }
        })
        
        // 监听 Watch WatchConnectivity 大文件传输（聊天记录+记忆）完成
        observers.append(NotificationCenter.default.addObserver(forName: .init("WatchConnectivityDidReceiveFullData"), object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in self.reloadFromWatchConnectivity() }
        })
        
        Task { [weak self] in
            await self?.loadAllDataOffMainThread()
        }
    }
    
    // 后台加载大型本地数据
    private func loadAllDataOffMainThread() async {
        // v2.6: Incognito 模式不需要读磁盘 I/O，直接标记加载完成
        if isIncognitoMode {
            self.isDataLoading = false
            return
        }
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
            trash: [MemoryItem],
            currentStoredSessionId: String?
        ) in
            // 1. 在完全独立的后台线程中执行 I/O 读取 (避免主线程 plist 解析卡顿)
            let defaults = UserDefaults.standard
            let providersData = defaults.data(forKey: "savedProviders_v3")
            let sessionsData = defaults.data(forKey: "chatSessions_v1")
            let settingsData = defaults.data(forKey: "modelSettings")
            let memoriesData = defaults.data(forKey: "userMemories_v1")
            let trashData = defaults.data(forKey: "deletedMemoriesBin_v1")
            
            // 由于 NavigationPath 不能在其他线程直接赋值传递，我们在后台取 String ID，前台组装
            let currentSIdStr = defaults.string(forKey: "currentSessionId_v1")
            
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
            
            return (pFinal, sFinal, stFinal, mFinal, tFinal, currentSIdStr)
        }.value
        
        // 2. 将后台解析好的大型对象写回主线程 @Published
        self.providers = result.providers
        self.saveProviders()
        
        self.sessions = result.sessions
        if self.sessions.isEmpty { self.createNewSession() }
        else if self.currentSessionId == nil {
            if let stringId = result.currentStoredSessionId, let parsedId = UUID(uuidString: stringId) {
                self.currentSessionId = parsedId
            } else {
                self.currentSessionId = self.sessions.first?.id
            }
        }
        
        // v2.0: 启动时直接进入最后一次会话
        if let id = self.currentSessionId {
            self.navigationPath = NavigationPath([id])
        }
        
        self.modelSettings = result.settings
        self.memories = result.memories
        self.deletedMemoriesBin = result.trash
        
        // 数据准备就绪，关闭遮罩
        self.isDataLoading = false
        
        // 3. 自动验证（后台静默进行）
        Task { [weak self] in
            guard let self = self else { return }
            for i in 0..<self.providers.count {
                if !self.providers[i].apiKeys.isEmpty && !self.providers[i].isValidated {
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
    
    // 从云端/本地重新加载配置
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
        let trashData = defaults.data(forKey: "deletedMemoriesBin_v1")
        
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
            if let t = result.trash { self?.deletedMemoriesBin = t }
            
            self?.objectWillChange.send()
            print("⌚ [ViewModel] 已从 Watch 同步刷新全部数据")
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
    // v2.1: 重命名会话
    func renameSession(id: UUID, newTitle: String) {
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].title = newTitle
            saveSessions()
        }
    }

    func deleteSession(at offsets: IndexSet) {
        let idsToDelete = offsets.map { sessions[$0].id }
        sessions.remove(atOffsets: offsets)
        if let current = currentSessionId, idsToDelete.contains(current) {
            if let first = sessions.first { currentSessionId = first.id } else { createNewSession() }
        }
        saveSessions()
    }
    func saveSessions() {
        // v2.1: Incognito Mode - Do not save to disk
        if isIncognitoMode { return }
        
        // BUG-2 fix: persist currentSessionId so it survives App restarts
        if let id = currentSessionId {
            UserDefaults.standard.set(id.uuidString, forKey: "currentSessionId_v1")
        }
        
        let sessionsCopy = self.sessions
        Task.detached(priority: .background) {
            if let encoded = try? JSONEncoder().encode(sessionsCopy) {
                UserDefaults.standard.set(encoded, forKey: "chatSessions_v1")
                
                // 写入轻量级数据供 Widget 使用，防止 OOM
                if let first = sessionsCopy.first {
                    var msg = "No messages"
                    if let lastM = first.messages.last(where: { $0.role != .system }) {
                        msg = lastM.text
                    }
                    let widgetData: [String: String] = ["title": first.title, "lastMessage": msg]
                    UserDefaults.standard.set(widgetData, forKey: "widget_tiny_data")
                } else {
                     UserDefaults.standard.set(["title": "OpenChat", "lastMessage": "No conversations"], forKey: "widget_tiny_data")
                }
            // 确保 WidgetKit 刷新数据 (如果没有 App Group，这步其实无法跨进程刷新，这里主要为了逻辑完整性)
             #if canImport(WidgetKit)
             // WidgetCenter.shared.reloadAllTimelines() // 主 App 无法直接调用 WidgetCenter 刷新，除非配置了正确的目标
             #endif

                // 刷新表盘组件
                #if os(watchOS)
                DispatchQueue.main.async {
                    let server = CLKComplicationServer.sharedInstance()
                    for complication in server.activeComplications ?? [] {
                        server.reloadTimeline(for: complication)
                    }
                }
                #endif
            }
        }
    }
    
    var filteredSessions: [ChatSession] {
        let sorted = sessions.sorted { $0.lastModified > $1.lastModified }
        if searchText.isEmpty { return sorted }
        return sorted.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
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
        
        // 移除了高频的 sessions.sort()
        // 在流式输出期间，频繁对包含大量数据的 sessions 进行排序会引发极高内存分配 (OOM)
        // 会话排序在启动时和保存时处理即可由于当前会话必定是最新的，不需要每秒排 6 次。
    }
    
    // MARK: - 供应商与模型逻辑
    func saveProviders() {
        let providersCopy = self.providers
        Task.detached(priority: .background) {
            if let encoded = try? JSONEncoder().encode(providersCopy) {
                UserDefaults.standard.set(encoded, forKey: "savedProviders_v3")
                // 写入完成后跳回主线程推送 Watch（WatchSessionManager 非线程安全）
                await MainActor.run {
                    if !WatchSessionManager.shared.isSyncingFromRemote {
                        WatchSessionManager.shared.pushConfigToWatch()
                    }
                }
            }
        }
    }
    
    func updateProvider(_ updated: ProviderConfig) {
        if let index = providers.firstIndex(where: { $0.id == updated.id }) {
            providers[index] = updated
            saveProviders()
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
    
    // v2.6: 获取最近使用的模型（最多 3 条，按真实使用时间倒序）
    var recentlyUsedModels: [(id: String, displayName: String, providerName: String)] {
        guard let data = recentModelHistoryData.data(using: .utf8),
              let arr = try? JSONDecoder().decode([[String: String]].self, from: data) else { return [] }
        var result: [(String, String, String)] = []
        for entry in arr {
            guard let providerIDStr = entry["providerID"],
                  let modelID = entry["modelID"],
                  let providerUUID = UUID(uuidString: providerIDStr),
                  let provider = providers.first(where: { $0.id == providerUUID }),
                  let model = provider.availableModels.first(where: { $0.id == modelID }) else { continue }
            let compositeID = "\(providerIDStr)|\(modelID)"
            result.append((compositeID, model.displayName ?? model.id, provider.name))
        }
        return result
    }
    
    // v2.6: 记录一次模型使用，插入到历史头部，去重，截断为 3 条
    func recordRecentModel(providerID: UUID, modelID: String) {
        var arr: [[String: String]] = []
        if let data = recentModelHistoryData.data(using: .utf8) {
            arr = (try? JSONDecoder().decode([[String: String]].self, from: data)) ?? []
        }
        // 移除同一条旧记录
        arr.removeAll { $0["providerID"] == providerID.uuidString && $0["modelID"] == modelID }
        // 插到头部
        arr.insert(["providerID": providerID.uuidString, "modelID": modelID], at: 0)
        // 截断为最多 3 条
        if arr.count > 3 { arr = Array(arr.prefix(3)) }
        if let encoded = try? JSONEncoder().encode(arr), let str = String(data: encoded, encoding: .utf8) {
            recentModelHistoryData = str
        }
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
        
        // v2.6: 先尝试获取现有云端配置，以保留手表专用字段
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
        
        // 注入差异化字段
        exportData.iphoneRecentModelHistory = recentModelHistoryData
        if let existing = existingConfig {
            exportData.watchSelectedGlobalModelID = existing.watchSelectedGlobalModelID
            exportData.watchHelperGlobalModelID = existing.watchHelperGlobalModelID
            exportData.watchRecentModelHistory = existing.watchRecentModelHistory
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
            
            let (_, response) = try await URLSession.shared.data(for: request)
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
        // BUG-12 fix: 防止并发上传（检查是否已在进行中）
        guard cloudUploadStatus != "⬆️ 正在上传..." else { return }
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
            // v2.6: 应用手机专属模型历史
            if let iphoneHistory = config.iphoneRecentModelHistory {
                self.recentModelHistoryData = iphoneHistory
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
        // v2.6: 应用手机专属模型历史
        if let iphoneHistory = config.iphoneRecentModelHistory {
            self.recentModelHistoryData = iphoneHistory
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
        
        // v1.12: 验证 selectedGlobalModelID 引用的供应商是否存在
        let importedID = config.selectedGlobalModelID
        let idComponents = importedID.split(separator: "|")
        if idComponents.count == 2,
           let providerUUID = UUID(uuidString: String(idComponents[0])),
           providers.contains(where: { $0.id == providerUUID }) {
            self.selectedGlobalModelID = importedID
        }
        
        // v2.6: 恢复手机专用历史
        if let iphoneHistory = config.iphoneRecentModelHistory {
            self.recentModelHistoryData = iphoneHistory
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
        
        if let helperID = config.helperGlobalModelID {
            self.helperGlobalModelID = helperID
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
        // v2.4: Capture query BEFORE clearing inputText (was a bug: search query was always empty)
        let localQuery = inputText
        let localSearchEnabled = isSearchContextEnabled && webSearchEnabled
        
        var userMsg = ChatMessage(role: .user, text: inputText, imageData: selectedImageData)
        userMsg.sendTime = sendTime
        msgs.append(userMsg)
        updateCurrentSessionMessages(msgs)
        
        inputText = ""; selectedImageItem = nil; selectedImageData = nil; isLoading = true
        if enableHapticFeedback {
            #if os(watchOS)
            WKInterfaceDevice.current().play(.click)
            #else
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } // 开始生成震动

        // v1.6: 初始化流式输出状态
        streamingText = ""
        streamingThinkingText = ""
        streamingBlocks = []            // v2.5: 修复重复显示上一次回复
        streamingThinkingBlocks = []    // v2.5: 同上
        lastMemoryActivity = nil // v2.4: 重置记忆活动
        // v1.5: AI 消息也记录发送时间
        var assistantMsg = ChatMessage(role: .assistant, text: "")
        assistantMsg.sendTime = sendTime
        msgs.append(assistantMsg)
        updateCurrentSessionMessages(msgs)
        let botIndex = msgs.count - 1
        
        currentTask = Task {
            var searchContext: String? = nil
            if localSearchEnabled, !webSearchWorkerURL.isEmpty {
                await MainActor.run { self.streamingText = "🧠 提取搜索关键词..." }
                let extractQuery = await self.extractSearchQuery(from: localQuery, context: msgs)
                if extractQuery.contains("[不需要搜索]") {
                    print("🧠 意图判定：无搜索必要，跳过联网检索。")
                    await MainActor.run { self.streamingText = "" }
                } else {
                    await MainActor.run { self.streamingText = "🔍 正在检索网络: \(extractQuery)..." }
                    print("🔍 搜索开始: original=\(localQuery), extracted=\(extractQuery), url=\(webSearchWorkerURL), hasAuth=\(!webSearchAuthKey.isEmpty)")
                    do {
                        let results = try await service.fetchWebSearchResults(query: extractQuery, workerURL: webSearchWorkerURL, authKey: webSearchAuthKey)
                        searchContext = results
                        print("✅ 搜索完成: \(results.prefix(100))...")
                        await MainActor.run { self.streamingText = "" }
                    } catch {
                        print("⚠️ Web Search Failed: \(error)")
                        await MainActor.run { self.streamingText = "" }
                    }
                }
            } else if localSearchEnabled {
                print("⚠️ 搜索已启用但 URL 为空")
            }
            
            let history = await buildHistoryWithContext(from: msgs, searchContext: searchContext)
            await streamChatResponse(
                history: history,
                modelID: modelID,
                provider: provider,
                botIndex: botIndex
            )
            
            // v2.6 Toggle persists until turned off manually
        }
    }
    
    /// 构建带系统上下文的历史消息列表（注入记忆、时间、位置、搜索等）
    private func buildHistoryWithContext(from msgs: [ChatMessage], searchContext: String? = nil) async -> [ChatMessage] {
        var history = msgs.dropLast(1).suffix(max(historyMessageCount, 1)).map { $0 }
        
        // v2.9: 辅助模型自动压缩超长上下文
        let totalChars = history.reduce(0) { $0 + $1.text.count }
        if totalChars > 8000 && !helperGlobalModelID.isEmpty && history.count > 3 {
            let messagesToCompress = Array(history.prefix(history.count - 2))
            let keptMessages = Array(history.suffix(2))
            
            let conversationText = messagesToCompress.map { "\($0.role == .user ? "User" : "AI"): \($0.text)" }.joined(separator: "\n")
            let summaryPrompt = """
            请将以下历史对话压缩为高密度的核心上下文摘要，保留关键事实、核心逻辑和未解决的语境，剔除日常寒暄和所有无意义的中间推理过程：
            
            \(conversationText)
            """
            
            let summaryMsg = ChatMessage(role: .user, text: summaryPrompt)
            print("🗜️ 触发上下文压缩 (原始文本长度: \(totalChars))...")
            
            var compressedText = ""
            let components = helperGlobalModelID.split(separator: "|")
            if components.count == 2,
               let providerID = UUID(uuidString: String(components[0])),
               let provider = providers.first(where: { $0.id == providerID }) {
                let modelID = String(components[1])
                do {
                    let stream = service.streamChat(messages: [summaryMsg], modelId: modelID, config: provider, temperature: 0.1)
                    for try await chunk in stream {
                        compressedText += chunk
                    }
                    if !compressedText.isEmpty {
                        print("✅ 上下文压缩完成 (摘要长度: \(compressedText.count))")
                        var newHistory = [ChatMessage(role: .system, text: "【以往对话摘要】\n" + compressedText)]
                        newHistory.append(contentsOf: keptMessages)
                        history = newHistory
                    }
                } catch {
                    print("❌ 上下文压缩失败: \(error)")
                }
            }
        }
        
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
                // 向量检索 Top-K（综合相似度 + 重要性）
                if let queryEmb = try? await service.fetchEmbedding(text: userQuery, modelId: embModel, config: embConfig) {
                    var scored: [(MemoryItem, Float)] = memories.compactMap { m in
                        let similarity = m.embedding.map { cosineSimilarity(queryEmb, $0) } ?? 0.3
                        // v2.5: 相似度阈值过滤
                        guard similarity >= Float(self.memoryRetrievalThreshold) else { return nil }
                        let finalScore = similarity * 0.7 + m.importance * 0.3
                        return (m, finalScore)
                    }
                    scored.sort { $0.1 > $1.1 }
                    relevantMemories = scored.prefix(memoryMaxRetrievalCount).map { $0.0 }
                } else {
                    relevantMemories = Array(memories.sorted { $0.importance > $1.importance }.prefix(memoryMaxRetrievalCount))
                }
            } else {
                // 无 Embedding，按重要性排序注入
                relevantMemories = Array(memories.sorted { $0.importance > $1.importance }.prefix(memoryMaxRetrievalCount))
            }
            
            if !relevantMemories.isEmpty {
                let memoryLines = relevantMemories.map { "- \($0.content)" }.joined(separator: "\n")
                systemParts.append("你知道以下关于用户的信息（长期记忆）：\n\(memoryLines)")
                
                // v2.4: 记录本轮调用的记忆
                await MainActor.run {
                    var activity = self.lastMemoryActivity ?? MemoryActivity()
                    activity.retrievedMemories = relevantMemories.map { $0.content }
                    self.lastMemoryActivity = activity
                }
            }
        }
        
        // 4. (已移除强制思考格式，避免弄巧成拙)
        
        // 5. 时间和位置信息（可由用户关闭）
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
        
        // 6. Web Search Context
        if let sc = searchContext {
            systemParts.append(sc)
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
    
    func saveMemories() {
        let memoriesCopy = self.memories
        Task.detached(priority: .background) {
            if let encoded = try? JSONEncoder().encode(memoriesCopy) {
                UserDefaults.standard.set(encoded, forKey: "userMemories_v1")
                // 备份重心已转移至 R2，不再同步到 iCloud KVS（1MB 限制易溢出）
            }
        }
    }
    
    func loadMemories() {
        // 从本地 UserDefaults 加载（备份/恢复走 R2）
        if let data = UserDefaults.standard.data(forKey: "userMemories_v1"),
           let decoded = try? JSONDecoder().decode([MemoryItem].self, from: data) {
            memories = decoded
        }
        // v2.5: 加载回收站
        if let data = UserDefaults.standard.data(forKey: "deletedMemoriesBin_v1"),
           let decoded = try? JSONDecoder().decode([MemoryItem].self, from: data) {
            deletedMemoriesBin = decoded
        }
    }
    
    // v2.5: 回收站持久化
    func saveDeletedBin() {
        if let encoded = try? JSONEncoder().encode(deletedMemoriesBin) {
            UserDefaults.standard.set(encoded, forKey: "deletedMemoriesBin_v1")
        }
    }
    
    // v2.5: 软删除（移到回收站）
    func softDeleteMemory(at index: Int) {
        guard index < memories.count else { return }
        var item = memories.remove(at: index)
        item.deletedAt = Date() // 打上删除时间戳
        deletedMemoriesBin.insert(item, at: 0) // 放回最前面
        saveMemories()
        saveDeletedBin()
        WatchSessionManager.shared.pushFullDataToWatch() // 同步到手表
    }
    
    // v2.5: 从回收站恢复
    func restoreMemory(at index: Int) {
        guard index < deletedMemoriesBin.count else { return }
        var item = deletedMemoriesBin.remove(at: index)
        item.deletedAt = nil // 移除删除标记
        memories.insert(item, at: 0) // 恢复到最前面
        saveMemories()
        saveDeletedBin()
        WatchSessionManager.shared.pushFullDataToWatch() // 同步到手表
    }
    
    // v2.5: 永久删除（从回收站彻底删除）
    func permanentlyDeleteMemory(at index: Int) {
        guard index < deletedMemoriesBin.count else { return }
        deletedMemoriesBin.remove(at: index)
        saveDeletedBin()
        WatchSessionManager.shared.pushFullDataToWatch() // 同步到手表
    }
    
    // v2.5: 清空回收站
    func emptyRecycleBin() {
        deletedMemoriesBin.removeAll()
        saveDeletedBin()
        WatchSessionManager.shared.pushFullDataToWatch() // 同步到手表
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
                    // v2.8: 去重阈值——提高标准，防止微弱相关的记忆被错误合并
                    let dedupThreshold: Float = importance >= 0.9 ? 0.85 : 0.80
                    if sim > dedupThreshold {
                        let existingContent = memories[i].content
                        print("🔄 语义相似：\(trimmed) ≈ \(existingContent)（相似度 \(String(format: "%.2f", sim))）")
                        
                        // v2.5: 用辅助模型合并记忆（异步），先立即更新以防丢失
                        memories[i].lastUpdated = Date()
                        if memories[i].type == .shortTerm && type == .longTerm {
                            memories[i].type = .longTerm
                            memories[i].expiration = nil
                        }
                        if importance > memories[i].importance { memories[i].importance = importance }
                        
                        let mergeIdx = i
                        Task { [weak self] in
                            guard let self = self else { return }
                            if let merged = await self.mergeMemoriesWithLLM(existing: existingContent, new: trimmed) {
                                await MainActor.run {
                                    guard mergeIdx < self.memories.count,
                                          self.memories[mergeIdx].content == existingContent else {
                                        // 索引已变动，安全退出
                                        return
                                    }
                                    self.memories[mergeIdx].content = merged
                                    self.saveMemories()  // v2.5: 立即保存合并结果，不等 embedding
                                    print("✅ 记忆合并：\(existingContent) + \(trimmed) → \(merged)")
                                    // 重新生成合并后的向量（异步，不阻塞保存）
                                    Task {
                                        if let (embConfig, embModel) = self.getEmbeddingProvider(),
                                           let newEmb = try? await self.service.fetchEmbedding(text: merged, modelId: embModel, config: embConfig) {
                                            await MainActor.run {
                                                if mergeIdx < self.memories.count {
                                                    self.memories[mergeIdx].embedding = newEmb
                                                    self.saveMemories()
                                                }
                                            }
                                        }
                                    }
                                }
                            } else {
                                // LLM 合并失败，回退：直接用新内容覆盖
                                await MainActor.run {
                                    if mergeIdx < self.memories.count {
                                        self.memories[mergeIdx].content = trimmed
                                        self.memories[mergeIdx].embedding = newEmb
                                        self.saveMemories()
                                    }
                                }
                            }
                        }
                        saveMemories()
                        return
                    }
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
        
        // v1.8 智能淘汰：只清理过期临时记忆，长期记忆无上限
        // 1. 清理过期临时记忆
        memories.removeAll { $0.type == .shortTerm && $0.isExpired }
        
        // 2. 临时记忆超 500 条时，淘汰最旧的临时记忆
        let shortTermMems = memories.enumerated().filter { $0.element.type == .shortTerm && !$0.element.isExpired }
        if shortTermMems.count > 500 {
            if let oldestIdx = shortTermMems
                .min(by: { ($0.element.lastUpdated ?? $0.element.createdAt) < ($1.element.lastUpdated ?? $1.element.createdAt) })
                .map({ $0.offset }) {
                memories.remove(at: oldestIdx)
            }
        }
        saveMemories()
    }
    
    func deleteMemory(id: UUID) {
        // v2.5 fix: 软删除（移到回收站），与 Watch 端对称，保证 iOS 回收站有数据
        if let idx = memories.firstIndex(where: { $0.id == id }) {
            softDeleteMemory(at: idx)
        }
    }
    
    func deleteMemories(at offsets: IndexSet) {
        // 从大到小排序，避免先删小 index 后大 index 漂移
        let sortedOffsets = offsets.sorted(by: >)
        for idx in sortedOffsets {
            softDeleteMemory(at: idx)
        }
    }
    
    func clearAllMemories() {
        let now = Date()
        var items = memories
        for i in items.indices { items[i].deletedAt = now }
        deletedMemoriesBin.insert(contentsOf: items, at: 0)
        memories.removeAll()
        saveMemories()
        saveDeletedBin()
        WatchSessionManager.shared.pushFullDataToWatch()
    }
    
    // v2.5: 用辅助模型合并相似记忆
    func mergeMemoriesWithLLM(existing: String, new: String) async -> String? {
        let targetModelID = helperGlobalModelID.isEmpty ? selectedGlobalModelID : helperGlobalModelID
        let components = targetModelID.split(separator: "|")
        guard components.count == 2,
              let providerID = UUID(uuidString: String(components[0])),
              let provider = providers.first(where: { $0.id == providerID }),
              !provider.apiKey.isEmpty else { return nil }
        let modelID = String(components[1])
        
        let mergePrompt = """
        将以下两条关于同一用户的记忆合并为一条，保留所有不重复的信息。
        要求：第三人称，≤30字，不要编号，不要引号，直接输出合并后的内容。

        记忆1：\(existing)
        记忆2：\(new)
        """
        
        let msg = ChatMessage(role: .user, text: mergePrompt)
        let stream = service.streamChat(messages: [msg], modelId: modelID, config: provider, temperature: 0.2)
        
        var result = ""
        do {
            for try await chunk in stream { result += chunk }
        } catch {
            print("⚠️ 记忆合并失败: \(error.localizedDescription)")
            return nil
        }
        
        let merged = result.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
        guard !merged.isEmpty, merged.count <= 50 else { return nil }
        return merged
    }
    
    /// v1.8: 利用 LLM 从当前对话中提取记忆（双轨模式 + 反幻觉）
    func extractMemories() async {
        guard memoryEnabled else { return }
        
        let msgs = currentMessages
        guard msgs.count >= 2 else { return }
        
        // v2.5: 只传用户消息给提取模型，防止把 AI 说的内容当作用户事实（幻觉）
        let recentMsgs = msgs.suffix(min(6, msgs.count))
        let conversationText = recentMsgs.compactMap { msg -> String? in
            guard msg.role == .user else { return nil }
            return "用户: \(msg.text)"
        }.joined(separator: "\n")
        
        guard !conversationText.isEmpty else { return }
        
        // v1.8: 反幻觉 + 去重侧写 Prompt
        let extractionPrompt = """
        任务：你是一个用户侧写分析师，从对话中提取用户的真实信息，并识别需要删除的过时信息。

        ━━━ 绝对禁止 ━━━
        • 禁止提取 AI 说的任何内容（建议、举例、假设、反问）作为用户事实。
        • 禁止自行推测或补充信息。
        • 只有用户亲口说出或明确确认的内容才能提取。
        • 禁止把"用户要求记住X"作为单独一条——直接记X本身。
        • 相关联的信息必须合并为一条，绝不拆分。

        ━━━ 合并规则（极重要） ━━━
        同一个人/事/属性的不同侧面必须合并为一条：
        ❌ 错误（拆分）：1. 用户今年17岁  2. 用户2009年出生
        ✅ 正确（合并）：[长期] 用户2009年生，今年17岁

        ━━━ 删除规则（重要！） ━━━
        如果用户明确表示某个信息已过时或变化，必须用 [删除] 标记旧信息：
        例如：
        用户: 我已经不是学生了，我现在在工作
        ✅ [删除] 用户是学生
        ✅ [长期] 用户已工作

        用户: 我不喜欢Python了，我现在用Swift
        ✅ [删除] 用户喜欢Python
        ✅ [长期] 用户现在使用Swift

        ━━━ 输出格式 ━━━
        - [临时] 用户的短期计划或具体的待办事项（24h失效。严禁提取由于对话引起的短暂情感、心理活动、无实质内容的牢骚）
        - [长期] 身份、习惯、喜好、关系等永久事实
        - [!] 用户明确要求记住的信息（永久）
        - [删除] 需要删除的过时信息

        第三人称，每条≤20字，相关信息合并为一条。无新信息回复"无"。

        对话内容：
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
            temperature: 0.05  // 极低温度
        )
        
        var result = ""
        do {
            for try await chunk in stream {
                result += chunk
                // v2.5: 安全阀 — AI 输出超过 2000 字符直接截断，防止无限生成
                if result.count > 2000 {
                    print("⚠️ 记忆提取输出超过 2000 字符，截断")
                    break
                }
            }
        } catch {
            print("⚠️ 记忆提取失败: \(error.localizedDescription)")
            return
        }
        
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "无", !trimmed.hasPrefix("无") else { return }
        
        let embProvider = getEmbeddingProvider()
        
        // v2.5: 解析双轨前缀，安全限制最多处理 20 行
        let allLines = trimmed.components(separatedBy: "\n")
        let lines = Array(allLines.prefix(20))
        if allLines.count > 20 {
            print("⚠️ 记忆提取输出 \(allLines.count) 行，仅处理前 20 行")
        }
        var batchedDeletions: [(content: String, index: Int)] = []  // v2.5: 收集删除，循环结束后一次性提交
        // BUG-8 fix: 用临时 Set 跟踪本次提取中已处理的记忆（按 content 而非 index）
        var processedContents: Set<String> = []
        let maxDeletionsPerExtraction = 3  // v2.5: 每次提取最多删除 3 条
        for line in lines {
            var cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
            var memType: MemoryType = .longTerm
            var memExpiration: Date? = nil
            var isHighPriority = false
            var isDelete = false
            
            // v2.5: 解析删除前缀
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
                memExpiration = Date().addingTimeInterval(24 * 3600)
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
            
            // v2.5: 删除路径 — 用语义匹配找到并软删除对应记忆
            if isDelete {
                // v2.5: 安全阀 — 已达删除上限则跳过
                if batchedDeletions.count >= maxDeletionsPerExtraction {
                    print("⚠️ 已达最大删除数 \(maxDeletionsPerExtraction)，跳过: \(cleaned)")
                    continue
                }
                var matchedContent: String? = nil
                
                // BUG-8 fix: 只记录 content，不记录 index，避免异步期间索引漂移
                // 优先用向量相似度匹配
                if let (embConfig, embModel) = embProvider {
                    if let deleteEmb = try? await service.fetchEmbedding(text: cleaned, modelId: embModel, config: embConfig) {
                        var bestSim: Float = 0.6
                        let memoriesSnapshot = await MainActor.run { self.memories }
                        for mem in memoriesSnapshot {
                            if let existingEmb = mem.embedding {
                                let sim = cosineSimilarity(deleteEmb, existingEmb)
                                if sim > bestSim {
                                    bestSim = sim
                                    matchedContent = mem.content
                                }
                            }
                        }
                        if let c = matchedContent {
                            print("🗑️ 语义匹配：\(cleaned) ≈ \(c)（相似度 \(String(format: "%.2f", bestSim))）")
                        }
                    }
                }
                
                // 备用：文本包含匹配
                if matchedContent == nil {
                    let lowered = cleaned.lowercased()
                    matchedContent = await MainActor.run {
                        self.memories.first(where: { $0.content.lowercased().contains(lowered) || lowered.contains($0.content.lowercased()) })?.content
                    }
                    if let c = matchedContent {
                        print("🗑️ 文本匹配：\(cleaned) ≈ \(c)")
                    }
                }
                
                // 跳过本次提取中已处理的记忆
                if let c = matchedContent, processedContents.contains(c) {
                    print("⚠️ 跳过重复删除: \(c.prefix(30))")
                    continue
                }
                if let c = matchedContent { processedContents.insert(c) }
                
                if let content = matchedContent {
                    // BUG-8 fix: 用 content 匹配而非 index，避免异步执行期间索引漂移
                    // processedContents 已在主循环中按 content 去重，不需要额外的 index 集合
                    await MainActor.run {
                        guard let currentIdx = self.memories.firstIndex(where: { $0.content == content }) else {
                            print("⚠️ 删除时记忆已不存在: \(content.prefix(30))")
                            return
                        }
                        if self.memoryDeleteConfirm {
                            batchedDeletions.append((content: content, index: currentIdx))
                            print("⏳ 待确认删除：\(content)")
                        } else {
                            self.softDeleteMemory(at: currentIdx)
                            var activity = self.lastMemoryActivity ?? MemoryActivity()
                            activity.deletedMemories.append(content)
                            self.lastMemoryActivity = activity
                        }
                    }
                } else {
                    print("⚠️ 删除失败：找不到与 '\(cleaned.prefix(50))' 匹配的记忆")
                }
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
                // v2.4: 跟踪新增的记忆
                var activity = self.lastMemoryActivity ?? MemoryActivity()
                activity.addedMemories.append(cleaned)
                self.lastMemoryActivity = activity
            }
        }
        
        // v2.5: 批量提交所有待确认删除（只触发一次弹窗）
        if !batchedDeletions.isEmpty {
            await MainActor.run {
                self.pendingMemoryDeletions = batchedDeletions
            }
        }
        
        // BUG-10 fix: 新增记忆后推送到 Watch
        await MainActor.run {
            if !WatchSessionManager.shared.isSyncingFromRemote {
                WatchSessionManager.shared.pushFullDataToWatch()
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
    
    /// v2.5: 提取搜索关键词 (辅助模型)
    private func extractSearchQuery(from text: String, context: [ChatMessage] = []) async -> String {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanText.count <= 10 {
            return cleanText
        }
        
        let targetModelID = helperGlobalModelID.isEmpty ? selectedGlobalModelID : helperGlobalModelID
        let components = targetModelID.split(separator: "|")
        guard components.count == 2,
              let providerID = UUID(uuidString: String(components[0])),
              let provider = providers.first(where: { $0.id == providerID }),
              !provider.apiKey.isEmpty else { return cleanText }
        let modelID = String(components[1])
        
        let prompt = """
        【前置辅助模型 Prompt 优化版】
        你是一个专业的搜索引擎 Query 重写专家与意图识别专家。你的任务是判断用户的自然语言是否需要进行全网搜索，并将需要搜索的内容转化为最容易搜到高质量结果的关键词。
        **规则：**
        1. **意图判断（最优先）**：如果用户的提问是日常寒暄（如“你好”）、代码编写/解释、通用常识解释（如“什么是黑洞”、“写诗”等完全不需要联网最新资料的问题），请**直接且唯一地输出：[不需要搜索]**。
        2. 去除所有口语化废话（如“帮我查一下”、“呢”）。
        3. **实体展开（关键）**：如果用户使用了模糊的集合名词（如“各家”、“主流”、“大厂”），你必须利用你的常识，将其展开为具体的头部企业或产品名称。例如，遇到“各家大模型”，请替换为“OpenAI 谷歌 Anthropic 阿里 百度 字节 大模型”。
        4. 仅输出最终的搜索词或“[不需要搜索]”，绝对不要包含任何其他解释性文字。

        用户自然语言：
        \(cleanText.prefix(500))
        """
        let msg = ChatMessage(role: .user, text: prompt)
        
        do {
            let stream = service.streamChat(
                messages: [msg],
                modelId: modelID,
                config: provider,
                temperature: 0.1
            )
            var result = ""
            for try await chunk in stream {
                result += chunk
                if result.count > 150 { break } // v2.9: 增加实体展开所需的安全截断长度
            }
            let keyword = result.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "。", with: "")
                .replacingOccurrences(of: "！", with: "")
                .replacingOccurrences(of: "？", with: "")
            
            print("🧠 意图抽取: [\(cleanText.prefix(20))] -> [\(keyword)]")
            return keyword.isEmpty ? cleanText : keyword
        } catch {
            print("⚠️ 意图抽取失败: \(error.localizedDescription)")
            return cleanText
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
        streamingBlocks = []            // v2.5: 修复重试时重复显示上一次回复
        streamingThinkingBlocks = []    // v2.5: 同上
        
        msgs.append(ChatMessage(role: .assistant, text: ""))
        updateCurrentSessionMessagesInMemory(msgs) // 只更新内存，不写磁盘
        let botIndex = msgs.count - 1
        
        let localSearchEnabled = isSearchContextEnabled && webSearchEnabled
        let localQuery = lastUserMsg.text
        
        currentTask = Task {
            var searchContext: String? = nil
            if localSearchEnabled, !webSearchWorkerURL.isEmpty {
                await MainActor.run { self.streamingText = "🧠 提取搜索关键词..." }
                let extractQuery = await self.extractSearchQuery(from: localQuery)
                if extractQuery.contains("[不需要搜索]") {
                    print("🧠 意图判定：无搜索必要，跳过联网检索。")
                    await MainActor.run { self.streamingText = "" }
                } else {
                    await MainActor.run { self.streamingText = "🔍 正在检索网络: \(extractQuery)..." }
                    print("🔍 重试检索: original=\(localQuery), extracted=\(extractQuery), url=\(webSearchWorkerURL), hasAuth=\(!webSearchAuthKey.isEmpty)")
                    do {
                        let results = try await service.fetchWebSearchResults(query: extractQuery, workerURL: webSearchWorkerURL, authKey: webSearchAuthKey)
                        searchContext = results
                        print("✅ 重试检索完成")
                        await MainActor.run { self.streamingText = "" }
                    } catch {
                        print("⚠️ Web Search Failed: \(error)")
                        await MainActor.run { self.streamingText = "" }
                    }
                }
            }
            
            let history = await buildHistoryWithContext(from: msgs, searchContext: searchContext)
            await streamChatResponse(
                history: history,
                modelID: modelID,
                provider: provider,
                botIndex: botIndex
            )
            
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
           lower.contains("deepseek-reasoner") ||
           lower.contains("thinking") || // e.g. gemini-2.5-flash-thinking
           lower.contains("gemini-2.5-pro") || // v1.13: Gemini 2.5 Pro 及以上支持思考
           lower.contains("gemini-3") {        // v1.13: 囊括 gemini-3, 3.1 甚至全系 3.x
            return .supported
        }
        
        // v1.12: 精确匹配不支持思考的模型（避免误判 o1/o3/claude-3.5-sonnet 等）
        // v1.13: 移除了对 Gemini 的全盘否定，因为 Gemini 2.0/3.0 Pro 原生支持思考
        if lower.contains("gpt-3") ||
           (lower.contains("gpt-4") && !lower.contains("4o")) || // gpt-4-turbo 不支持，gpt-4o 交给 ModelRegistry
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
        
        let localSearchEnabled = isSearchContextEnabled && webSearchEnabled
        let localQuery = editingText
        
        currentTask = Task {
            var searchContext: String? = nil
            if localSearchEnabled, !webSearchWorkerURL.isEmpty {
                await MainActor.run { self.streamingText = "🧠 提取搜索关键词..." }
                let extractQuery = await self.extractSearchQuery(from: localQuery)
                if extractQuery.contains("[不需要搜索]") {
                    print("🧠 意图判定：无搜索必要，跳过联网检索。")
                    await MainActor.run { self.streamingText = "" }
                } else {
                    await MainActor.run { self.streamingText = "🔍 正在检索网络: \(extractQuery)..." }
                    print("🔍 编辑重试检索: original=\(localQuery), extracted=\(extractQuery), url=\(webSearchWorkerURL), hasAuth=\(!webSearchAuthKey.isEmpty)")
                    do {
                        let results = try await service.fetchWebSearchResults(query: extractQuery, workerURL: webSearchWorkerURL, authKey: webSearchAuthKey)
                        searchContext = results
                        print("✅ 编辑检索完成")
                        await MainActor.run { self.streamingText = "" }
                    } catch {
                        print("⚠️ Web Search Failed: \(error)")
                        await MainActor.run { self.streamingText = "" }
                    }
                }
            }
            
            let history = await buildHistoryWithContext(from: msgs, searchContext: searchContext)
            await streamChatResponse(
                history: history,
                modelID: modelID,
                provider: provider,
                botIndex: botIndex
            )
            
        }
    }
    
    // MARK: - 通用流式响应逻辑 (v2.2)
    private func streamChatResponse(
        history: [ChatMessage],
        modelID: String,
        provider: ProviderConfig,
        botIndex: Int
    ) async {
        var responseText = ""
        var thinkingText = ""
        var firstTokenReceived = false
        var localFirstTokenTime: Date? = nil
        
        // 状态机变量
        var isThinking = false
        var pendingBuffer = ""
        var hasSeenFirstThink = false
        var responseTextBeforeThink = ""
        
        var lastUIUpdateTime = Date()
        var uiUpdateInterval: TimeInterval = 0.05 // 动态调节：初始 50ms，实现丝滑流畅的逐字滚动
        var retryCount = 0
        
        while true {
            // 重试前重置状态
            responseText = ""
            thinkingText = ""
            isThinking = false
            pendingBuffer = ""
            firstTokenReceived = false
            hasSeenFirstThink = false
            responseTextBeforeThink = ""
            
            do {
                // 重试 UI 提示
                if retryCount > 0 {
                    await MainActor.run {
                        self.streamingText = "正在重试 (\(retryCount)/\(maxRetries))..."
                        self.streamingThinkingText = ""
                    }
                }
                
                let stream = service.streamChat(messages: history, modelId: modelID, config: provider, temperature: temperature)
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    
                    // 记录首 Token
                    if !firstTokenReceived {
                        firstTokenReceived = true
                        localFirstTokenTime = Date()
                        if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                            currentMsgs[botIndex].firstTokenTime = localFirstTokenTime
                            updateCurrentSessionMessagesInMemory(currentMsgs)
                        }
                    }
                    
                    // 1. 追加缓冲
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
                    
                    // 4. 节流动态 UI 更新 (极其激进的 OOM 防护)
                    let now = Date()
                    let currentLength = responseText.count + thinkingText.count
                    
                    // 动态调整刷新率：文本越长，界面刷新越慢，降低 CPU 和内存拷贝堆积
                    if currentLength > 50_000 {
                        uiUpdateInterval = 1.0 // 超过 5 万字，1 秒刷新一次
                    } else if currentLength > 20_000 {
                        uiUpdateInterval = 0.5 // 超过 2 万字，0.5 秒刷新
                    } else if currentLength > 5_000 {
                        uiUpdateInterval = 0.25 // 5 千字，0.25 秒
                    }
                    
                    if now.timeIntervalSince(lastUIUpdateTime) >= uiUpdateInterval {
                        var totalResponseText = (responseTextBeforeThink + responseText).trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        let parsedBlocks = totalResponseText.splitIntoMarkdownBlocks()
                        // v2.4: Filter out empty/whitespace-only thinking blocks to prevent empty "思考过程" frame
                        let rawThinkingBlocks = thinkingMode != .disabled ? thinkingText.splitIntoMarkdownBlocks() : []
                        let parsedThinkingBlocks = rawThinkingBlocks.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                        
                        await MainActor.run {
                            self.streamingText = totalResponseText
                            self.streamingBlocks = parsedBlocks
                            if self.thinkingMode != .disabled {
                                self.streamingThinkingText = thinkingText
                                self.streamingThinkingBlocks = parsedThinkingBlocks
                            }
                        }
                        
                        // 不再实时往 messages 里塞（极耗内存，导致 ScrollView 崩溃），仅用 streaming 承载
                        lastUIUpdateTime = now
                    }
                }
                
                // 成功流式结束
                break
                
            } catch {
                if Task.isCancelled {
                     await MainActor.run {
                         self.streamingText = ""
                         self.streamingThinkingText = ""
                         self.streamingBlocks = []
                         self.streamingThinkingBlocks = []
                     }
                     
                     if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                         // 刷新还在缓冲区的尾部残余 Token，防止“停止”瞬间文段回缩
                         if isThinking { thinkingText += pendingBuffer }
                         else { responseText += pendingBuffer }
                         
                         let finalContent = (responseTextBeforeThink + responseText).trimmingCharacters(in: .whitespacesAndNewlines)
                         currentMsgs[botIndex].text = finalContent.isEmpty ? "" : finalContent + "\n[已停止]"
                         if thinkingMode != .disabled && !thinkingText.isEmpty {
                             currentMsgs[botIndex].thinkingContent = thinkingText
                         }
                         updateCurrentSessionMessagesInMemory(currentMsgs)
                     }
                     saveSessions()
                     if enableHapticFeedback {
                         #if os(watchOS)
                         WKInterfaceDevice.current().play(.directionDown)
                         #else
                         UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                         #endif
                     }
                     await MainActor.run {
                         self.isLoading = false
                         self.currentTask = nil
                     }
                     return
                }
                
                print("Stream failed: \(error)")
                
                if autoRetryEnabled && retryCount < maxRetries {
                    retryCount += 1
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    continue
                }
                
                // 最终失败
                await MainActor.run {
                    self.streamingText = ""
                    self.streamingThinkingText = ""
                }
                
                if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
                     let finalContent = (responseTextBeforeThink + responseText).trimmingCharacters(in: .whitespacesAndNewlines)
                     
                     var errorMsg = "❌ \(error.localizedDescription)"
                     if retryCount > 0 { errorMsg = "❌ [已重试 \(retryCount) 次] \(error.localizedDescription)" }
                     
                     if finalContent.isEmpty { currentMsgs[botIndex].text = errorMsg }
                     else { currentMsgs[botIndex].text = finalContent + "\n[中断] \(error.localizedDescription)" }
                     
                     if thinkingMode != .disabled && !thinkingText.isEmpty {
                         currentMsgs[botIndex].thinkingContent = thinkingText
                     }
                     updateCurrentSessionMessagesInMemory(currentMsgs)
                     saveSessions()
                     if enableHapticFeedback {
                         #if os(watchOS)
                         WKInterfaceDevice.current().play(.failure)
                         #else
                         UINotificationFeedbackGenerator().notificationOccurred(.error)
                         #endif
                     }
                }
                await MainActor.run {
                    self.isLoading = false
                    self.currentTask = nil
                }
                return
            }
        }
        
        // 循环结束（成功）：处理剩余 Buffer
        if !pendingBuffer.isEmpty {
            if isThinking { thinkingText += pendingBuffer }
            else { responseText += pendingBuffer }
        }
        
        var finalContent = (responseTextBeforeThink + responseText).trimmingCharacters(in: .whitespacesAndNewlines)
        let finalThinking = thinkingText
        

        
        // v2.6: 日志打印完整响应
        print("\n🤖 AI 完整响应:")
        print(finalContent.isEmpty ? "[空]" : finalContent)
        print("--------------------")
        
        if !finalThinking.isEmpty {
            print("\n🧠 AI 思考过程:")
            print(finalThinking)
            print("--------------------")
        }
        
        
        if var currentMsgs = sessions.first(where: { $0.id == currentSessionId })?.messages, botIndex < currentMsgs.count {
            currentMsgs[botIndex].text = finalContent
            if thinkingMode == .disabled {
                currentMsgs[botIndex].thinkingContent = nil
            } else {
                currentMsgs[botIndex].thinkingContent = finalThinking.isEmpty ? nil : finalThinking
            }
            currentMsgs[botIndex].completeTime = Date()
            if let t = localFirstTokenTime { currentMsgs[botIndex].firstTokenTime = t }
            
            await MainActor.run {
                self.streamingText = ""
                self.streamingThinkingText = ""
            }
            updateCurrentSessionMessagesInMemory(currentMsgs)
        }
        
        saveSessions()
        if enableHapticFeedback {
            #if os(watchOS)
            WKInterfaceDevice.current().play(.success)
            #else
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
        }
        
        // 记忆提取
        if self.memoryEnabled {
            Task { [weak self] in await self?.extractMemories() }
        }
        
        // 生成标题 (仅当是新对话)
        if let session = self.sessions.first(where: { $0.id == self.currentSessionId }),
           session.title == "新对话",
           let firstUserMsg = session.messages.first(where: { $0.role == .user }) {
            Task { [weak self] in await self?.generateSessionTitle(from: firstUserMsg.text) }
        }
        
        await MainActor.run {
            self.isLoading = false
            self.currentTask = nil
        }
    }
    
    // MARK: - Markdown Helpers
    
    /// v2.4: 高性能子串出现次数统计（O(N) 单次扫描，零分配）
    private func countOccurrences(of needle: String, in haystack: Substring) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let range = haystack.range(of: needle, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<haystack.endIndex
        }
        return count
    }
}

// MARK: - Markdown Block Splitter
extension String {
    // 高级注视点拆分器：保证 ``` 代码块不断行，并且长正常文本按空行拆分，防闪退 OOM
    // v2.3: 高性能重写，全程使用 Substring 索引操作，避免频繁 String concat 和 components(separatedBy:) 导致的内存暴增
    func splitIntoMarkdownBlocks() -> [String] {
        var blocks: [String] = []
        blocks.reserveCapacity(100)
        
        var inCodeBlock = false
        var blockStart = self.startIndex
        var currentIndex = self.startIndex
        var currentBlockCharCount = 0
        
        while currentIndex < self.endIndex {
            let nextNewline = self[currentIndex...].firstIndex(of: "\n") ?? self.endIndex
            let line = self[currentIndex..<nextNewline]
            
            let isCodeFence = line.drop(while: { $0.isWhitespace }).hasPrefix("```")
            
            if isCodeFence {
                if !inCodeBlock {
                    // 进入代码块之前，把前面的纯文本压入
                    if currentIndex > blockStart {
                        let content = self[blockStart..<currentIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                        if !content.isEmpty { blocks.append(String(content)) }
                    }
                    blockStart = currentIndex // 代码块起点
                    inCodeBlock = true
                    currentBlockCharCount = line.count
                } else {
                    // 离开代码块
                    let endIndex = nextNewline
                    blocks.append(String(self[blockStart..<endIndex]))
                    
                    if endIndex < self.endIndex {
                        blockStart = self.index(after: endIndex) // 下一行起点
                    } else {
                        blockStart = endIndex
                    }
                    inCodeBlock = false
                    currentBlockCharCount = 0
                }
            } else {
                if !inCodeBlock {
                    let isLineEmpty = line.allSatisfy { $0.isWhitespace }
                    if isLineEmpty {
                        if currentIndex > blockStart {
                            let content = self[blockStart..<currentIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                            if !content.isEmpty { blocks.append(String(content)) }
                        }
                        blocks.append("") // 空行占位，保持原渲染逻辑兼容
                        
                        if nextNewline < self.endIndex {
                            blockStart = self.index(after: nextNewline)
                        } else {
                            blockStart = nextNewline
                        }
                        currentBlockCharCount = 0
                    } else {
                        currentBlockCharCount += line.count
                        // 兜底防爆存：普通文本超过1000字符自动强截断
                        if currentBlockCharCount > 1000 {
                            let endIndex = nextNewline
                            blocks.append(String(self[blockStart..<endIndex]))
                            if nextNewline < self.endIndex {
                                blockStart = self.index(after: nextNewline)
                            } else {
                                blockStart = nextNewline
                            }
                            currentBlockCharCount = 0
                        }
                    }
                }
            }
            
            if nextNewline == self.endIndex { break }
            currentIndex = self.index(after: nextNewline)
        }
        
        if blockStart < self.endIndex {
            let remainder = self[blockStart..<self.endIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            if !remainder.isEmpty {
                blocks.append(String(remainder))
            }
        }
        
        // 过滤首尾多余的空占位符，避免产生大量空白
        while blocks.last == "" { blocks.removeLast() }
        while blocks.first == "" { blocks.removeFirst() }
        
        return blocks
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
