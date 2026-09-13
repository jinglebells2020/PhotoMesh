import Foundation

/// Mesh-current method. Uses the recognizer's mesh hints when they form a valid, independent
/// set of loops; otherwise computes a short cycle basis itself. Current sources are handled
/// with an extra voltage unknown internally and presented as known currents / supermeshes.
enum MeshAnalysis {
    struct Loop {
        /// Component index and whether it is traversed from nodeA to nodeB.
        var edges: [(index: Int, forward: Bool)]
        var nodeSequence: [String]

        func sign(of edge: Int) -> Double {
            guard let hit = edges.first(where: { $0.index == edge }) else { return 0 }
            return hit.forward ? 1 : -1
        }

        func contains(_ edge: Int) -> Bool { edges.contains { $0.index == edge } }
    }

    static func solve(_ circuit: Circuit, formatter: QuantityFormatter) throws -> MethodSolution {
        let context = AnalysisContext(circuit: circuit, formatter: formatter)
        let graph = CircuitGraph(circuit)
        let loops = try findLoops(circuit: circuit, graph: graph)
        let components = circuit.components
        let currentSourceIndices = components.indices.filter { components[$0].kind == .currentSource }
        let L = loops.count
        let C = currentSourceIndices.count

        // MARK: Loop equations (KVL per loop + current constraints)
        var system = LinearSystem(size: L + C)
        for (k, loop) in loops.enumerated() {
            for (index, forward) in loop.edges {
                let component = components[index]
                let s: Double = forward ? 1 : -1
                switch component.kind {
                case .resistor:
                    for (j, other) in loops.enumerated() {
                        let sj = other.sign(of: index)
                        if sj != 0 { system.a[k][j] += s * component.value * sj }
                    }
                case .voltageSource:
                    system.b[k] -= s * component.value
                case .currentSource:
                    if let column = currentSourceIndices.firstIndex(of: index) {
                        system.a[k][L + column] += s
                    }
                }
            }
        }
        for (c, index) in currentSourceIndices.enumerated() {
            let row = L + c
            for (j, loop) in loops.enumerated() {
                let sj = loop.sign(of: index)
                if sj != 0 { system.a[row][j] += sj }
            }
            system.b[row] = components[index].value
        }
        let x = try system.solve()
        let meshCurrents = Array(x.prefix(L))
        var sourceVoltages: [Int: Double] = [:]
        for (c, index) in currentSourceIndices.enumerated() { sourceVoltages[index] = x[L + c] }

        // Element currents and voltages
        var currents: [Double] = []
        var drops: [Double] = []
        for (index, component) in components.enumerated() {
            let i = loops.enumerated().reduce(0.0) { $0 + $1.element.sign(of: index) * meshCurrents[$1.offset] }
            currents.append(i)
            switch component.kind {
            case .resistor: drops.append(i * component.value)
            case .voltageSource: drops.append(component.value)
            case .currentSource: drops.append(sourceVoltages[index] ?? 0)
            }
        }

        // Node voltages by walking from ground
        var voltages: [String: Double] = [circuit.groundNode: 0]
        var queue = [circuit.groundNode]
        while let node = queue.popLast() {
            for (edge, neighbor) in graph.neighbors(of: node) where voltages[neighbor] == nil {
                let component = components[edge]
                let drop = drops[edge]   // V(nodeA) − V(nodeB)
                voltages[neighbor] = component.nodeA == node ? (voltages[node]! - drop) : (voltages[node]! + drop)
                queue.append(neighbor)
            }
        }

        var sourceCurrents: [String: Double] = [:]
        for (index, component) in components.enumerated() where component.kind == .voltageSource {
            sourceCurrents[component.id] = currents[index]
        }
        var elements = ElementResults.compute(circuit: circuit, voltages: voltages, sourceCurrents: sourceCurrents)
        // Use the loop currents directly for resistors to avoid round-off differences.
        elements = elements.enumerated().map { offset, element in
            var copy = element
            if element.kind == .resistor {
                copy = ElementResult(id: element.id, kind: element.kind, value: element.value, nodeA: element.nodeA, nodeB: element.nodeB, current: currents[offset], voltage: drops[offset])
            }
            return copy
        }

        let answers = Answers.build(context: context, voltages: voltages, elements: elements)
        let steps = buildSteps(context: context, loops: loops, meshCurrents: meshCurrents, currentSourceIndices: currentSourceIndices, sourceVoltages: sourceVoltages, elements: elements, answers: answers)

        return MethodSolution(
            method: .mesh,
            headline: answers.first.map { "\($0.label): \($0.value)" } ?? "Solved",
            steps: steps,
            nodeVoltages: voltages,
            elements: elements,
            answers: answers
        )
    }

    // MARK: Loop discovery

    enum LoopError: LocalizedError {
        case noLoops
        var errorDescription: String? { "No closed loop was found, so mesh analysis does not apply." }
    }

    static func findLoops(circuit: Circuit, graph: CircuitGraph) throws -> [Loop] {
        let needed = circuit.components.count - circuit.nodes.count + 1
        guard needed > 0 else { throw LoopError.noLoops }

        if let hinted = loopsFromHints(circuit: circuit), hinted.count == needed, areIndependent(hinted, edgeCount: circuit.components.count) {
            return hinted
        }
        let computed = shortestCycleBasis(circuit: circuit, graph: graph, needed: needed)
        guard computed.count == needed else { throw LoopError.noLoops }
        return computed
    }

    /// Turns "[V1, R1, R2]" style hints into oriented loops, or nil if any hint is not a closed simple cycle.
    static func loopsFromHints(circuit: Circuit) -> [Loop]? {
        guard !circuit.meshes.isEmpty else { return nil }
        let components = circuit.components
        var loops: [Loop] = []
        for hint in circuit.meshes {
            let indices = hint.compactMap { id in components.firstIndex { $0.id == id } }
            guard indices.count == hint.count, indices.count >= 2, Set(indices).count == indices.count else { return nil }
            var built: Loop?
            for startForward in [true, false] {
                let first = components[indices[0]]
                var node = startForward ? first.nodeA : first.nodeB
                let start = node
                var edges: [(Int, Bool)] = []
                var sequence: [String] = [node]
                var ok = true
                for index in indices {
                    let component = components[index]
                    if component.nodeA == node {
                        edges.append((index, true))
                        node = component.nodeB
                    } else if component.nodeB == node {
                        edges.append((index, false))
                        node = component.nodeA
                    } else {
                        ok = false
                        break
                    }
                    sequence.append(node)
                }
                if ok, node == start, Set(sequence.dropLast()).count == sequence.count - 1 {
                    built = Loop(edges: edges, nodeSequence: sequence)
                    break
                }
            }
            guard let loop = built else { return nil }
            loops.append(loop)
        }
        return loops
    }

    /// GF(2) rank check on the edge-incidence vectors.
    static func areIndependent(_ loops: [Loop], edgeCount: Int) -> Bool {
        guard edgeCount <= 64 else { return true }
        var basis: [UInt64] = []
        for loop in loops {
            var vector: UInt64 = 0
            for (index, _) in loop.edges { vector |= (1 << UInt64(index)) }
            for b in basis where vector & (1 << UInt64(b.trailingZeroBitCount)) != 0 { vector ^= b }
            if vector == 0 { return false }
            basis.append(vector)
            basis.sort { $0.trailingZeroBitCount < $1.trailingZeroBitCount }
            // Re-reduce so each basis vector has a unique lowest bit.
            var reduced: [UInt64] = []
            for v in basis {
                var w = v
                for r in reduced where w & (1 << UInt64(r.trailingZeroBitCount)) != 0 { w ^= r }
                if w != 0 { reduced.append(w) }
            }
            basis = reduced.sorted { $0.trailingZeroBitCount < $1.trailingZeroBitCount }
        }
        return true
    }

    /// Horton-style: candidate cycles from shortest-path trees, greedily kept when independent.
    static func shortestCycleBasis(circuit: Circuit, graph: CircuitGraph, needed: Int) -> [Loop] {
        let components = circuit.components
        var candidates: [[Int]] = []
        var seen: Set<[Int]> = []
        for root in circuit.nodes {
            let tree = graph.shortestPathTree(from: root)
            for (index, component) in components.enumerated() {
                let pathA = graph.path(in: tree, to: component.nodeA)
                let pathB = graph.path(in: tree, to: component.nodeB)
                var edges = pathA + [index] + pathB
                guard Set(edges).count == edges.count else { continue }
                // Every vertex on a simple cycle has degree exactly 2 within the cycle.
                var degree: [String: Int] = [:]
                for e in edges {
                    degree[components[e].nodeA, default: 0] += 1
                    degree[components[e].nodeB, default: 0] += 1
                }
                guard degree.values.allSatisfy({ $0 == 2 }) else { continue }
                edges.sort()
                if seen.insert(edges).inserted { candidates.append(edges) }
            }
        }
        candidates.sort { $0.count < $1.count || ($0.count == $1.count && $0.lexicographicallyPrecedes($1)) }

        var chosen: [Loop] = []
        for candidate in candidates where chosen.count < needed {
            guard let loop = orient(edges: candidate, components: components) else { continue }
            if areIndependent(chosen + [loop], edgeCount: components.count) {
                chosen.append(loop)
            }
        }
        return chosen
    }

    /// Orders an edge set into a traversal starting at its lowest-named node.
    static func orient(edges: [Int], components: [Component]) -> Loop? {
        var remaining = Set(edges)
        let nodesInSet = Set(edges.flatMap { [components[$0].nodeA, components[$0].nodeB] })
        guard let start = nodesInSet.sorted(by: Circuit.naturalOrder).first else { return nil }
        var node = start
        var ordered: [(Int, Bool)] = []
        var sequence = [start]
        while !remaining.isEmpty {
            // Prefer the edge that keeps a consistent orientation (nodeA → nodeB) for readability.
            guard let next = remaining.sorted().first(where: { components[$0].touches(node) }) else { return nil }
            remaining.remove(next)
            let component = components[next]
            let forward = component.nodeA == node
            ordered.append((next, forward))
            node = component.otherNode(node)
            sequence.append(node)
        }
        guard node == start else { return nil }
        return Loop(edges: ordered, nodeSequence: sequence)
    }

    // MARK: Steps

    private static func buildSteps(context: AnalysisContext, loops: [Loop], meshCurrents: [Double], currentSourceIndices: [Int], sourceVoltages: [Int: Double], elements: [ElementResult], answers: [Answer]) -> [AnalysisStep] {
        let circuit = context.circuit
        let components = circuit.components
        let f = context.formatter
        var steps: [AnalysisStep] = []
        let L = loops.count

        // 1. Meshes
        let meshLines = loops.enumerated().map { k, loop -> String in
            let path = loop.nodeSequence.joined(separator: " → ")
            let ids = loop.edges.map { components[$0.index].id }.joined(separator: ", ")
            return "Mesh \(k + 1), current \(context.meshCurrentSymbol(k)): \(path)  (\(ids))"
        }
        steps.append(AnalysisStep(
            title: "Identify the meshes",
            summary: "\(L) independent loop\(L == 1 ? "" : "s")",
            equations: meshLines,
            explanation: "A mesh is a loop that encloses no other loop. Each one gets its own circulating current in the direction listed; an element shared by two meshes carries the difference of their currents.",
            result: "Mesh currents: " + (0..<L).map { context.meshCurrentSymbol($0) }.joined(separator: ", ")
        ))

        // 2. Current sources
        var knownMesh: [Int: Double] = [:]
        var supermeshPairs: [(a: Int, b: Int, source: Int)] = []
        var extendedSources: [Int] = []
        var sourceLines: [String] = []
        for index in currentSourceIndices {
            let component = components[index]
            let inLoops = loops.indices.filter { loops[$0].contains(index) }
            if inLoops.count == 1 {
                let k = inLoops[0]
                let value = component.value * loops[k].sign(of: index)
                knownMesh[k] = value
                sourceLines.append("\(context.meshCurrentSymbol(k)) = \(context.amps(value))  (\(component.id) lies only in mesh \(k + 1))")
            } else if inLoops.count == 2 {
                let (a, b) = (inLoops[0], inLoops[1])
                supermeshPairs.append((a, b, index))
                let sa = loops[a].sign(of: index), sb = loops[b].sign(of: index)
                var constraint = DisplayEquation()
                constraint.add(sa, to: context.meshCurrentSymbol(a))
                constraint.add(sb, to: context.meshCurrentSymbol(b))
                constraint.addConstant(component.value)
                sourceLines.append("\(constraint.rendered(with: f))  (\(component.id) is shared by meshes \(a + 1) and \(b + 1) → supermesh)")
            } else {
                extendedSources.append(index)
                sourceLines.append("\(component.id) spans \(inLoops.count) meshes: keep its voltage \(context.elementVoltageSymbol(component.id)) as an extra unknown")
            }
        }
        if !sourceLines.isEmpty {
            steps.append(AnalysisStep(
                title: "Account for the current sources",
                summary: "\(currentSourceIndices.count) current source\(currentSourceIndices.count == 1 ? "" : "s")",
                equations: sourceLines,
                explanation: "A current source fixes the current of any mesh it belongs to alone. When it sits between two meshes, their KVL loops are merged into one supermesh and the source gives the relation between the two mesh currents.",
                result: sourceLines.first ?? ""
            ))
        }

        // 3. KVL equations
        func kvlPieces(loop k: Int, skipping skip: Int?, scale: Double) -> (TermList, DisplayEquation) {
            var terms = TermList()
            var equation = DisplayEquation()
            let loop = loops[k]
            for (index, forward) in loop.edges where index != skip {
                let component = components[index]
                let s: Double = (forward ? 1 : -1) * scale
                switch component.kind {
                case .resistor:
                    var inner = ""
                    var count = 0
                    for (j, other) in loops.enumerated() {
                        let sj = other.sign(of: index)
                        guard sj != 0 else { continue }
                        let relative = (forward ? 1 : -1) * sj
                        let symbol = context.meshCurrentSymbol(j)
                        if let value = knownMesh[j] {
                            equation.addConstant(-s * component.value * sj * value)
                            inner += (count == 0 ? (relative < 0 ? "−" : "") : (relative < 0 ? " − " : " + ")) + f.term(abs(value))
                        } else {
                            equation.add(s * component.value * sj, to: symbol)
                            inner += (count == 0 ? (relative < 0 ? "−" : "") : (relative < 0 ? " − " : " + ")) + symbol
                        }
                        count += 1
                    }
                    let body = count > 1 ? "\(f.number(component.value))·(\(inner))" : "\(f.number(component.value))·\(inner)"
                    terms.add(body, negative: s < 0)
                case .voltageSource:
                    terms.add(f.number(component.value), negative: s < 0)
                    equation.addConstant(-s * component.value)
                case .currentSource:
                    terms.add(context.elementVoltageSymbol(component.id), negative: s < 0)
                    equation.add(s, to: context.elementVoltageSymbol(component.id))
                }
            }
            return (terms, equation)
        }

        var systemLines: [String] = []
        var handledLoops: Set<Int> = Set(knownMesh.keys)
        for pair in supermeshPairs {
            handledLoops.insert(pair.a)
            handledLoops.insert(pair.b)
            let sa = loops[pair.a].sign(of: pair.source), sb = loops[pair.b].sign(of: pair.source)
            let scaleB = -(sa * sb)   // cancels the source voltage
            let (termsA, eqA) = kvlPieces(loop: pair.a, skipping: pair.source, scale: 1)
            let (termsB, eqB) = kvlPieces(loop: pair.b, skipping: pair.source, scale: scaleB)
            var combined = eqA
            combined.add(eqB)
            let written = [termsA.renderedLeftSide(), termsB.renderedLeftSide()].filter { !$0.isEmpty && $0 != "0" }.joined(separator: " + ") + " = 0"
            let collected = combined.rendered(with: f)
            systemLines.append(collected)
            steps.append(AnalysisStep(
                title: "Apply KVL around the supermesh (meshes \(pair.a + 1) and \(pair.b + 1))",
                summary: "Go around both meshes, skipping \(components[pair.source].id)",
                equations: [written, "→ " + collected],
                explanation: "Walking around the outside of the two merged meshes avoids the unknown voltage across the current source. Sum of voltage drops = 0.",
                result: collected
            ))
        }
        for k in 0..<L where !handledLoops.contains(k) {
            let (terms, equation) = kvlPieces(loop: k, skipping: nil, scale: 1)
            let written = terms.rendered()
            let collected = equation.rendered(with: f)
            systemLines.append(collected)
            steps.append(AnalysisStep(
                title: "Apply KVL around mesh \(k + 1)",
                summary: "Sum of voltage drops in the direction of \(context.meshCurrentSymbol(k)) = 0",
                equations: [written, "→ " + collected],
                explanation: "Going around the loop, a resistor drops R times the net current through it, a voltage source adds +V when crossed from + to − and −V when crossed from − to +.",
                result: collected
            ))
        }

        // 4. Solve
        let unknownMeshes = (0..<L).filter { knownMesh[$0] == nil }
        if !unknownMeshes.isEmpty || !extendedSources.isEmpty {
            var lines = systemLines
            for pair in supermeshPairs {
                let sa = loops[pair.a].sign(of: pair.source), sb = loops[pair.b].sign(of: pair.source)
                var constraint = DisplayEquation()
                constraint.add(sa, to: context.meshCurrentSymbol(pair.a))
                constraint.add(sb, to: context.meshCurrentSymbol(pair.b))
                constraint.addConstant(components[pair.source].value)
                lines.append(constraint.rendered(with: f))
            }
            var solution = unknownMeshes.map { "\(context.meshCurrentSymbol($0)) = \(context.amps(meshCurrents[$0]))" }
            for index in extendedSources {
                solution.append("\(context.elementVoltageSymbol(components[index].id)) = \(context.volts(sourceVoltages[index] ?? 0))")
            }
            steps.append(AnalysisStep(
                title: unknownMeshes.count == 1 ? "Solve for the mesh current" : "Solve the system of equations",
                summary: "\(lines.count) equation\(lines.count == 1 ? "" : "s"), \(solution.count) unknown\(solution.count == 1 ? "" : "s")",
                equations: lines + ["→ " + solution.joined(separator: ", ")],
                explanation: unknownMeshes.count == 1
                    ? "Divide the constant by the coefficient of the unknown."
                    : "Solve by substitution or with a matrix; all mesh currents come out together.",
                result: solution.joined(separator: ", ")
            ))
        }

        // 5. Element currents
        var currentLines: [String] = []
        for (index, e) in elements.enumerated() {
            if e.kind == .currentSource {
                currentLines.append("\(context.currentSymbol(e.id)) = \(context.amps(e.value)) (given)")
                continue
            }
            var expression = ""
            var count = 0
            for (j, loop) in loops.enumerated() {
                let sj = loop.sign(of: index)
                guard sj != 0 else { continue }
                let symbol = context.meshCurrentSymbol(j)
                expression += (count == 0 ? (sj < 0 ? "−" : "") : (sj < 0 ? " − " : " + ")) + symbol
                count += 1
            }
            let contributions = loops.enumerated().compactMap { j, loop -> String? in
                let sj = loop.sign(of: index)
                guard sj != 0 else { return nil }
                return f.term(sj * meshCurrents[j], "A")
            }
            let numeric = contributions.count > 1 ? contributions.joined(separator: " + ") + " = " : ""
            let suffix = e.kind == .voltageSource ? "  (\(e.id) \(-e.current >= 0 ? "delivers" : "absorbs") \(context.amps(abs(e.current))))" : ""
            currentLines.append("\(context.currentSymbol(e.id)) = \(expression) = \(numeric)\(context.amps(e.current))\(suffix)")
        }
        steps.append(AnalysisStep(
            title: "Find the current through each element",
            summary: "Combine the mesh currents",
            equations: currentLines,
            explanation: "An element in one mesh carries that mesh current; an element shared by two meshes carries their difference. Currents are given from the element's first terminal to its second.",
            result: currentLines.count == 1 ? currentLines[0] : "\(currentLines.count) currents found"
        ))

        // 6. Voltages, 7. Answer
        steps.append(SharedSteps.elementVoltages(context: context, elements: elements))
        steps.append(SharedSteps.answerStep(context: context, answers: answers, elements: elements))
        return steps
    }
}
