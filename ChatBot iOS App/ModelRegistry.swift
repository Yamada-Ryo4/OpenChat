import Foundation

struct ModelCapabilityInfo: Sendable {
    var supportsVision: Bool
    var supportsThinking: Bool // 推理/思考模型 (CoT)
    var description: String? = nil
}

/// 本地模型能力数据库
/// 包含主流供应商的模型能力信息
class ModelRegistry {
    static let shared = ModelRegistry()
    
    private let preciseMap: [String: ModelCapabilityInfo] = [:]
    
    // 模糊匹配规则 (正则/关键词)
    // 顺序很重要，越具体的越靠前
    func getCapability(modelId: String) -> ModelCapabilityInfo? {
        let lowerId = modelId.lowercased()
        
        // 1. 尝试精确匹配 (优先)
        if let info = preciseMap[lowerId] {
            return info
        }
        
        // 2. 启发式逻辑 (Heuristic Logic)
        // 默认能力
        var isThinking = false
        var isVision = false
        
        // (A) 判断 Thinking / Reasoning 能力
        if lowerId.contains("thinking") ||
           lowerId.contains("reasoner") ||
           lowerId.contains("reasoning") ||
           lowerId.contains("deepseek-r1") || // R1 系列
           lowerId.contains("dracarys") ||
           lowerId.range(of: #"\bo[13]-"#, options: .regularExpression) != nil || // o1-xxx / o3-xxx
           lowerId.range(of: #"\bo[13]$"#, options: .regularExpression) != nil ||  // 精确 o1 / o3
           lowerId.contains("cot") ||
           lowerId.contains("qvq") ||         // QwQ is visual reasoning
           lowerId.contains("gemini-3") ||    // Gemini 3 series usually supports reasoning
           lowerId.contains("gemini-2.5-pro") ||
           lowerId.contains("qwq") {
            isThinking = true
        }
        
        // (B) 判断 Vision 能力
        if lowerId.contains("gpt") ||
           lowerId.contains("vision") ||
           lowerId.contains("vl") ||
           lowerId.contains("claude") ||    // Claude 3 all support vision
           lowerId.contains("gemini") ||      // Modern Gemini supports vision
           lowerId.contains("llava") ||
           lowerId.contains("vila") ||
           lowerId.contains("neva") ||
           lowerId.contains("fuyu") ||
           lowerId.contains("paligemma") ||
           lowerId.contains("multimodal") ||
           lowerId.contains("image") ||
           lowerId.contains("qvq") ||
           lowerId.range(of: #"\bo[134]-"#, options: .regularExpression) != nil {  // o1/o3/o4-mini 系列
            isVision = true
        }
        
        // (C) 特殊修正 / 排除 (Known Exceptions not in preciseMap)
        // o1-preview / o1-mini: Vision = False (If not caught by preciseMap)
        if lowerId.contains("o1-preview") || lowerId.contains("o1-mini") {
            isVision = false 
        }
        
        // DeepSeek-R1 (Pure) usually Text Only, unless specified Distill/Vision
        if lowerId.contains("deepseek-r1") && !lowerId.contains("distill") && !lowerId.contains("vision") {
            // R1 is text-only reasoning usually
            isVision = false
        }
        
        // QwQ is visual reasoning? Actually QwQ is text-reasoning, QVQ is visual.
        // QVQ: Vision=True, Thinking=True (handled above)
        // QwQ: Vision=False? (Usually).
        if lowerId.contains("qwq") {
            isVision = false // QwQ is text reasoning
        }
        if lowerId.contains("qvq") {
            isVision = true // QVQ is visual reasoning
            isThinking = true
        }

        // Return inferred capability
        if isThinking || isVision {
             return .init(supportsVision: isVision, supportsThinking: isThinking)
        }
        
        return nil // 未命中，返回 nil
    }
}
