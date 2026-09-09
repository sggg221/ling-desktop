import Foundation
import Security
import SwiftUI
import LingCore

enum KeychainStore {
    private static let service = "chat.uboxya.LingDesktop"
    private static let account = "ant-ling-api-key"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func read() throws -> String {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw KeychainError(status: status)
        }
        return key
    }

    static func save(_ key: String) throws {
        if key.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError(status: status)
            }
            return
        }
        let update = [kSecValueData as String: Data(key.utf8)]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = Data(key.utf8)
            item[kSecAttrLabel as String] = "百灵视觉助手 API Key"
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        "钥匙串错误（\(status)）：\(SecCopyErrorMessageString(status, nil) as String? ?? "无法访问钥匙串")"
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var baseURL: String
    @Published private(set) var model: String
    @Published private(set) var apiKey = ""
    @Published private(set) var loadError: String?
    private let defaults: UserDefaults
    private let saveKey: (String) throws -> Void

    init(defaults: UserDefaults = .standard,
         readKey: () throws -> String = KeychainStore.read,
         saveKey: @escaping (String) throws -> Void = KeychainStore.save) {
        self.defaults = defaults
        self.saveKey = saveKey
        baseURL = defaults.string(forKey: "lingBaseURL") ?? LingConfiguration().baseURL
        model = defaults.string(forKey: "lingModel") ?? "Ling-3.0-flash-VL"
        do { apiKey = try readKey() }
        catch { loadError = error.localizedDescription }
    }

    var configuration: LingConfiguration {
        LingConfiguration(baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                          model: model.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func save(configuration: LingConfiguration, apiKey: String) throws {
        let configuration = LingConfiguration(
            baseURL: configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            model: configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        try configuration.validate()
        try saveKey(key)
        defaults.set(configuration.baseURL, forKey: "lingBaseURL")
        defaults.set(configuration.model, forKey: "lingModel")
        baseURL = configuration.baseURL
        model = configuration.model
        self.apiKey = key
        loadError = nil
    }
}
