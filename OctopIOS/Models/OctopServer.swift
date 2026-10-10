import Foundation

/// 一台已保存的 Octop 服务器。
struct OctopServer: Identifiable, Codable, Hashable {
    var id: String
    /// 用户起的备注名，可为空
    var name: String
    /// 规范化后的地址，例如 http://192.168.1.9:8088
    var address: String
    /// 上次登录用的用户名，用于回填
    var username: String
    var lastUsedAt: Date

    init(id: String = UUID().uuidString,
         name: String = "",
         address: String,
         username: String = "",
         lastUsedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.address = address
        self.username = username
        self.lastUsedAt = lastUsedAt
    }

    var baseURL: URL? { URL(string: address) }

    var hostLabel: String {
        guard let url = URL(string: address), let host = url.host else { return address }
        if let port = url.port { return "\(host):\(port)" }
        return host
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? hostLabel : trimmed
    }

    var schemeIsSecure: Bool {
        address.lowercased().hasPrefix("https://")
    }

    /// 和网页层 location.origin 对比用（省略默认端口）。
    var origin: String? {
        guard let url = URL(string: address),
              let scheme = url.scheme,
              let host = url.host, !host.isEmpty else { return nil }
        var result = "\(scheme.lowercased())://\(host)"
        if let port = url.port, port != 80, port != 443 {
            result += ":\(port)"
        }
        return result
    }

    // MARK: - 地址规范化

    /// 把用户手输的地址变成可用的 URL 字符串。失败返回 nil。
    static func normalize(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // 允许用户粘贴 "192.168.1.9:8088/" 之类
        text = text.replacingOccurrences(of: " ", with: "")
        text = text.replacingOccurrences(of: "\n", with: "")
        text = text.replacingOccurrences(of: "\t", with: "")

        let lower = text.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            text = "http://" + text
        }
        while text.hasSuffix("/") {
            text.removeLast()
        }
        // 用户可能直接贴了控制台地址，去掉常见后缀
        for suffix in ["/index.html", "/dashboard", "/login"] {
            if text.lowercased().hasSuffix(suffix) {
                text.removeLast(suffix.count)
            }
        }
        guard let url = URL(string: text),
              let host = url.host,
              !host.isEmpty else { return nil }
        return text
    }

    /// 没写端口时返回补上默认端口 8089 的地址，用于「测试连接」时的自动重试。
    static func withDefaultPort(_ address: String) -> String? {
        guard let url = URL(string: address), url.port == nil else { return nil }
        let scheme = url.scheme ?? "http"
        guard let host = url.host, !host.isEmpty else { return nil }
        if scheme == "https" { return nil } // 反代域名一般就是 443，不动它
        return "\(scheme)://\(host):8089"
    }
}
