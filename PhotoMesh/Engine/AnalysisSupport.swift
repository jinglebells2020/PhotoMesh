import Foundation

/// Shared naming, equation formatting, element bookkeeping and answer building for both methods.
struct AnalysisContext {
    let circuit: Circuit
    let formatter: QuantityFormatter

    // MARK: Symbols

    /// "V₁" for node "n1", "V(A)" for other ids, nil for the reference node.
    func voltageSymbol(_ node: String) -> String? {
        guard node != circuit.groundNode else { return nil }
        return AnalysisContext.voltageSymbol(forNodeId: node)
    }

    static func voltageSymbol(forNodeId node: String) -> String {
        if node.count > 1, node.first == "n", node.dropFirst().allSatisfy(\.isNumber) {
            return "V" + QuantityFormatter.subscriptDigits(String(node.dropFirst()))
        }
        return "V(\(node))"
    }

    /// The voltage of a node as it appears inside an equation: a symbol, or a number when known.
    func voltageTerm(_ node: String, known: [String: Double]) -> String {
        if node == circuit.groundNode { return "0" }
        if let value = known[node] { return formatter.term(value) }
        return voltageSymbol(node) ?? "0"
    }

    func currentSymbol(_ elementId: String) -> String { "I(\(elementId))" }
    func elementVoltageSymbol(_ elementId: String) -> String { "V(\(elementId))" }
    func meshCurrentSymbol(_ index: Int) -> String { "I" + QuantityFormatter.subscriptDigits(String(index + 1)) }

    func ohms(_ value: Double) -> String { formatter.format(value, "Ω") }
    func volts(_ value: Double) -> String { formatter.format(value, "V") }
    func amps(_ value: Double) -> String { formatter.format(value, "A") }
    func watts(_ value: Double) -> String { formatter.format(value, "W") }

    func describe(_ component: Component) -> String {
        switch component.kind {
        case .resistor:
            return "\(component.id) = \(ohms(component.value)) between \(component.nodeA) and \(component.nodeB)"
        case .voltageSource:
            return "\(component.id) = \(volts(component.value)), + at \(component.nodeA), − at \(component.nodeB)"
        case .currentSource:
            return "\(component.id) = \(amps(component.value)) from \(component.nodeA) into \(component.nodeB)"
        }
    }
}

// MARK: - Linear equations for display

/// Σ coefficient·symbol = constant, kept in insertion order of the symbols.
struct DisplayEquation {
    var symbols: [String] = []
    var coefficients: [String: Double] = [:]
    var constant: Double = 0

    mutating func add(_ coefficient: Double, to symbol: String) {
        if coefficients[symbol] == nil { symbols.append(symbol) }
        coefficients[symbol, default: 0] += coefficient
    }

    mutating func addConstant(_ value: Double) {
        constant += value
    }

    /// Adds `scale` × `other` into this equation.
    mutating func add(_ other: DisplayEquation, scale: Double = 1) {
        for symbol in other.symbols { add(scale * (other.coefficients[symbol] ?? 0), to: symbol) }
        constant += scale * other.constant
    }

    var isTrivial: Bool { symbols.allSatisfy { abs(coefficients[$0] ?? 0) < 1e-12 } }

    /// "0.01455·V₂ − 0.01·V₁ = 0.002"
    func rendered(with formatter: QuantityFormatter) -> String {
        var lhs = ""
        for symbol in symbols {
            let c = coefficients[symbol] ?? 0
            guard abs(c) > 1e-12 else { continue }
            let magnitude = abs(c)
            let factor = abs(magnitude - 1) < 1e-12 ? "" : "\(formatter.number(magnitude))·"
            if lhs.isEmpty {
                lhs = (c < 0 ? "−" : "") + factor + symbol
            } else {
                lhs += (c < 0 ? " − " : " + ") + factor + symbol
            }
        }
        if lhs.isEmpty { lhs = "0" }
        return "\(lhs) = \(formatter.number(constant))"
    }
}

/// Builds "term + term − term = 0" strings from signed pieces.
struct TermList {
    private var pieces: [(negative: Bool, text: String)] = []

    mutating func add(_ text: String, negative: Bool = false) {
        pieces.append((negative, text))
    }

    var isEmpty: Bool { pieces.isEmpty }

    func rendered(rhs: String = "0") -> String {
        "\(renderedLeftSide()) = \(rhs)"
    }

    func renderedLeftSide() -> String {
        var out = ""
        for (index, piece) in pieces.enumerated() {
            if index == 0 {
                out = (piece.negative ? "−" : "") + piece.text
            } else {
                out += (piece.negative ? " − " : " + ") + piece.text
            }
        }
        if out.isEmpty { out = "0" }
        return out
    }
}

// MARK: - Element results

enum ElementResults {
    /// Derives every element's current and voltage from node voltages.
    /// `sourceCurrents` supplies the current through each voltage source (from + to − inside the source).
    static func compute(circuit: Circuit, voltages: [String: Double], sourceCurrents: [String: Double]) -> [ElementResult] {
        circuit.components.map { component in
            let va = voltages[component.nodeA] ?? 0
            let vb = voltages[component.nodeB] ?? 0
            switch component.kind {
            case .resistor:
                let v = va - vb
                return ElementResult(id: component.id, kind: .resistor, value: component.value, nodeA: component.nodeA, nodeB: component.nodeB, current: v / component.value, voltage: v)
            case .voltageSource:
                return ElementResult(id: component.id, kind: .voltageSource, value: component.value, nodeA: component.nodeA, nodeB: component.nodeB, current: sourceCurrents[component.id] ?? 0, voltage: component.value)
            case .currentSource:
                return ElementResult(id: component.id, kind: .currentSource, value: component.value, nodeA: component.nodeA, nodeB: component.nodeB, current: component.value, voltage: va - vb)
            }
        }
    }

    /// Current leaving `node` through `element` (positive when it flows away from the node).
    static func currentLeaving(_ node: String, through element: ElementResult) -> Double {
        element.nodeA == node ? element.current : -element.current
    }
}

// MARK: - Answers

enum Answers {
    static func build(context: AnalysisContext, voltages: [String: Double], elements: [ElementResult]) -> [Answer] {
        let circuit = context.circuit
        let f = context.formatter
        let byId = Dictionary(uniqueKeysWithValues: elements.map { ($0.id, $0) })
        var answers: [Answer] = []

        for unknown in circuit.unknowns {
            switch unknown.kind {
            case .current:
                guard let id = unknown.element, let element = byId[id] else { continue }
                answers.append(Answer(label: "Current through \(id)", value: currentDescription(element, context: context)))
            case .voltage:
                if let id = unknown.element, let element = byId[id] {
                    answers.append(Answer(label: "Voltage across \(id)", value: voltageDescription(element, context: context)))
                } else if let node = unknown.node, let v = voltages[node] {
                    answers.append(Answer(label: "Voltage at node \(node)", value: context.volts(v)))
                } else if let pair = unknown.between, pair.count == 2, let va = voltages[pair[0]], let vb = voltages[pair[1]] {
                    answers.append(Answer(label: "Voltage from \(pair[0]) to \(pair[1])", value: context.volts(va - vb)))
                }
            case .power:
                guard let id = unknown.element, let element = byId[id] else { continue }
                let p = element.power
                let verb = element.kind == .resistor ? "dissipated" : (p >= 0 ? "absorbed" : "delivered")
                answers.append(Answer(label: "Power \(verb) by \(id)", value: f.format(abs(p), "W")))
            case .resistance:
                continue
            }
        }

        if answers.isEmpty {
            for element in elements where element.kind == .resistor {
                answers.append(Answer(label: "Current through \(element.id)", value: currentDescription(element, context: context)))
            }
        }
        return answers
    }

    /// "1.538 A from n2 to 0"
    static func currentDescription(_ element: ElementResult, context: AnalysisContext) -> String {
        let magnitude = context.amps(abs(element.current))
        if abs(element.current) < 1e-12 { return magnitude }
        let from = element.current >= 0 ? element.nodeA : element.nodeB
        let to = element.current >= 0 ? element.nodeB : element.nodeA
        return "\(magnitude) from \(from) to \(to)"
    }

    /// "24 V (n2 higher than 0)"
    static func voltageDescription(_ element: ElementResult, context: AnalysisContext) -> String {
        let magnitude = context.volts(abs(element.voltage))
        if abs(element.voltage) < 1e-12 { return magnitude }
        let high = element.voltage >= 0 ? element.nodeA : element.nodeB
        let low = element.voltage >= 0 ? element.nodeB : element.nodeA
        return "\(magnitude), \(high) higher than \(low)"
    }
}

// MARK: - Shared final steps

enum SharedSteps {
    static func elementVoltages(context: AnalysisContext, elements: [ElementResult]) -> AnalysisStep {
        let f = context.formatter
        var lines: [String] = []
        for e in elements {
            switch e.kind {
            case .resistor:
                lines.append("\(context.elementVoltageSymbol(e.id)) = \(e.id)·\(context.currentSymbol(e.id)) = \(context.ohms(e.value))·\(f.term(e.current, "A")) = \(context.volts(e.voltage))")
            case .voltageSource:
                lines.append("\(context.elementVoltageSymbol(e.id)) = \(context.volts(e.voltage)) (given)")
            case .currentSource:
                lines.append("\(context.elementVoltageSymbol(e.id)) = \(context.voltageTerm(e.nodeA, known: [:])) − \(context.voltageTerm(e.nodeB, known: [:])) = \(context.volts(e.voltage))")
            }
        }
        return AnalysisStep(
            title: "Find the voltage across each element",
            summary: "Ohm's law for resistors, node differences for sources",
            equations: lines,
            explanation: "For a resistor the voltage is R·I (positive at the terminal the current enters). Sources keep their given voltage, and a current source takes whatever voltage the rest of the circuit imposes.",
            result: lines.count == 1 ? lines[0] : "\(lines.count) voltages found"
        )
    }

    static func answerStep(context: AnalysisContext, answers: [Answer], elements: [ElementResult]) -> AnalysisStep {
        let question = context.circuit.question ?? "What was asked"
        let lines = answers.map { "\($0.label): \($0.value)" }
        let power = elements.map(\.power)
        let delivered = -power.filter { $0 < 0 }.reduce(0, +)
        let absorbed = power.filter { $0 > 0 }.reduce(0, +)
        return AnalysisStep(
            title: "Answer",
            summary: question,
            equations: lines,
            explanation: "Check: the sources deliver \(context.watts(delivered)) and the circuit absorbs \(context.watts(absorbed)); these match, so the solution is consistent.",
            result: lines.first ?? "Solved"
        )
    }
}
