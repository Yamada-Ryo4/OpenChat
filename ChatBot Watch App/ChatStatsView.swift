import SwiftUI

// MARK: - 消息统计视图 (v1.5)

struct ChatStatsView: View {
    let message: ChatMessage
    
    var body: some View {
        // 直接显示时间统计，不再分页
        List {
            Section("时间统计") {
                if let latency = message.firstTokenLatencyMs {
                    HStack {
                        Image(systemName: "bolt")
                            .foregroundColor(.yellow)
                        Text("首 Token")
                        Spacer()
                        Text(formatMs(latency))
                            .foregroundColor(.secondary)
                    }
                }
                
                if let genTime = message.generationTimeMs {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.cyan)
                        Text("生成时间")
                        Spacer()
                        Text(formatMs(genTime))
                            .foregroundColor(.secondary)
                    }
                }
                
                if let total = message.totalTimeMs {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(.purple)
                        Text("总时间")
                        Spacer()
                        Text(formatMs(total))
                            .foregroundColor(.secondary)
                    }
                }
                
                if message.firstTokenLatencyMs == nil && message.generationTimeMs == nil && message.totalTimeMs == nil {
                     Text("暂无时间数据")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("统计信息")
    }
    
    // 辅助函数：格式化毫秒
    private func formatMs(_ ms: Int) -> String {
        if ms < 1000 {
            return "\(ms) ms"
        } else {
            return String(format: "%.2f s", Double(ms) / 1000.0)
        }
    }
    
}

// MARK: - 会话统计视图
struct SessionStatsView: View {
    let session: ChatSession
    
    var body: some View {
        List {
            Section("消息统计") {
                HStack {
                    Text("消息数量")
                    Spacer()
                    Text("\(session.messages.count)")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("最后更新")
                    Spacer()
                    Text(session.lastModified.formatted(date: .numeric, time: .shortened))
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            
            if let note = session.note, !note.isEmpty {
                Section("备注") {
                    Text(note)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("会话统计")
    }
}
