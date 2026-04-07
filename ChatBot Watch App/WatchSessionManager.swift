import Foundation
import Combine
import WatchConnectivity

/// watchOS 端 WatchConnectivity 管理器
/// 双向同步：自动推送 Watch 配置 + 聊天记录 + 记忆 到 iPhone，并接收 iPhone 推送的相应数据
class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSessionManager()
    
    /// 收到新配置时发出的通知名
    static let configDidUpdateNotification = Notification.Name("WatchConnectivityDidReceiveConfig")
    
    @Published var lastReceiveStatus: String? = nil
    @Published var isSyncing: Bool = false
    
    /// 防止同步循环：正在从远端应用配置时，不要触发反向推送
    var isSyncingFromRemote = false
    
    private var cancellables = Set<AnyCancellable>()
    private var lastCorePayload: NSDictionary? = nil
    /// 上次推送的聊天/记忆数据哈希，避免重复发送大文件
    private var lastFullDataHash: Int = 0
    private var syncFlagResetTimer: DispatchWorkItem? = nil
    
    private override init() {
        super.init()
    }
    
    // MARK: - 激活
    func activate() {
        guard WCSession.isSupported() else {
            print("📱 WatchConnectivity 不可用")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        print("📱 WatchConnectivity 正在激活...")
        setupObservers()
    }
    
    // MARK: - 自动监听变化
    private func setupObservers() {
        // 监听 UserDefaults 变化，自动防抖后推送配置到 iPhone
        // 注意：仅推送配置，不自动推送大文件（聊天+记忆）以避免循环
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self, !self.isSyncingFromRemote else { return }
                self.pushConfigToPhone(force: false)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 需要同步的所有配置 Keys（与 iOS 一致）
    
    private static let stringKeys: [String] = [
        "selectedGlobalModelID",
        "cloudBackupURL",
        "cloudBackupAuthKey",
        "helperGlobalModelID",
        "embeddingProviderID",
        "embeddingModelID",
        "workersAIEmbeddingURL",
        "customSystemPrompt",
        "thinkingMode",
        "markdownRenderMode",
        "appThemeRaw",
        "preferredColorSchemeRaw",
        "userName",
        "webSearchWorkerURL",
        "webSearchAuthKey",
    ]
    
    private static let boolKeys: [String] = [
        "memoryEnabled",
        "latexRenderingEnabled",
        "advancedLatexEnabled",
        "enableMessageAnimation",
        "showModelNameInNavBar",
        "showScrollToBottomButton",
        "enableHapticFeedback",
        "webSearchEnabled",
        "autoBackupEnabled",
        "autoRetryEnabled",
        "memoryDeleteConfirm",
        "sendTimeToAI",
        "sendLocationToAI",
    ]
    
    private static let numericKeys: [String] = [
        "temperature",
        "historyMessageCount",
        "detectedEmbeddingDim",
        "memoryMaxRetrievalCount",
        "memoryRetrievalThreshold",
        "maxRetries",
    ]
    
    private static let dataKeys: [String] = [
        "savedProviders_v3",
        "modelSettings",
        "userAvatarData",
    ]
    
    /// 不应该被同步的占位符默认值
    private static let placeholderValues: Set<String> = [
        "https://your-domain.com",
        "https://your-domain.com/config.json",
        "YOUR_AUTH_KEY",
    ]
    
    // MARK: - 推送配置到 iPhone
    func pushConfigToPhone(force: Bool = false) {
        guard force || !isSyncingFromRemote else { return }
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            print("📱 WCSession 未激活，跳过推送")
            return
        }
        
        let context = collectConfig(sourceDevice: "watch")
        
        // 过滤掉时间戳等元数据，判断核心配置是否真的变了
        var corePayload = context
        corePayload.removeValue(forKey: "_syncTimestamp")
        corePayload.removeValue(forKey: "_sourceDevice")
        let nsCore = corePayload as NSDictionary
        
        if let last = lastCorePayload, last.isEqual(nsCore) {
            return  // 没有变化，跳过推送
        }
        lastCorePayload = nsCore
        
        do {
            try session.updateApplicationContext(context)
            let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            DispatchQueue.main.async {
                self.lastReceiveStatus = "⬆️ 已推送到 iPhone (\(dateStr))"
            }
            print("📱 配置已推送到 iPhone (\(context.count) 项)")
        } catch {
            print("📱 推送到 iPhone 失败: \(error)")
        }
    }
    
    // MARK: - 收集配置数据
    private func collectConfig(sourceDevice: String) -> [String: Any] {
        var context: [String: Any] = [:]
        let defaults = UserDefaults.standard
        
        // Data 类型
        for key in Self.dataKeys {
            if let data = defaults.data(forKey: key), !data.isEmpty {
                context[key] = data
            }
        }
        
        // String 类型 — 排除空字符串和占位符值
        for key in Self.stringKeys {
            if let val = defaults.string(forKey: key), !val.isEmpty, !Self.placeholderValues.contains(val) {
                context[key] = val
            }
        }
        
        // Bool 类型
        for key in Self.boolKeys {
            context[key] = defaults.bool(forKey: key)
        }
        
        // Numeric 类型
        for key in Self.numericKeys {
            context[key] = defaults.double(forKey: key)
        }
        
        context["_syncTimestamp"] = Date().timeIntervalSince1970
        context["_sourceDevice"] = sourceDevice
        
        return context
    }
    
    // MARK: - 大文件推送 (聊天记录、记忆) — 自动触发
    
    func pushFullDataToPhone(force: Bool = false) {
        guard force || !isSyncingFromRemote else { return }
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        
        let defaults = UserDefaults.standard
        var payload: [String: Any] = [:]
        
        if let sessionsData = defaults.data(forKey: "chatSessions_v1") {
            if let jsonObj = try? JSONSerialization.jsonObject(with: sessionsData) {
                payload["chatSessions_v1"] = jsonObj
            }
        }
        
        if let memoriesData = defaults.data(forKey: "userMemories_v1") { // v1.7: 修复错误的 UserDefaults Key (之前写了 "memories_v2", 实际上 Watch 保存和加载都是 "userMemories_v1")
            if let jsonObj = try? JSONSerialization.jsonObject(with: memoriesData) {
                payload["userMemories_v1"] = jsonObj
            }
        }
        
        if let trashData = defaults.data(forKey: "memoryTrash_v1") { // v2.1: 回收站
            if let jsonObj = try? JSONSerialization.jsonObject(with: trashData) {
                payload["memoryTrash_v1"] = jsonObj
            }
        }
        
        guard !payload.isEmpty else { return }
        
        // 计算数据哈希避免重复发送
        let hashValue = (payload as NSDictionary).description.hashValue
        if hashValue == lastFullDataHash { return }
        lastFullDataHash = hashValue
        
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent("ChatBot_FullData_Sync_\(UUID().uuidString).json")
            try data.write(to: fileURL)
            
            session.transferFile(fileURL, metadata: ["type": "FullDataSync", "source": "watch"])
            let sizeKB = data.count / 1024
            print("📱 聊天记录+记忆已通过文件推送到 iPhone (\(sizeKB) KB)")
            // BUG-11 fix: 清理临时文件避免无限堆积
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                try? FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            print("📱 文件推送失败: \(error)")
        }
    }
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("📱 WCSession 激活失败: \(error)")
        } else {
            print("📱 WCSession 激活成功: \(activationState.rawValue)")
            
            // 激活后检查是否有待处理的 applicationContext
            let context = session.receivedApplicationContext
            if !context.isEmpty, let source = context["_sourceDevice"] as? String, source == "phone" {
                print("📱 发现待处理的 iPhone applicationContext (\(context.count) 项)")
                applyConfig(context)
            }
            
        }
    }
    
    // 收到 iPhone 推送的配置
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        print("📱 收到 iPhone 配置推送: \(applicationContext.keys)")
        applyConfig(applicationContext)
    }
    
    // MARK: - 应用配置
    private func applyConfig(_ context: [String: Any]) {
        // 防止同步循环
        if let source = context["_sourceDevice"] as? String, source == "watch" { return }
        
        isSyncingFromRemote = true
        // 不用 defer，改用延迟重置，确保超过 debounce 周期（3s）
        
        // 缓存核心配置防止反弹
        var corePayload = context
        corePayload.removeValue(forKey: "_syncTimestamp")
        corePayload.removeValue(forKey: "_sourceDevice")
        lastCorePayload = corePayload as NSDictionary
        
        let defaults = UserDefaults.standard
        var updatedKeys: [String] = []
        
        // Data 类型 (特殊处理：增量合并数组和字典以防覆盖)
        for key in Self.dataKeys {
            if let incomingData = context[key] as? Data {
                if key == "savedProviders_v3" {
                    // 撤销 v2.1.1 的增量合并：数组元素如果被删除（例如取消收藏模型），增量合并会导致 Watch 无法察觉“删除”动作，从而将其复活。
                    defaults.set(incomingData, forKey: key)
                } else if key == "modelSettings" {
                    // 增量合并模型设置字典
                    if let incomingSettings = try? JSONDecoder().decode([String: ModelSettings].self, from: incomingData) {
                        var localSettings: [String: ModelSettings] = [:]
                        if let localData = defaults.data(forKey: key),
                           let decoded = try? JSONDecoder().decode([String: ModelSettings].self, from: localData) {
                            localSettings = decoded
                        }
                        
                        for (modelId, setting) in incomingSettings {
                            localSettings[modelId] = setting
                        }
                        if let mergedData = try? JSONEncoder().encode(localSettings) {
                            defaults.set(mergedData, forKey: key)
                        }
                    }
                } else {
                    // 普通 Data，直接覆盖
                    defaults.set(incomingData, forKey: key)
                }
                updatedKeys.append(key)
            }
        }
        
        // String 类型 — 忽略占位符
        for key in Self.stringKeys {
            if let value = context[key] as? String, !Self.placeholderValues.contains(value) {
                defaults.set(value, forKey: key)
                updatedKeys.append(key)
            }
        }
        
        // Bool 类型
        for key in Self.boolKeys {
            if let value = context[key] as? Bool {
                defaults.set(value, forKey: key)
            }
        }
        
        // Numeric 类型
        for key in Self.numericKeys {
            if let value = context[key] as? Double {
                defaults.set(value, forKey: key)
            }
        }
        
        defaults.synchronize()
        
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        
        DispatchQueue.main.async {
            self.lastReceiveStatus = "✅ 已同步 [\(updatedKeys.joined(separator: ","))] (\(dateStr))"
            NotificationCenter.default.post(name: Self.configDidUpdateNotification, object: nil)
            // BUG-4 fix: 在主线程通知发出后再开始倒计，确保 debounce 周期内不会还原 flag
            self.scheduleResetSyncFlag()
        }
    }
    
    /// 延迟 10 秒后重置 isSyncingFromRemote，确保超过 debounce 周期（5s）+ ViewModel reload
    private func scheduleResetSyncFlag() {
        syncFlagResetTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.isSyncingFromRemote = false
        }
        syncFlagResetTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: item)
    }
    
    // 接收 iPhone 的大文件推送
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let metadata = file.metadata,
              let type = metadata["type"] as? String, type == "FullDataSync",
              let source = metadata["source"] as? String, source == "phone" else { return }
        
        print("📱 收到来自 iPhone 的聊天记录+记忆文件")
        
        isSyncingFromRemote = true
        defer { self.scheduleResetSyncFlag() }
        
        do {
            let data = try Data(contentsOf: file.fileURL)
            guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            
            let defaults = UserDefaults.standard
            var updated = false
            
            // 合并聊天记录 (按 ID 匹配，取 lastModified 较新的版本)
            if let incomingSessions = payload["chatSessions_v1"] {
                let incomingData = try JSONSerialization.data(withJSONObject: incomingSessions)
                let incoming = try JSONDecoder().decode([ChatSession].self, from: incomingData)
                
                var existing: [ChatSession] = []
                if let existData = defaults.data(forKey: "chatSessions_v1"),
                   let decoded = try? JSONDecoder().decode([ChatSession].self, from: existData) {
                    existing = decoded
                }
                // 构建本地索引表，以便就地修改
                var existingMap: [UUID: Int] = [:]
                for (i, s) in existing.enumerated() { existingMap[s.id] = i }
                var newAdded = 0
                var updatedCount = 0
                for session in incoming {
                    if let idx = existingMap[session.id] {
                        // ID 已存在：取 lastModified 较新的版本
                        if session.lastModified > existing[idx].lastModified {
                            existing[idx] = session
                            updatedCount += 1
                        }
                    } else {
                        existing.append(session)
                        newAdded += 1
                    }
                }
                let merged = try JSONEncoder().encode(existing)
                defaults.set(merged, forKey: "chatSessions_v1")
                updated = true
                print("📱 聊天记录合并: 新増 \(newAdded) 条, 更新 \(updatedCount) 条")
            }
            
            // 合并记忆 (按 ID 匹配，取 lastUpdated 较新的版本，与 session 合并逻辑对齐)
            if let incomingMemories = payload["userMemories_v1"] ?? payload["memories_v2"] { // 兼容旧版 memories_v2
                let incomingData = try JSONSerialization.data(withJSONObject: incomingMemories)
                let incoming = try JSONDecoder().decode([MemoryItem].self, from: incomingData)
                
                var existing: [MemoryItem] = []
                if let existData = defaults.data(forKey: "userMemories_v1"),
                   let decoded = try? JSONDecoder().decode([MemoryItem].self, from: existData) {
                    existing = decoded
                }
                var existingMap: [UUID: Int] = [:]
                for (i, m) in existing.enumerated() { existingMap[m.id] = i }
                var newAdded = 0, updatedMemCount = 0
                for mem in incoming {
                    if let idx = existingMap[mem.id] {
                        // ID 已存在：取 lastUpdated 较新的版本覆盖
                        let existingUpdated = existing[idx].lastUpdated ?? existing[idx].createdAt
                        let incomingUpdated = mem.lastUpdated ?? mem.createdAt
                        if incomingUpdated > existingUpdated {
                            existing[idx] = mem
                            updatedMemCount += 1
                        }
                    } else {
                        existing.append(mem)
                        existingMap[mem.id] = existing.count - 1
                        newAdded += 1
                    }
                }
                let merged = try JSONEncoder().encode(existing)
                defaults.set(merged, forKey: "userMemories_v1")
                updated = true
                print("📱 记忆合并完成: 新增 \(newAdded) 条, 更新 \(updatedMemCount) 条")
            }
            
            // v2.1: 回收站使用全量覆盖（而非增量合并）—— iPhone 端恢复/清空操作需要在 Watch 上生效
            if let incomingTrash = payload["memoryTrash_v1"] {
                let incomingData = try JSONSerialization.data(withJSONObject: incomingTrash)
                let incoming = try JSONDecoder().decode([MemoryItem].self, from: incomingData)
                let encoded = try JSONEncoder().encode(incoming)
                defaults.set(encoded, forKey: "memoryTrash_v1")
                updated = true
                print("📱 回收站已从 iPhone 全量更新 (\(incoming.count) 条)")
            }
            
            if updated {
                defaults.synchronize()
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Self.configDidUpdateNotification, object: nil)
                    NotificationCenter.default.post(name: Notification.Name("WatchConnectivityDidReceiveFullData"), object: nil)
                }
                print("📱 聊天记录+记忆已从 iPhone 写入 UserDefaults")
            }
            
        } catch {
            print("📱 解析 iPhone 发来的数据失败: \(error)")
        }
    }
}
