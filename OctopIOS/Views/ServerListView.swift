import SwiftUI

/// 首页：服务器列表。
struct ServerListView: View {
    @EnvironmentObject private var store: ServerStore
    @EnvironmentObject private var settings: AppSettings
    @State private var showAddSheet = false
    @State private var serverToEdit: OctopServer?
    @State private var serverToDelete: OctopServer?

    var body: some View {
        Group {
            if store.servers.isEmpty {
                emptyState
            } else {
                serverList
            }
        }
        .navigationTitle("Octop")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationLink(destination: GlobalSettingsView()) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("设置")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加服务器")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            ServerEditView(server: nil)
        }
        .sheet(item: $serverToEdit) { server in
            ServerEditView(server: server)
        }
        .alert("删除这台服务器？", isPresented: deleteAlertBinding) {
            Button("删除", role: .destructive) {
                if let server = serverToDelete {
                    store.remove(server)
                }
                serverToDelete = nil
            }
            Button("取消", role: .cancel) { serverToDelete = nil }
        } message: {
            Text("会同时清除这台服务器保存的登录状态。")
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { serverToDelete != nil }, set: { if !$0 { serverToDelete = nil } })
    }

    // MARK: 列表

    private var serverList: some View {
        List {
            Section(footer: Text("点一下进入登录 / 控制台，长按可以编辑或删除。")) {
                ForEach(store.servers) { server in
                    NavigationLink(destination: ServerSessionView(server: server)) {
                        ServerRow(server: server, loggedIn: store.isLoggedIn(server))
                    }
                    .contextMenu {
                        Button {
                            serverToEdit = server
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            serverToDelete = server
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: 空态

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 40)

                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 0.11, green: 0.12, blue: 0.29),
                                                      Color(red: 0.43, green: 0.16, blue: 0.85)],
                                             startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                        .frame(width: 104, height: 104)
                        .shadow(color: Color.black.opacity(0.25), radius: 16, y: 8)

                    Circle()
                        .stroke(Color.white, lineWidth: 7)
                        .frame(width: 52, height: 52)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 11, height: 11)
                }

                VStack(spacing: 8) {
                    Text("连接你的 Octop")
                        .font(.title2.bold())

                    Text("填上飞牛上 Octop 的地址（默认端口 8089，反代域名也支持），\n登录一次就能在手机上直接用控制台。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                Button {
                    showAddSheet = true
                } label: {
                    Label("添加服务器", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 40)

                VStack(alignment: .leading, spacing: 10) {
                    Label("直连 http://192.168.8.8:8089，反代填域名", systemImage: "link")
                    Label("账号密码就是 Octop 控制台的登录账号", systemImage: "person")
                    Label(" token 存在本机，不会上传到任何地方", systemImage: "lock.shield")
                }
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

// MARK: - 行

private struct ServerRow: View {
    let server: OctopServer
    let loggedIn: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.11, green: 0.12, blue: 0.29),
                                                  Color(red: 0.43, green: 0.16, blue: 0.85)],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)

                Circle()
                    .stroke(Color.white, lineWidth: 3.5)
                    .frame(width: 21, height: 21)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(server.displayName)
                    .font(.body.weight(.medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(server.address)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if loggedIn {
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("已登录")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("未登录")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
