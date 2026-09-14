import Foundation

/// Series/parallel reduction: the way a first course solves a one-source resistor network.
/// Resistors in series or in parallel are combined one pair at a time until a single equivalent
/// sits across the source; Ohm's law gives the total; then the reductions are undone one by one,
/// sharing the current along series parts and the voltage across parallel parts.
/// Not every network reduces this way (a bridge does not); then the method is simply not offered.
enum ReductionAnalysis {
    enum Failure: LocalizedError {
        case notApplicable(String)
        var errorDescription: String? {
            switch self {
            case .notApplicable(let why): return "Series/parallel reduction does not apply: \(why)"
            }
        }
    }

    /// A resistor or an equivalent standing in for several.
    private final class Group {
        let id: String
        let value: Double
        var nodeA: String
        var nodeB: String
        let members: [String]                 // original element ids
        let kind: Kind
        enum Kind { case single, series(Group, Group, via: String), parallel(Group, Group) }
        var current = 0.0                     // from nodeA to nodeB
        var voltage = 0.0                     // V(nodeA) − V(nodeB)

        init(id: String, value: Double, nodeA: String, nodeB: String, members: [String], kind: Kind) {
            self.id = id; self.value = value; self.nodeA = nodeA; self.nodeB = nodeB; self.members = members; self.kind = kind
        }

        func connects(_ x: String, _ y: String) -> Bool { (nodeA == x && nodeB == y) || (nodeA == y && nodeB == x) }
        func touches(_ node: String) -> Bool { nodeA == node || nodeB == node }
        func otherNode(_ node: String) -> String { node == nodeA ? nodeB : nodeA }
    }

    static func solve(_ circuit: Circuit, formatter f: QuantityFormatter, presented: Circuit? = nil) throws -> MethodSolution {
        let context = AnalysisContext(circuit: circuit, formatter: f, presented: presented)
        let sources = circuit.components.filter { $0.kind.isSource }
        guard sources.count == 1, let source = sources.first else {
            throw Failure.notApplicable("it needs exactly one source")
        }
        guard circuit.components.allSatisfy({ $0.kind == .resistor || $0.id == source.id }) else {
            throw Failure.notApplicable("only resistors and one source can be combined")
        }
        guard circuit.resistors.count >= 1 else { throw Failure.notApplicable("there is nothing to combine") }

        var groups = circuit.resistors.map { Group(id: $0.id, value: $0.value, nodeA: $0.nodeA, nodeB: $0.nodeB, members: [$0.id], kind: .single) }
        var steps: [AnalysisStep] = []
        steps.append(SharedSteps.readCircuit(context: context))

        steps.append(AnalysisStep(
            title: "Plan: simplify, then work back",
            summary: "One source and only resistors",
            equations: ["Series: R = R₁ + R₂ (same current)", "Parallel: R = (R₁·R₂)/(R₁ + R₂) (same voltage)"],
            explanation: "With a single source feeding nothing but resistors, the whole network can usually be collapsed into one equivalent resistance. Two resistors in series carry the same current, so their resistances add. Two resistors in parallel share the same voltage, so their conductances add, which is the product-over-sum rule for a pair. Once one resistor is left, Ohm's law gives the total current, and each combination can be undone to find every individual current and voltage.",
            result: "Combine until one resistor remains",
            focus: StepFocus(elements: circuit.components.map(\.id))
        ))

        // MARK: Reduce
        var equivalentCount = 0
        func name(for members: [String]) -> String {
            let digits = members.compactMap { id -> String? in
                guard id.hasPrefix("R"), id.dropFirst().allSatisfy(\.isNumber), id.count <= 3 else { return nil }
                return String(id.dropFirst())
            }
            if digits.count == members.count, digits.joined().count <= 5 {
                return "R" + digits.sorted { Circuit.naturalOrder($0, $1) }.joined()
            }
            equivalentCount += 1
            return "Req" + QuantityFormatter.subscriptDigits(String(equivalentCount))
        }

        var merges: [Group] = []
        var progress = true
        while progress, groups.count > 1 {
            progress = false
            // Parallel pair first: same two nodes.
            var merged = false
            outer: for i in groups.indices {
                for j in (i + 1)..<groups.count where groups[j].connects(groups[i].nodeA, groups[i].nodeB) {
                    let g1 = groups[i], g2 = groups[j]
                    let value = g1.value * g2.value / (g1.value + g2.value)
                    let group = Group(id: name(for: g1.members + g2.members), value: value, nodeA: g1.nodeA, nodeB: g1.nodeB, members: g1.members + g2.members, kind: .parallel(g1, g2))
                    groups.remove(at: j); groups.remove(at: i)
                    groups.append(group)
                    merges.append(group)
                    steps.append(AnalysisStep(
                        title: "Combine \(g1.id) and \(g2.id) in parallel",
                        summary: "Both sit between \(g1.nodeA) and \(g1.nodeB)",
                        equations: [
                            "\(g1.id) ‖ \(g2.id): both between \(g1.nodeA) and \(g1.nodeB)",
                            "\(group.id) = (\(g1.id)·\(g2.id))/(\(g1.id) + \(g2.id)) = (\(f.number(g1.value))·\(f.number(g2.value)))/(\(f.number(g1.value)) + \(f.number(g2.value))) = \(context.ohms(value))",
                        ],
                        explanation: "Two elements that connect the same pair of nodes are in parallel: the same voltage sits across both, and the current splits between them. Their combined resistance is smaller than either one, given by the product over the sum. \(group.id) now stands in for \(g1.id) and \(g2.id).",
                        result: "\(group.id) = \(context.ohms(value))",
                        focus: StepFocus(nodes: [g1.nodeA, g1.nodeB], elements: group.members, zoom: true)
                    ))
                    merged = true
                    break outer
                }
            }
            if merged { progress = true; continue }
            // Series pair: a node that joins exactly two groups and nothing else.
            let sourceNodes = Set([source.nodeA, source.nodeB])
            for node in circuit.nodes where !sourceNodes.contains(node) {
                let at = groups.filter { $0.touches(node) }
                guard at.count == 2, !at[0].connects(node, node) else { continue }
                let g1 = at[0], g2 = at[1]
                let a = g1.otherNode(node), b = g2.otherNode(node)
                guard a != b else { continue }   // that would be a parallel pair, handled above
                let value = g1.value + g2.value
                let group = Group(id: name(for: g1.members + g2.members), value: value, nodeA: a, nodeB: b, members: g1.members + g2.members, kind: .series(g1, g2, via: node))
                groups.removeAll { $0 === g1 || $0 === g2 }
                groups.append(group)
                merges.append(group)
                steps.append(AnalysisStep(
                    title: "Combine \(g1.id) and \(g2.id) in series",
                    summary: "Node \(node) joins only these two",
                    equations: [
                        "\(g1.id) — \(node) — \(g2.id): nothing else connects at \(node)",
                        "\(group.id) = \(g1.id) + \(g2.id) = \(f.number(g1.value)) + \(f.number(g2.value)) = \(context.ohms(value))",
                    ],
                    explanation: "When a node joins exactly two elements, every bit of current that enters through one must leave through the other, so they carry the same current: they are in series and their resistances add. \(group.id) now stands in for \(g1.id) and \(g2.id), running from \(a) to \(b).",
                    result: "\(group.id) = \(context.ohms(value))",
                    focus: StepFocus(nodes: [node], elements: group.members, zoom: true)
                ))
                progress = true
                break
            }
        }
        guard groups.count == 1, let root = groups.first, root.connects(source.nodeA, source.nodeB) else {
            throw Failure.notApplicable("the resistors are not connected in a plain series/parallel pattern (a bridge needs node or mesh analysis)")
        }

        // MARK: Ohm's law for the whole network
        // Orient the equivalent from the source's + (or "from") terminal to the other terminal.
        if root.nodeA != source.nodeA { swap(&root.nodeA, &root.nodeB) }
        let total: Double
        switch source.kind.dcRole {
        case .voltageSource:
            total = source.value / root.value           // out of + into the network
            root.current = total
            root.voltage = source.value
            steps.append(AnalysisStep(
                title: "Ohm's law for the whole circuit",
                summary: "\(source.id) drives \(root.id)",
                equations: [
                    "I = \(source.id)/\(root.id) = \(f.number(source.value))/\(f.number(root.value))",
                    "→ I = \(context.amps(total))",
                ],
                explanation: "The source now sees a single resistor \(root.id) across its terminals, so the total current is simply the source voltage divided by the equivalent resistance. This current leaves the + terminal, flows through the network and returns to the − terminal.",
                result: "I = \(context.amps(total))",
                focus: StepFocus(elements: [source.id] + root.members, elementCurrents: [source.id: -total], animateCurrents: true)
            ))
        default:
            // A current source pushes its current from nodeA into nodeB inside itself, so the
            // network carries it from nodeB back to nodeA.
            total = -source.value
            root.current = total
            root.voltage = total * root.value
            steps.append(AnalysisStep(
                title: "Ohm's law for the whole circuit",
                summary: "\(source.id) pushes its current through \(root.id)",
                equations: [
                    "V = \(source.id)·\(root.id) = \(f.number(source.value))·\(f.number(root.value))",
                    "→ V = \(context.volts(source.value * root.value)) across \(root.id), \(source.nodeB) higher than \(source.nodeA)",
                ],
                explanation: "A current source fixes the current, so the unknown is the voltage it must develop: the source current times the equivalent resistance. The current enters the network at \(source.nodeB) and returns to the source at \(source.nodeA).",
                result: "V = \(context.volts(source.value * root.value))",
                focus: StepFocus(elements: [source.id] + root.members, elementCurrents: [source.id: source.value], animateCurrents: true)
            ))
        }

        // MARK: Unwind
        var known: [String: Double] = [:]   // element currents found so far (original ids)
        for group in merges.reversed() {
            switch group.kind {
            case .single:
                continue
            case .series(let g1, let g2, let via):
                // Same current through both, in the direction of the combined group.
                for child in [g1, g2] {
                    let forward = child.nodeA == group.nodeA || child.nodeB == group.nodeB
                    // The child's orientation relative to the group's: it starts where the group starts, or ends where it ends.
                    child.current = forward ? group.current : -group.current
                    if child.nodeA != group.nodeA && child.nodeB != group.nodeB {
                        // Middle-of-chain orientation is decided by the shared node.
                        child.current = child.nodeA == via ? -group.current : group.current
                        if child.nodeA == group.nodeA { child.current = group.current }
                    }
                    child.voltage = child.current * child.value
                }
                var lines = ["Series: I(\(g1.id)) = I(\(g2.id)) = I(\(group.id)) = \(context.amps(abs(group.current)))"]
                for child in [g1, g2] {
                    lines.append("V(\(child.id)) = \(child.id)·I = \(context.ohms(child.value))·\(context.amps(abs(child.current))) = \(context.volts(abs(child.voltage)))")
                }
                lines.append("Check: \(context.volts(abs(g1.voltage))) + \(context.volts(abs(g2.voltage))) = \(context.volts(abs(g1.voltage) + abs(g2.voltage))) = V(\(group.id)) ✓")
                for child in [g1, g2] where child.members.count == 1 { known[child.id] = child.current }
                steps.append(AnalysisStep(
                    title: "Split \(group.id) back into \(g1.id) and \(g2.id)",
                    summary: "Series parts share the current; the voltage divides",
                    equations: lines,
                    explanation: "Undoing a series combination: the current through \(group.id) is the current through each part. Each part's voltage is its own resistance times that current, and the two voltages add up to the voltage across \(group.id) (the voltage-divider rule).",
                    result: "V(\(g1.id)) = \(context.volts(abs(g1.voltage))), V(\(g2.id)) = \(context.volts(abs(g2.voltage)))",
                    focus: StepFocus(nodes: [via], elements: group.members, zoom: true, elementCurrents: known, animateCurrents: true)
                ))
            case .parallel(let g1, let g2):
                for child in [g1, g2] {
                    let forward = child.nodeA == group.nodeA
                    child.voltage = forward ? group.voltage : -group.voltage
                    child.current = child.voltage / child.value
                }
                var lines = ["Parallel: V(\(g1.id)) = V(\(g2.id)) = V(\(group.id)) = \(context.volts(abs(group.voltage)))"]
                for child in [g1, g2] {
                    lines.append("I(\(child.id)) = V/\(child.id) = \(f.number(abs(child.voltage)))/\(f.number(child.value)) = \(context.amps(abs(child.current)))")
                }
                lines.append("Check: \(context.amps(abs(g1.current))) + \(context.amps(abs(g2.current))) = \(context.amps(abs(g1.current) + abs(g2.current))) = I(\(group.id)) ✓")
                for child in [g1, g2] where child.members.count == 1 { known[child.id] = child.current }
                steps.append(AnalysisStep(
                    title: "Split \(group.id) back into \(g1.id) and \(g2.id)",
                    summary: "Parallel parts share the voltage; the current divides",
                    equations: lines,
                    explanation: "Undoing a parallel combination: the voltage across \(group.id) is the voltage across each part, so each part's current is that voltage divided by its own resistance. The two currents add up to the current through \(group.id) (the current-divider rule): the smaller resistor takes the larger share.",
                    result: "I(\(g1.id)) = \(context.amps(abs(g1.current))), I(\(g2.id)) = \(context.amps(abs(g2.current)))",
                    focus: StepFocus(nodes: [group.nodeA, group.nodeB], elements: group.members, zoom: true, elementCurrents: known, animateCurrents: true)
                ))
            }
        }
        if merges.isEmpty { known[root.id] = root.current }

        // MARK: Results
        var elementVoltages: [String: Double] = [:]
        var currents: [String: Double] = [:]
        func collect(_ group: Group) {
            switch group.kind {
            case .single:
                currents[group.id] = group.current
                elementVoltages[group.id] = group.voltage
            case .series(let g1, let g2, _), .parallel(let g1, let g2):
                collect(g1); collect(g2)
            }
        }
        collect(root)
        // Element convention: current from nodeA to nodeB of the *component*; the group may be flipped.
        var results: [ElementResult] = []
        for component in circuit.components {
            if component.id == source.id {
                switch source.kind.dcRole {
                case .voltageSource:
                    results.append(ElementResult(id: component.id, kind: component.kind, value: component.value, nodeA: component.nodeA, nodeB: component.nodeB, current: -total, voltage: component.value))
                    elementVoltages[component.id] = component.value
                default:
                    results.append(ElementResult(id: component.id, kind: component.kind, value: component.value, nodeA: component.nodeA, nodeB: component.nodeB, current: component.value, voltage: -root.voltage))
                    elementVoltages[component.id] = -root.voltage
                }
                continue
            }
            guard let group = groupLookup(root, id: component.id) else { continue }
            let sameOrientation = group.nodeA == component.nodeA
            let current = sameOrientation ? group.current : -group.current
            let voltage = current * component.value
            elementVoltages[component.id] = voltage
            results.append(ElementResult(id: component.id, kind: component.kind, value: component.value, nodeA: component.nodeA, nodeB: component.nodeB, current: current, voltage: voltage))
        }
        let voltages = SharedSteps.nodeVoltages(circuit: circuit, elementVoltages: elementVoltages)
        let answers = Answers.build(context: context, voltages: voltages, elements: results)
        steps.append(SharedSteps.checkStep(context: context, elements: results, voltages: voltages))
        steps.append(SharedSteps.answerStep(context: context, answers: answers, elements: results, voltages: voltages))

        return MethodSolution(
            method: .reduction,
            headline: answers.first.map { "\($0.label): \($0.value)" } ?? "Solved",
            steps: steps,
            nodeVoltages: voltages,
            elements: results,
            answers: answers
        )
    }

    private static func groupLookup(_ group: Group, id: String) -> Group? {
        switch group.kind {
        case .single: return group.id == id ? group : nil
        case .series(let g1, let g2, _), .parallel(let g1, let g2): return groupLookup(g1, id: id) ?? groupLookup(g2, id: id)
        }
    }
}
