import Foundation

/// Small arithmetic evaluator used for the live "= result" line in the calculator.
/// Supports + − × ÷ ^, parentheses, √, ² ³ ! %, π, e, implicit multiplication,
/// and the common one-argument functions.
struct ExpressionEvaluator {
    enum Failure: Error, Equatable {
        case empty
        case incomplete
        case invalid
        case undefined
    }

    var decimalSign: Character = "."

    func evaluate(_ input: String) throws -> Double {
        let tokens = try tokenize(input)
        guard !tokens.isEmpty else { throw Failure.empty }
        var parser = Parser(tokens: tokens)
        let value = try parser.parseExpression()
        guard parser.isAtEnd else { throw Failure.invalid }
        guard value.isFinite else { throw Failure.undefined }
        return value
    }

    // MARK: Tokens

    enum Token: Equatable {
        case number(Double)
        case op(Character)
        case lparen
        case rparen
        case ident(String)
        case postfix(Character)
        case sqrt
    }

    func tokenize(_ input: String) throws -> [Token] {
        var tokens: [Token] = []
        let chars = Array(input)
        var i = 0

        func isDigitLike(_ c: Character) -> Bool {
            // ASCII digits only: superscripts like ² are numeric characters but are postfix operators here.
            (c.isASCII && c.isWholeNumber) || c == decimalSign
        }

        while i < chars.count {
            let c = chars[i]
            if c == " " { i += 1; continue }

            if isDigitLike(c) {
                var text = ""
                var j = i
                while j < chars.count, isDigitLike(chars[j]) {
                    text.append(chars[j] == decimalSign ? "." : chars[j])
                    j += 1
                }
                guard let value = Double(text) else { throw Failure.incomplete }
                tokens.append(.number(value))
                i = j
                continue
            }

            switch c {
            case "+": tokens.append(.op("+"))
            case "-", "−", "–": tokens.append(.op("-"))
            case "*", "×", "·": tokens.append(.op("*"))
            case "/", "÷": tokens.append(.op("/"))
            case "^": tokens.append(.op("^"))
            case "(", "[": tokens.append(.lparen)
            case ")", "]": tokens.append(.rparen)
            case "√": tokens.append(.sqrt)
            case "²", "³", "!", "%": tokens.append(.postfix(c))
            case "π": tokens.append(.ident("π"))
            case "=": throw Failure.incomplete
            default:
                if c.isLetter {
                    var word = ""
                    var j = i
                    while j < chars.count, chars[j].isLetter {
                        word.append(chars[j])
                        j += 1
                    }
                    tokens.append(.ident(word))
                    i = j
                    continue
                }
                throw Failure.invalid
            }
            i += 1
        }
        return tokens
    }

    // MARK: Parser

    struct Parser {
        let tokens: [Token]
        var index = 0

        var isAtEnd: Bool { index >= tokens.count }
        var peek: Token? { isAtEnd ? nil : tokens[index] }

        mutating func advance() {
            index += 1
        }

        mutating func parseExpression() throws -> Double {
            var value = try parseTerm()
            while let token = peek, case .op(let c) = token, c == "+" || c == "-" {
                advance()
                let rhs = try parseTerm()
                value = (c == "+") ? value + rhs : value - rhs
            }
            return value
        }

        mutating func parseTerm() throws -> Double {
            var value = try parseUnary()
            loop: while let token = peek {
                switch token {
                case .op(let c) where c == "*":
                    advance()
                    value *= try parseUnary()
                case .op(let c) where c == "/":
                    advance()
                    let divisor = try parseUnary()
                    guard divisor != 0 else { throw Failure.undefined }
                    value /= divisor
                case .number, .lparen, .ident, .sqrt:
                    // Implicit multiplication: 2π, 2(3), 3sin(x)
                    value *= try parseUnary()
                default:
                    break loop
                }
            }
            return value
        }

        mutating func parseUnary() throws -> Double {
            if let token = peek, case .op(let c) = token {
                if c == "-" {
                    advance()
                    return -(try parseUnary())
                }
                if c == "+" {
                    advance()
                    return try parseUnary()
                }
            }
            return try parsePower()
        }

        mutating func parsePower() throws -> Double {
            let base = try parsePostfix()
            if let token = peek, case .op(let c) = token, c == "^" {
                advance()
                let exponent = try parseUnary()
                let result = pow(base, exponent)
                guard result.isFinite else { throw Failure.undefined }
                return result
            }
            return base
        }

        mutating func parsePostfix() throws -> Double {
            var value = try parsePrimary()
            while let token = peek, case .postfix(let c) = token {
                advance()
                switch c {
                case "²": value *= value
                case "³": value = value * value * value
                case "%": value /= 100
                case "!": value = try Parser.factorial(value)
                default: throw Failure.invalid
                }
            }
            return value
        }

        mutating func parsePrimary() throws -> Double {
            guard let token = peek else { throw Failure.incomplete }
            switch token {
            case .number(let value):
                advance()
                return value
            case .lparen:
                advance()
                let value = try parseExpression()
                guard let close = peek, close == .rparen else { throw Failure.incomplete }
                advance()
                return value
            case .sqrt:
                advance()
                let value = try parseUnary()
                guard value >= 0 else { throw Failure.undefined }
                return value.squareRoot()
            case .ident(let name):
                advance()
                switch name {
                case "π", "pi": return .pi
                case "e": return M_E
                default:
                    guard let function = Parser.functions[name] else { throw Failure.invalid }
                    let argument: Double
                    if let next = peek, next == .lparen {
                        argument = try parsePrimary()
                    } else {
                        argument = try parseUnary()
                    }
                    let result = function(argument)
                    guard result.isFinite else { throw Failure.undefined }
                    return result
                }
            case .rparen, .postfix:
                throw Failure.invalid
            case .op:
                throw Failure.incomplete
            }
        }

        static func factorial(_ value: Double) throws -> Double {
            guard value >= 0, value == value.rounded(), value <= 170 else { throw Failure.undefined }
            var result: Double = 1
            var n = value
            while n > 1 {
                result *= n
                n -= 1
            }
            return result
        }

        static let functions: [String: (Double) -> Double] = [
            "sin": sin, "cos": cos, "tan": tan,
            "cot": { 1 / tan($0) }, "sec": { 1 / cos($0) }, "csc": { 1 / sin($0) },
            "asin": asin, "acos": acos, "atan": atan, "acot": { atan(1 / $0) },
            "arcsin": asin, "arccos": acos, "arctan": atan,
            "sinh": sinh, "cosh": cosh, "tanh": tanh, "coth": { 1 / tanh($0) },
            "ln": log, "log": log10, "lg": log10,
            "sqrt": { $0.squareRoot() }, "abs": abs, "exp": exp,
            "sgn": { $0 > 0 ? 1 : ($0 < 0 ? -1 : 0) },
        ]
    }

    // MARK: Formatting

    static func format(_ value: Double, decimalSign: Character = ".") -> String {
        var v = value
        if abs(v) < 1e-12 { v = 0 }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = false
        formatter.decimalSeparator = String(decimalSign)
        formatter.minimumFractionDigits = 0

        if v != 0, abs(v) >= 1e12 || abs(v) < 1e-6 {
            // Engineering-friendly scientific notation: 1.5×10^13
            let exponent = Int(floor(log10(abs(v))))
            let mantissa = v / pow(10, Double(exponent))
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 4
            let mantissaText = formatter.string(from: NSNumber(value: mantissa)) ?? String(mantissa)
            return "\(mantissaText)×10^\(exponent)"
        }
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 8
        return formatter.string(from: NSNumber(value: v)) ?? String(v)
    }
}
