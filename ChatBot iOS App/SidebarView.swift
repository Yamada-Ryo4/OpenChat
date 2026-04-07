import SwiftUI
import PhotosUI

struct SidebarView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var showSettings = false
    @State private var showAvatarPicker = false
    @State private var showingRenameAlert = false
    @State private var sessionToRename: ChatSession?
    @State private var newSessionTitle = ""

    var userAvatar: Image {
        if let data = viewModel.userAvatarData, let uiImg = UIImage(data: data) {
            return Image(uiImage: uiImg)
        }
        return Image(systemName: "person.crop.circle.fill")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: Search + New Chat
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("搜索", text: $viewModel.searchText)
                }
                .padding(8)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(10)

                Button {
                    viewModel.createNewSession()
                    withAnimation { viewModel.isSidebarVisible = false }
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 20))
                        .foregroundColor(.primary)
                }
            }
            .padding()

            // Session List
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if viewModel.filteredSessions.isEmpty {
                        Text("无历史记录")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(viewModel.filteredSessions) { session in
                            Button(action: {
                                viewModel.currentSessionId = session.id
                                withAnimation { viewModel.isSidebarVisible = false }
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(session.title)
                                            .font(.body)
                                            .lineLimit(1)
                                            .foregroundColor(.primary)
                                        Text(session.lastModified.formatted(date: .numeric, time: .shortened))
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    viewModel.currentSessionId == session.id ?
                                    Color(UIColor.secondarySystemBackground) : Color.clear
                                )
                                .cornerRadius(12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    sessionToRename = session
                                    newSessionTitle = session.title
                                    showingRenameAlert = true
                                } label: {
                                    Label("重命名", systemImage: "pencil")
                                }
                                
                                Button(role: .destructive) {
                                    if let index = viewModel.sessions.firstIndex(where: { $0.id == session.id }) {
                                        let indexSet = IndexSet(integer: index)
                                        viewModel.deleteSession(at: indexSet)
                                    }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 10) // Margin from sidebar edges for card appearance
            }

            // Footer: User Profile / Settings (no Divider)
            Button(action: { showSettings = true }) {
                HStack(spacing: 12) {
                    // Avatar
                    userAvatar
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                        .foregroundColor(.gray)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.userName.isEmpty ? "用户" : viewModel.userName)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("设置")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "ellipsis")
                        .foregroundColor(.gray)
                }
                .padding()
            }
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView(viewModel: viewModel) }
        }
        .alert("重命名对话", isPresented: $showingRenameAlert) {
            TextField("新标题", text: $newSessionTitle)
            Button("取消", role: .cancel) { }
            Button("保存") {
                if let session = sessionToRename {
                    viewModel.renameSession(id: session.id, newTitle: newSessionTitle)
                }
            }
        }
    }
}
