import Foundation

/// Node-voltage method with textbook-style steps. Internally a modified nodal analysis
/// (extra unknowns for voltage-source currents) so any DC resistor network solves the same way;
/// the walkthrough derives every KCL equation term by term, clears the fractions, and solves the
/// system by elimination one operation at a time.
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
        let steps = buildSteps(context: context, voltages: voltages, elements: elements, answers: answers)

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

    /// One current leaving a node through one element, in symbols and in numbers.
    private struct BranchTerm {
        var label: String        // "through R1 to n1"
        var symbolic: String     // "(V₂ − V₁)/R1"
        var numeric: String      // "(V₂ − 9)/1000"
        var inner: String        // "V₂ − 9" (what gets multiplied when fractions are cleared)
        var resistance: Double?  // nil for a current source term
        var equation: DisplayEquation
    }

    private static func buildSteps(context: AnalysisContext, voltages: [String: Double], elements: [ElementResult], answers: [Answer]) -> [AnalysisStep] {
        let circuit = context.circuit
        let f = context.formatter
        let ground = circuit.groundNode
        let nodes = circuit.nodes
        let unknownNodes = nodes.filter { $0 != ground }
        var steps: [AnalysisStep] = []

        // 0. Given / find
        steps.append(SharedSteps.readCircuit(context: context))

        // 1. Nodes
        steps.append(AnalysisStep(
            title: "Identify the nodes",
            summary: "\(nodes.count) nodes join \(circuit.components.count) elements",
            equations: nodes.map { node in "Node \(node): " + circuit.components(at: node).map(\.id).joined(separator: ", ") },
            explanation: "A node is a junction where two or more elements meet, wires included: a wire never makes a new node, it only extends one. Every element sits between two of these \(nodes.count) nodes, and the whole method is about finding the voltage of each node.",
            result: "Nodes: " + nodes.joined(separator: ", "),
            focus: StepFocus(nodes: nodes)
        ))

        // 2. Reference + plan
        let unknownSymbols = unknownNodes.compactMap { context.voltageSymbol($0) }
        let groundedSourceCount = circuit.voltageSources.filter { $0.nodeA == ground || $0.nodeB == ground }.count
        let equationsNeeded = max(0, unknownNodes.count - groundedSourceCount)
        steps.append(AnalysisStep(
            title: "Choose the reference node",
            summary: "Node \(ground) is ground: 0 V by definition",
            equations: ["V(\(ground)) = 0", "Unknowns: " + unknownSymbols.joined(separator: ", ")],
            explanation: "Voltages are always differences, so one node is declared 0 V and every other node voltage is measured against it. The node with the most connections (or the one drawn with a ground symbol) keeps the equations short. That leaves \(unknownSymbols.count) unknown\(unknownSymbols.count == 1 ? "" : "s")\(groundedSourceCount > 0 ? ", of which \(groundedSourceCount) will be fixed directly by a source, so \(equationsNeeded) KCL equation\(equationsNeeded == 1 ? " is" : "s are") needed" : ", so \(equationsNeeded) KCL equation\(equationsNeeded == 1 ? " is" : "s are") needed").",
            result: "\(unknownSymbols.count) unknown node voltage\(unknownSymbols.count == 1 ? "" : "s")",
            focus: StepFocus(nodes: [ground], zoom: true)
        ))

        // 3. Voltages fixed by grounded sources; supernodes for floating sources
        var known: [String: Double] = [:]
        var fixedLines: [String] = []
        var floatingSources: [Component] = []
        for source in circuit.voltageSources {
            if source.nodeB == ground {
                known[source.nodeA] = source.value
                fixedLines.append("\(context.voltageSymbol(source.nodeA) ?? "") = \(context.volts(source.value))  (\(source.id): + at \(source.nodeA), − on ground)")
            } else if source.nodeA == ground {
                known[source.nodeB] = -source.value
                fixedLines.append("\(context.voltageSymbol(source.nodeB) ?? "") = \(context.volts(-source.value))  (\(source.id): + on ground, − at \(source.nodeB))")
            } else {
                floatingSources.append(source)
            }
        }
        if !fixedLines.isEmpty {
            let groundedSources = circuit.voltageSources.filter { $0.nodeA == ground || $0.nodeB == ground }.map(\.id)
            steps.append(AnalysisStep(
                title: "Read off the voltages fixed by sources",
                summary: "\(fixedLines.count) node voltage\(fixedLines.count == 1 ? " is" : "s are") known immediately",
                equations: fixedLines,
                explanation: "A voltage source between a node and ground holds that node at exactly its voltage, whatever current flows. No equation is needed for such a node; its value is simply substituted into the others.",
                result: fixedLines.map { String($0.split(separator: "  ").first ?? "") }.joined(separator: ", "),
                focus: StepFocus(nodes: Array(known.keys).sorted(by: Circuit.naturalOrder), elements: groundedSources, nodeVoltages: known)
            ))
        }

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
        let supernodeGroups = groups.values.filter { $0.count > 1 }.sorted { Circuit.naturalOrder($0[0], $1[0]) }

        var constraintEquations: [(DisplayEquation, StepFocus)] = []
        for group in supernodeGroups {
            let sources = floatingSources.filter { group.contains($0.nodeA) && group.contains($0.nodeB) }
            var lines: [String] = []
            for source in sources {
                let a = context.voltageSymbol(source.nodeA) ?? "", b = context.voltageSymbol(source.nodeB) ?? ""
                lines.append("\(a) − \(b) = \(context.volts(source.value))  (\(source.id): + at \(source.nodeA))")
                var constraint = DisplayEquation()
                constraint.add(1, to: a)
                constraint.add(-1, to: b)
                constraint.addConstant(source.value)
                constraintEquations.append((constraint, StepFocus(nodes: [source.nodeA, source.nodeB], elements: [source.id], zoom: true)))
            }
            steps.append(AnalysisStep(
                title: "Form a supernode",
                summary: "Nodes \(group.joined(separator: " and ")) are tied together by \(sources.map(\.id).joined(separator: ", "))",
                equations: lines,
                explanation: "Ohm's law does not give the current through a voltage source, so KCL cannot be written for either of its nodes alone. Draw a boundary around both nodes (a supernode): the source current stays inside and cancels out. The source still contributes an equation, the fixed difference between the two node voltages.",
                result: lines.first ?? "",
                focus: StepFocus(nodes: group, elements: sources.map(\.id), zoom: true, nodeVoltages: known)
            ))
        }

        // 4. KCL, term by term
        var systemEquations: [DisplayEquation] = []
        var equationFocus: [StepFocus] = []
        var handled: Set<String> = []
        let resistors = circuit.resistors
        let currentSources = circuit.currentSources

        func branchTerms(for node: String) -> [BranchTerm] {
            var terms: [BranchTerm] = []
            let symbol = context.voltageSymbol(node) ?? "0"
            for r in resistors where r.touches(node) {
                let other = r.otherNode(node)
                var equation = DisplayEquation()
                let g = 1 / r.value
                equation.add(g, to: symbol)
                let symbolic: String, numeric: String, inner: String, label: String
                if other == ground {
                    symbolic = "\(symbol)/\(r.id)"
                    numeric = "\(symbol)/\(f.number(r.value))"
                    inner = symbol
                    label = "through \(r.id) to ground"
                } else if let value = known[other] {
                    symbolic = "(\(symbol) − \(context.voltageSymbol(other) ?? ""))/\(r.id)"
                    numeric = "(\(symbol) − \(f.term(value)))/\(f.number(r.value))"
                    inner = "\(symbol) − \(f.term(value))"
                    label = "through \(r.id) to \(other)"
                    equation.addConstant(g * value)
                } else {
                    let otherSymbol = context.voltageSymbol(other) ?? ""
                    symbolic = "(\(symbol) − \(otherSymbol))/\(r.id)"
                    numeric = "(\(symbol) − \(otherSymbol))/\(f.number(r.value))"
                    inner = "\(symbol) − \(otherSymbol)"
                    label = "through \(r.id) to \(other)"
                    equation.add(-g, to: otherSymbol)
                }
                terms.append(BranchTerm(label: label, symbolic: symbolic, numeric: numeric, inner: inner, resistance: r.value, equation: equation))
            }
            for s in currentSources where s.touches(node) {
                var equation = DisplayEquation()
                if s.nodeA == node {
                    // The source pulls its current out of this node.
                    equation.addConstant(-s.value)
                    terms.append(BranchTerm(label: "\(s.id) draws \(context.amps(s.value)) out of \(node)", symbolic: "+\(s.id)", numeric: "+\(f.number(s.value))", inner: "+\(f.number(s.value))", resistance: nil, equation: equation))
                } else {
                    equation.addConstant(s.value)
                    terms.append(BranchTerm(label: "\(s.id) pushes \(context.amps(s.value)) into \(node)", symbolic: "−\(s.id)", numeric: "−\(f.number(s.value))", inner: "−\(f.number(s.value))", resistance: nil, equation: equation))
                }
            }
            return terms
        }

        func joined(_ parts: [String]) -> String {
            var out = ""
            for part in parts {
                if out.isEmpty { out = part; continue }
                if part.hasPrefix("−") { out += " − " + part.dropFirst() } else if part.hasPrefix("+") { out += " + " + part.dropFirst() } else { out += " + " + part }
            }
            return out.isEmpty ? "0" : out
        }

        for node in unknownNodes where known[node] == nil && !handled.contains(node) {
            let group = supernodeGroups.first { $0.contains(node) } ?? [node]
            handled.formUnion(group)
            let isSuper = group.count > 1
            var lines: [String] = []
            var allTerms: [BranchTerm] = []
            var combined = DisplayEquation()
            for member in group {
                let terms = branchTerms(for: member)
                if isSuper, !terms.isEmpty { lines.append("Leaving \(member):") }
                for term in terms {
                    lines.append("\(term.label): \(term.symbolic) = \(term.numeric)")
                    combined.add(term.equation)
                }
                allTerms.append(contentsOf: terms)
            }
            let sumLine = joined(allTerms.map(\.numeric)) + " = 0"
            lines.append((isSuper ? "Sum of all currents leaving the supernode = 0:  " : "Sum of currents leaving \(node) = 0:  ") + sumLine)

            // Clear the fractions with a common multiple when the resistances are nice numbers.
            let resistances = allTerms.compactMap(\.resistance)
            if let multiple = NiceNumbers.commonMultiple(of: resistances), abs(multiple - 1) > 1e-9 || allTerms.contains(where: { $0.resistance == nil }) {
                var pieces: [String] = []
                for term in allTerms {
                    if let r = term.resistance {
                        let factor = multiple / r
                        let factorText = f.number(factor)
                        let needsParens = term.inner.contains(" ")
                        if abs(factor - 1) < 1e-9 {
                            pieces.append(needsParens ? "(\(term.inner))" : term.inner)
                        } else {
                            pieces.append(needsParens ? "\(factorText)·(\(term.inner))" : "\(factorText)·\(term.inner)")
                        }
                    } else {
                        // Source term: the whole number scales too.
                        let sign = term.numeric.hasPrefix("−") ? "−" : "+"
                        let magnitude = Double(term.numeric.dropFirst().replacingOccurrences(of: ",", with: ".")) ?? 0
                        pieces.append("\(sign)\(f.number(magnitude * multiple))")
                    }
                }
                lines.append("× \(f.number(multiple)):  " + joined(pieces) + " = 0")
                combined = combined.scaled(by: multiple)
            }
            let collected = combined.rendered(with: f, order: unknownSymbols)
            lines.append("→ " + collected)
            systemEquations.append(combined)
            let adjacent = circuit.components.filter { c in c.kind != .voltageSource && group.contains(where: { c.touches($0) }) }.map(\.id)
            let focus = StepFocus(nodes: group, elements: adjacent, zoom: true, nodeVoltages: known)
            equationFocus.append(focus)
            steps.append(AnalysisStep(
                title: isSuper ? "Apply KCL to the supernode \(group.joined(separator: "–"))" : "Apply KCL at node \(node)",
                summary: "Currents leaving \(isSuper ? "the supernode" : node) add up to zero",
                equations: lines,
                explanation: (isSuper
                    ? "Kirchhoff's current law: whatever flows into a region flows out again. Write each current leaving the supernode as (this node − other node)/R, add the current-source terms, and set the total to zero. "
                    : "Kirchhoff's current law: charge does not pile up at a node, so the currents leaving it add up to zero. Each resistor current is (this node − other node)/R, a current source contributes its value with a sign. ")
                    + "Multiplying by a common multiple of the resistances clears the fractions and leaves an equation with whole-number coefficients.",
                result: collected,
                focus: focus
            ))
        }

        // 5. Solve, narrated
        let solvedNodes = unknownNodes.filter { known[$0] == nil }
        let solvedSymbols = solvedNodes.compactMap { context.voltageSymbol($0) }
        if !solvedSymbols.isEmpty {
            var equations = systemEquations
            var focuses = equationFocus
            for (constraint, focus) in constraintEquations {
                equations.append(constraint)
                focuses.append(focus)
            }
            let nodeOf = Dictionary(uniqueKeysWithValues: zip(solvedSymbols, solvedNodes))
            let options = SystemNarrator.Options(
                unknowns: solvedSymbols,
                unit: "V",
                formatter: f,
                systemFocus: StepFocus(nodes: solvedNodes, nodeVoltages: known),
                equationFocus: focuses,
                solvedFocus: { symbol, value in
                    var partial = known
                    if let node = nodeOf[symbol] { partial[node] = value }
                    return StepFocus(nodes: nodeOf[symbol].map { [$0] } ?? [], zoom: true, nodeVoltages: partial)
                },
                describe: { symbol in nodeOf[symbol].map { "the voltage at node \($0) relative to ground" } ?? "a node voltage" }
            )
            if let narrated = SystemNarrator.narrate(equations, options: options),
               solvedSymbols.allSatisfy({ symbol in
                   guard let node = nodeOf[symbol], let expected = voltages[node], let got = narrated.solution[symbol] else { return false }
                   return abs(expected - got) <= 1e-6 * max(1, abs(expected))
               }) {
                steps.append(contentsOf: narrated.steps)
            } else {
                let lines = equations.map { $0.rendered(with: f, order: solvedSymbols) }
                let solution = solvedNodes.map { "\(context.voltageSymbol($0) ?? "") = \(context.volts(voltages[$0] ?? 0))" }
                steps.append(AnalysisStep(
                    title: "Solve the system of equations",
                    summary: "\(equations.count) equations, \(solvedSymbols.count) unknowns",
                    equations: lines + ["→ " + solution.joined(separator: ", ")],
                    explanation: "Solved as a linear system; every node voltage comes out at once.",
                    result: solution.joined(separator: ", "),
                    focus: StepFocus(nodes: solvedNodes, nodeVoltages: voltages)
                ))
            }
        }

        // 6. Element currents
        var currentLines: [String] = []
        for e in elements where e.kind != .voltageSource {
            switch e.kind {
            case .resistor:
                currentLines.append("\(context.currentSymbol(e.id)) = (\(context.voltageTerm(e.nodeA, known: voltages)) − \(context.voltageTerm(e.nodeB, known: voltages)))/\(f.number(e.value)) = \(context.amps(e.current))  (\(Answers.flowWords(e)))")
            default:
                currentLines.append("\(context.currentSymbol(e.id)) = \(context.amps(e.value)) (given, from \(e.nodeA) to \(e.nodeB))")
            }
        }
        for e in elements where e.kind == .voltageSource {
            // Ohm's law says nothing about a source; KCL at its + terminal does.
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
            currentLines.append("\(context.currentSymbol(e.id)): KCL at \(e.nodeA) → \(expression) = \(numeric)\(context.amps(delivered)) leaves through the other elements, so \(e.id) \(delivered >= 0 ? "delivers" : "absorbs") \(context.amps(abs(delivered)))")
        }
        let currents = Dictionary(uniqueKeysWithValues: elements.map { ($0.id, $0.current) })
        steps.append(AnalysisStep(
            title: "Find the current through each element",
            summary: "Ohm's law on every resistor, KCL at the sources",
            equations: currentLines,
            explanation: "With every node voltage known, the current through a resistor is the voltage drop across it divided by its resistance, flowing from the higher node to the lower one. A voltage source's current is not given by Ohm's law, so it comes from KCL at its terminal: it must supply whatever the elements next to it carry away.",
            result: currentLines.count == 1 ? currentLines[0] : "\(currentLines.count) currents found",
            focus: StepFocus(nodeVoltages: voltages, elementCurrents: currents, animateCurrents: true)
        ))

        // 7. Voltages, 8. Check, 9. Answer
        steps.append(SharedSteps.elementVoltages(context: context, elements: elements, voltages: voltages))
        steps.append(SharedSteps.checkStep(context: context, elements: elements, voltages: voltages))
        steps.append(SharedSteps.answerStep(context: context, answers: answers, elements: elements, voltages: voltages))
        return steps
    }
}
