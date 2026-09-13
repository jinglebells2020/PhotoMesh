import Foundation

/// Node-voltage method with textbook-style steps. Internally a modified nodal analysis
/// (extra unknowns for voltage-source currents) so any DC resistor network solves the same way.
enum NodalAnalysis {
    static func solve(_ circuit: Circuit, formatter: QuantityFormatter) throws -> MethodSolution {
        let context = AnalysisContext(circuit: circuit, formatter: formatter)
        let ground = circuit.groundNode
        let nodes = circuit.nodes
        let unknownNodes = nodes.filter { $0 != ground }
        let nodeIndex = Dictionary(uniqueKeysWithValues: unknownNodes.enumerated().map { ($1, $0) })
        let voltageSources = circuit.voltageSources
        let n = unknownNodes.count
        let m = voltageSources.count

        // MARK: Modified nodal analysis
        var system = LinearSystem(size: n + m)
        for r in circuit.resistors {
            let g = 1 / r.value
            let ia = nodeIndex[r.nodeA]
            let ib = nodeIndex[r.nodeB]
            if let ia { system.a[ia][ia] += g }
            if let ib { system.a[ib][ib] += g }
            if let ia, let ib {
                system.a[ia][ib] -= g
                system.a[ib][ia] -= g
            }
        }
        for s in circuit.currentSources {
            if let ia = nodeIndex[s.nodeA] { system.b[ia] -= s.value }   // leaves nodeA
            if let ib = nodeIndex[s.nodeB] { system.b[ib] += s.value }   // enters nodeB
        }
        for (k, s) in voltageSources.enumerated() {
            let row = n + k
            if let ip = nodeIndex[s.nodeA] {
                system.a[ip][row] += 1
                system.a[row][ip] += 1
            }
            if let ineg = nodeIndex[s.nodeB] {
                system.a[ineg][row] -= 1
                system.a[row][ineg] -= 1
            }
            system.b[row] = s.value
        }
        let x = try system.solve()

        var voltages: [String: Double] = [ground: 0]
        for (node, index) in nodeIndex { voltages[node] = x[index] }
        var sourceCurrents: [String: Double] = [:]
        for (k, s) in voltageSources.enumerated() { sourceCurrents[s.id] = x[n + k] }

        let elements = ElementResults.compute(circuit: circuit, voltages: voltages, sourceCurrents: sourceCurrents)
        let answers = Answers.build(context: context, voltages: voltages, elements: elements)
        let steps = buildSteps(context: context, nodeIndex: nodeIndex, voltages: voltages, elements: elements, answers: answers)

        return MethodSolution(
            method: .nodal,
            headline: answers.first.map { "\($0.label): \($0.value)" } ?? "Solved",
            steps: steps,
            nodeVoltages: voltages,
            elements: elements,
            answers: answers
        )
    }

    // MARK: Steps

    private static func buildSteps(context: AnalysisContext, nodeIndex: [String: Int], voltages: [String: Double], elements: [ElementResult], answers: [Answer]) -> [AnalysisStep] {
        let circuit = context.circuit
        let f = context.formatter
        let ground = circuit.groundNode
        let nodes = circuit.nodes
        let unknownNodes = nodes.filter { $0 != ground }
        var steps: [AnalysisStep] = []

        // 1. Nodes
        steps.append(AnalysisStep(
            title: "Identify the nodes",
            summary: "\(nodes.count) nodes, \(circuit.components.count) elements",
            equations: nodes.map { node in "\(node): " + circuit.components(at: node).map(\.id).joined(separator: ", ") },
            explanation: "A node is any point where two or more elements meet. A wire never creates a new node, so every element connects two of these \(nodes.count) nodes.",
            result: "Nodes: " + nodes.joined(separator: ", ")
        ))

        // 2. Reference
        let unknownSymbols = unknownNodes.compactMap { context.voltageSymbol($0) }
        steps.append(AnalysisStep(
            title: "Choose the reference node",
            summary: "Node \(ground) is ground, 0 V",
            equations: ["V(\(ground)) = 0", "Unknowns: " + unknownSymbols.joined(separator: ", ")],
            explanation: "Every node voltage is measured relative to the reference. Picking the node with the most connections (or the marked ground) keeps the equations short.",
            result: "\(unknownSymbols.count) unknown node voltage\(unknownSymbols.count == 1 ? "" : "s")"
        ))

        // 3. Voltages fixed by grounded sources; supernodes for floating sources
        var known: [String: Double] = [:]
        var fixedLines: [String] = []
        var supernodeGroups: [[String]] = []
        var floatingSources: [Component] = []
        for source in circuit.voltageSources {
            if source.nodeB == ground {
                known[source.nodeA] = source.value
                fixedLines.append("\(context.voltageSymbol(source.nodeA) ?? "") = \(context.volts(source.value))  (\(source.id) sits between \(source.nodeA) and ground)")
            } else if source.nodeA == ground {
                known[source.nodeB] = -source.value
                fixedLines.append("\(context.voltageSymbol(source.nodeB) ?? "") = \(context.volts(-source.value))  (\(source.id) has its + terminal on ground)")
            } else {
                floatingSources.append(source)
            }
        }
        if !fixedLines.isEmpty {
            steps.append(AnalysisStep(
                title: "Read off voltages fixed by sources",
                summary: "\(fixedLines.count) node voltage\(fixedLines.count == 1 ? " is" : "s are") known immediately",
                equations: fixedLines,
                explanation: "A voltage source connected to the reference node pins its other terminal: no equation is needed for that node.",
                result: fixedLines.first.map { String($0.split(separator: "  ").first ?? "") } ?? ""
            ))
        }

        // Union floating sources into supernodes
        var parent: [String: String] = [:]
        func find(_ node: String) -> String {
            var current = node
            while let p = parent[current], p != current { current = p }
            return current
        }
        for node in unknownNodes { parent[node] = node }
        for source in floatingSources {
            let a = find(source.nodeA), b = find(source.nodeB)
            if a != b { parent[a] = b }
        }
        var groups: [String: [String]] = [:]
        for node in unknownNodes { groups[find(node), default: []].append(node) }
        supernodeGroups = groups.values.filter { $0.count > 1 }.sorted { Circuit.naturalOrder($0[0], $1[0]) }

        for group in supernodeGroups {
            let sources = floatingSources.filter { group.contains($0.nodeA) && group.contains($0.nodeB) }
            let constraints = sources.map { "\(context.voltageSymbol($0.nodeA) ?? "") − \(context.voltageSymbol($0.nodeB) ?? "") = \(context.volts($0.value))  (\($0.id))" }
            steps.append(AnalysisStep(
                title: "Form a supernode",
                summary: "Nodes \(group.joined(separator: " and ")) are tied by \(sources.map(\.id).joined(separator: ", "))",
                equations: constraints,
                explanation: "The current through an ideal voltage source is unknown, so KCL is written for the two nodes together (a supernode) and the source adds a simple voltage constraint.",
                result: constraints.first ?? ""
            ))
        }

        // 4. KCL equations
        var systemEquations: [DisplayEquation] = []
        var handled: Set<String> = []
        let resistors = circuit.resistors
        let currentSources = circuit.currentSources

        func kclTerms(for node: String) -> (TermList, DisplayEquation) {
            var terms = TermList()
            var equation = DisplayEquation()
            let symbol = context.voltageSymbol(node) ?? "0"
            for r in resistors where r.touches(node) {
                let other = r.otherNode(node)
                let otherTerm = context.voltageTerm(other, known: known)
                let g = 1 / r.value
                let text: String
                if other == ground {
                    text = "\(symbol)/\(f.number(r.value))"
                } else {
                    text = "(\(symbol) − \(otherTerm))/\(f.number(r.value))"
                }
                terms.add(text)
                equation.add(g, to: symbol)
                if other != ground {
                    if let value = known[other] {
                        equation.addConstant(g * value)
                    } else if let otherSymbol = context.voltageSymbol(other) {
                        equation.add(-g, to: otherSymbol)
                    }
                }
            }
            for s in currentSources where s.touches(node) {
                if s.nodeA == node {
                    terms.add(f.number(s.value), negative: false)   // leaves the node through the source
                    equation.addConstant(-s.value)
                } else {
                    terms.add(f.number(s.value), negative: true)    // injected into the node
                    equation.addConstant(s.value)
                }
            }
            return (terms, equation)
        }

        for node in unknownNodes where known[node] == nil && !handled.contains(node) {
            let group = supernodeGroups.first { $0.contains(node) } ?? [node]
            handled.formUnion(group)
            var combined = DisplayEquation()
            var pieces: [String] = []
            for member in group {
                let (terms, equation) = kclTerms(for: member)
                combined.add(equation)
                if !terms.isEmpty { pieces.append(terms.renderedLeftSide()) }
            }
            let sumLine = pieces.joined(separator: " + ") + " = 0"
            let collected = combined.rendered(with: f)
            systemEquations.append(combined)
            let isSuper = group.count > 1
            steps.append(AnalysisStep(
                title: isSuper ? "Apply KCL to the supernode \(group.joined(separator: "–"))" : "Apply KCL at node \(node)",
                summary: "Sum of currents leaving = 0",
                equations: [sumLine, "→ " + collected],
                explanation: isSuper
                    ? "Add the currents leaving every node of the supernode through resistors and current sources; the current through the internal voltage source cancels out."
                    : "Each resistor term is (this node − other node)/R. A current source contributes its value directly, with a minus sign when it pushes current into the node.",
                result: collected
            ))
        }

        // 5. Solve
        let solvedSymbols = unknownNodes.filter { known[$0] == nil }
        if !solvedSymbols.isEmpty {
            var lines = systemEquations.map { $0.rendered(with: f) }
            for group in supernodeGroups {
                for source in floatingSources where group.contains(source.nodeA) && group.contains(source.nodeB) {
                    lines.append("\(context.voltageSymbol(source.nodeA) ?? "") − \(context.voltageSymbol(source.nodeB) ?? "") = \(f.number(source.value))")
                }
            }
            let solution = solvedSymbols.map { "\(context.voltageSymbol($0) ?? "") = \(context.volts(voltages[$0] ?? 0))" }
            steps.append(AnalysisStep(
                title: solvedSymbols.count == 1 ? "Solve for the node voltage" : "Solve the system of equations",
                summary: "\(solvedSymbols.count) equation\(solvedSymbols.count == 1 ? "" : "s"), \(solvedSymbols.count) unknown\(solvedSymbols.count == 1 ? "" : "s")",
                equations: lines + ["→ " + solution.joined(separator: ", ")],
                explanation: solvedSymbols.count == 1
                    ? "Divide the constant by the coefficient of the unknown."
                    : "Solve by substitution or with a matrix; every node voltage comes out at once.",
                result: solution.joined(separator: ", ")
            ))
        }

        // 6. Element currents
        var currentLines: [String] = []
        for e in elements {
            switch e.kind {
            case .resistor:
                currentLines.append("\(context.currentSymbol(e.id)) = (\(context.voltageTerm(e.nodeA, known: voltages)) − \(context.voltageTerm(e.nodeB, known: voltages)))/\(f.number(e.value)) = \(context.amps(e.current))")
            case .currentSource:
                currentLines.append("\(context.currentSymbol(e.id)) = \(context.amps(e.value)) (given, from \(e.nodeA) to \(e.nodeB))")
            case .voltageSource:
                let others = elements.filter { $0.id != e.id && ($0.nodeA == e.nodeA || $0.nodeB == e.nodeA) }
                var symbols = TermList()
                var numbers: [String] = []
                for other in others {
                    let leaving = ElementResults.currentLeaving(e.nodeA, through: other)
                    symbols.add(context.currentSymbol(other.id), negative: other.nodeA != e.nodeA)
                    numbers.append(f.term(leaving, "A"))
                }
                let delivered = -e.current
                let expression = symbols.isEmpty ? "0" : symbols.renderedLeftSide()
                let numeric = numbers.count > 1 ? numbers.joined(separator: " + ") + " = " : ""
                currentLines.append("KCL at \(e.nodeA): \(expression) = \(numeric)\(context.amps(delivered)) → \(e.id) \(delivered >= 0 ? "delivers" : "absorbs") \(context.amps(abs(delivered)))")
            }
        }
        steps.append(AnalysisStep(
            title: "Find the current through each element",
            summary: "Ohm's law on every resistor",
            equations: currentLines,
            explanation: "With the node voltages known, each resistor current is the voltage difference across it divided by its resistance. The current a voltage source delivers follows from KCL at its terminal.",
            result: currentLines.count == 1 ? currentLines[0] : "\(currentLines.count) currents found"
        ))

        // 7. Voltages, 8. Answer
        steps.append(SharedSteps.elementVoltages(context: context, elements: elements))
        steps.append(SharedSteps.answerStep(context: context, answers: answers, elements: elements))
        return steps
    }
}
