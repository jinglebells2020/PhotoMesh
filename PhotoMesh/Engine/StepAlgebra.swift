import Foundation

/// Keeps the arithmetic in the steps looking the way a textbook writes it: integers where possible,
/// fractions cleared with a common multiple, and systems solved by elimination one operation at a time.
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

    /// "5·V₂ − 2·V₃ = 96", symbols in `order`; known symbols are replaced by their numbers and
    /// left on the left-hand side so the reader sees the substitution before it is simplified.
    func rendered(with f: QuantityFormatter, order: [String], substituting known: [String: Double] = [:]) -> String {
        var lhs = ""
        let ordered = order.filter { symbols.contains($0) } + symbols.filter { !order.contains($0) }
        for symbol in ordered {
            let c = coefficients[symbol] ?? 0
            guard abs(c) > 1e-12 else { continue }
            let magnitude = abs(c)
            let body: String
            if let value = known[symbol] {
                let numberText = f.term(value)
                body = abs(magnitude - 1) < 1e-12 ? numberText : "\(f.number(magnitude))·\(numberText)"
            } else {
                body = abs(magnitude - 1) < 1e-12 ? symbol : "\(f.number(magnitude))·\(symbol)"
            }
            if lhs.isEmpty {
                lhs = (c < 0 ? "−" : "") + body
            } else {
                lhs += (c < 0 ? " − " : " + ") + body
            }
        }
        if lhs.isEmpty { lhs = "0" }
        return "\(lhs) = \(f.number(constant))"
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
        /// Unknown symbols in display order (e.g. V₁, V₂, V₃ or I₁, I₂).
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
        /// Prose name of an unknown, e.g. "the voltage at node n2".
        var describe: (String) -> String
    }

    private struct Row {
        var equation: DisplayEquation
        var label: String
        var focus: StepFocus
        var pivotSymbol: String?
    }

    /// Nil when the system is not square or turns out singular; the caller then shows a plain summary.
    static func narrate(_ equations: [DisplayEquation], options: Options) -> NarratedSystem? {
        let f = options.formatter
        let unknowns = options.unknowns
        let n = unknowns.count
        guard n > 0, equations.count == n else { return nil }
        var rows = equations.enumerated().map { index, equation in
            Row(equation: equation, label: "(\(index + 1))", focus: index < options.equationFocus.count ? options.equationFocus[index] : options.systemFocus)
        }
        var steps: [AnalysisStep] = []
        var solution: [String: Double] = [:]

        func valueText(_ value: Double) -> String { f.format(value, options.unit) }
        func mergedFocus(_ a: StepFocus, _ b: StepFocus) -> StepFocus {
            var focus = a
            for node in b.nodes where !focus.nodes.contains(node) { focus.nodes.append(node) }
            for element in b.elements where !focus.elements.contains(element) { focus.elements.append(element) }
            for loop in b.loops where !focus.loops.contains(loop) { focus.loops.append(loop) }
            focus.showMeshArrows = a.showMeshArrows || b.showMeshArrows
            focus.zoom = a.zoom && b.zoom
            return focus
        }

        // One unknown: divide.
        if n == 1 {
            let symbol = unknowns[0]
            let row = rows[0]
            let a = row.equation.coefficient(of: symbol)
            guard abs(a) > 1e-12 else { return nil }
            let value = row.equation.constant / a
            solution[symbol] = value
            var lines = [row.equation.rendered(with: f, order: unknowns)]
            if abs(abs(a) - 1) > 1e-12 {
                lines.append("\(symbol) = \(f.number(row.equation.constant))/\(f.term(a))")
            }
            lines.append("→ \(symbol) = \(valueText(value))")
            steps.append(AnalysisStep(
                title: "Solve for \(symbol)",
                summary: "One equation, one unknown",
                equations: lines,
                explanation: "Only \(symbol) is unknown, so divide both sides by its coefficient. \(symbol) is \(options.describe(symbol)).",
                result: "\(symbol) = \(valueText(value))",
                focus: options.solvedFocus(symbol, value)
            ))
            return NarratedSystem(steps: steps, solution: solution)
        }

        // Several unknowns: number the equations, eliminate one unknown at a time, then substitute back.
        steps.append(AnalysisStep(
            title: "Line up the equations",
            summary: "\(n) equations, \(n) unknowns: \(unknowns.joined(separator: ", "))",
            equations: rows.map { "\($0.label)  \($0.equation.rendered(with: f, order: unknowns))" },
            explanation: "\(n) unknowns need \(n) independent equations. Numbering them makes the next moves easy to follow: we will combine pairs so that one unknown disappears at a time.",
            result: "\(n) equations ready",
            focus: options.systemFocus
        ))

        var remaining = Array(rows.indices)          // rows still carrying unknowns
        var pivots: [(row: Int, symbol: String)] = []
        var eliminationOrder = unknowns

        while remaining.count > 1 {
            // Textbook order: eliminate the first unknown using the first equation that has it,
            // unless another equation has that unknown with coefficient ±1 (then that one is easier).
            var best: (symbol: String, row: Int, score: Double)?
            for symbol in eliminationOrder {
                for (position, r) in remaining.enumerated() {
                    let c = rows[r].equation.coefficient(of: symbol)
                    guard abs(c) > 1e-12 else { continue }
                    let others = remaining.filter { $0 != r && abs(rows[$0].equation.coefficient(of: symbol)) > 1e-12 }
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
            let a = rows[k].equation.coefficient(of: symbol)

            for i in remaining where i != k {
                let b = rows[i].equation.coefficient(of: symbol)
                guard abs(b) > 1e-12 else { continue }
                var lines: [String] = []
                let newLabel = rows[i].label.replacingOccurrences(of: ")", with: "′)")
                let newEquation: DisplayEquation
                let verb: String
                if NiceNumbers.isInteger(a), NiceNumbers.isInteger(b) {
                    let g = Double(NiceNumbers.gcd(Int64(a.rounded()), Int64(b.rounded())))
                    let mk = abs(b) / g, mi = abs(a) / g
                    let sameSign = (a > 0) == (b > 0)
                    verb = sameSign ? "subtract" : "add"
                    if abs(mk - 1) > 1e-12 {
                        lines.append("\(f.number(mk))×\(rows[k].label): \(rows[k].equation.scaled(by: mk).rendered(with: f, order: unknowns))")
                    }
                    if abs(mi - 1) > 1e-12 {
                        lines.append("\(f.number(mi))×\(rows[i].label): \(rows[i].equation.scaled(by: mi).rendered(with: f, order: unknowns))")
                    }
                    let scaledI = rows[i].equation.scaled(by: mi)
                    let scaledK = rows[k].equation.scaled(by: mk)
                    newEquation = scaledI.subtracting(scaledK, times: sameSign ? 1 : -1, eliminating: symbol)
                    let operation = sameSign
                        ? "\(mi == 1 ? "" : f.number(mi) + "×")\(rows[i].label) − \(mk == 1 ? "" : f.number(mk) + "×")\(rows[k].label)"
                        : "\(mi == 1 ? "" : f.number(mi) + "×")\(rows[i].label) + \(mk == 1 ? "" : f.number(mk) + "×")\(rows[k].label)"
                    lines.append("\(operation): \(newEquation.rendered(with: f, order: unknowns))")
                } else {
                    let m = b / a
                    verb = m > 0 ? "subtract" : "add"
                    lines.append("\(f.number(abs(m)))×\(rows[k].label): \(rows[k].equation.scaled(by: abs(m)).rendered(with: f, order: unknowns))")
                    newEquation = rows[i].equation.subtracting(rows[k].equation, times: m, eliminating: symbol)
                    lines.append("\(rows[i].label) \(m > 0 ? "−" : "+") \(f.number(abs(m)))×\(rows[k].label): \(newEquation.rendered(with: f, order: unknowns))")
                }
                lines.append("→ \(newLabel)  \(newEquation.rendered(with: f, order: unknowns))")
                let remainingUnknowns = newEquation.unknownSymbols.filter { unknowns.contains($0) }
                steps.append(AnalysisStep(
                    title: "Eliminate \(symbol) from \(rows[i].label)",
                    summary: "Combine \(rows[k].label) and \(rows[i].label) so the \(symbol) terms cancel",
                    equations: lines,
                    explanation: "Scale the two equations until their \(symbol) terms are equal, then \(verb) one from the other. \(symbol) drops out, leaving \(newLabel) with only \(remainingUnknowns.isEmpty ? "numbers" : remainingUnknowns.joined(separator: ", ")).",
                    result: "\(newLabel)  \(newEquation.rendered(with: f, order: unknowns))",
                    focus: mergedFocus(rows[k].focus, rows[i].focus)
                ))
                rows[i].equation = newEquation
                rows[i].label = newLabel
            }
            rows[k].pivotSymbol = symbol
            remaining.removeAll { $0 == k }
        }

        // The last row has a single unknown.
        guard let lastIndex = remaining.first else { return nil }
        let lastUnknowns = rows[lastIndex].equation.unknownSymbols.filter { unknowns.contains($0) }
        guard lastUnknowns.count == 1 else { return nil }
        let lastSymbol = lastUnknowns[0]
        rows[lastIndex].pivotSymbol = lastSymbol
        pivots.append((lastIndex, lastSymbol))

        // Back substitution, last pivot first.
        for (position, pivot) in pivots.reversed().enumerated() {
            let row = rows[pivot.row]
            let symbol = pivot.symbol
            let a = row.equation.coefficient(of: symbol)
            guard abs(a) > 1e-12 else { return nil }
            var lines: [String] = []
            var constant = row.equation.constant
            let known = solution
            let substituted = row.equation.unknownSymbols.contains { $0 != symbol && known[$0] != nil }
            lines.append("\(row.label)  \(row.equation.rendered(with: f, order: unknowns))")
            if substituted {
                lines.append(row.equation.rendered(with: f, order: unknowns, substituting: known))
                var products = 0.0
                for other in row.equation.unknownSymbols where other != symbol {
                    guard let value = known[other] else { return nil }
                    products += row.equation.coefficient(of: other) * value
                }
                constant -= products
                // The products worked out, then the constant moved across.
                let pivotText = abs(abs(a) - 1) < 1e-12 ? (a < 0 ? "−" + symbol : symbol) : "\(f.number(abs(a)))·\(symbol)".replacingOccurrences(of: "\(f.number(abs(a)))·", with: (a < 0 ? "−" : "") + "\(f.number(abs(a)))·")
                lines.append("\(pivotText) \(products < 0 ? "−" : "+") \(f.number(abs(products))) = \(f.number(row.equation.constant))")
                var isolated = DisplayEquation()
                isolated.add(a, to: symbol)
                isolated.addConstant(constant)
                lines.append(isolated.rendered(with: f, order: unknowns))
            }
            let value = constant / a
            solution[symbol] = value
            if abs(abs(a) - 1) > 1e-12 {
                lines.append("\(symbol) = \(f.number(constant))/\(f.term(a))")
            }
            lines.append("→ \(symbol) = \(valueText(value))")
            let isFirst = position == 0
            steps.append(AnalysisStep(
                title: isFirst ? "Solve for \(symbol)" : "Back-substitute to get \(symbol)",
                summary: isFirst ? "\(row.label) has only \(symbol) left" : "Put the known value\(solution.count > 2 ? "s" : "") into \(row.label)",
                equations: lines,
                explanation: isFirst
                    ? "After elimination, \(row.label) contains a single unknown. Divide by its coefficient. \(symbol) is \(options.describe(symbol))."
                    : "\(row.label) still holds \(symbol). Replace the unknowns we already know by their numbers, move the constants to the right, and divide. \(symbol) is \(options.describe(symbol)).",
                result: "\(symbol) = \(valueText(value))",
                focus: options.solvedFocus(symbol, value)
            ))
        }

        guard solution.count == n else { return nil }
        return NarratedSystem(steps: steps, solution: solution)
    }
}
