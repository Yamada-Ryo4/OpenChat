import SwiftUI

struct CloudImportSelectionView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var fetchedConfig: ExportableConfig? = nil
    @State private var isLoading = false
    @State private var errorMsg: String? = nil
    
    // 默认全选
    @State private var selectedOptions: Set<ChatViewModel.ImportOption> = Set(ChatViewModel.ImportOption.allCases)
    
    var body: some View {
        Form {
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("正在获取云端配置...")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            } else if let error = errorMsg {
                Section {
                    VStack(alignment: .leading) {
                        Text("获取失败").font(.headline).foregroundColor(.red)
                        Text(error).font(.caption2).foregroundColor(.secondary)
                    }
                    Button("重试") { loadConfig() }
                }
            } else if let config = fetchedConfig {
                // 数据类
                Section(header: Text("数据")) {
                    importRow(.providers, config: config)
                    importRow(.memories, config: config)
                    importRow(.sessions, config: config)
                }
                
                // 配置类
                Section(header: Text("配置"), footer: Text("仅导入选中项，保留本地原有数据")) {
                    importRow(.modelParams, config: config)
                    importRow(.embeddingConfig, config: config)
                    importRow(.cloudConfig, config: config)
                    importRow(.helperModel, config: config)
                    importRow(.modelSettings, config: config)
                }
                
                Section {
                    Button {
                        performImport()
                    } label: {
                        HStack {
                            Spacer()
                            Text("开始合并导入 (\(selectedOptions.count) 项)")
                                .bold()
                            Spacer()
                        }
                    }
                    .disabled(selectedOptions.isEmpty)
                    .listItemTint(.blue)
                }
            }
        }
        .navigationTitle("选择导入")
        .onAppear { loadConfig() }
    }
    
    // MARK: - 行组件
    
    @ViewBuilder
    private func importRow(_ option: ChatViewModel.ImportOption, config: ExportableConfig) -> some View {
        Button {
            toggle(option)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.rawValue)
                    Text(detailText(for: option, config: config))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if selectedOptions.contains(option) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.gray)
                }
            }
        }
    }
    
    private func toggle(_ option: ChatViewModel.ImportOption) {
        if selectedOptions.contains(option) {
            selectedOptions.remove(option)
        } else {
            selectedOptions.insert(option)
        }
    }
    
    // MARK: - 网络
    
    private func loadConfig() {
        isLoading = true
        errorMsg = nil
        Task {
            do {
                let config = try await viewModel.fetchConfigFromCloud()
                await MainActor.run {
                    self.fetchedConfig = config
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMsg = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func performImport() {
        guard let config = fetchedConfig else { return }
        do {
            try viewModel.mergeConfig(from: config, options: selectedOptions)
            Task { @MainActor in
                viewModel.cloudUploadStatus = "✅ 已导入 \(selectedOptions.count) 项"
                dismiss()
            }
        } catch {
            Task { @MainActor in
                viewModel.cloudUploadStatus = "❌ 导入失败: \(error.localizedDescription)"
                dismiss()
            }
        }
    }
    
    // MARK: - 详情文本
    
    private func detailText(for option: ChatViewModel.ImportOption, config: ExportableConfig) -> String {
        switch option {
        case .providers:
            return "云端 \(config.providers.count) 个供应商"
        case .memories:
            return "云端 \(config.memories?.count ?? 0) 条记忆"
        case .sessions:
            return "云端 \(config.sessions?.count ?? 0) 条对话"
        case .modelParams:
            return "温度 \(String(format: "%.1f", config.temperature)), 历史 \(config.historyMessageCount) 条, \(config.thinkingMode.rawValue)"
        case .embeddingConfig:
            var parts: [String] = []
            if let pid = config.embeddingProviderID {
                parts.append(pid == "workersAI" ? "Workers AI" : "自定义供应商")
            }
            if let mid = config.embeddingModelID, !mid.isEmpty {
                // 截取模型名最后一段
                let shortName = mid.components(separatedBy: "/").last ?? mid
                parts.append(shortName)
            }
            if let dim = config.embeddingDimension, dim > 0 {
                parts.append("\(dim)d")
            }
            return parts.isEmpty ? "未配置" : parts.joined(separator: " · ")
        case .cloudConfig:
            if let curl = config.cloudBackupURL {
                let short = curl.replacingOccurrences(of: "https://", with: "")
                return short
            }
            return "未配置"
        case .helperModel:
            if let hid = config.helperGlobalModelID, !hid.isEmpty {
                let shortName = hid.components(separatedBy: "/").last ?? hid
                return shortName
            }
            return "未设置"
        case .modelSettings:
            let count = config.modelSettings.count
            return count > 0 ? "\(count) 个模型的能力设置" : "无自定义"
        }
    }
}
