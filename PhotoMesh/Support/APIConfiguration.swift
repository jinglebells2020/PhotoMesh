import Foundation
import Security

/// Where the recognizer's credentials and model come from.
/// Priority for the key: `OPENROUTER_API_KEY` environment variable (Xcode scheme) → Keychain (entered in Settings).
enum APIConfiguration {
    static let defaultModel = "google/gemini-3.6-flash"
    static let keychainAccount = "openrouter.apiKey"

    static var apiKey: String? {
        if let env = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !env.isEmpty { return env }
        return KeychainStore.read(account: keychainAccount)
    }

    static var isEnvironmentKey: Bool {
        !(ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? "").isEmpty
    }

    static func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.delete(account: keychainAccount)
        } else {
            KeychainStore.write(trimmed, account: keychainAccount)
        }
    }

    static var model: String {
        let stored = UserDefaults.standard.string(forKey: SettingsKeys.openRouterModel) ?? ""
        return stored.isEmpty ? defaultModel : stored
    }

    static var useSampleCircuit: Bool {
        UserDefaults.standard.bool(forKey: SettingsKeys.useSampleCircuit)
    }

    /// Ask the user to check the recognized circuit before solving (default on).
    static var confirmRecognizedCircuits: Bool {
        UserDefaults.standard.object(forKey: SettingsKeys.confirmRecognized) as? Bool ?? true
    }

    /// Low reasoning effort: faster answers, slightly less careful on messy pictures (default off).
    static var fastRecognition: Bool {
        UserDefaults.standard.bool(forKey: SettingsKeys.fastRecognition)
    }
}

/// Number formatting preferences shared by the engine and the UI.
enum FormattingPreferences {
    static var decimalSign: Character {
        UserDefaults.standard.string(forKey: SettingsKeys.decimalSign) == DecimalSign.comma.rawValue ? "," : "."
    }

    static func formatter() -> QuantityFormatter {
        let notationRaw = UserDefaults.standard.string(forKey: SettingsKeys.unitNotation) ?? ""
        let notation: QuantityFormatter.Notation
        switch UnitNotation(rawValue: notationRaw) ?? .engineering {
        case .engineering: notation = .engineering
        case .scientific: notation = .scientific
        case .plain: notation = .plain
        }
        return QuantityFormatter(notation: notation, decimalSign: decimalSign)
    }
}

/// Tiny generic-password Keychain wrapper.
enum KeychainStore {
    private static let service = "app.photomesh"

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
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, account: String) {
        delete(account: account)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(value.utf8),
        ]
        _ = SecItemAdd(attributes as CFDictionary, nil)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        _ = SecItemDelete(query as CFDictionary)
    }
}
