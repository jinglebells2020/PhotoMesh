import Foundation

/// Turns the engine's plain-text equation lines, e.g. "(V₂ − 12)/100 + V₂/220 = 0" or
/// "V(R1) = R1·I(R1) = 100 Ω·37.5 mA = 3.75 V", into LaTeX for typeset display.
/// Divisions become fractions, subscripts and units are typeset, prose stays prose.
/// The plain line remains the source of truth (logs, accessibility, feedback).
enum EquationLaTeX {
    static func latex(for line: String) -> String {
        var tokens = tokenize(line)
        // A line that starts with an arrow is a consequence: show it as ⇒.
        if case .symbol("→")? = tokens.first { tokens[0] = .symbol("⇒") }
        var index = 0
        let nodes = parse(tokens, &index)
        return render(fold(nodes)).trimmingCharacters(in: .whitespaces)
    }

    // MARK: Tokens

    private enum Token: Equatable {
        case number(String)
        case word(String)
        case superscript(String)
        case symbol(Character)
        case open, close
        case space(Int)
    }

    private static let subscriptDigits: [Character: Character] = ["₀": "0", "₁": "1", "₂": "2", "₃": "3", "₄": "4", "₅": "5", "₆": "6", "₇": "7", "₈": "8", "₉": "9"]
    private static let superscriptDigits: [Character: Character] = ["⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9", "⁻": "-"]
    private static let operatorCharacters: Set<Character> = ["=", "+", "−", "-", "·", "/", "→", "⇒", "×", "÷", "^", "√", ":", ",", "!", "%", "*", "<", ">", "≈", "≠", "≤", "≥", "′", "✓", "✗", "‖", "—"]
    private static let functionNames: Set<String> = ["sin", "cos", "tan", "log", "ln", "exp"]

    private static func tokenize(_ line: String) -> [Token] {
        let chars = Array(line)
        var tokens: [Token] = []
        var i = 0
        func isDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }
        func isLetter(_ c: Character) -> Bool { (c.isASCII && c.isLetter) || c == "Ω" || c == "µ" || c == "μ" || c == "π" }
        while i < chars.count {
            let c = chars[i]
            if c == " " {
                var n = 0
                while i < chars.count, chars[i] == " " { n += 1; i += 1 }
                tokens.append(.space(n))
            } else if isDigit(c) {
                var s = ""
                while i < chars.count {
                    let d = chars[i]
                    if isDigit(d) {
                        s.append(d); i += 1
                    } else if (d == "." || d == ","), i + 1 < chars.count, isDigit(chars[i + 1]), !s.isEmpty {
                        s.append(d); i += 1
                    } else {
                        break
                    }
                }
                tokens.append(.number(s))
            } else if isLetter(c) {
                var s = ""
                while i < chars.count, isLetter(chars[i]) { s.append(chars[i]); i += 1 }
                var digits = ""
                while i < chars.count, isDigit(chars[i]) || subscriptDigits[chars[i]] != nil {
                    digits.append(subscriptDigits[chars[i]] ?? chars[i]); i += 1
                }
                tokens.append(.word(digits.isEmpty ? s : s + "_" + digits))
            } else if let d = superscriptDigits[c] {
                var s = ""
                while i < chars.count, let e = superscriptDigits[chars[i]] { s.append(e); i += 1 }
                _ = d
                tokens.append(.superscript(s))
            } else if c == "(" {
                tokens.append(.open); i += 1
            } else if c == ")" {
                tokens.append(.close); i += 1
            } else if operatorCharacters.contains(c) {
                tokens.append(.symbol(c)); i += 1
            } else {
                // Anything else (stray punctuation, letters outside ASCII) is shown as text.
                var s = ""
                while i < chars.count, !isDigit(chars[i]), !isLetter(chars[i]), chars[i] != " ", chars[i] != "(", chars[i] != ")", !operatorCharacters.contains(chars[i]), superscriptDigits[chars[i]] == nil {
                    s.append(chars[i]); i += 1
                }
                tokens.append(.word(s))
            }
        }
        return tokens
    }

    // MARK: Nodes

    private indirect enum Node {
        case number(String)
        case symbol(String)          // LaTeX
        case unit(String)            // LaTeX including the thin space
        case text(String)
        case op(String)              // LaTeX operator carrying its own spacing
        case punct(String)           // LaTeX
        case group([Node])
        case frac([Node], [Node])
        case sqrt([Node])
        case power([Node], [Node])
        case function(String, [Node])
        case space(Int)

        var isOperand: Bool {
            switch self {
            case .number, .symbol, .group, .frac, .sqrt, .power, .function: return true
            default: return false
            }
        }
    }

    private static func parse(_ tokens: [Token], _ i: inout Int) -> [Node] {
        var nodes: [Node] = []
        var previousMeaningful: Token?
        var gapBeforeCurrent = 0
        while i < tokens.count {
            let token = tokens[i]
            i += 1
            switch token {
            case .space(let n):
                nodes.append(.space(n))
                gapBeforeCurrent = n
                continue
            case .close:
                return nodes
            case .open:
                let inner = parse(tokens, &i)
                nodes.append(.group(inner))
            case .number(let s):
                nodes.append(.number(s.replacingOccurrences(of: ",", with: "{,}")))
            case .superscript(let s):
                nodes.append(.op("^"))
                nodes.append(.number(s))
            case .symbol(let c):
                nodes.append(operatorNode(c))
            case .word(let raw):
                let isUnitPosition: Bool = {
                    if case .number? = previousMeaningful, gapBeforeCurrent == 1 { return true }
                    return false
                }()
                if isUnitPosition, let unit = unitLaTeX(raw) {
                    nodes.append(.unit(unit))
                } else if functionNames.contains(raw), i < tokens.count, tokens[i] == .open {
                    i += 1
                    let inner = parse(tokens, &i)
                    nodes.append(.function(raw, inner))
                } else if raw.count == 1, "IVP".contains(raw), i < tokens.count, tokens[i] == .open {
                    // I(R1) → I with an upright subscript
                    i += 1
                    let inner = parse(tokens, &i)
                    nodes.append(.symbol("\(raw)_{\(subscriptLaTeX(inner))}"))
                } else if let symbol = symbolLaTeX(raw) {
                    nodes.append(.symbol(symbol))
                } else {
                    nodes.append(.text(raw))
                }
            }
            previousMeaningful = token
            gapBeforeCurrent = 0
        }
        return nodes
    }

    private static func operatorNode(_ c: Character) -> Node {
        switch c {
        case "=": return .op("=")
        case "+": return .op("+")
        case "−", "-": return .op("-")
        case "·", "*": return .op("\\cdot")
        case "×": return .op("\\times")
        case "÷": return .op("\\div")
        case "→": return .op("\\rightarrow")
        case "⇒": return .op("\\Rightarrow")
        case "≈": return .op("\\approx")
        case "≠": return .op("\\neq")
        case "≤": return .op("\\leq")
        case "≥": return .op("\\geq")
        case "<": return .op("<")
        case ">": return .op(">")
        case "/": return .op("/")
        case "^": return .op("^")
        case "√": return .op("\\sqrt")
        case ",": return .punct(",\\;")
        case ":": return .punct("{:}\\;")
        case "!": return .punct("!")
        case "%": return .punct("\\%")
        case "‖": return .op("\\parallel")
        case "—": return .op("\\rightarrow")
        case "′": return .punct("'")
        // SwiftMath has no check-mark glyph; a word keeps the line typeset instead of falling back.
        case "✓": return .punct("\\;(\\text{OK})")
        case "✗": return .punct("\\;(\\text{no})")
        default: return .text(String(c))
        }
    }

    /// "V_2" → "V_{2}", "R_12" → "R_{12}", "a" → "a", "π" → "\pi"; nil for prose words.
    private static func symbolLaTeX(_ raw: String) -> String? {
        if raw == "π" { return "\\pi" }
        if raw == "Ω" { return "\\Omega" }
        let parts = raw.split(separator: "_", maxSplits: 1).map(String.init)
        let letters = parts[0]
        let digits = parts.count > 1 ? parts[1] : ""
        guard !letters.isEmpty, letters.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        if !digits.isEmpty {
            guard letters.count <= 2 else { return nil }
            return "\(letters)_{\(digits)}"
        }
        // Node voltages: "Va" → V with subscript a, "Vab" → V with subscript ab.
        if letters.count >= 2, letters.count <= 3, letters.first == "V", letters.dropFirst().allSatisfy({ $0.isLowercase }) {
            return "V_{\(letters.dropFirst())}"
        }
        return letters.count == 1 ? letters : nil
    }

    /// Subscript for I(...) / V(...): ids upright, single letters italic, numbers as they are.
    private static func subscriptLaTeX(_ inner: [Node]) -> String {
        var out = ""
        for node in inner {
            switch node {
            case .symbol(let s):
                // "R_{1}" → upright "R1"; a lone letter stays italic
                let plain = s.replacingOccurrences(of: "_{", with: "").replacingOccurrences(of: "}", with: "")
                out += plain.count > 1 ? "\\mathrm{\(plain)}" : plain
            case .number(let n): out += n
            case .text(let t): out += "\\mathrm{\(t)}"
            case .space: continue
            default: out += render([node])
            }
        }
        return out
    }

    /// "mA" → "\,\mathrm{mA}", "kΩ" → "\,\mathrm{k}\Omega", "µA" → "\,\mu\mathrm{A}".
    private static func unitLaTeX(_ raw: String) -> String? {
        var text = raw
        var prefix = ""
        if let first = text.first, "pnµμmkMG".contains(first), text.count > 1 {
            prefix = String(first)
            text.removeFirst()
        }
        let base: String
        switch text {
        case "Ω": base = "\\Omega"
        case "V", "A", "W", "F", "H", "Hz", "s", "S", "J", "C": base = "\\mathrm{\(text)}"
        default: return nil
        }
        switch prefix {
        case "": return "\\,\(base)"
        case "µ", "μ": return "\\,\\mu \(base)"
        default:
            // "mA" as one upright group; "k" + Ω stay separate because Ω is a symbol
            return text == "Ω" ? "\\,\\mathrm{\(prefix)}\(base)" : "\\,\\mathrm{\(prefix)\(text)}"
        }
    }

    // MARK: Structure

    /// Folds a/b into fractions, x^y into powers and √x into roots, innermost groups first.
    private static func fold(_ nodes: [Node]) -> [Node] {
        var items: [Node] = nodes.map { node in
            switch node {
            case .group(let inner): return .group(fold(inner))
            case .function(let name, let inner): return .function(name, fold(inner))
            default: return node
            }
        }
        // Powers bind tightest.
        var i = 0
        while i < items.count {
            if case .op("^") = items[i], i > 0, i + 1 < items.count, items[i - 1].isOperand, items[i + 1].isOperand {
                let power = Node.power([items[i - 1]], operandContents(items[i + 1]))   // a group base keeps its parentheses
                items.replaceSubrange((i - 1)...(i + 1), with: [power])
                i -= 1
            } else {
                i += 1
            }
        }
        // Roots take the operand that follows.
        i = 0
        while i < items.count {
            if case .op("\\sqrt") = items[i], i + 1 < items.count, items[i + 1].isOperand {
                items.replaceSubrange(i...(i + 1), with: [.sqrt(operandContents(items[i + 1]))])
            }
            i += 1
        }
        // Fractions.
        i = 0
        while i < items.count {
            if case .op("/") = items[i], i > 0, i + 1 < items.count, items[i - 1].isOperand, items[i + 1].isOperand {
                let frac = Node.frac(operandContents(items[i - 1]), operandContents(items[i + 1]))
                items.replaceSubrange((i - 1)...(i + 1), with: [frac])
                i -= 1
            } else {
                i += 1
            }
        }
        return items
    }

    /// The parts of an operand as they should appear inside braces: parentheses are dropped.
    private static func operandContents(_ node: Node) -> [Node] {
        if case .group(let inner) = node { return inner }
        return [node]
    }

    // MARK: Rendering

    private static func render(_ nodes: [Node]) -> String {
        var out = ""
        var textRun: [String] = []
        var pendingSpace = 0
        func flushText() {
            guard !textRun.isEmpty else { return }
            out += "\\text{\(textRun.joined(separator: " "))}"
            textRun = []
        }
        func emitSpace(before node: Node) {
            guard pendingSpace > 0 else { return }
            defer { pendingSpace = 0 }
            if pendingSpace >= 2 { out += "\\quad "; return }
            if case .op = node { return }
            if case .punct = node { return }
            if case .unit = node { return }            // units bring their own thin space
            if out.hasSuffix("\\;") || out.hasSuffix("\\quad ") { return }   // punctuation already spaced
            if let last = out.last, last == " " { return }
            if out.isEmpty { return }
            // A thick space: the TeX-in-math way to separate words and symbols. (Never emit "\\ ",
            // the backslash-space control: SwiftMath's parser rejects it and the whole line would
            // fall back to plain text.)
            out += "\\;"
        }
        for node in nodes {
            if case .space(let n) = node {
                pendingSpace = max(pendingSpace, n)
                continue
            }
            if case .text(let t) = node {
                if textRun.isEmpty {
                    emitSpace(before: node)
                } else if pendingSpace >= 2 {
                    flushText()
                    emitSpace(before: node)
                } else {
                    pendingSpace = 0
                }
                textRun.append(t)
                continue
            }
            flushText()
            emitSpace(before: node)
            switch node {
            case .number(let s): out += s
            case .symbol(let s): out += s
            case .unit(let s): out += s
            case .op(let s): out += " \(s) "
            case .punct(let s): out += s
            case .group(let inner):
                let tall = inner.contains { if case .frac = $0 { return true }; return false }
                out += tall ? "\\left(\(render(inner))\\right)" : "(\(render(inner)))"
            case .frac(let num, let den): out += "\\frac{\(render(num))}{\(render(den))}"
            case .sqrt(let inner): out += "\\sqrt{\(render(inner))}"
            case .power(let base, let exponent): out += "{\(render(base))}^{\(render(exponent))}"
            case .function(let name, let inner): out += "\\\(name)(\(render(inner)))"
            case .text, .space: break
            }
        }
        flushText()
        return out.replacingOccurrences(of: "  ", with: " ")
    }
}
