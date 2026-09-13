import SwiftUI

/// UserDefaults keys shared by every `@AppStorage` in the app.
enum SettingsKeys {
    static let language = "settings.language"
    static let decimalSign = "settings.decimalSign"
    static let unitNotation = "settings.unitNotation"
    static let resistorStyle = "settings.resistorStyle"
    static let currentConvention = "settings.currentConvention"
    static let calculatorHistory = "calculator.history"
    static let hasSeenHelp = "onboarding.hasSeenHelp"
    static let openRouterModel = "recognition.model"
    static let useSampleCircuit = "recognition.useSample"
}

/// Something a settings picker can show: a fixed list of titled cases.
protocol SettingsOption: CaseIterable, RawRepresentable, Identifiable, Hashable where RawValue == String {
    var title: String { get }
    var subtitle: String? { get }
}

extension SettingsOption {
    var id: String { rawValue }
    var subtitle: String? { nil }
}

enum DecimalSign: String, SettingsOption {
    case point, comma

    var title: String {
        switch self {
        case .point: return "Point (3.14)"
        case .comma: return "Comma (3,14)"
        }
    }

    var symbol: String { self == .point ? "." : "," }
}

enum UnitNotation: String, SettingsOption {
    case engineering, scientific, plain

    var title: String {
        switch self {
        case .engineering: return "Engineering"
        case .scientific: return "Scientific"
        case .plain: return "Plain"
        }
    }

    var subtitle: String? {
        switch self {
        case .engineering: return "4.7 kΩ, 220 µF"
        case .scientific: return "4.7 × 10³ Ω"
        case .plain: return "4700 Ω"
        }
    }
}

enum ResistorStyle: String, SettingsOption {
    case ansi, iec

    var title: String {
        switch self {
        case .ansi: return "ANSI (zigzag)"
        case .iec: return "IEC (rectangle)"
        }
    }

    var subtitle: String? {
        switch self {
        case .ansi: return "Common in US textbooks"
        case .iec: return "Common in European textbooks"
        }
    }
}

enum CurrentConvention: String, SettingsOption {
    case conventional, electron

    var title: String {
        switch self {
        case .conventional: return "Conventional current"
        case .electron: return "Electron flow"
        }
    }

    var subtitle: String? {
        switch self {
        case .conventional: return "Positive to negative"
        case .electron: return "Negative to positive"
        }
    }
}

struct AppLanguage: Identifiable, Hashable {
    let code: String
    let nativeName: String
    let englishName: String

    var id: String { code }

    static let all: [AppLanguage] = [
        .init(code: "en", nativeName: "English", englishName: "English"),
        .init(code: "ar", nativeName: "العربية", englishName: "Arabic"),
        .init(code: "zh-Hans", nativeName: "简体中文", englishName: "Chinese (Simplified)"),
        .init(code: "de", nativeName: "Deutsch", englishName: "German"),
        .init(code: "es", nativeName: "Español", englishName: "Spanish"),
        .init(code: "fr", nativeName: "Français", englishName: "French"),
        .init(code: "it", nativeName: "Italiano", englishName: "Italian"),
        .init(code: "ja", nativeName: "日本語", englishName: "Japanese"),
        .init(code: "kk", nativeName: "Қазақша", englishName: "Kazakh"),
        .init(code: "ko", nativeName: "한국어", englishName: "Korean"),
        .init(code: "pt", nativeName: "Português", englishName: "Portuguese"),
        .init(code: "ru", nativeName: "Русский", englishName: "Russian"),
        .init(code: "tr", nativeName: "Türkçe", englishName: "Turkish"),
        .init(code: "uk", nativeName: "Українська", englishName: "Ukrainian"),
    ]

    static func named(_ code: String) -> AppLanguage {
        all.first { $0.code == code } ?? all[0]
    }
}
