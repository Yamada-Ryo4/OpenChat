import SwiftUI
import UIKit

@main
struct ChatBotApp: App {
    @StateObject private var viewModel = ChatViewModel()
    @Environment(\.scenePhase) private var scenePhase
    /// 后台任务标识符，用于保活 LLM 流式响应
    @State private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    init() {
        WatchSessionManager.shared.activate()
    }

    var preferredScheme: ColorScheme? {
        switch viewModel.preferredColorSchemeRaw {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil  // system default
        }
    }

    var body: some Scene {
        WindowGroup {
            SideMenuContainer(isSidebarVisible: $viewModel.isSidebarVisible) {
                ChatView()
            } sidebarContent: {
                SidebarView(viewModel: viewModel)
            }
            .environmentObject(viewModel)
            .preferredColorScheme(preferredScheme)
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    viewModel.performAutoBackupIfNeeded()
                    // 回到前台时结束后台任务
                    endBackgroundTaskIfNeeded()
                case .background:
                    // 如果正在生成 LLM 回复，申请后台保活（~30s）
                    if viewModel.isLoading {
                        beginBackgroundKeepAlive()
                    }
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
            // 监听 isLoading：若后台任务还在、但生成已完成，立即释放
            .onChange(of: viewModel.isLoading) { _, newValue in
                if !newValue {
                    endBackgroundTaskIfNeeded()
                }
            }
        }
    }
    
    // MARK: - 后台保活
    private func beginBackgroundKeepAlive() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "LLMStreaming") {
            // 系统即将到期，主动结束
            self.endBackgroundTaskIfNeeded()
        }
        print("🔋 [Background] 申请后台保活: \(backgroundTaskID)")
    }
    
    private func endBackgroundTaskIfNeeded() {
        guard backgroundTaskID != .invalid else { return }
        print("🔋 [Background] 释放后台任务: \(backgroundTaskID)")
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
}
