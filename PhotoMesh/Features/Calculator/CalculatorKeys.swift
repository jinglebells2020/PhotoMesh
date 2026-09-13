import SwiftUI

enum KeyAction: Hashable {
    /// Inserts text at the cursor. `cursorOffset` places the cursor that many characters after
    /// the insertion point; `nil` puts it after the inserted text.
    case insert(String, cursorOffset: Int?)
    case backspace
    case moveLeft
    case moveRight
    case enter
    case toggleAlpha
    case history
}

/// How a key is drawn. Composite cases render dotted placeholder boxes like Photomath.
enum KeyLabel: Hashable {
    case text(String)
    case symbol(String)
    case parens
    case fraction
    case sqrt
    case cubeRoot
    case nthRoot
    case square
    case cube
    case power
    case reciprocal
    case abs
    case logBase
    case exp
    case floor
    case ceil
    case derivative
    case derivativeGeneric
    case secondDerivative
    case integral
    case definiteIntegral
    case doubleIntegral
    case limit
    case limitRight
    case limitLeft
    case sum
    case product
    case subscriptN
    case dyDx
    case brackets
    case empty
}

struct CalcKey: Identifiable, Hashable {
    let id: String
    let label: KeyLabel
    let action: KeyAction
    var alternates: [CalcKey] = []

    var isEmpty: Bool { label == .empty }

    var accessibilityLabel: String {
        switch label {
        case .text(let s): return s
        case .symbol(let name): return name
        case .empty: return ""
        default: return id
        }
    }

    // MARK: Builders

    static func text(_ shown: String, insert: String? = nil, cursorOffset: Int? = nil, alternates: [CalcKey] = []) -> CalcKey {
        CalcKey(id: "text:\(shown)", label: .text(shown), action: .insert(insert ?? shown, cursorOffset: cursorOffset), alternates: alternates)
    }

    static func composite(_ id: String, _ label: KeyLabel, insert: String, cursorOffset: Int? = nil, alternates: [CalcKey] = []) -> CalcKey {
        CalcKey(id: id, label: label, action: .insert(insert, cursorOffset: cursorOffset), alternates: alternates)
    }

    static func empty(_ id: String) -> CalcKey {
        CalcKey(id: "empty:\(id)", label: .empty, action: .insert("", cursorOffset: 0))
    }

    static func fn(_ name: String, insert: String? = nil) -> CalcKey {
        .text(name, insert: (insert ?? name) + "(")
    }
}

enum CalcTab: String, CaseIterable, Identifiable {
    case basic, functions, trig, calculus

    var id: String { rawValue }

    var topLine: String {
        switch self {
        case .basic: return "+ −"
        case .functions: return "f(x)  e"
        case .trig: return "sin cos"
        case .calculus: return "lim  dx"
        }
    }

    var bottomLine: String {
        switch self {
        case .basic: return "× ÷"
        case .functions: return "log  ln"
        case .trig: return "tan cot"
        case .calculus: return "∫ Σ ∞"
        }
    }
}

/// Key layouts per tab. Rows are rendered top to bottom.
enum KeyboardLayouts {
    // Shared composite keys
    static let parens = CalcKey.composite("parens", .parens, insert: "()", cursorOffset: 1, alternates: [
        .text("("), .text(")"),
        .composite("brackets", .brackets, insert: "[]", cursorOffset: 1),
        .composite("abs", .abs, insert: "||", cursorOffset: 1),
    ])
    static let fraction = CalcKey.composite("fraction", .fraction, insert: "/")
    static let sqrt = CalcKey.composite("sqrt", .sqrt, insert: "√()", cursorOffset: 2, alternates: [
        .composite("cubeRoot", .cubeRoot, insert: "∛()", cursorOffset: 2),
        .composite("nthRoot", .nthRoot, insert: "root()", cursorOffset: 5),
    ])
    static let square = CalcKey.composite("square", .square, insert: "²", alternates: [
        .composite("cube", .cube, insert: "³"),
        .composite("power", .power, insert: "^"),
        .composite("reciprocal", .reciprocal, insert: "⁻¹"),
    ])
    static let power = CalcKey.composite("power", .power, insert: "^")
    static let abs = CalcKey.composite("abs", .abs, insert: "||", cursorOffset: 1)
    static let variableX = CalcKey.text("x", alternates: [.text("y"), .text("z"), .text("t"), .text("n")])
    static let pi = CalcKey.text("π", alternates: [.text("e"), .text("∞"), .text("θ")])

    static func rows(for tab: CalcTab) -> [[CalcKey]] {
        switch tab {
        case .basic: return basic
        case .functions: return functions
        case .trig: return trig
        case .calculus: return calculus
        }
    }

    static let basic: [[CalcKey]] = [
        [parens, .text(">", alternates: [.text("<"), .text("≥"), .text("≤"), .text("≠")]), .text("7"), .text("8"), .text("9"), .text("÷")],
        [fraction, sqrt, .text("4"), .text("5"), .text("6"), .text("×")],
        [square, variableX, .text("1"), .text("2"), .text("3"), .text("−")],
        [pi, .text("%", alternates: [.text("‰"), .text("!")]), .text("0"), .text(".", alternates: [.text(",")]), .text("=", alternates: [.text("≈"), .text("≡")]), .text("+")],
    ]

    static let functions: [[CalcKey]] = [
        [.text("f(x)", insert: "f(x)="), .text("e"), .fn("log"), .fn("ln"),
         .composite("logBase", .logBase, insert: "log[]()", cursorOffset: 4),
         .composite("exp", .exp, insert: "e^")],
        [.text("sgn", insert: "sgn("), .text("!"), power, abs,
         .composite("floor", .floor, insert: "⌊⌋", cursorOffset: 1),
         .composite("ceil", .ceil, insert: "⌈⌉", cursorOffset: 1)],
        [.text("mod", insert: " mod "), .fn("gcd"), .fn("lcm"), .fn("min"), .fn("max"), .text("nCr", insert: "C(")],
        [.composite("subscriptN", .subscriptN, insert: "_"), .text("i"), .text("∞"), .text("%"),
         .composite("sum", .sum, insert: "Σ("), .composite("product", .product, insert: "∏(")],
    ]

    static let trig: [[CalcKey]] = [
        [.fn("sin"), .fn("cos"), .fn("tan"), .fn("cot"), .fn("sec"), .fn("csc")],
        [.text("sin⁻¹", insert: "asin("), .text("cos⁻¹", insert: "acos("), .text("tan⁻¹", insert: "atan("), .text("cot⁻¹", insert: "acot("), pi, .text("°")],
        [.fn("sinh"), .fn("cosh"), .fn("tanh"), .fn("coth"), .text("θ"), .text("rad")],
        [parens, fraction, variableX, sqrt, square, .text(",")],
    ]

    static let calculus: [[CalcKey]] = [
        [.composite("limit", .limit, insert: "lim("), .composite("derivative", .derivative, insert: "d/dx("),
         .composite("integral", .integral, insert: "∫()dx", cursorOffset: 2), .composite("dyDx", .dyDx, insert: "dy/dx"),
         .composite("subscriptN", .subscriptN, insert: "a_")],
        [.composite("limitRight", .limitRight, insert: "lim⁺("), .composite("derivativeGeneric", .derivativeGeneric, insert: "d/d"),
         .composite("definiteIntegral", .definiteIntegral, insert: "∫[,]()", cursorOffset: 2), .text("dx"), .text("…", insert: "...")],
        [.composite("limitLeft", .limitLeft, insert: "lim⁻("), .composite("secondDerivative", .secondDerivative, insert: "d²/dx²("),
         .composite("doubleIntegral", .doubleIntegral, insert: "∬()", cursorOffset: 2), .text("dy"), .empty("c-3-5")],
        [.text("∞"), .empty("c-4-2"), .composite("sum", .sum, insert: "Σ("), .text("y′", insert: "y'"), .empty("c-4-5")],
    ]

    static let alpha: [[CalcKey]] = [
        ["a", "b", "c", "d", "e", "f", "g", "h"].map { CalcKey.text($0) },
        ["i", "j", "k", "l", "m", "n", "o", "p"].map { CalcKey.text($0) },
        ["q", "r", "s", "t", "u", "v", "w", "x"].map { CalcKey.text($0) },
        ["y", "z", "α", "β", "θ", "ρ", "Φ"].map { CalcKey.text($0) } + [CalcKey.empty("a-4-8")],
    ]
}
