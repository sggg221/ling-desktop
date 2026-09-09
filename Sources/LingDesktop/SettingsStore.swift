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
    @Published var baseURL: String
    @Published var model: String
    @Published var apiKey = ""
    @Published var loadError: String?

    init() {
        baseURL = UserDefaults.standard.string(forKey: "lingBaseURL") ?? LingConfiguration().baseURL
        model = UserDefaults.standard.string(forKey: "lingModel") ?? "Ling-3.0-flash-VL"
        do { apiKey = try KeychainStore.read() }
        catch { loadError = error.localizedDescription }
    }

    var configuration: LingConfiguration {
        LingConfiguration(baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                          model: model.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func save() throws {
        try KeychainStore.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
        UserDefaults.standard.set(baseURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "lingBaseURL")
        UserDefaults.standard.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "lingModel")
        loadError = nil
    }
}
