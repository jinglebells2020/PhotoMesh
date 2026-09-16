import Foundation
import Security

/// Developer-only surfaces (API key entry, model choice, allowance reset). On in Debug builds, and
/// in any build once unlocked by tapping the version in About seven times.
enum DeveloperOptions {
    static let unlockedKey = "developer.unlocked"

    static var enabled: Bool {
        #if DEBUG
        return true
        #else
        return UserDefaults.standard.bool(forKey: unlockedKey)
        #endif
    }
}

/// Where the recognizer's credentials and model come from.
/// Priority for the key: `OPENROUTER_API_KEY` environment variable (Xcode scheme) → Keychain
/// (entered in developer settings) → the key embedded in tester builds (`BuiltinKey`).
enum APIConfiguration {
    enum KeySource {
        case environment, personal, builtIn, none
    }

    /// Cheap and fast first pass (measured: same accuracy as the big model on the test set at a quarter of the cost).
    static let defaultModel = "google/gemini-3.5-flash-lite"
    /// Stronger model used only when the first pass fails validation or the two methods disagree.
    static let defaultFallbackModel = "google/gemini-3.6-flash"
    static let keychainAccount = "openrouter.apiKey"
    /// OpenRouter's chat-completions endpoint; a self-hosted PhotoMesh recognition server speaks the same protocol.
    static let defaultEndpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    /// Where recognition requests go. Developers can point the app at a self-hosted server
    /// (`ml/photomesh_ml/serve`, which fronts the fine-tuned model and escalates to the cloud itself).
    static var endpoint: URL {
        guard DeveloperOptions.enabled else { return defaultEndpoint }
        let stored = (UserDefaults.standard.string(forKey: SettingsKeys.recognitionEndpoint) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stored.isEmpty, let url = URL(string: stored), url.scheme != nil, url.host != nil else { return defaultEndpoint }
        return url
    }

    static var usesCustomEndpoint: Bool { endpoint != defaultEndpoint }

    static var apiKey: String? {
        if let env = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !env.isEmpty { return env }
        if let personal = KeychainStore.read(account: keychainAccount), !personal.isEmpty { return personal }
        if let builtIn = BuiltinKey.openRouter { return builtIn }
        // A self-hosted server may not require a key; the client only insists on a non-empty bearer token.
        return usesCustomEndpoint ? "photomesh-local" : nil
    }

    static var keySource: KeySource {
        if !(ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? "").isEmpty { return .environment }
        if let personal = KeychainStore.read(account: keychainAccount), !personal.isEmpty { return .personal }
        return BuiltinKey.openRouter == nil ? .none : .builtIn
    }

    static var isEnvironmentKey: Bool { keySource == .environment }

    /// Calls on the shared tester key are metered by `UsageAllowance`; personal keys are not.
    static var usesBuiltInKey: Bool { keySource == .builtIn }

    static func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.delete(account: keychainAccount)
        } else {
            KeychainStore.write(trimmed, account: keychainAccount)
        }
    }

    /// Testers always get the defaults; a developer can pick models in developer settings.
    static var model: String {
        guard DeveloperOptions.enabled else { return defaultModel }
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

    /// Low reasoning effort on the first pass (default on; the fallback always thinks fully).
    static var fastRecognition: Bool {
        guard DeveloperOptions.enabled else { return true }
        return UserDefaults.standard.object(forKey: SettingsKeys.fastRecognition) as? Bool ?? true
    }

    /// Model for the second pass, or nil when escalation is switched off.
    static var fallbackModel: String? {
        guard DeveloperOptions.enabled else { return defaultFallbackModel }
        guard UserDefaults.standard.object(forKey: SettingsKeys.escalate) as? Bool ?? true else { return nil }
        let stored = UserDefaults.standard.string(forKey: SettingsKeys.fallbackModel) ?? ""
        return stored.isEmpty ? defaultFallbackModel : stored
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
