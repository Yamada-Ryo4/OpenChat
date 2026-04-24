import SwiftUI
import Combine

class SyncService: ObservableObject {
    static let shared = SyncService()
    
    private let kvs = NSUbiquitousKeyValueStore.default
    
    // 需要同步的 Keys
    private let syncKeys = [
        "savedProviders_v3",
        "savedProviders_v3_gemini", // 兼容旧Key
        "selectedGlobalModelID",
        "showModelNameInNavBar",
        "showScrollToBottomButton",
        "chatSessions_v1" // 新增：同步聊天记录
    ]
    
    private init() {
        // 监听 iCloud 变更通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didChangeExternally),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs
        )
        // 尝试首次同步
        kvs.synchronize()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    /// 上传本地数据到 iCloud
    func upload() {
        for key in syncKeys {
            if let data = UserDefaults.standard.object(forKey: key) {
                kvs.set(data, forKey: key)
            }
        }
        kvs.synchronize()
        print("☁️ [SyncService] Uploaded to iCloud")
    }
    
    /// 从 iCloud 下载并应用到本地 UserDefaults
    /// 返回 true 表示有数据更新
    @objc func didChangeExternally(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonForChange = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int,
              let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] else {
            return
        }
        
        // 只处理 ServerChange (1) 或 InitialSync (2)
        guard reasonForChange == NSUbiquitousKeyValueStoreServerChange || reasonForChange == NSUbiquitousKeyValueStoreInitialSyncChange else {
            return
        }
        
        print("☁️ [SyncService] Cloud changes detected: \(changedKeys)")
        
        var hasRelevantChanges = false
        
        for key in changedKeys {
            if syncKeys.contains(key) {
                // 如果云端有值，才覆盖本地
                if let cloudValue = kvs.object(forKey: key) {
                    UserDefaults.standard.set(cloudValue, forKey: key)
                    hasRelevantChanges = true
                }
            }
        }
        
        if hasRelevantChanges {
            // 发出通知让 ViewModel 刷新
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .init("CloudDataDidUpdate"), object: nil)
            }
        }
    }
}
