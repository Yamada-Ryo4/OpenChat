//
//  MemoryTrashView.swift
//  ChatBot iOS App
//

import SwiftUI

struct MemoryTrashView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var showingClearConfirmation = false
    
    var body: some View {
        List {
            if viewModel.deletedMemoriesBin.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "trash")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("回收站为空")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            } else {
                Section(header: Text("已删除的记忆").textCase(nil)) {
                    ForEach(viewModel.deletedMemoriesBin.indices, id: \.self) { index in
                        let memory = viewModel.deletedMemoriesBin[index]
                        VStack(alignment: .leading, spacing: 6) {
                            Text(memory.content)
                                .font(.body)
                                .lineLimit(3)
                            
                            HStack {
                                if let source = memory.source {
                                    Text(source)
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if let deletedAt = memory.deletedAt {
                                    Text("删除于: \(deletedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption2)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                viewModel.restoreMemory(at: index)
                            } label: {
                                Label("恢复", systemImage: "arrow.uturn.left")
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.permanentlyDeleteMemory(at: index)
                            } label: {
                                Label("彻底删除", systemImage: "trash.slash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("记忆回收站")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !viewModel.deletedMemoriesBin.isEmpty {
                    Button(role: .destructive) {
                        showingClearConfirmation = true
                    } label: {
                        Image(systemName: "trash.fill")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .alert("清空回收站", isPresented: $showingClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                viewModel.emptyRecycleBin()
            }
        } message: {
            Text("确定要彻底删除回收站里的所有记忆吗？此操作无法撤销。")
        }
    }
}
