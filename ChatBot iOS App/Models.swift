import Foundation
import SwiftUI

// MARK: - 基础枚举

enum APIType: String, Codable, Sendable, CaseIterable, Identifiable {
    case openAI = "OpenAI 兼容"
    case gemini = "Google Gemini"
    case openAIResponses = "OpenAI Responses"
    case anthropic = "Anthropic"
    case workersAI = "Workers AI"
    var id: String { rawValue }
}

enum Role: String, Codable, Sendable {
    case user
    case assistant
    case system
    var apiValue: String { rawValue }
}

// MARK: - 核心数据结构

struct ChatMessage: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var role: Role
    var text: String
    var imageData: Data? = nil
    var thinkingContent: String? = nil
    var isThinkingExpanded: Bool = false
    
    // v1.5: 时间统计
    var sendTime: Date? = nil         // 发送时间
    var firstTokenTime: Date? = nil   // 首 Token 到达时间
    var completeTime: Date? = nil     // 完成时间
    
    // 计算属性：首 Token 延迟（毫秒）
    var firstTokenLatencyMs: Int? {
        guard let send = sendTime, let first = firstTokenTime else { return nil }
        return Int(first.timeIntervalSince(send) * 1000)
    }
    
    // 计算属性：生成时间（毫秒）
    var generationTimeMs: Int? {
        guard let first = firstTokenTime, let complete = completeTime else { return nil }
        return Int(complete.timeIntervalSince(first) * 1000)
    }
    
    // 计算属性：总时间（毫秒）
    var totalTimeMs: Int? {
        guard let send = sendTime, let complete = completeTime else { return nil }
        return Int(complete.timeIntervalSince(send) * 1000)
    }
}

// v1.8.6: Markdown 渲染模式
enum MarkdownRenderMode: String, Codable, CaseIterable, Identifiable {
    case realtime = "实时渲染"         // 流式时实时渲染
    case onComplete = "完成后渲染"     // 完成后自动渲染
    case manual = "手动渲染"           // 仅手动触发渲染
    
    var id: String { rawValue }
}

// v1.6: 主题配色
enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case classic = "经典"     // 绿色用户 + 灰色AI
    case ocean   = "海洋"     // 蓝色用户 + 深蓝AI
    case purple  = "紫韵"     // 紫色用户 + 深紫AI
    case sunset  = "日落"     // 橙色用户 + 暖灰AI
    
    var id: String { rawValue }
    
    var userBubbleColor: Color {
        switch self {
        case .classic: return Color.green
        case .ocean:   return Color(red: 0.2, green: 0.5, blue: 0.9)
        case .purple:  return Color(red: 0.6, green: 0.3, blue: 0.85)
        case .sunset:  return Color(red: 0.95, green: 0.5, blue: 0.2)
        }
    }
    
    var botBubbleColor: Color {
        switch self {
        case .classic: return Color.gray.opacity(0.3)
        case .ocean:   return Color(red: 0.12, green: 0.2, blue: 0.35)
        case .purple:  return Color(red: 0.2, green: 0.15, blue: 0.3)
        case .sunset:  return Color(red: 0.25, green: 0.2, blue: 0.18)
        }
    }
    
    var accentColor: Color {
        switch self {
        case .classic: return Color.blue
        case .ocean:   return Color(red: 0.3, green: 0.7, blue: 1.0)
        case .purple:  return Color(red: 0.75, green: 0.5, blue: 1.0)
        case .sunset:  return Color(red: 1.0, green: 0.6, blue: 0.3)
        }
    }
    
    // 用于设置页颜色预览的小圆点
    var previewColors: [Color] {
        [userBubbleColor, botBubbleColor]
    }
}

struct ChatSession: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var messages: [ChatMessage]
    var lastModified: Date
    var note: String? = nil  // v1.5: 自定义备注
}

struct ProviderConfig: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var baseURL: String
    var apiKeys: [String] = []           // 支持多个 API Key
    var currentKeyIndex: Int = 0          // 当前使用的 Key 索引
    var isPreset: Bool
    var icon: String
    var apiType: APIType = .openAI
    var availableModels: [AIModelInfo] = []  // 所有可用模型（从 API 获取）
    var favoriteModelIds: [String] = []       // 收藏的模型 ID
    var isValidated: Bool = false
    var lastUsedModelId: String? = nil        // 最近使用的模型 ID
    var modelsLastFetched: Date? = nil        // 模型列表上次获取时间（用于缓存）
    
    // 向后兼容：savedModels 映射到 availableModels
    var savedModels: [AIModelInfo] {
        get { availableModels }
        set { availableModels = newValue }
    }
    
    // 兼容性：保留单 Key 访问接口
    var apiKey: String {
        get { apiKeys.isEmpty ? "" : apiKeys[min(currentKeyIndex, max(0, apiKeys.count - 1))] }
        set {
            if apiKeys.isEmpty { apiKeys = [newValue] }
            else if currentKeyIndex < apiKeys.count { apiKeys[currentKeyIndex] = newValue }
            else { apiKeys.append(newValue) }
        }
    }
    
    // 轮询到下一个 Key
    mutating func rotateKey() {
        guard apiKeys.count > 1 else { return }
        currentKeyIndex = (currentKeyIndex + 1) % apiKeys.count
    }
    
    // 检查模型是否被收藏
    func isModelFavorited(_ modelId: String) -> Bool {
        favoriteModelIds.contains(modelId)
    }
    
    // 切换模型收藏状态
    mutating func toggleFavorite(_ modelId: String) {
        if let index = favoriteModelIds.firstIndex(of: modelId) {
            favoriteModelIds.remove(at: index)
        } else {
            favoriteModelIds.append(modelId)
        }
    }
    
    // 合并新获取的模型列表，保留已收藏或手动添加的自定义模型
    mutating func mergeModels(fetchedModels: [AIModelInfo]) {
        var merged = fetchedModels
        let fetchedIDs = Set(fetchedModels.map { $0.id })
        
        for existing in self.availableModels {
            let isCustom = existing.isCustom == true
            let isFav = self.favoriteModelIds.contains(existing.id)
            
            if (isCustom || isFav) && !fetchedIDs.contains(existing.id) {
                merged.append(existing)
            }
        }
        self.availableModels = merged
        
        let validIDs = Set(merged.map { $0.id })
        self.favoriteModelIds = self.favoriteModelIds.filter { validIDs.contains($0) }
    }
    
    // 兼容旧数据的初始化器
    init(name: String, baseURL: String, apiKey: String, isPreset: Bool, icon: String, apiType: APIType = .openAI, savedModels: [AIModelInfo] = [], isValidated: Bool = false) {
        self.name = name
        self.baseURL = baseURL
        self.apiKeys = apiKey.isEmpty ? [] : [apiKey]
        self.currentKeyIndex = 0
        self.isPreset = isPreset
        self.icon = icon
        self.apiType = apiType
        self.availableModels = savedModels
        self.favoriteModelIds = savedModels.map { $0.id }  // 初始预设模型默认收藏
        self.isValidated = isValidated
    }
}

struct AIModelInfo: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var displayName: String?
    var isCustom: Bool? // 是否为用户手动添加的模型
    var name: String { id }
}

// MARK: - 配置导出/导入结构

struct ExportableConfig: Codable {
    var providers: [ProviderConfig]
    var selectedGlobalModelID: String
    var temperature: Double
    var historyMessageCount: Int
    var customSystemPrompt: String // 补回字段
    var thinkingMode: ThinkingMode = .auto // v1.6: 全局思考模式策略
    var modelSettings: [String: ModelSettings] = [:] // v1.7: 模型级设置
    var memories: [MemoryItem]? = nil // v1.7: 记忆数据（可选）
    var sessions: [ChatSession]? = nil // v1.7: 聊天记录（可选）
    var helperGlobalModelID: String? = nil // v1.7: 辅助模型 ID
    var embeddingDimension: Int? = nil // v1.8: 记忆向量维度
    // v1.12: 补齐的配置字段
    var embeddingProviderID: String? = nil    // 向量供应商 ID
    var embeddingModelID: String? = nil       // 向量模型 ID
    var workersAIEmbeddingURL: String? = nil  // Workers AI 端点
    var cloudBackupURL: String? = nil         // 云备份地址
    var cloudBackupAuthKey: String? = nil     // 云备份认证密钥
    var memoryEnabled: Bool? = nil            // 记忆功能开关
}

// MARK: - 模型能力配置 (v1.7)
enum CapabilityState: String, Codable, Sendable, CaseIterable, Identifiable {
    case auto = "自动"
    case enabled = "开启"
    case disabled = "关闭"
    
    var id: String { rawValue }
}

struct ModelSettings: Codable, Hashable, Sendable {
    var thinking: CapabilityState = .auto
    var vision: CapabilityState = .auto
}

// MARK: - 思考模式 (v1.6) -> 全局策略
enum ThinkingMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case auto = "自动 / 跟随模型"
    case enabled = "强制开启"
    case disabled = "强制关闭"
    
    var id: String { rawValue }
}

// MARK: - 记忆系统 (v1.7 -> v1.8 双轨升级)

enum MemoryType: String, Codable, Sendable, CaseIterable, Identifiable {
    case shortTerm = "临时"
    case longTerm = "长期"
    var id: String { rawValue }
}

struct MemoryItem: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var content: String          // 记忆内容（如"用户有两只猫"）
    var createdAt: Date          // 创建时间
    var source: String? = nil    // 来源会话标题（可选）
    var embedding: [Float]? = nil // v1.7: 向量嵌入
    var importance: Float = 0.5  // v1.7: 重要性评分 (0.0-1.0)
    // v1.8: 双轨记忆新字段
    var type: MemoryType = .longTerm       // 默认长期（兼容旧数据）
    var expiration: Date? = nil            // 临时记忆过期时间（长期为 nil）
    var lastUpdated: Date? = nil           // 最后更新时间（用于 LRU 淘汰）
    var deletedAt: Date? = nil             // v2.1: 非 nil 表示在回收站
    
    /// 是否已过期
    var isExpired: Bool {
        guard let exp = expiration else { return false }
        return Date() > exp
    }
}
