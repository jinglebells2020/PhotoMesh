import Foundation

/// Keeps the arithmetic in the steps looking the way a textbook writes it: integers where possible,
/// fractions cleared with a common multiple, exact fractions while a system is being solved, and
/// systems solved by elimination one operation at a time.
enum NiceNumbers {
    static func isInteger(_ x: Double) -> Bool {
        abs(x - x.rounded()) < 1e-9 * max(1, abs(x))
    }

    /// Power of ten (1…1000) that turns every value into an integer, or nil.
    static func integerScale(_ values: [Double]) -> Double? {
        for scale in [1.0, 10, 100, 1000] where values.allSatisfy({ isInteger($0 * scale) }) { return scale }
        return nil
    }

    static func gcd(_ a: Int64, _ b: Int64) -> Int64 {
        var x = abs(a), y = abs(b)
        while y != 0 { (x, y) = (y, x % y) }
        return x
    }

    /// Smallest number L such that L / value is an integer for every value (e.g. 100, 220 → 1100).
    /// Nil when the values are not "nice" or L would be unreadably large.
    static func commonMultiple(of values: [Double], cap: Double = 2e7) -> Double? {
        guard !values.isEmpty, values.allSatisfy({ $0 > 0 && $0.isFinite }) else { return nil }
        guard let scale = integerScale(values) else { return nil }
        var l: Int64 = 1
        for value in values {
            let n = Int64((value * scale).rounded())
            guard n > 0 else { return nil }
            let g = gcd(l, n)
            let (product, overflow) = (l / g).multipliedReportingOverflow(by: n)
            guard !overflow, Double(product) <= cap * scale else { return nil }
            l = product
        }
        let result = Double(l) / scale
        return values.allSatisfy { isInteger(result / $0) } ? result : nil
    }
}

// MARK: - Exact fractions

/// An exact rational number. The narrated algebra keeps every coefficient and every intermediate
/// result as one of these whenever the circuit's numbers allow it, so the printed arithmetic is
/// exactly reproducible (Vc = 4600/775 = 184/31) and no rounding creeps from one line to the next.
struct Fraction: Hashable {
    let num: Int64
    /// Always positive; the fraction is kept reduced.
    let den: Int64

    static let zero = Fraction(integer: 0)

    init(integer: Int64) {
        num = integer
        den = 1
    }

    init?(_ numerator: Int64, over denominator: Int64) {
        guard denominator != 0 else { return nil }
        let g = max(1, NiceNumbers.gcd(numerator, denominator))
        let sign: Int64 = denominator < 0 ? -1 : 1
        num = sign * (numerator / g)
        den = sign * (denominator / g)
    }

    /// The fraction a double stands for, found by continued fractions; nil unless a fraction with a
    /// denominator up to `maxDenominator` reproduces the double to floating-point accuracy.
    init?(approximating x: Double, maxDenominator: Int64 = 1_000_000) {
        guard x.isFinite, abs(x) < 1e15 else { return nil }
        if abs(x) < 1e-15 {
            self.init(integer: 0)
            return
        }
        var h: (previous: Int64, current: Int64) = (0, 1)   // convergent numerators h₋₂, h₋₁
        var k: (previous: Int64, current: Int64) = (1, 0)   // convergent denominators k₋₂, k₋₁
        var rest = x
        for _ in 0..<64 {
            let whole = rest.rounded(.down)
            guard abs(whole) < 4e18 else { return nil }
            let a = Int64(whole)
            let (ah, o1) = a.multipliedReportingOverflow(by: h.current)
            let (hn, o2) = ah.addingReportingOverflow(h.previous)
            let (ak, o3) = a.multipliedReportingOverflow(by: k.current)
            let (kn, o4) = ak.addingReportingOverflow(k.previous)
            guard !o1, !o2, !o3, !o4, kn <= maxDenominator else { return nil }
            h = (h.current, hn)
            k = (k.current, kn)
            if abs(Double(hn) / Double(kn) - x) <= 1e-12 * max(1, abs(x)) {
                self.init(hn, over: kn)
                return
            }
            let fractional = rest - whole
            guard fractional > 1e-18 else { return nil }
            rest = 1 / fractional
        }
        return nil
    }

    var isInteger: Bool { den == 1 }
    var isZero: Bool { num == 0 }
    var double: Double { Double(num) / Double(den) }
    var negated: Fraction { Fraction(-num, over: den) ?? .zero }
    var magnitude: Fraction { Fraction(abs(num), over: den) ?? .zero }

    /// Small enough to print as a fraction: 184/31 yes, 600/7037 no (a decimal reads better).
    var isReadable: Bool {
        den == 1 ? abs(num) < 1_000_000_000_000 : (den <= 999 && abs(num) <= 99_999)
    }

    func adding(_ other: Fraction) -> Fraction? {
        let g = max(1, NiceNumbers.gcd(den, other.den))
        let (l, o1) = den.multipliedReportingOverflow(by: other.den / g)
        let (x, o2) = num.multipliedReportingOverflow(by: other.den / g)
        let (y, o3) = other.num.multipliedReportingOverflow(by: den / g)
        let (s, o4) = x.addingReportingOverflow(y)
        guard !o1, !o2, !o3, !o4 else { return nil }
        return Fraction(s, over: l)
    }

    func subtracting(_ other: Fraction) -> Fraction? { adding(other.negated) }

    func multiplied(by other: Fraction) -> Fraction? {
        let g1 = max(1, NiceNumbers.gcd(num, other.den))
        let g2 = max(1, NiceNumbers.gcd(other.num, den))
        let (n, o1) = (num / g1).multipliedReportingOverflow(by: other.num / g2)
        let (d, o2) = (den / g2).multipliedReportingOverflow(by: other.den / g1)
        guard !o1, !o2 else { return nil }
        return Fraction(n, over: d)
    }

    func divided(by other: Fraction) -> Fraction? {
        guard !other.isZero, let inverse = Fraction(other.den, over: other.num) else { return nil }
        return multiplied(by: inverse)
    }

    /// "184/31", "12", "−5/7".
    var text: String {
        let n = num < 0 ? "−\(-num)" : "\(num)"
        return den == 1 ? n : "\(n)/\(den)"
    }

    /// The fraction as a factor or subtrahend inside a larger expression: fractions and negatives
    /// are parenthesised so that "2·(184/31)" and "3 − (−5)" read unambiguously.
    var termText: String { (den == 1 && num >= 0) ? text : "(\(text))" }
}

/// Σ coefficient·symbol = constant with exact coefficients, mirroring a DisplayEquation.
struct ExactEquation {
    var symbols: [String]
    var coefficients: [String: Fraction]
    var constant: Fraction

    init?(_ equation: DisplayEquation) {
        symbols = equation.symbols
        var map: [String: Fraction] = [:]
        for symbol in equation.symbols {
            guard let c = Fraction(approximating: equation.coefficients[symbol] ?? 0) else { return nil }
            map[symbol] = c
        }
        guard let k = Fraction(approximating: equation.constant) else { return nil }
        coefficients = map
        constant = k
    }

    func coefficient(of symbol: String) -> Fraction { coefficients[symbol] ?? .zero }

    func scaled(by factor: Fraction) -> ExactEquation? {
        var copy = self
        for symbol in symbols {
            guard let c = coefficient(of: symbol).multiplied(by: factor) else { return nil }
            copy.coefficients[symbol] = c
        }
        guard let k = constant.multiplied(by: factor) else { return nil }
        copy.constant = k
        return copy
    }

    /// self + factor × other.
    func adding(_ other: ExactEquation, times factor: Fraction) -> ExactEquation? {
        var copy = self
        for symbol in other.symbols {
            guard let product = other.coefficient(of: symbol).multiplied(by: factor),
                  let sum = coefficient(of: symbol).adding(product) else { return nil }
            if copy.coefficients[symbol] == nil { copy.symbols.append(symbol) }
            copy.coefficients[symbol] = sum
        }
        guard let product = other.constant.multiplied(by: factor), let sum = constant.adding(product) else { return nil }
        copy.constant = sum
        return copy
    }

    /// The same equation in floating point.
    var display: DisplayEquation {
        var equation = DisplayEquation()
        for symbol in symbols { equation.add(coefficient(of: symbol).double, to: symbol) }
        equation.addConstant(constant.double)
        return equation
    }
}

extension DisplayEquation {
    func coefficient(of symbol: String) -> Double { coefficients[symbol] ?? 0 }

    /// Every coefficient and the constant multiplied by `factor`.
    func scaled(by factor: Double) -> DisplayEquation {
        var copy = self
        for symbol in symbols { copy.coefficients[symbol] = (coefficients[symbol] ?? 0) * factor }
        copy.constant = constant * factor
        return copy
    }

    /// self − factor × other, with the given symbol forced to exactly zero (no float residue).
    func subtracting(_ other: DisplayEquation, times factor: Double, eliminating symbol: String) -> DisplayEquation {
        var copy = self
        copy.add(other, scale: -factor)
        copy.coefficients[symbol] = 0
        return copy
    }

    var unknownSymbols: [String] { symbols.filter { abs(coefficients[$0] ?? 0) > 1e-12 } }

    /// "5·V₂ − 2·V₃ = 96", symbols in `order`. A symbol listed in `substituting` is replaced by
    /// that text ("(184/31)") and left in place, so the reader sees the substitution before it
    /// is simplified. Numbers carry a guard digit whenever four digits would not reproduce them.
    func rendered(with f: QuantityFormatter, order: [String], substituting known: [String: String] = [:]) -> String {
        var lhs = ""
        let ordered = order.filter { symbols.contains($0) } + symbols.filter { !order.contains($0) }
        for symbol in ordered {
            let c = coefficients[symbol] ?? 0
            guard abs(c) > 1e-12 else { continue }
            let magnitude = abs(c)
            let isUnit = abs(magnitude - 1) < 1e-12
            let body: String
            if let text = known[symbol] {
                body = isUnit ? text : "\(f.precise(magnitude))·\(text)"
            } else {
                body = isUnit ? symbol : "\(f.precise(magnitude))·\(symbol)"
            }
            if lhs.isEmpty {
                lhs = (c < 0 ? "−" : "") + body
            } else {
                lhs += (c < 0 ? " − " : " + ") + body
            }
        }
        if lhs.isEmpty { lhs = "0" }
        return "\(lhs) = \(f.precise(constant))"
    }
}

// MARK: - Narrated elimination

/// The steps of solving n linear equations in n unknowns by hand, plus the values they lead to.
struct NarratedSystem {
    var steps: [AnalysisStep]
    var solution: [String: Double]
}

enum SystemNarrator {
    struct Options {
        /// Unknown symbols in display order (e.g. Va, Vb, Vc or I₁, I₂).
        var unknowns: [String]
        /// Unit of the unknowns ("V" or "A").
        var unit: String
        var formatter: QuantityFormatter
        /// Focus while manipulating all equations at once.
        var systemFocus: StepFocus
        /// Focus for one equation (the node / loop it came from), in the same order as the equations.
        var equationFocus: [StepFocus]
        /// Focus that highlights a solved unknown.
        var solvedFocus: (String, Double) -> StepFocus
        /// Prose name of an unknown, e.g. "the voltage at node b relative to ground".
        var describe: (String) -> String
    }

    /// One equation of the system, in floating point and (while the numbers allow it) exactly.
    private struct Row {
        var equation: DisplayEquation
        var exact: ExactEquation?
        var label: String
        var focus: StepFocus

        func coefficient(of symbol: String) -> Double { equation.coefficient(of: symbol) }

        func scaled(by factor: Double, exactly exactFactor: Fraction?) -> Row {
            var copy = self
            if let exactFactor, let scaled = exact?.scaled(by: exactFactor) {
                copy.exact = scaled
                copy.equation = scaled.display
            } else {
                copy.exact = nil
                copy.equation = equation.scaled(by: factor)
            }
            return copy
        }

        /// self + sign × other, with `symbol` forced to exactly zero.
        func combined(with other: Row, sign: Double, eliminating symbol: String) -> Row {
            var copy = self
            if let mine = exact, let theirs = other.exact, let sum = mine.adding(theirs, times: Fraction(integer: Int64(sign))) {
                var exactSum = sum
                exactSum.coefficients[symbol] = .zero
                copy.exact = exactSum
                copy.equation = exactSum.display
            } else {
                copy.exact = nil
                copy.equation = equation.subtracting(other.equation, times: -sign, eliminating: symbol)
            }
            return copy
        }
    }

    /// A number in the working: exact when the whole chain of arithmetic was exact.
    private struct Value {
        var double: Double
        var exact: Fraction?

        var isZero: Bool { exact?.isZero ?? (abs(double) < 1e-12) }
        var isNegative: Bool { exact.map { $0.num < 0 } ?? (double < 0) }
        var magnitude: Value { Value(double: abs(double), exact: exact?.magnitude) }
        var negated: Value { Value(double: -double, exact: exact?.negated) }

        func times(_ other: Value) -> Value {
            Value(double: double * other.double, exact: exact.flatMap { a in other.exact.flatMap { a.multiplied(by: $0) } })
        }
        func minus(_ other: Value) -> Value {
            Value(double: double - other.double, exact: exact.flatMap { a in other.exact.flatMap { a.subtracting($0) } })
        }
        func dividedBy(_ other: Value) -> Value {
            let exactQuotient = exact.flatMap { a in other.exact.flatMap { a.divided(by: $0) } }
            return Value(double: exactQuotient?.double ?? (double / other.double), exact: exactQuotient)
        }
    }

    /// Nil when the system is not square or turns out singular; the caller then shows a plain summary.
    static func narrate(_ equations: [DisplayEquation], options: Options) -> NarratedSystem? {
        let f = options.formatter
        let unknowns = options.unknowns
        let n = unknowns.count
        guard n > 0, equations.count == n else { return nil }

        let exactEquations = equations.map { ExactEquation($0) }
        let exactMode = exactEquations.allSatisfy { $0 != nil }
        var rows = equations.enumerated().map { index, equation in
            Row(
                equation: equation,
                exact: exactMode ? exactEquations[index] : nil,
                label: "(\(index + 1))",
                focus: index < options.equationFocus.count ? options.equationFocus[index] : options.systemFocus
            )
        }
        var steps: [AnalysisStep] = []
        var solution: [String: Value] = [:]

        // MARK: Text helpers

        func render(_ row: Row) -> String { row.equation.rendered(with: f, order: unknowns) }
        func valueText(_ value: Value) -> String { f.format(value.double, options.unit) }
        /// A number as it appears in the working: a readable exact fraction, else a decimal with a guard digit.
        func numberText(_ value: Value) -> String {
            if let x = value.exact, x.isReadable { return x.text }
            return f.precise(value.double)
        }
        func termText(_ value: Value) -> String {
            if let x = value.exact, x.isReadable { return x.termText }
            return f.preciseTerm(value.double)
        }
        /// A number as an equation line shows it (whole numbers as they are, anything else as a
        /// decimal), so that a value quoted from a line above looks the way it did there.
        func rowNumberText(_ value: Value) -> String {
            if let x = value.exact, x.isInteger { return x.text }
            return f.precise(value.double)
        }
        func rowTermText(_ value: Value) -> String {
            value.isNegative ? "(\(rowNumberText(value)))" : rowNumberText(value)
        }
        func value(of row: Row, coefficient symbol: String) -> Value {
            Value(double: row.coefficient(of: symbol), exact: row.exact?.coefficient(of: symbol))
        }
        func constant(of row: Row) -> Value { Value(double: row.equation.constant, exact: row.exact?.constant) }
        /// "17·Vb", "Vb", "−Vb", "−5·Vb".
        func pivotText(_ a: Value, _ symbol: String) -> String {
            let magnitude = a.magnitude
            let unit = abs(magnitude.double - 1) < 1e-12
            return (a.isNegative ? "−" : "") + (unit ? symbol : "\(rowNumberText(magnitude))·\(symbol)")
        }
        func appendUnique(_ line: String, to lines: inout [String]) {
            if lines.last != line { lines.append(line) }
        }
        func mergedFocus(_ a: StepFocus, _ b: StepFocus) -> StepFocus {
            var focus = a
            for node in b.nodes where !focus.nodes.contains(node) { focus.nodes.append(node) }
            for element in b.elements where !focus.elements.contains(element) { focus.elements.append(element) }
            for loop in b.loops where !focus.loops.contains(loop) { focus.loops.append(loop) }
            focus.showMeshArrows = a.showMeshArrows || b.showMeshArrows
            focus.zoom = a.zoom && b.zoom
            return focus
        }

        /// The final division "Vc = 4600/775 = 184/31" (and the value), for a·symbol = constant.
        /// `constantText` is the constant as the line above wrote it, so the division quotes it exactly.
        func divide(_ symbol: String, by a: Value, constant: Value, constantText: String) -> (lines: [String], value: Value) {
            let value = constant.dividedBy(a)
            var lines: [String] = []
            if abs(abs(a.double) - 1) < 1e-12 {
                if a.isNegative {
                    let negated = constantText.hasPrefix("−") ? String(constantText.dropFirst()) : "−" + constantText
                    lines.append("\(symbol) = \(negated)")
                }
            } else {
                let numerator = constantText.hasPrefix("−") || constantText.contains("/") ? "(\(constantText))" : constantText
                var line = "\(symbol) = \(numerator)/\(rowTermText(a))"
                if let x = value.exact, x.isReadable, !x.isInteger, x.text != "\(constantText)/\(rowNumberText(a))" {
                    line += " = \(x.text)"
                }
                lines.append(line)
            }
            lines.append("→ \(symbol) = \(valueText(value))")
            return (lines, value)
        }

        /// "Divide both sides by 775" / "The coefficient of Vc is 1, so the equation already gives it".
        func divisionWords(_ a: Value, _ symbol: String) -> String {
            if abs(a.double - 1) < 1e-12 { return "The coefficient of \(symbol) is 1, so the equation already gives its value" }
            if abs(a.double + 1) < 1e-12 { return "The coefficient of \(symbol) is −1, so changing the sign on both sides gives its value" }
            return "Divide both sides by \(rowNumberText(a.magnitude))\(a.isNegative ? " (keeping the minus sign)" : "")"
        }

        // MARK: One unknown: divide

        if n == 1 {
            let symbol = unknowns[0]
            let row = rows[0]
            let a = value(of: row, coefficient: symbol)
            guard abs(a.double) > 1e-12 else { return nil }
            let (divisionLines, result) = divide(symbol, by: a, constant: constant(of: row), constantText: rowNumberText(constant(of: row)))
            solution[symbol] = result
            steps.append(AnalysisStep(
                title: "Solve for \(symbol)",
                summary: "One equation, one unknown",
                equations: [render(row)] + divisionLines,
                explanation: "Only \(symbol) is unknown. \(divisionWords(a, symbol)). \(symbol) is \(options.describe(symbol)).",
                result: "\(symbol) = \(valueText(result))",
                focus: options.solvedFocus(symbol, result.double)
            ))
            return NarratedSystem(steps: steps, solution: solution.mapValues(\.double))
        }

        // MARK: Several unknowns: number the equations, eliminate one unknown at a time, then substitute back

        steps.append(AnalysisStep(
            title: "Line up the equations",
            summary: "\(n) equations, \(n) unknowns: \(unknowns.joined(separator: ", "))",
            equations: rows.map { "\($0.label)  \(render($0))" },
            explanation: "\(n) unknowns need \(n) independent equations, and we have exactly that many. Numbering them makes the next moves easy to follow: we combine two equations at a time so that one unknown disappears, until a single equation with a single unknown is left.",
            result: "\(n) equations ready",
            focus: options.systemFocus
        ))

        var remaining = Array(rows.indices)          // rows still carrying unknowns
        var pivots: [(row: Int, symbol: String)] = []
        var eliminationOrder = unknowns

        while remaining.count > 1 {
            // An equation that already contains a single unknown needs no elimination: it is
            // solved directly in the substitution phase (decoupled meshes, for example).
            if let solo = remaining.first(where: { r in
                let present = rows[r].equation.unknownSymbols.filter { unknowns.contains($0) }
                return present.count == 1 && !pivots.contains { $0.symbol == present[0] }
            }) {
                let symbol = rows[solo].equation.unknownSymbols.filter { unknowns.contains($0) }[0]
                pivots.append((solo, symbol))
                eliminationOrder.removeAll { $0 == symbol }
                remaining.removeAll { $0 == solo }
                continue
            }
            // Textbook order: eliminate the first unknown using the first equation that has it,
            // unless another equation has that unknown with coefficient ±1 (then that one is easier).
            var best: (symbol: String, row: Int, score: Double)?
            for symbol in eliminationOrder {
                for (position, r) in remaining.enumerated() {
                    let c = rows[r].coefficient(of: symbol)
                    guard abs(c) > 1e-12 else { continue }
                    let others = remaining.filter { $0 != r && abs(rows[$0].coefficient(of: symbol)) > 1e-12 }
                    guard !others.isEmpty else { continue }
                    let unit = abs(abs(c) - 1) < 1e-12
                    let score = (unit ? 0.0 : 10.0) + Double(position)
                    if best == nil || score < best!.score { best = (symbol, r, score) }
                }
                if best != nil { break }
            }
            guard let pivot = best else { return nil }
            let symbol = pivot.symbol
            let k = pivot.row
            pivots.append((k, symbol))
            eliminationOrder.removeAll { $0 == symbol }
            let a = value(of: rows[k], coefficient: symbol)

            for i in remaining where i != k {
                let b = value(of: rows[i], coefficient: symbol)
                guard abs(b.double) > 1e-12 else { continue }
                var lines: [String] = []
                let newLabel = rows[i].label.replacingOccurrences(of: ")", with: "′)")
                let sameSign = a.isNegative == b.isNegative
                var newRow: Row
                var explanation: String

                // Whole-number multipliers: bring both coefficients to a common integer and divide by their gcd.
                var integerMultipliers: (mi: Int64, mk: Int64)?
                if let ea = a.exact, let eb = b.exact {
                    let g = max(1, NiceNumbers.gcd(ea.den, eb.den))
                    let (l, o1) = ea.den.multipliedReportingOverflow(by: eb.den / g)
                    if !o1 {
                        let (A, o2) = ea.num.multipliedReportingOverflow(by: l / ea.den)
                        let (B, o3) = eb.num.multipliedReportingOverflow(by: l / eb.den)
                        if !o2, !o3, A != 0, B != 0 {
                            let gg = max(1, NiceNumbers.gcd(A, B))
                            let mk = abs(B) / gg, mi = abs(A) / gg
                            if max(mk, mi) <= 99 { integerMultipliers = (mi, mk) }
                        }
                    }
                } else if NiceNumbers.isInteger(a.double), NiceNumbers.isInteger(b.double) {
                    let A = Int64(a.double.rounded()), B = Int64(b.double.rounded())
                    let g = max(1, NiceNumbers.gcd(A, B))
                    let mk = abs(B) / g, mi = abs(A) / g
                    if max(mk, mi) <= 99 { integerMultipliers = (mi, mk) }
                }

                if let (mi, mk) = integerMultipliers {
                    let scaledK = rows[k].scaled(by: Double(mk), exactly: Fraction(integer: mk))
                    let scaledI = rows[i].scaled(by: Double(mi), exactly: Fraction(integer: mi))
                    if mk != 1 { lines.append("\(mk)×\(rows[k].label): \(render(scaledK))") }
                    if mi != 1 { lines.append("\(mi)×\(rows[i].label): \(render(scaledI))") }
                    newRow = scaledI.combined(with: scaledK, sign: sameSign ? -1 : 1, eliminating: symbol)
                    let opI = (mi == 1 ? "" : "\(mi)×") + rows[i].label
                    let opK = (mk == 1 ? "" : "\(mk)×") + rows[k].label
                    lines.append("\(newLabel) = \(opI) \(sameSign ? "−" : "+") \(opK):  \(render(newRow))")
                    let target = "\(rowNumberText(value(of: scaledK, coefficient: symbol).magnitude))·\(symbol)"
                    let signs = sameSign ? "" : " with opposite signs"
                    let preparation: String
                    switch (mk != 1, mi != 1) {
                    case (true, true): preparation = "Multiply \(rows[k].label) by \(mk) and \(rows[i].label) by \(mi) so that both contain \(target)\(signs)"
                    case (true, false): preparation = "Multiply \(rows[k].label) by \(mk) so that it contains \(target) like \(rows[i].label)\(signs)"
                    case (false, true): preparation = "Multiply \(rows[i].label) by \(mi) so that it contains \(target) like \(rows[k].label)\(signs)"
                    case (false, false): preparation = "Both equations already contain \(target)\(signs)"
                    }
                    let operation = sameSign ? "subtract \(opK) from \(opI)" : "add them"
                    explanation = "\(preparation), then \(operation): the \(symbol) terms cancel."
                } else {
                    // Whole-number multipliers would be unwieldy: scale the pivot row by the ratio
                    // b/a itself, shown as the fraction of the two coefficients when it is one.
                    let m = b.dividedBy(a)
                    let ratio = m.exact?.magnitude
                    let mProse = ratio.map { !$0.isInteger && $0.num <= 999_999 && $0.den <= 999_999 ? $0.text : numberText(m.magnitude) } ?? numberText(m.magnitude)
                    let mText = mProse.contains("/") ? "(\(mProse))" : mProse
                    let scaledK = rows[k].scaled(by: abs(m.double), exactly: ratio)
                    lines.append("\(mText)×\(rows[k].label): \(render(scaledK))")
                    newRow = rows[i].combined(with: scaledK, sign: sameSign ? -1 : 1, eliminating: symbol)
                    lines.append("\(newLabel) = \(rows[i].label) \(sameSign ? "−" : "+") \(mText)×\(rows[k].label):  \(render(newRow))")
                    let target = "\(rowNumberText(value(of: scaledK, coefficient: symbol).magnitude))·\(symbol)"
                    explanation = "Multiply \(rows[k].label) by \(mProse) so that its \(symbol) term becomes \(target), matching \(rows[i].label)\(sameSign ? "" : " with the opposite sign"), then \(sameSign ? "subtract it from" : "add it to") \(rows[i].label): the \(symbol) terms cancel."
                }
                newRow.label = newLabel
                let remainingUnknowns = newRow.equation.unknownSymbols.filter { unknowns.contains($0) }
                explanation += " \(newLabel) is left with \(remainingUnknowns.isEmpty ? "numbers only" : "only " + remainingUnknowns.joined(separator: ", "))."
                steps.append(AnalysisStep(
                    title: "Eliminate \(symbol) from \(rows[i].label)",
                    summary: "Combine \(rows[k].label) and \(rows[i].label) so the \(symbol) terms cancel",
                    equations: lines,
                    explanation: explanation,
                    result: "\(newLabel)  \(render(newRow))",
                    focus: mergedFocus(rows[k].focus, rows[i].focus)
                ))
                rows[i] = newRow
            }
            remaining.removeAll { $0 == k }
        }

        // The last row has a single unknown left (plus, possibly, unknowns other rows gave directly).
        guard let lastIndex = remaining.first else { return nil }
        let lastUnknowns = rows[lastIndex].equation.unknownSymbols.filter { symbol in
            unknowns.contains(symbol) && !pivots.contains { $0.symbol == symbol }
        }
        guard lastUnknowns.count == 1 else { return nil }
        pivots.append((lastIndex, lastUnknowns[0]))

        // MARK: Back substitution: the most-reduced equation first, then upwards

        var unsolved = pivots
        while !unsolved.isEmpty {
            func solvable(_ p: (row: Int, symbol: String)) -> Bool {
                rows[p.row].equation.unknownSymbols.allSatisfy { $0 == p.symbol || !unknowns.contains($0) || solution[$0] != nil }
            }
            func depth(_ p: (row: Int, symbol: String)) -> Int { rows[p.row].label.filter { $0 == "′" }.count }
            guard let pivot = unsolved.filter(solvable).max(by: { (depth($0), -$0.row) < (depth($1), -$1.row) }) else { return nil }
            unsolved.removeAll { $0.row == pivot.row && $0.symbol == pivot.symbol }
            let row = rows[pivot.row]
            let symbol = pivot.symbol
            let a = value(of: row, coefficient: symbol)
            guard abs(a.double) > 1e-12 else { return nil }
            var lines = ["\(row.label)  \(render(row))"]
            var rhs = constant(of: row)
            var rhsText = rowNumberText(rhs)
            let others = row.equation.unknownSymbols.filter { $0 != symbol && unknowns.contains($0) }
            var substitutedWords = ""
            if !others.isEmpty {
                // 1. Put the known values in.
                var substitution: [String: String] = [:]
                var products: [(symbol: String, value: Value)] = []
                for other in others {
                    guard let known = solution[other] else { return nil }
                    let coefficient = value(of: row, coefficient: other)
                    // "− 2·(184/31)" needs the brackets; "+ 39/7" (coefficient 1) does not.
                    let unit = abs(abs(coefficient.double) - 1) < 1e-12
                    substitution[other] = unit && !known.isNegative ? numberText(known) : termText(known)
                    products.append((other, coefficient.times(known)))
                }
                appendUnique(row.equation.rendered(with: f, order: unknowns, substituting: substitution), to: &lines)
                // 2. Work out the products.
                let lead = pivotText(a, symbol)
                var worked = lead
                for product in products {
                    worked += (product.value.isNegative ? " − " : " + ") + numberText(product.value.magnitude)
                }
                appendUnique("\(worked) = \(rowNumberText(rhs))", to: &lines)
                // 3. Move the numbers to the right-hand side.
                var parts: [String] = []
                if !rhs.isZero { parts.append(rowNumberText(rhs)) }
                for product in products {
                    parts.append((product.value.isNegative ? "+" : "−") + numberText(product.value.magnitude))
                    rhs = rhs.minus(product.value)
                }
                var moved = ""
                for part in parts {
                    if moved.isEmpty {
                        moved = part.hasPrefix("+") ? String(part.dropFirst()) : part
                    } else if part.hasPrefix("+") {
                        moved += " + " + part.dropFirst()
                    } else if part.hasPrefix("−") {
                        moved += " − " + part.dropFirst()
                    } else {
                        moved += " + " + part
                    }
                }
                if moved.isEmpty { moved = "0" }
                let total = numberText(rhs)
                rhsText = total
                appendUnique("\(lead) = \(moved)" + (moved == total ? "" : " = \(total)"), to: &lines)
                let knownWords = others.map { "\($0) = \(numberText(solution[$0] ?? Value(double: 0, exact: nil)))" }.joined(separator: " and ")
                substitutedWords = "Put in \(knownWords), work out the product\(others.count == 1 ? "" : "s") and move the numbers to the right-hand side. "
            }
            // 4. Divide.
            let (divisionLines, result) = divide(symbol, by: a, constant: rhs, constantText: rhsText)
            for line in divisionLines { appendUnique(line, to: &lines) }
            solution[symbol] = result
            let direct = others.isEmpty
            steps.append(AnalysisStep(
                title: direct ? "Solve for \(symbol)" : "Back-substitute to get \(symbol)",
                summary: direct ? "\(row.label) has only \(symbol) left" : "Put the known value\(others.count > 1 ? "s" : "") into \(row.label)",
                equations: lines,
                explanation: (direct
                    ? "\(row.label.contains("′") ? "After the eliminations, " : "")\(row.label) contains a single unknown. \(divisionWords(a, symbol)). "
                    : "\(row.label) still contains \(symbol). \(substitutedWords)\(divisionWords(a, symbol)). ")
                    + "\(symbol) is \(options.describe(symbol)).",
                result: "\(symbol) = \(valueText(result))",
                focus: options.solvedFocus(symbol, result.double)
            ))
        }

        guard solution.count == n else { return nil }
        return NarratedSystem(steps: steps, solution: solution.mapValues(\.double))
    }
}
