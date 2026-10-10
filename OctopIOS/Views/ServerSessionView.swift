import SwiftUI

/// 进入一台服务器：有 token 直接进控制台，没有就走登录页。
struct ServerSessionView: View {
    @EnvironmentObject private var store: ServerStore

    /// 进来时传入的 server；地址可能被编辑过，所以取值时优先读 store 里的最新版本。
    let server: OctopServer

    @State private var token: String?
    @State private var showEdit = false

    private var currentServer: OctopServer {
        store.servers.first { $0.id == server.id } ?? server
    }

    var body: some View {
        Group {
            if let token {
                ConsoleView(server: currentServer,
                            token: token,
                            onLogout: { logout() },
                            onEditServer: { showEdit = true })
            } else {
                LoginView(server: currentServer, onSuccess: { newToken in
                    token = newToken
                    store.touch(currentServer)
                })
            }
        }
        .onAppear {
            if token == nil {
                token = store.token(for: server)
            }
        }
        .sheet(isPresented: $showEdit) {
            ServerEditView(server: currentServer)
        }
    }

    private func logout() {
        store.clearToken(for: currentServer)
        token = nil
    }
}
