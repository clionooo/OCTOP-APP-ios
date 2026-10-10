import Foundation

/// Keychain 封装。未签名 / TrollStore 安装的应用有时拿不到 keychain entitlement，
/// 所以外面还会套一层 UserDefaults 兜底，见 SecureTokenStore。
enum KeychainStore {
    private static let service = "com.clionooo.octopios.token"

    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)

        var attrs = base
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else { return nil }
        return text
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// 先试 Keychain，失败自动落 UserDefaults。两条路都能读写，保证 JWT 不会丢。
enum SecureTokenStore {
    private static func fallbackKey(_ id: String) -> String { "octop.token." + id }

    static func save(_ token: String, for id: String) {
        let ok = KeychainStore.save(token, account: id)
        if ok && KeychainStore.read(account: id) != nil {
            UserDefaults.standard.removeObject(forKey: fallbackKey(id))
        } else {
            UserDefaults.standard.set(token, forKey: fallbackKey(id))
        }
    }

    static func read(_ id: String) -> String? {
        if let token = KeychainStore.read(account: id), !token.isEmpty { return token }
        let fallback = UserDefaults.standard.string(forKey: fallbackKey(id))
        return (fallback?.isEmpty ?? true) ? nil : fallback
    }

    static func delete(_ id: String) {
        KeychainStore.delete(account: id)
        UserDefaults.standard.removeObject(forKey: fallbackKey(id))
    }
}
