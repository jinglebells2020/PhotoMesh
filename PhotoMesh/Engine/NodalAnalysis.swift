import Foundation

/// Node-voltage method with textbook-style steps. Internally a modified nodal analysis
/// (extra unknowns for voltage-source currents) so any DC resistor network solves the same way;
/// the walkthrough derives every KCL equation term by term, clears the fractions, and solves the
/// system by elimination one operation at a time.
enum NodalAnalysis {
    static func solve(_ circuit: Circuit, formatter: QuantityFormatter, presented: Circuit? = nil) throws -> MethodSolution {
        let context = AnalysisContext(circuit: circuit, formatter: formatter, presented: presented)
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

        // Voltages fixed by sources: a source to ground fixes its node, and a source whose other
        // end is already fixed carries the value one node further (two batteries in series).
        var known: [String: Double] = [:]
        var fixedLines: [String] = []
        var fixedSources: [String] = []
        var chained = false
        var pending = circuit.voltageSources
        var progress = true
        while progress {
            progress = false
            for source in pending {
                let a = source.nodeA, b = source.nodeB
                let va: Double? = a == ground ? 0 : known[a]
                let vb: Double? = b == ground ? 0 : known[b]
                if let vb, va == nil {
                    known[a] = vb + source.value
                    if b == ground {
                        fixedLines.append("\(context.voltageSymbol(a) ?? "") = \(context.volts(source.value))  (\(source.id): + at \(a), − on ground)")
                    } else {
                        chained = true
                        fixedLines.append("\(context.voltageSymbol(a) ?? "") = \(context.voltageSymbol(b) ?? "") + \(source.id) = \(f.term(vb, "V")) + \(context.volts(source.value)) = \(context.volts(vb + source.value))  (\(source.id): + at \(a), − at \(b))")
                    }
                } else if let va, vb == nil {
                    known[b] = va - source.value
                    if a == ground {
                        fixedLines.append("\(context.voltageSymbol(b) ?? "") = \(context.volts(-source.value))  (\(source.id): + on ground, − at \(b))")
                    } else {
                        chained = true
                        fixedLines.append("\(context.voltageSymbol(b) ?? "") = \(context.voltageSymbol(a) ?? "") − \(source.id) = \(f.term(va, "V")) − \(context.volts(source.value)) = \(context.volts(va - source.value))  (\(source.id): + at \(a), − at \(b))")
                    }
                } else {
                    continue
                }
                fixedSources.append(source.id)
                pending.removeAll { $0.id == source.id }
                progress = true
                break
            }
        }
        let floatingSources = pending

        // 2. Reference + plan
        let unknownSymbols = unknownNodes.compactMap { context.voltageSymbol($0) }
        let fixedCount = known.count
        let floatingCount = floatingSources.count
        let kclCount = max(0, unknownNodes.count - fixedCount - floatingCount)
        var plan = "That leaves \(unknownSymbols.count) unknown node voltage\(unknownSymbols.count == 1 ? "" : "s")"
        var clauses: [String] = []
        if fixedCount > 0 {
            let which = fixedCount == unknownSymbols.count ? (fixedCount == 1 ? "it" : "all of them") : "\(fixedCount) of them"
            clauses.append("\(which) \(fixedCount == 1 ? "is" : "are") fixed directly by \(fixedCount == 1 ? "a voltage source" : "voltage sources")")
        }
        if floatingCount > 0 {
            clauses.append("\(floatingCount) voltage source\(floatingCount == 1 ? " sits" : "s sit") between two unknown nodes and will tie them into a supernode, each giving one relation between the two voltages")
        }
        if !clauses.isEmpty { plan += "; " + clauses.joined(separator: ", and ") }
        if kclCount == 0 {
            plan += ", so no KCL equation is needed at all"
        } else {
            plan += ", so \(kclCount) KCL equation\(kclCount == 1 ? " is" : "s are") needed"
            if floatingCount > 0 { plan += " besides the \(floatingCount) source relation\(floatingCount == 1 ? "" : "s")" }
        }
        plan += "."
        let otherDegree = unknownNodes.map { circuit.components(at: $0).count }.max() ?? 0
        let groundIsBusiest = circuit.components(at: ground).count > otherDegree
        steps.append(AnalysisStep(
            title: "Choose the reference node",
            summary: "Node \(ground) is ground: 0 V by definition",
            equations: ["V(\(ground)) = 0", "Unknowns: " + unknownSymbols.joined(separator: ", ")],
            explanation: "Voltages are always differences, so one node is declared 0 V and every other node voltage is measured against it. Node \(ground) is that reference here\(groundIsBusiest ? "; it is also the node with the most connections, which keeps the equations short" : ""). Any node would do: the element currents and voltages would come out the same, only the node numbers would shift. \(plan)",
            result: "\(unknownSymbols.count) unknown node voltage\(unknownSymbols.count == 1 ? "" : "s")",
            focus: StepFocus(nodes: [ground], zoom: true)
        ))

        // 3. Voltages fixed by sources; supernodes for floating sources
        if !fixedLines.isEmpty {
            steps.append(AnalysisStep(
                title: "Read off the voltages fixed by sources",
                summary: "\(fixedLines.count) node voltage\(fixedLines.count == 1 ? " is" : "s are") known immediately",
                equations: fixedLines,
                explanation: "A voltage source between a node and ground holds that node at exactly its voltage, whatever current flows. "
                    + (chained ? "A source whose other end is already known does the same one node further along: add its voltage when its + terminal is at the new node, subtract it when its − terminal is. " : "")
                    + "No equation is needed for such a node; its value is simply substituted into the others.",
                result: known.keys.sorted(by: Circuit.naturalOrder).map { "\(context.voltageSymbol($0) ?? "") = \(context.volts(known[$0] ?? 0))" }.joined(separator: ", "),
                focus: StepFocus(nodes: Array(known.keys).sorted(by: Circuit.naturalOrder), elements: fixedSources, nodeVoltages: known)
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
                result: lines.map { String($0.split(separator: "  ").first ?? "") }.joined(separator: ", "),
                focus: StepFocus(nodes: group, elements: sources.map(\.id), zoom: true, nodeVoltages: known, supernodes: [Supernode(nodes: group, elements: sources.map(\.id))])
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
                    numeric = "(\(symbol) − \(f.preciseTerm(value)))/\(f.number(r.value))"
                    inner = "\(symbol) − \(f.preciseTerm(value))"
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

        var explainedNode = false
        var explainedSupernode = false
        for node in unknownNodes where known[node] == nil && !handled.contains(node) {
            let group = supernodeGroups.first { $0.contains(node) } ?? [node]
            handled.formUnion(group)
            let isSuper = group.count > 1
            var cleared = false
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
                cleared = true
            }
            let collected = combined.rendered(with: f, order: unknownSymbols)
            lines.append("→ " + collected)
            systemEquations.append(combined)
            let adjacent = circuit.components.filter { c in c.kind != .voltageSource && group.contains(where: { c.touches($0) }) }.map(\.id)
            let tied = isSuper ? floatingSources.filter { group.contains($0.nodeA) && group.contains($0.nodeB) }.map(\.id) : []
            let focus = StepFocus(nodes: group, elements: adjacent, zoom: true, nodeVoltages: known, supernodes: isSuper ? [Supernode(nodes: group, elements: tied)] : [])
            equationFocus.append(focus)
            let clearing = cleared ? " Multiplying by a common multiple of the resistances clears the fractions and leaves whole-number coefficients." : ""
            let explanation: String
            if isSuper, !explainedSupernode {
                explainedSupernode = true
                explanation = "Kirchhoff's current law for a region: whatever flows into the supernode flows out again, so the currents leaving it through its resistors add up to zero. The source current inside the boundary never appears. Each current is (this node − other node)/R, positive when it really leaves; a current source counts with its value, negative when it pushes current in." + clearing
            } else if !isSuper, !explainedNode {
                explainedNode = true
                explanation = "Kirchhoff's current law: charge does not pile up at a node, so the currents leaving it add up to zero. Each resistor current is written as (this node − other node)/R, which is positive when it really leaves; a current source counts with its value, negative when it pushes current into the node." + clearing
            } else {
                explanation = "Same procedure at \(isSuper ? "the supernode" : "node \(node)"): write each current leaving as (this node − other node)/R, add any source term, set the sum to zero\(cleared ? " and clear the fractions" : "")."
            }
            steps.append(AnalysisStep(
                title: isSuper ? "Apply KCL to the supernode \(group.joined(separator: "–"))" : "Apply KCL at node \(node)",
                summary: "Currents leaving \(isSuper ? "the supernode" : node) add up to zero",
                equations: lines,
                explanation: explanation,
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
                currentLines.append("\(context.currentSymbol(e.id)) = (\(context.voltageTerm(e.nodeA, known: voltages)) − \(context.voltageTerm(e.nodeB, known: voltages)))/\(f.precise(e.value)) = \(context.amps(e.current))  (\(Answers.flowWords(e)))")
            default:
                currentLines.append("\(context.currentSymbol(e.id)) = \(context.amps(e.value)) (given, from \(e.nodeA) to \(e.nodeB))")
            }
        }
        for e in elements where e.kind == .voltageSource {
            // Ohm's law says nothing about a source; KCL at one of its terminals does. Prefer a
            // terminal with no other voltage source, so that every other current there is known.
            func sourcesAt(_ node: String) -> Int {
                elements.filter { $0.id != e.id && $0.kind == .voltageSource && ($0.nodeA == node || $0.nodeB == node) }.count
            }
            let terminal = (sourcesAt(e.nodeA) == 0 || sourcesAt(e.nodeB) > 0) ? e.nodeA : e.nodeB
            let atPlus = terminal == e.nodeA
            let others = elements.filter { $0.id != e.id && $0.nodeA != $0.nodeB && ($0.nodeA == terminal || $0.nodeB == terminal) }
            var symbols = TermList()
            var numbers = TermList()
            var leavingSum = 0.0
            for other in others {
                let negative = other.nodeA != terminal
                symbols.add(context.currentSymbol(other.id), negative: negative)
                numbers.add(f.preciseTerm(other.current, "A"), negative: negative)
                leavingSum += ElementResults.currentLeaving(terminal, through: other)
            }
            // The source pushes `leavingSum` into this terminal: out of its + terminal means delivering.
            let delivered = atPlus ? leavingSum : -leavingSum
            let expression = symbols.isEmpty ? "0" : symbols.renderedLeftSide()
            let numeric = others.count > 1 ? numbers.renderedLeftSide() + " = " : ""
            let sign = atPlus ? "+" : "−"
            var line = "\(context.currentSymbol(e.id)): KCL at \(terminal) → \(expression) = \(numeric)\(context.amps(leavingSum))"
            if leavingSum >= 0 {
                line += " leaves \(terminal) through the other elements; \(e.id) supplies it from its \(sign) terminal"
            } else {
                line += ", i.e. \(context.amps(-leavingSum)) arrives at \(terminal) through the other elements and enters \(e.id) at its \(sign) terminal"
            }
            line += ", so \(e.id) \(delivered >= 0 ? "delivers" : "absorbs") \(context.amps(abs(delivered)))\(delivered >= 0 ? "" : " (it is being charged)")"
            currentLines.append(line)
        }
        let currents = Dictionary(uniqueKeysWithValues: elements.map { ($0.id, $0.current) })
        steps.append(AnalysisStep(
            title: "Find the current through each element",
            summary: "Ohm's law on every resistor, KCL at the sources",
            equations: currentLines,
            explanation: "With every node voltage known, the current through a resistor is the voltage drop across it divided by its resistance, flowing from the higher node to the lower one. A voltage source's current is not given by Ohm's law, so it comes from KCL at one of its terminals: the source carries whatever the elements next to it carry away. Current coming out of a source's + terminal means it delivers power; current coming out of its − terminal means the rest of the circuit is pushing current through it backwards, and it absorbs power.",
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
