import SwiftUI

// MARK: - v1.12: 重命名备份弹窗
struct RenameBackupSheet: View {
    @ObservedObject var viewModel: ChatViewModel
    let version: ChatViewModel.BackupVersion
    @Binding var isPresented: Bool
    @State private var newName: String = ""
    @State private var isRenaming = false
    @State private var errorMessage: String? = nil
    
    var body: some View {
        VStack(spacing: 12) {
            Text("重命名备份")
                .font(.headline)
            
            TextField("输入名称...", text: $newName)
                .textInputAutocapitalization(.never)
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            
            Button {
                guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                isRenaming = true
                errorMessage = nil
                Task {
                    let result = await viewModel.renameBackup(key: version.key, name: newName)
                    if result.success {
                        isPresented = false
                    } else {
                        errorMessage = result.message
                        isRenaming = false
                    }
                }
            } label: {
                if isRenaming {
                    ProgressView()
                } else {
                    Text("保存")
                }
            }
            .disabled(isRenaming || newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .onAppear {
            newName = version.customName ?? ""
        }
        .padding()
    }
}
