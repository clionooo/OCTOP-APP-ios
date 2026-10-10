import Foundation

/// 服务器列表 + 每台服务器的登录态。
final class ServerStore: ObservableObject {
    @Published private(set) var servers: [OctopServer] = []

    private let storageKey = "octop.servers.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: 持久化

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([OctopServer].self, from: data) else {
            servers = []
            return
        }
        servers = decoded.sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    private func persist() {
        servers.sort { $0.lastUsedAt > $1.lastUsedAt }
        if let data = try? JSONEncoder().encode(servers) {
            defaults.set(data, forKey: storageKey)
        }
    }

    // MARK: 增删改

    func upsert(_ server: OctopServer) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
        } else {
            servers.append(server)
        }
        persist()
    }

    func remove(_ server: OctopServer) {
        servers.removeAll { $0.id == server.id }
        SecureTokenStore.delete(server.id)
        persist()
    }

    /// 最近使用时间更新，用于列表排序。
    func touch(_ server: OctopServer) {
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else { return }
        servers[index].lastUsedAt = Date()
        persist()
    }

    func rememberUsername(_ username: String, for server: OctopServer) {
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else { return }
        servers[index].username = username
        persist()
    }

    // MARK: 登录态

    func token(for server: OctopServer) -> String? {
        SecureTokenStore.read(server.id)
    }

    func isLoggedIn(_ server: OctopServer) -> Bool {
        token(for: server) != nil
    }

    func saveToken(_ token: String, for server: OctopServer) {
        SecureTokenStore.save(token, for: server.id)
    }

    func clearToken(for server: OctopServer) {
        SecureTokenStore.delete(server.id)
    }
}
