import Foundation
import Combine
import WatchConnectivity

/// iOS 端 WatchConnectivity 管理器
/// 双向同步：自动推送 iPhone 配置 + 聊天记录 + 记忆 到 Watch，并接收 Watch 推送的相应数据
class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSessionManager()

    /// 收到 Watch 配置时发出的通知名
    static let configDidUpdateNotification = Notification.Name("WatchConnectivityDidReceiveConfig")

    @Published var lastSyncStatus: String? = nil
    @Published var isWatchReachable: Bool = false
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
            print("WatchConnectivity 不可用")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        print("WatchConnectivity 正在激活...")
        setupObservers()
    }

    // MARK: - 自动监听变化
    private func setupObservers() {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self, !self.isSyncingFromRemote else { return }
                self.pushConfigToWatch(force: false)
            }
            .store(in: &cancellables)
    }

    // MARK: - 同步 Keys

    private static let stringKeys: [String] = [
        "selectedGlobalModelID", "cloudBackupURL", "cloudBackupAuthKey",
        "helperGlobalModelID", "embeddingProviderID", "embeddingModelID",
        "workersAIEmbeddingURL", "customSystemPrompt", "thinkingMode",
        "markdownRenderMode", "appThemeRaw", "preferredColorSchemeRaw",
        "userName", "webSearchWorkerURL", "webSearchAuthKey",
    ]

    private static let boolKeys: [String] = [
        "memoryEnabled", "latexRenderingEnabled", "advancedLatexEnabled",
        "enableMessageAnimation", "showModelNameInNavBar", "showScrollToBottomButton",
        "enableHapticFeedback", "webSearchEnabled", "autoBackupEnabled",
        "autoRetryEnabled", "memoryDeleteConfirm", "sendTimeToAI", "sendLocationToAI",
    ]

    private static let numericKeys: [String] = [
        "temperature", "historyMessageCount", "detectedEmbeddingDim",
        "memoryMaxRetrievalCount", "memoryRetrievalThreshold", "maxRetries",
    ]

    private static let dataKeys: [String] = [
        "savedProviders_v3", "modelSettings", "userAvatarData",
    ]

    private static let placeholderValues: Set<String> = [
        "https://your-domain.com",
        "https://your-domain.com/config.json",
        "YOUR_AUTH_KEY",
    ]

    // MARK: - 推送配置到 Watch
    func pushConfigToWatch(force: Bool = false) {
        guard force || !isSyncingFromRemote else { return }
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            DispatchQueue.main.async {
                self.lastSyncStatus = "未连接手表 (state=\(session.activationState.rawValue))"
            }
            return
        }

        let context = collectConfig(sourceDevice: "phone")

        var corePayload = context
        corePayload.removeValue(forKey: "_syncTimestamp")
        corePayload.removeValue(forKey: "_sourceDevice")
        let nsCore = corePayload as NSDictionary

        if let last = lastCorePayload, last.isEqual(nsCore) {
            return
        }
        lastCorePayload = nsCore

        do {
            try session.updateApplicationContext(context)
            let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            DispatchQueue.main.async { self.lastSyncStatus = "已推送到 Watch (\(dateStr))" }
            print("配置已推送到 Watch (\(context.count) 项)")
        } catch {
            DispatchQueue.main.async { self.lastSyncStatus = "推送失败: \(error.localizedDescription)" }
            print("推送失败: \(error)")
        }
    }

    // MARK: - 收集配置数据
    private func collectConfig(sourceDevice: String) -> [String: Any] {
        var context: [String: Any] = [:]
        let defaults = UserDefaults.standard

        for key in Self.dataKeys {
            if let data = defaults.data(forKey: key), !data.isEmpty {
                context[key] = data
            }
        }
        for key in Self.stringKeys {
            if let val = defaults.string(forKey: key), !val.isEmpty, !Self.placeholderValues.contains(val) {
                context[key] = val
            }
        }
        for key in Self.boolKeys { context[key] = defaults.bool(forKey: key) }
        for key in Self.numericKeys { context[key] = defaults.double(forKey: key) }

        context["_syncTimestamp"] = Date().timeIntervalSince1970
        context["_sourceDevice"] = sourceDevice
        return context
    }

    // MARK: - 大文件推送 (聊天记录、记忆)
    func pushFullDataToWatch(force: Bool = false) {
        guard force || !isSyncingFromRemote else { return }
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        let defaults = UserDefaults.standard
        var payload: [String: Any] = [:]

        if let sessionsData = defaults.data(forKey: "chatSessions_v1"),
           let jsonObj = try? JSONSerialization.jsonObject(with: sessionsData) {
            payload["chatSessions_v1"] = jsonObj
        }
        if let memoriesData = defaults.data(forKey: "userMemories_v1"),
           let jsonObj = try? JSONSerialization.jsonObject(with: memoriesData) {
            payload["userMemories_v1"] = jsonObj
        }
        // 回收站：iOS 用 deletedMemoriesBin_v1，推送给 Watch 时用 Watch 认识的 memoryTrash_v1
        if let trashData = defaults.data(forKey: "deletedMemoriesBin_v1"),
           let jsonObj = try? JSONSerialization.jsonObject(with: trashData) {
            payload["memoryTrash_v1"] = jsonObj
        }

        guard !payload.isEmpty else { return }

        let hashValue = (payload as NSDictionary).description.hashValue
        if hashValue == lastFullDataHash { return }
        lastFullDataHash = hashValue

        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent("OpenChat_FullData_Sync_\(UUID().uuidString).json")
            try data.write(to: fileURL)
            session.transferFile(fileURL, metadata: ["type": "FullDataSync", "source": "phone"])
            print("聊天记录+记忆已通过文件推送到 Watch (\(data.count / 1024) KB)")
            // BUG-11 fix: 延迟 30s 后删除临时文件（WC 传输完成后就无需保留）
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                try? FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            print("文件推送失败: \(error)")
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.isWatchReachable = session.isReachable }
        if let error = error {
            print("WCSession 激活失败: \(error)")
        } else {
            print("WCSession 激活成功: \(activationState.rawValue)")
            let context = session.receivedApplicationContext
            if !context.isEmpty, let source = context["_sourceDevice"] as? String, source == "watch" {
                print("发现待处理的 Watch applicationContext (\(context.count) 项)")
                applyConfig(context)
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) { print("WCSession 变为非活跃") }

    func sessionDidDeactivate(_ session: WCSession) {
        print("WCSession 已停用，重新激活...")
        session.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.isWatchReachable = session.isReachable }
        print("Watch 可达性变更: \(session.isReachable)")
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        print("收到 Watch 端配置推送: \(applicationContext.keys)")
        applyConfig(applicationContext)
    }

    // MARK: - 应用配置（applicationContext）
    private func applyConfig(_ context: [String: Any]) {
        if let source = context["_sourceDevice"] as? String, source == "phone" { return }

        isSyncingFromRemote = true

        var corePayload = context
        corePayload.removeValue(forKey: "_syncTimestamp")
        corePayload.removeValue(forKey: "_sourceDevice")
        lastCorePayload = corePayload as NSDictionary

        let localDataKeys = Self.dataKeys
        let localStringKeys = Self.stringKeys
        let localBoolKeys = Self.boolKeys
        let localNumericKeys = Self.numericKeys
        let localPlaceholderValues = Self.placeholderValues

        Task.detached(priority: .userInitiated) {
            let defaults = UserDefaults.standard
            var updatedKeys: [String] = []

            for key in localDataKeys {
                if let incomingData = context[key] as? Data {
                    if key == "savedProviders_v3" {
                        defaults.set(incomingData, forKey: key)
                    } else if key == "modelSettings" {
                        if let incomingSettings = try? JSONDecoder().decode([String: ModelSettings].self, from: incomingData) {
                            var localSettings: [String: ModelSettings] = [:]
                            if let localData = defaults.data(forKey: key),
                               let decoded = try? JSONDecoder().decode([String: ModelSettings].self, from: localData) {
                                localSettings = decoded
                            }
                            for (modelId, setting) in incomingSettings { localSettings[modelId] = setting }
                            if let mergedData = try? JSONEncoder().encode(localSettings) {
                                defaults.set(mergedData, forKey: key)
                            }
                        }
                    } else {
                        defaults.set(incomingData, forKey: key)
                    }
                    updatedKeys.append(key)
                }
            }
            for key in localStringKeys {
                if let value = context[key] as? String, !localPlaceholderValues.contains(value) {
                    defaults.set(value, forKey: key)
                    updatedKeys.append(key)
                }
            }
            for key in localBoolKeys {
                if let value = context[key] as? Bool { defaults.set(value, forKey: key) }
            }
            for key in localNumericKeys {
                if let value = context[key] as? Double { defaults.set(value, forKey: key) }
            }

            defaults.synchronize()
            let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            let finalUpdatedKeys = updatedKeys
            await MainActor.run {
                self.lastSyncStatus = "已从 Watch 同步 [\(finalUpdatedKeys.joined(separator: ","))] (\(dateStr))"
                NotificationCenter.default.post(name: Self.configDidUpdateNotification, object: nil)
                // 写入完成后再开始计时，防止提前重置导致反弹推送
                self.scheduleResetSyncFlag()
            }
            print("配置已从 Watch 写入 UserDefaults: \(finalUpdatedKeys)")
        }
    }

    private func scheduleResetSyncFlag() {
        syncFlagResetTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.isSyncingFromRemote = false }
        syncFlagResetTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: item)
    }

    // MARK: - 接收 Watch 的大文件推送
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let metadata = file.metadata,
              let type = metadata["type"] as? String, type == "FullDataSync",
              let source = metadata["source"] as? String, source == "watch" else { return }

        print("收到来自 Watch 的聊天记录+记忆文件")
        isSyncingFromRemote = true
        defer { self.scheduleResetSyncFlag() }

        do {
            let data = try Data(contentsOf: file.fileURL)
            guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            let defaults = UserDefaults.standard
            var updated = false

            // 合并聊天记录（按 ID 匹配，取 lastModified 较新的版本）
            if let incomingSessions = payload["chatSessions_v1"] {
                let incomingData = try JSONSerialization.data(withJSONObject: incomingSessions)
                let incoming = try JSONDecoder().decode([ChatSession].self, from: incomingData)

                var existing: [ChatSession] = []
                if let existData = defaults.data(forKey: "chatSessions_v1"),
                   let decoded = try? JSONDecoder().decode([ChatSession].self, from: existData) {
                    existing = decoded
                }
                var existingMap: [UUID: Int] = [:]
                for (i, s) in existing.enumerated() { existingMap[s.id] = i }
                var newAdded = 0, updatedCount = 0
                for sess in incoming {
                    if let idx = existingMap[sess.id] {
                        if sess.lastModified > existing[idx].lastModified {
                            existing[idx] = sess
                            updatedCount += 1
                        }
                    } else {
                        existing.append(sess)
                        newAdded += 1
                    }
                }
                let merged = try JSONEncoder().encode(existing)
                defaults.set(merged, forKey: "chatSessions_v1")
                updated = true
                print("聊天记录合并: 新增 \(newAdded) 条, 更新 \(updatedCount) 条")
            }

            // 合并记忆（按 ID 匹配，取 lastUpdated 较新的版本，与 session 合并逻辑对齐）
            if let incomingMemories = payload["userMemories_v1"] ?? payload["memories_v2"] {
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
                print("记忆合并完成: 新增 \(newAdded) 条, 更新 \(updatedMemCount) 条")
            }

            // 回收站：全量覆盖（Watch 端删除/恢复操作需要在 iPhone 上生效）
            if let incomingTrash = payload["memoryTrash_v1"] ?? payload["deletedMemoriesBin_v1"] {
                let incomingData = try JSONSerialization.data(withJSONObject: incomingTrash)
                let incoming = try JSONDecoder().decode([MemoryItem].self, from: incomingData)
                let encoded = try JSONEncoder().encode(incoming)
                defaults.set(encoded, forKey: "deletedMemoriesBin_v1")
                updated = true
                print("回收站已从 Watch 全量更新 (\(incoming.count) 条)")
            }

            if updated {
                defaults.synchronize()
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Self.configDidUpdateNotification, object: nil)
                    NotificationCenter.default.post(name: Notification.Name("WatchConnectivityDidReceiveFullData"), object: nil)
                }
                print("聊天记录+记忆已从 Watch 写入 UserDefaults")
            }
        } catch {
            print("解析 Watch 发来的数据失败: \(error)")
        }
    }
}
