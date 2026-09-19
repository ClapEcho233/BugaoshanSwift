import Foundation
import CryptoKit

/// 存储键名（与 Flutter 版逐字对齐，键名兼容便于代码对照）
enum StorageKeys {
    // Keychain
    static let scuAccessToken = "scu_access_token"
    static let scuPrincipalBinding = "scu_principal_binding_v1"
    static let scuSavedUsername = "scu_saved_username"
    static let scuSavedPassword = "scu_saved_password"
    static let scuRememberPassword = "scu_remember_password"
    static let scuAutoLogin = "scu_auto_login"
    static let zhhqTokenKey = "zhhq_token_key"
    static let ccylSession = "ccyl_session_v2"
    static let ccylTokenLegacy = "ccyl_token"
    static let ccylUserIdLegacy = "ccyl_user_id"

    // UserDefaults
    static let scuLoginTimestamp = "scu_login_timestamp"
    static let scuUserRealname = "scu_user_realname"
    static let scuUserNumber = "scu_user_number"
    static let cachedAcademicCalendarJson = "cached_academic_calendar_json"
}

/// 安全存储协议（Keychain 抽象，便于测试注入内存实现）
protocol SecureStore: Sendable {
    func read(_ key: String) async -> String?
    func write(_ key: String, _ value: String) async
    func delete(_ key: String) async
}

/// Keychain 实现：kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
/// （对应 FlutterSecureStorage first_unlock_this_device）
final class KeychainStore: SecureStore {
    private let service: String

    init(service: String = "io.github.ClapEcho233.BugaoshanSwift") {
        self.service = service
    }

    func read(_ key: String) async -> String? {
        var query = baseQuery(key: key)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ key: String, _ value: String) async {
        let data = Data(value.utf8)
        var query = baseQuery(key: key)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    func delete(_ key: String) async {
        SecItemDelete(baseQuery(key: key) as CFDictionary)
    }

    private func baseQuery(key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}

/// 测试用内存实现
final class InMemorySecureStore: SecureStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]

    func read(_ key: String) async -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    func write(_ key: String, _ value: String) async {
        lock.lock(); defer { lock.unlock() }
        storage[key] = value
    }

    func delete(_ key: String) async {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }
}

/// 偏好存储协议
protocol DefaultsStore: Sendable {
    func string(_ key: String) async -> String?
    func setString(_ key: String, _ value: String?) async
    func int(_ key: String) async -> Int?
    func setInt(_ key: String, _ value: Int?) async
    func remove(_ key: String) async
}

/// UserDefaults 实现（标准库；小组件偏好走 App Group suite，另行构造）
final class UserDefaultsStore: DefaultsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    init(suiteName: String) {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    func string(_ key: String) async -> String? { defaults.string(forKey: key) }
    func setString(_ key: String, _ value: String?) async {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
    func int(_ key: String) async -> Int? {
        let value = defaults.object(forKey: key) as? Int
        return value
    }
    func setInt(_ key: String, _ value: Int?) async {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
    func remove(_ key: String) async { defaults.removeObject(forKey: key) }
}

/// 测试用内存实现
final class InMemoryDefaultsStore: DefaultsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var strings: [String: String] = [:]
    private var ints: [String: Int] = [:]

    func string(_ key: String) async -> String? {
        lock.lock(); defer { lock.unlock() }
        return strings[key]
    }

    func setString(_ key: String, _ value: String?) async {
        lock.lock(); defer { lock.unlock() }
        if let value { strings[key] = value } else { strings.removeValue(forKey: key) }
    }

    func int(_ key: String) async -> Int? {
        lock.lock(); defer { lock.unlock() }
        return ints[key]
    }

    func setInt(_ key: String, _ value: Int?) async {
        lock.lock(); defer { lock.unlock() }
        if let value { ints[key] = value } else { ints.removeValue(forKey: key) }
    }

    func remove(_ key: String) async {
        lock.lock(); defer { lock.unlock() }
        strings.removeValue(forKey: key)
        ints.removeValue(forKey: key)
    }
}

/// principal 绑定的 token 指纹（SHA-256 hex，对应 Dart 版 sha256Hex）
func tokenFingerprint(_ token: String) -> String {
    SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
}
