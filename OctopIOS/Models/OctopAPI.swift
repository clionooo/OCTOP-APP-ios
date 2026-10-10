import Foundation

// MARK: - 服务端返回的数据结构（只解我们要用的字段，多余字段忽略）

struct OctopUser: Codable, Hashable {
    let id: Int?
    let username: String
    let role: String?
    let displayName: String?
    let locale: String?

    enum CodingKeys: String, CodingKey {
        case id, username, role, locale
        case displayName = "display_name"
    }

    var friendlyName: String {
        if let name = displayName, !name.isEmpty { return name }
        return username
    }

    var roleLabel: String {
        switch (role ?? "").lowercased() {
        case "admin": return "管理员"
        case "user": return "成员"
        default: return role ?? "成员"
        }
    }
}

struct SetupStatus {
    let setupRequired: Bool
}

extension SetupStatus: Decodable {
    enum CodingKeys: String, CodingKey { case setupRequired = "setup_required" }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        setupRequired = (try? container.decode(Bool.self, forKey: .setupRequired)) ?? false
    }
}

struct CaptchaPublic {
    let provider: String
    let siteKey: String?

    /// 服务端是否启用了登录验证码；启用了原生登录就没法走，得退回网页登录。
    var isEnabled: Bool {
        let value = provider.lowercased()
        return !(value.isEmpty || value == "none" || value == "off" || value == "disabled" || value == "false")
    }
}

extension CaptchaPublic: Decodable {
    enum CodingKeys: String, CodingKey {
        case provider
        case siteKey = "site_key"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = (try? container.decode(String.self, forKey: .provider)) ?? "none"
        siteKey = (try? container.decodeIfPresent(String.self, forKey: .siteKey)) ?? nil
    }
}

struct LoginResponse: Decodable {
    let accessToken: String
    let expiresIn: Int?
    let user: OctopUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case user
    }
}

// MARK: - 错误

enum OctopAPIError: LocalizedError {
    case badAddress
    case network(String)
    case http(Int, String)
    case decoding(String)
    case notLoggedIn

    var errorDescription: String? {
        switch self {
        case .badAddress:
            return "服务器地址格式不对"
        case .network(let message):
            return message
        case .http(let code, let message):
            if code == 401 || code == 403 { return message.isEmpty ? "用户名或密码不正确" : message }
            return "\(message)（HTTP \(code)）"
        case .decoding(let message):
            return "返回内容无法解析：\(message)"
        case .notLoggedIn:
            return "登录状态已失效，请重新登录"
        }
    }
}

// MARK: - 客户端

/// Octop 的 HTTP 客户端。基地址是 `<服务器地址>/api`。
final class OctopAPI {
    private let base: String
    private let session: URLSession

    init(baseAddress: String, allowInsecureTLS: Bool) {
        self.base = baseAddress
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 30
        config.httpAdditionalHeaders = ["Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8"]
        self.session = URLSession(configuration: config,
                                  delegate: InsecureTLSDelegate(allow: allowInsecureTLS),
                                  delegateQueue: nil)
    }

    // MARK: 接口

    func setupStatus() async throws -> SetupStatus {
        try await send(makeRequest("/setup/status", method: "GET"))
    }

    func captchaConfig() async throws -> CaptchaPublic {
        try await send(makeRequest("/auth/captcha", method: "GET"))
    }

    func login(username: String, password: String, captchaToken: String? = nil) async throws -> LoginResponse {
        var request = try makeRequest("/auth/login", method: "POST")
        var body: [String: Any] = ["username": username, "password": password]
        if let captchaToken, !captchaToken.isEmpty { body["captcha_token"] = captchaToken }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    func me(token: String) async throws -> OctopUser {
        var request = try makeRequest("/auth/me", method: "GET")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    func logout(token: String) async {
        guard var request = try? makeRequest("/auth/logout", method: "POST") else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await session.data(for: request)
    }

    // MARK: 内部

    private func makeRequest(_ path: String, method: String) throws -> URLRequest {
        guard let url = URL(string: base + "/api" + path) else { throw OctopAPIError.badAddress }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if method != "GET" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw OctopAPIError.network(Self.describe(error))
        } catch {
            throw OctopAPIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OctopAPIError.network("服务器返回了无效响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw OctopAPIError.http(http.statusCode, Self.extractMessage(from: data) ?? "用户名或密码不正确")
            }
            throw OctopAPIError.http(http.statusCode, Self.extractMessage(from: data) ?? "请求失败")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw OctopAPIError.decoding(error.localizedDescription)
        }
    }

    /// Octop 的错误体可能是 {detail} / {message} / {error}，字符串或对象都要能认。
    static func extractMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else { return nil }

        if let text = dictionary["detail"] as? String, !text.isEmpty { return text }
        if let text = dictionary["message"] as? String, !text.isEmpty { return text }
        if let text = dictionary["error"] as? String, !text.isEmpty { return text }

        if let detail = dictionary["detail"] as? [String: Any] {
            if let text = detail["message"] as? String, !text.isEmpty { return text }
            if let text = detail["detail"] as? String, !text.isEmpty { return text }
        }
        if let error = dictionary["error"] as? [String: Any],
           let text = error["message"] as? String, !text.isEmpty { return text }

        return nil
    }

    /// 把 URLError 翻成用户看得懂的中文。
    static func describe(_ error: URLError) -> String {
        switch error.code {
        case .cannotConnectToHost:
            return "连不上服务器，请确认地址、端口以及 Octop 是否在运行"
        case .cannotFindHost, .dnsLookupFailed:
            return "找不到这个主机名，请检查地址是否写错"
        case .timedOut:
            return "连接超时，服务器没有响应"
        case .notConnectedToInternet:
            return "手机当前没有网络"
        case .networkConnectionLost:
            return "网络连接中断，请重试"
        case .serverCertificateUntrusted,
             .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .secureConnectionFailed:
            return "服务器证书不被信任（自签名证书），请到「设置」开启「允许自签名证书」"
        case .appTransportSecurityRequiresSecureConnection:
            return "系统安全策略拦截了明文请求"
        case .cancelled:
            return "请求已取消"
        default:
            return error.localizedDescription
        }
    }
}

/// 允许自签名证书时放行服务端信任校验。
private final class InsecureTLSDelegate: NSObject, URLSessionDelegate {
    private let allow: Bool
    init(allow: Bool) { self.allow = allow }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard allow,
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
