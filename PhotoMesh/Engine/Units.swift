import Foundation

/// Number formatting for engineering quantities: 0.0375 A → "37.5 mA".
struct QuantityFormatter {
    enum Notation { case engineering, scientific, plain }

    var notation: Notation = .engineering
    var decimalSign: Character = "."
    var significantDigits = 4

    private static let prefixes: [(exponent: Int, symbol: String)] = [
        (-12, "p"), (-9, "n"), (-6, "µ"), (-3, "m"), (0, ""), (3, "k"), (6, "M"), (9, "G"),
    ]

    /// Formats a value with its unit, e.g. `format(4700, "Ω")` → "4.7 kΩ".
    func format(_ value: Double, _ unit: String) -> String {
        guard value.isFinite else { return "—" }
        let magnitude = abs(value)
        if magnitude < 1e-12 { return "0 \(unit)".trimmingCharacters(in: .whitespaces) }

        switch notation {
        case .engineering:
            let exponent = Int(floor(log10(magnitude) / 3)) * 3
            let clamped = min(max(exponent, -12), 9)
            guard let prefix = Self.prefixes.first(where: { $0.exponent == clamped }) else {
                return "\(number(value)) \(unit)"
            }
            let scaled = value / pow(10, Double(clamped))
            return "\(number(scaled)) \(prefix.symbol)\(unit)".trimmingCharacters(in: .whitespaces)
        case .scientific:
            let exponent = Int(floor(log10(magnitude)))
            if exponent == 0 { return "\(number(value)) \(unit)" }
            let mantissa = value / pow(10, Double(exponent))
            return "\(number(mantissa))×10\(Self.superscript(exponent)) \(unit)"
        case .plain:
            return "\(number(value)) \(unit)"
        }
    }

    /// A bare number rounded to the configured significant digits ("0.0375", "320", "1.455").
    func number(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        if abs(value) < 1e-12 { return "0" }
        let digits = max(1, significantDigits)
        let exponent = Int(floor(log10(abs(value))))
        let decimals = max(0, digits - 1 - exponent)
        var text = String(format: "%.\(min(decimals, 12))f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        if text == "-0" { text = "0" }
        if decimalSign != "." { text = text.replacingOccurrences(of: ".", with: String(decimalSign)) }
        return text.replacingOccurrences(of: "-", with: "−")
    }

    /// Number used inside an equation: negative values are wrapped in parentheses.
    func term(_ value: Double) -> String {
        value < 0 ? "(\(number(value)))" : number(value)
    }

    /// A number that will be used again in later arithmetic: shown with one extra significant
    /// digit whenever the usual rounding would not reproduce it, so that redoing the printed
    /// arithmetic gives the printed result (12/140.74 = 85.26 mA, not 12/140.7 = 85.29 mA).
    /// (Trailing zeros are trimmed, so the extra digit only appears when it carries information.)
    func precise(_ value: Double) -> String {
        finer.number(value)
    }

    /// `precise` wrapped in parentheses when negative.
    func preciseTerm(_ value: Double) -> String {
        value < 0 ? "(\(precise(value)))" : precise(value)
    }

    /// `precise` with a unit.
    func precise(_ value: Double, _ unit: String) -> String {
        finer.format(value, unit)
    }

    private var finer: QuantityFormatter {
        var more = self
        more.significantDigits = significantDigits + 1
        return more
    }

    /// `precise(_:_:)` wrapped in parentheses when negative.
    func preciseTerm(_ value: Double, _ unit: String) -> String {
        value < 0 ? "(\(precise(value, unit)))" : precise(value, unit)
    }

    /// Quantity used inside an equation: negative values are wrapped in parentheses.
    func term(_ value: Double, _ unit: String) -> String {
        value < 0 ? "(\(format(value, unit)))" : format(value, unit)
    }

    static func superscript(_ exponent: Int) -> String {
        let map: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"]
        return String(String(exponent).map { map[$0] ?? $0 })
    }

    static func subscriptDigits(_ text: String) -> String {
        let map: [Character: Character] = ["0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉"]
        return String(text.map { map[$0] ?? $0 })
    }

    /// Parses "4.7k", "2.2 MΩ", "15m", "100µ", "0.5" into a base-unit number.
    static func parseValue(_ raw: String) -> Double? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
        for unit in ["ohms", "ohm", "Ω", "V", "A", "W", "volts", "amps"] {
            if text.hasSuffix(unit) { text.removeLast(unit.count) }
        }
        let multipliers: [String: Double] = ["p": 1e-12, "n": 1e-9, "u": 1e-6, "µ": 1e-6, "μ": 1e-6, "m": 1e-3, "k": 1e3, "K": 1e3, "M": 1e6, "G": 1e9]
        var multiplier = 1.0
        if let last = text.last, let m = multipliers[String(last)] {
            multiplier = m
            text.removeLast()
        }
        guard let number = Double(text) else { return nil }
        return number * multiplier
    }
}
