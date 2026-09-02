import Foundation
import Security

/// API keys, in the Keychain.
///
/// Not UserDefaults: keys entered here are the user's own paid credentials, and
/// UserDefaults is a plist in the app container that ends up in unencrypted backups.
/// `afterFirstUnlock` rather than `whenUnlocked` because image generation can complete
/// while the phone is locked in the user's pocket.
enum CredentialKey: String, CaseIterable, Sendable {
    case anthropic
    case gemini
    case openAI
    case usda

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .gemini: return "Google Gemini"
        case .openAI: return "OpenAI"
        case .usda: return "USDA FoodData Central"
        }
    }

    var purpose: String {
        switch self {
        case .anthropic: return "The conversation"
        case .gemini: return "Food photography"
        case .openAI: return "Food photography (alternative)"
        case .usda: return "Wider nutrition lookup"
        }
    }
}

enum Credentials {
    private static let service = "com.plate.Plate.credentials"

    static func value(for key: CredentialKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8),
              !string.isEmpty
        else { return nil }

        return string
    }

    static func has(_ key: CredentialKey) -> Bool { value(for: key) != nil }

    /// Stores, or removes when `value` is nil or blank.
    static func set(_ value: String?, for key: CredentialKey) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]

        guard let trimmed, !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            SecItemDelete(query as CFDictionary)
            return
        }

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
    }

    /// A redacted form for display: "sk-ant-…4f2a".
    static func redacted(for key: CredentialKey) -> String? {
        guard let value = value(for: key) else { return nil }
        guard value.count > 12 else { return String(repeating: "•", count: value.count) }
        return "\(value.prefix(7))…\(value.suffix(4))"
    }
}
