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

    /// "from n2 to 0" — which way the current really flows.
    static func flowWords(_ element: ElementResult) -> String {
        if abs(element.current) < 1e-12 { return "no current" }
        let from = element.current >= 0 ? element.nodeA : element.nodeB
        let to = element.current >= 0 ? element.nodeB : element.nodeA
        return "from \(from) to \(to)"
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

// MARK: - Shared steps

enum SharedSteps {
    /// "Given / find": every element with its value and where it sits, then the question.
    static func readCircuit(context: AnalysisContext) -> AnalysisStep {
        let circuit = context.circuit
        var lines = circuit.components.map { c -> String in
            switch c.kind {
            case .resistor: return "\(c.id) = \(context.ohms(c.value)) between \(c.nodeA) and \(c.nodeB)"
            case .voltageSource: return "\(c.id) = \(context.volts(c.value)), + at \(c.nodeA), − at \(c.nodeB)"
            case .currentSource: return "\(c.id) = \(context.amps(c.value)) from \(c.nodeA) into \(c.nodeB)"
            }
        }
        let question = circuit.question ?? "Find the current through every element"
        lines.append(question.lowercased().hasPrefix("find") ? question : "Find: \(question)")
        let sources = circuit.components.filter { $0.kind != .resistor }.count
        let resistors = circuit.components.count - sources
        return AnalysisStep(
            title: "Read the circuit",
            summary: "\(sources) source\(sources == 1 ? "" : "s"), \(resistors) resistor\(resistors == 1 ? "" : "s"), \(circuit.nodes.count) nodes",
            equations: lines,
            explanation: "Before solving anything, write down what is given and what is asked. Every value here comes straight from the diagram; the node names are the junctions the elements share.",
            result: question,
            focus: StepFocus(elements: circuit.components.map(\.id))
        )
    }

    static func elementVoltages(context: AnalysisContext, elements: [ElementResult], voltages: [String: Double]) -> AnalysisStep {
        let f = context.formatter
        var lines: [String] = []
        for e in elements {
            switch e.kind {
            case .resistor:
                lines.append("\(context.elementVoltageSymbol(e.id)) = \(e.id)·\(context.currentSymbol(e.id)) = \(context.ohms(e.value))·\(f.term(e.current, "A")) = \(context.volts(e.voltage))")
            case .voltageSource:
                lines.append("\(context.elementVoltageSymbol(e.id)) = \(context.volts(e.voltage)) (given)")
            case .currentSource:
                lines.append("\(context.elementVoltageSymbol(e.id)) = \(context.voltageTerm(e.nodeA, known: voltages)) − \(context.voltageTerm(e.nodeB, known: voltages)) = \(context.volts(e.voltage))")
            }
        }
        return AnalysisStep(
            title: "Find the voltage across each element",
            summary: "Ohm's law for resistors, node differences for sources",
            equations: lines,
            explanation: "For a resistor the voltage is R·I, positive at the terminal the current enters. A voltage source keeps its given voltage; a current source takes whatever voltage the rest of the circuit imposes, which is the difference of its node voltages.",
            result: lines.count == 1 ? lines[0] : "\(lines.count) voltages found",
            focus: StepFocus(nodeVoltages: voltages, elementCurrents: Dictionary(uniqueKeysWithValues: elements.map { ($0.id, $0.current) }), animateCurrents: true)
        )
    }

    /// Power balance and a KCL spot check: the two things a textbook asks you to verify.
    static func checkStep(context: AnalysisContext, elements: [ElementResult], voltages: [String: Double]) -> AnalysisStep {
        let f = context.formatter
        let circuit = context.circuit
        var lines: [String] = []
        var absorbedTerms: [String] = []
        var deliveredTerms: [String] = []
        var absorbed = 0.0, delivered = 0.0
        for e in elements {
            let p = e.power
            switch e.kind {
            case .resistor:
                lines.append("P(\(e.id)) = I²·R = (\(f.term(e.current, "A")))²·\(context.ohms(e.value)) = \(context.watts(p))")
                absorbedTerms.append(context.watts(p)); absorbed += p
            case .voltageSource, .currentSource:
                let magnitude = abs(p)
                lines.append("P(\(e.id)) = V·I = \(context.volts(e.voltage))·\(f.term(e.current, "A")) = \(context.watts(p))  (\(e.id) \(p < 0 ? "delivers" : "absorbs") \(context.watts(magnitude)))")
                if p < 0 { deliveredTerms.append(context.watts(magnitude)); delivered += magnitude } else if p > 1e-15 { absorbedTerms.append(context.watts(p)); absorbed += p }
            }
        }
        lines.append(deliveredTerms.count > 1 ? "Delivered: \(deliveredTerms.joined(separator: " + ")) = \(context.watts(delivered))" : "Delivered by the sources: \(context.watts(delivered))")
        lines.append(absorbedTerms.count > 1 ? "Absorbed: \(absorbedTerms.joined(separator: " + ")) = \(context.watts(absorbed))" : "Absorbed by the circuit: \(context.watts(absorbed))")
        let balanced = abs(delivered - absorbed) <= 1e-6 * max(1e-12, abs(delivered))
        lines.append("→ delivered \(balanced ? "=" : "≠") absorbed \(balanced ? "✓" : "✗")")

        // KCL at the busiest node
        var kclNode: String?
        var kclLine: String?
        let candidates = circuit.nodes.filter { $0 != circuit.groundNode }.sorted { circuit.components(at: $0).count > circuit.components(at: $1).count }
        if let node = candidates.first, circuit.components(at: node).count >= 2 {
            var into: [String] = [], out: [String] = []
            var sumIn = 0.0, sumOut = 0.0
            for e in elements where e.nodeA == node || e.nodeB == node {
                let leaving = ElementResults.currentLeaving(node, through: e)
                if leaving >= 0 { out.append(context.amps(leaving)); sumOut += leaving } else { into.append(context.amps(-leaving)); sumIn -= leaving }
            }
            kclNode = node
            kclLine = "KCL at \(node): in \(into.isEmpty ? "0 A" : into.joined(separator: " + ")) = \(context.amps(sumIn)), out \(out.isEmpty ? "0 A" : out.joined(separator: " + ")) = \(context.amps(sumOut)) ✓"
            lines.append(kclLine!)
        }
        let currents = Dictionary(uniqueKeysWithValues: elements.map { ($0.id, $0.current) })
        return AnalysisStep(
            title: "Check the result",
            summary: balanced ? "Power balances and KCL holds" : "Power does not balance",
            equations: lines,
            explanation: "Energy is conserved, so the power the sources deliver must equal the power the resistors turn into heat. A quick KCL check at a node confirms the currents add up. If either failed, a value or a sign would be wrong.",
            result: balanced ? "Delivered \(context.watts(delivered)) = absorbed \(context.watts(absorbed))" : "Mismatch: \(context.watts(delivered)) vs \(context.watts(absorbed))",
            focus: StepFocus(nodes: kclNode.map { [$0] } ?? [], nodeVoltages: voltages, elementCurrents: currents, animateCurrents: true)
        )
    }

    static func answerStep(context: AnalysisContext, answers: [Answer], elements: [ElementResult], voltages: [String: Double]) -> AnalysisStep {
        let question = context.circuit.question ?? "What was asked"
        let lines = answers.map { "\($0.label): \($0.value)" }
        var askedElements = context.circuit.unknowns.compactMap(\.element)
        var askedNodes = context.circuit.unknowns.flatMap { ($0.node.map { [$0] } ?? []) + ($0.between ?? []) }
        if askedElements.isEmpty, askedNodes.isEmpty {
            askedElements = elements.filter { $0.kind == .resistor }.map(\.id)
        }
        askedNodes = askedNodes.filter { node in context.circuit.nodes.contains(node) }
        let currents = Dictionary(uniqueKeysWithValues: elements.map { ($0.id, $0.current) })
        return AnalysisStep(
            title: "Answer",
            summary: question,
            equations: lines,
            explanation: "This is what the question asked for, read off from the currents and voltages found above. The direction words say which way the current actually flows; a negative value along the way only meant the assumed direction was backwards.",
            result: lines.first ?? "Solved",
            focus: StepFocus(nodes: askedNodes, elements: askedElements, zoom: true, nodeVoltages: voltages, elementCurrents: currents.filter { askedElements.contains($0.key) }, animateCurrents: true)
        )
    }

    /// Node voltages from element voltages by walking the graph from ground (used by the methods
    /// that solve for currents first).
    static func nodeVoltages(circuit: Circuit, elementVoltages: [String: Double]) -> [String: Double] {
        let graph = CircuitGraph(circuit)
        var voltages: [String: Double] = [circuit.groundNode: 0]
        var queue = [circuit.groundNode]
        while let node = queue.popLast() {
            for (edge, neighbor) in graph.neighbors(of: node) where voltages[neighbor] == nil {
                let component = circuit.components[edge]
                let drop = elementVoltages[component.id] ?? 0   // V(nodeA) − V(nodeB)
                voltages[neighbor] = component.nodeA == node ? (voltages[node]! - drop) : (voltages[node]! + drop)
                queue.append(neighbor)
            }
        }
        return voltages
    }
}
