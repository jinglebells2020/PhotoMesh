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

    /// The schematic layout lets every mesh current run clockwise on the drawing, the convention
    /// textbooks use so a shared resistor reads I₁ − I₂.
    static func solve(_ circuit: Circuit, formatter: QuantityFormatter, layout: SchematicLayout? = nil, presented: Circuit? = nil) throws -> MethodSolution {
        let context = AnalysisContext(circuit: circuit, formatter: formatter, presented: presented)
        let graph = CircuitGraph(circuit)
        var (loops, windows) = try findLoops(circuit: circuit, graph: graph, layout: layout)
        if let layout {
            let nodePositions = layout.nodePositions
            let centers = Dictionary(uniqueKeysWithValues: layout.symbols.map { ($0.id, $0.center) })
            loops = loops.map { clockwise($0, components: circuit.components, nodePositions: nodePositions, elementCenters: centers) }
        }
        if !windows { windows = directionsConsistent(loops) }
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
                switch component.kind.dcRole {
                case .open, .short:
                    continue
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
            switch component.kind.dcRole {
            case .resistor: drops.append(i * component.value)
            case .voltageSource: drops.append(component.value)
            case .currentSource: drops.append(sourceVoltages[index] ?? 0)
            case .open, .short: drops.append(0)
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
        let steps = buildSteps(context: context, loops: loops, windows: windows, meshCurrents: meshCurrents, currentSourceIndices: currentSourceIndices, sourceVoltages: sourceVoltages, elements: elements, voltages: voltages, answers: answers)
        let paths = loops.map { loop in
            LoopPath(elementIds: loop.edges.map { components[$0.index].id }, nodeSequence: loop.nodeSequence)
        }

        return MethodSolution(
            method: .mesh,
            headline: answers.first.map { "\($0.label): \($0.value)" } ?? "Solved",
            steps: steps,
            nodeVoltages: voltages,
            elements: elements,
            answers: answers,
            loops: paths
        )
    }

    // MARK: Loop discovery

    enum LoopError: LocalizedError {
        case noLoops
        var errorDescription: String? { "No closed loop was found, so mesh analysis does not apply." }
    }

    /// `windows` is true when the loops are the actual windows of the drawing (meshes proper);
    /// otherwise they are an independent loop set, which solves the same way but is worded as such.
    static func findLoops(circuit: Circuit, graph: CircuitGraph, layout: SchematicLayout? = nil) throws -> (loops: [Loop], windows: Bool) {
        let needed = circuit.components.count - circuit.nodes.count + 1
        guard needed > 0 else { throw LoopError.noLoops }

        // The windows of the drawing are the real meshes; anything else is just a valid loop set.
        if let layout, let faces = planarMeshes(circuit: circuit, layout: layout), faces.count == needed, areIndependent(faces, edgeCount: circuit.components.count) {
            return (faces, true)
        }
        if let hinted = loopsFromHints(circuit: circuit), hinted.count == needed, areIndependent(hinted, edgeCount: circuit.components.count) {
            return (hinted, false)
        }
        let computed = shortestCycleBasis(circuit: circuit, graph: graph, needed: needed)
        guard computed.count == needed else { throw LoopError.noLoops }
        return (computed, false)
    }

    /// Windows of a planar drawing never run through a shared element the same way twice; a loop
    /// set that does is a valid basis but not a set of meshes, and the steps say so.
    static func directionsConsistent(_ loops: [Loop]) -> Bool {
        var direction: [Int: Bool] = [:]
        for loop in loops {
            for edge in loop.edges {
                if let seen = direction[edge.index], seen == edge.forward { return false }
                direction[edge.index] = edge.forward
            }
        }
        return true
    }

    /// Inner faces of the drawn circuit (planar map traversal). Each element is an edge that passes
    /// through its symbol centre, which tells parallel elements apart. Nil when the drawing does not
    /// give a clean set of faces (degenerate positions, crossings).
    static func planarMeshes(circuit: Circuit, layout: SchematicLayout) -> [Loop]? {
        let components = circuit.components
        let positions = layout.nodePositions
        let centers = Dictionary(uniqueKeysWithValues: layout.symbols.map { ($0.id, $0.center) })
        guard components.allSatisfy({ positions[$0.nodeA] != nil && positions[$0.nodeB] != nil && centers[$0.id] != nil }) else { return nil }

        struct HalfEdge: Hashable { var edge: Int; var forward: Bool }   // forward: nodeA → nodeB
        func tail(_ h: HalfEdge) -> String { h.forward ? components[h.edge].nodeA : components[h.edge].nodeB }
        func head(_ h: HalfEdge) -> String { h.forward ? components[h.edge].nodeB : components[h.edge].nodeA }
        func angle(_ h: HalfEdge) -> Double {
            let from = positions[tail(h)]!, via = centers[components[h.edge].id]!
            return atan2(via.y - from.y, via.x - from.x)
        }

        // Rotation system: half-edges leaving each node, sorted by angle.
        var rotation: [String: [HalfEdge]] = [:]
        for (index, component) in components.enumerated() {
            rotation[component.nodeA, default: []].append(HalfEdge(edge: index, forward: true))
            rotation[component.nodeB, default: []].append(HalfEdge(edge: index, forward: false))
        }
        for (node, list) in rotation {
            let sorted = list.sorted { angle($0) < angle($1) }
            // Two half-edges at the same angle cannot be told apart: give up.
            for (a, b) in zip(sorted, sorted.dropFirst()) where abs(angle(a) - angle(b)) < 1e-6 { return nil }
            rotation[node] = sorted
        }

        var visited: Set<HalfEdge> = []
        var faces: [(loop: Loop, area: Double)] = []
        for (index, _) in components.enumerated() {
            for forward in [true, false] {
                let start = HalfEdge(edge: index, forward: forward)
                guard !visited.contains(start) else { continue }
                var edges: [(index: Int, forward: Bool)] = []
                var sequence = [tail(start)]
                var current = start
                var points: [SPoint] = []
                var guardCount = 0
                repeat {
                    visited.insert(current)
                    edges.append((current.edge, current.forward))
                    points.append(positions[tail(current)]!)
                    points.append(centers[components[current.edge].id]!)
                    let arrivedAt = head(current)
                    sequence.append(arrivedAt)
                    // Next half-edge: the one after the twin in the rotation at the node we arrived at.
                    let twin = HalfEdge(edge: current.edge, forward: !current.forward)
                    guard let list = rotation[arrivedAt], let position = list.firstIndex(of: twin) else { return nil }
                    current = list[(position + 1) % list.count]
                    guardCount += 1
                    if guardCount > components.count * 2 + 2 { return nil }
                } while current != start
                // A face that uses the same element twice is a dangling path, not a window.
                guard Set(edges.map(\.index)).count == edges.count, sequence.count == edges.count + 1 else { continue }
                var area = 0.0
                for i in points.indices {
                    let p = points[i], q = points[(i + 1) % points.count]
                    area += p.x * q.y - q.x * p.y
                }
                faces.append((Loop(edges: edges, nodeSequence: sequence), area))
            }
        }
        guard faces.count >= 2 else { return nil }
        // The outer face is the one with the largest area and the opposite orientation; drop it.
        let outer = faces.indices.max { abs(faces[$0].area) < abs(faces[$1].area) }!
        var inner = faces.enumerated().filter { $0.offset != outer }.map(\.element)
        // Inner faces share one orientation; anything oriented like the outer face is not a window.
        let outerSign = faces[outer].area >= 0
        inner = inner.filter { ($0.area >= 0) != outerSign && abs($0.area) > 1e-6 }
        guard !inner.isEmpty else { return nil }
        // Windows of a planar drawing traverse every shared element in opposite directions; if two
        // faces run the same way through an element the drawing has crossings, so give up.
        var direction: [Int: Bool] = [:]
        for face in inner {
            for edge in face.loop.edges {
                if let seen = direction[edge.index], seen == edge.forward { return nil }
                direction[edge.index] = edge.forward
            }
        }
        // Present them in a stable order: top-left window first.
        inner.sort { lhs, rhs in
            let a = SRect.around(lhs.loop.nodeSequence.compactMap { positions[$0] }), b = SRect.around(rhs.loop.nodeSequence.compactMap { positions[$0] })
            if abs(a.minY - b.minY) > 1 { return a.minY < b.minY }
            return a.minX < b.minX
        }
        return inner.map(\.loop)
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

    /// Reverses a loop that runs counter-clockwise on screen. The polygon alternates node positions
    /// and element midpoints, so even a two-element loop (two parts in parallel) has an area.
    /// y grows downward on screen, so a positive shoelace area is clockwise.
    static func clockwise(_ loop: Loop, components: [Component], nodePositions: [String: SPoint], elementCenters: [String: SPoint]) -> Loop {
        var points: [SPoint] = []
        for (offset, edge) in loop.edges.enumerated() {
            if let p = nodePositions[loop.nodeSequence[offset]] { points.append(p) }
            if let c = elementCenters[components[edge.index].id] { points.append(c) }
        }
        guard points.count >= 3 else { return loop }
        var area = 0.0
        for i in points.indices {
            let p = points[i], q = points[(i + 1) % points.count]
            area += p.x * q.y - q.x * p.y
        }
        guard area < 0 else { return loop }
        let reversedEdges = loop.edges.reversed().map { (index: $0.index, forward: !$0.forward) }
        let sequence = Array(loop.nodeSequence.reversed())
        return Loop(edges: reversedEdges, nodeSequence: sequence)
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

    private static func buildSteps(context: AnalysisContext, loops: [Loop], windows: Bool, meshCurrents: [Double], currentSourceIndices: [Int], sourceVoltages: [Int: Double], elements: [ElementResult], voltages: [String: Double], answers: [Answer]) -> [AnalysisStep] {
        let circuit = context.circuit
        let components = circuit.components
        let f = context.formatter
        var steps: [AnalysisStep] = []
        let L = loops.count
        let meshSymbols = (0..<L).map { context.meshCurrentSymbol($0) }
        let word = windows ? "mesh" : "loop"
        let words = windows ? "meshes" : "loops"

        // 0. Given / find
        steps.append(SharedSteps.readCircuit(context: context))

        // 1. Meshes
        let meshLines = loops.enumerated().map { k, loop -> String in
            let ids = loop.edges.map { components[$0.index].id }.joined(separator: " → ")
            return "\(windows ? "Mesh" : "Loop") \(k + 1), \(meshSymbols[k]) clockwise: \(ids)"
        }
        steps.append(AnalysisStep(
            title: windows ? "Identify the meshes" : "Choose independent loops",
            summary: "\(L) \(L == 1 ? word : words), so \(L) unknown current\(L == 1 ? "" : "s")",
            equations: meshLines,
            explanation: windows
                ? "A mesh is a loop that has no other loop inside it, a \"window\" of the drawing. Give each mesh its own circulating current and take them all clockwise: an element on the outside of a mesh carries that mesh current alone, and an element shared by two meshes carries the difference of the two (they run through it in opposite directions)."
                : "This drawing does not split into clean windows, so a set of independent loops is used instead; the method works exactly the same way. Give each loop its own circulating current. An element in one loop carries that loop current alone; an element shared by two loops carries both, each counted with the sign of that loop's direction through it: a difference when they pass in opposite directions, a sum when they pass the same way.",
            result: "\(windows ? "Mesh" : "Loop") currents: " + meshSymbols.joined(separator: ", "),
            focus: StepFocus(loops: Array(0..<L), showMeshArrows: true)
        ))

        // 2. Current sources
        var knownMesh: [Int: Double] = [:]
        var supermeshPairs: [(a: Int, b: Int, source: Int)] = []
        var extendedSources: [Int] = []
        var sourceLines: [String] = []
        var constraintEquations: [(DisplayEquation, StepFocus)] = []
        for index in currentSourceIndices {
            let component = components[index]
            let inLoops = loops.indices.filter { loops[$0].contains(index) }
            if inLoops.count == 1 {
                let k = inLoops[0]
                let value = component.value * loops[k].sign(of: index)
                knownMesh[k] = value
                sourceLines.append("\(meshSymbols[k]) = \(context.amps(value))  (\(component.id) lies only in \(word) \(k + 1)\(value < 0 ? "; it points against the clockwise direction" : ""))")
            } else if inLoops.count == 2 {
                let (a, b) = (inLoops[0], inLoops[1])
                supermeshPairs.append((a, b, index))
                let sa = loops[a].sign(of: index), sb = loops[b].sign(of: index)
                var constraint = DisplayEquation()
                constraint.add(sa, to: meshSymbols[a])
                constraint.add(sb, to: meshSymbols[b])
                constraint.addConstant(component.value)
                constraintEquations.append((constraint, StepFocus(elements: [component.id], loops: [a, b], zoom: true, showMeshArrows: true)))
                sourceLines.append("\(constraint.rendered(with: f, order: meshSymbols))  (\(component.id) is shared by \(words) \(a + 1) and \(b + 1), so the net \(word) current through it must equal its value)")
            } else {
                extendedSources.append(index)
                sourceLines.append("\(component.id) spans \(inLoops.count) \(words): keep its voltage \(context.elementVoltageSymbol(component.id)) as an extra unknown")
            }
        }
        if !sourceLines.isEmpty {
            let involvedLoops = loops.indices.filter { k in currentSourceIndices.contains { loops[k].contains($0) } }
            steps.append(AnalysisStep(
                title: "Account for the current sources",
                summary: "\(currentSourceIndices.count) current source\(currentSourceIndices.count == 1 ? "" : "s")",
                equations: sourceLines,
                explanation: "A current source forces its current whatever the voltage across it, so KVL cannot be written through it. If it lies in one mesh only, that mesh current is known at once. If two meshes share it, the two are merged into one bigger loop (a supermesh) for KVL, and the source gives the relation between their currents instead.",
                result: sourceLines.first.map { String($0.split(separator: "  ").first ?? "") } ?? "",
                focus: StepFocus(elements: currentSourceIndices.map { components[$0].id }, loops: involvedLoops, zoom: true, meshCurrents: knownMesh, showMeshArrows: true)
            ))
        }

        // 3. KVL, element by element
        struct Piece { var line: String; var term: String; var expanded: [String] }
        func kvlPieces(loop k: Int, skipping skip: Int?) -> ([Piece], DisplayEquation) {
            var pieces: [Piece] = []
            var equation = DisplayEquation()
            let loop = loops[k]
            for (index, forward) in loop.edges where index != skip {
                let component = components[index]
                let s: Double = forward ? 1 : -1
                switch component.kind.dcRole {
                case .open, .short:
                    continue
                case .resistor:
                    var inner = ""
                    var count = 0
                    var sharedWith: [Int] = []
                    var expanded: [String] = []
                    let rText = f.number(component.value)
                    // Own mesh current first, then the neighbours: "R·(I₂ − I₁)" reads naturally.
                    let order = [k] + loops.indices.filter { $0 != k }
                    for j in order {
                        let other = loops[j]
                        let sj = other.sign(of: index)
                        guard sj != 0 else { continue }
                        let relative = s * sj   // +1: mesh j runs through R the same way we are walking
                        if j != k { sharedWith.append(j) }
                        if let value = knownMesh[j] {
                            // A known mesh current is substituted with its own sign: (I₂ − (−2)).
                            equation.addConstant(-component.value * relative * value)
                            inner += (count == 0 ? (relative < 0 ? "−" : "") : (relative < 0 ? " − " : " + ")) + f.term(value)
                            let contribution = component.value * relative * value
                            expanded.append((contribution < 0 ? "−" : "+") + f.number(abs(contribution)))
                        } else {
                            equation.add(component.value * relative, to: meshSymbols[j])
                            inner += (count == 0 ? (relative < 0 ? "−" : "") : (relative < 0 ? " − " : " + ")) + meshSymbols[j]
                            expanded.append((relative < 0 ? "−" : "+") + (abs(component.value - 1) < 1e-12 ? "" : rText + "·") + meshSymbols[j])
                        }
                        count += 1
                    }
                    let unitResistance = abs(component.value - 1) < 1e-12
                    let body = count > 1 ? (unitResistance ? "(\(inner))" : "\(rText)·(\(inner))") : (unitResistance ? inner : "\(rText)·\(inner)")
                    let note = sharedWith.isEmpty ? "" : " (shared with \(word) \(sharedWith.map { String($0 + 1) }.joined(separator: ", ")))"
                    pieces.append(Piece(line: "\(component.id)\(note): +\(body)", term: "+" + body, expanded: expanded))
                case .voltageSource:
                    let drop = s * component.value   // crossing + → − is a drop
                    let text = f.number(abs(drop))
                    pieces.append(Piece(line: "\(component.id) (crossed \(s > 0 ? "+ to −, a drop" : "− to +, a rise")): \(drop >= 0 ? "+" : "−")\(text)", term: (drop >= 0 ? "+" : "−") + text, expanded: [(drop >= 0 ? "+" : "−") + text]))
                    equation.addConstant(-drop)
                case .currentSource:
                    let symbol = context.elementVoltageSymbol(component.id)
                    pieces.append(Piece(line: "\(component.id): \(s > 0 ? "+" : "−")\(symbol)", term: (s > 0 ? "+" : "−") + symbol, expanded: [(s > 0 ? "+" : "−") + symbol]))
                    equation.add(s, to: symbol)
                }
            }
            return (pieces, equation)
        }

        func joined(_ parts: [String]) -> String {
            var out = ""
            for part in parts {
                if out.isEmpty { out = part.hasPrefix("+") ? String(part.dropFirst()) : part; continue }
                if part.hasPrefix("−") { out += " − " + part.dropFirst() } else { out += " + " + (part.hasPrefix("+") ? String(part.dropFirst()) : part) }
            }
            return out.isEmpty ? "0" : out
        }

        var systemEquations: [DisplayEquation] = []
        var equationFocus: [StepFocus] = []
        var handledLoops: Set<Int> = Set(knownMesh.keys)
        var explainedSupermesh = false
        var explainedMesh = false
        for pair in supermeshPairs {
            handledLoops.insert(pair.a)
            handledLoops.insert(pair.b)
            let (piecesA, eqA) = kvlPieces(loop: pair.a, skipping: pair.source)
            let (piecesB, eqB) = kvlPieces(loop: pair.b, skipping: pair.source)
            var combined = eqA
            combined.add(eqB)
            var lines: [String] = []
            lines.append("Around \(word) \(pair.a + 1), skipping \(components[pair.source].id):")
            lines.append(contentsOf: piecesA.map(\.line))
            lines.append("Around \(word) \(pair.b + 1), skipping \(components[pair.source].id):")
            lines.append(contentsOf: piecesB.map(\.line))
            let sum = joined((piecesA + piecesB).map(\.term)) + " = 0"
            lines.append("Sum of drops around the supermesh = 0:  " + sum)
            let expanded = joined((piecesA + piecesB).flatMap(\.expanded)) + " = 0"
            if expanded != sum { lines.append("Expand:  " + expanded) }
            let collected = combined.rendered(with: f, order: meshSymbols)
            lines.append("→ " + collected)
            systemEquations.append(combined)
            let supermeshElements = (loops[pair.a].edges + loops[pair.b].edges).map { components[$0.index].id }.filter { $0 != components[pair.source].id }
            let focus = StepFocus(elements: supermeshElements, loops: [pair.a, pair.b], zoom: true, meshCurrents: knownMesh, showMeshArrows: true)
            equationFocus.append(focus)
            let explanation = explainedSupermesh
                ? "Same as the previous supermesh: walk around the outside of both meshes without crossing the current source, add the drops, expand the brackets and collect the terms."
                : "Kirchhoff's voltage law: the voltage drops around any closed path add up to zero. The path goes around the outside of the two merged meshes, so the unknown voltage across the current source never appears. A resistor drops R times the net current through it in the walking direction; a voltage source counts as a drop when crossed from + to − and as a rise (negative) from − to +. Then expand the brackets and collect the terms."
            explainedSupermesh = true
            steps.append(AnalysisStep(
                title: "Apply KVL around the supermesh (\(words) \(pair.a + 1) and \(pair.b + 1))",
                summary: "Walk the outside of both meshes; the current source is never crossed",
                equations: lines,
                explanation: explanation,
                result: collected,
                focus: focus
            ))
        }
        for k in 0..<L where !handledLoops.contains(k) {
            let (pieces, equation) = kvlPieces(loop: k, skipping: nil)
            var lines = pieces.map(\.line)
            let sum = joined(pieces.map(\.term)) + " = 0"
            lines.append("Sum of drops = 0:  " + sum)
            let expanded = joined(pieces.flatMap(\.expanded)) + " = 0"
            if expanded != sum { lines.append("Expand:  " + expanded) }
            let collected = equation.rendered(with: f, order: meshSymbols)
            lines.append("→ " + collected)
            systemEquations.append(equation)
            let focus = StepFocus(elements: loops[k].edges.map { components[$0.index].id }, loops: [k], zoom: true, meshCurrents: knownMesh, showMeshArrows: true)
            equationFocus.append(focus)
            let explanation = explainedMesh
                ? "Same procedure around \(word) \(k + 1): walk clockwise with \(meshSymbols[k]), add the drops (R times the net current through each resistor, each voltage source with its sign), expand the brackets and collect the terms."
                : "Kirchhoff's voltage law: going once around a closed loop brings you back to the same voltage, so the drops add up to zero. Walk the \(word) in the direction of \(meshSymbols[k]). A resistor drops R times the net current through it (its own \(word) current \(windows ? "minus any neighbouring mesh current running the other way" : "combined with any other loop current through it, with the sign of that loop's direction")); a voltage source is a drop when crossed from + to − and a rise when crossed from − to +. Then expand the brackets and collect the terms."
            explainedMesh = true
            steps.append(AnalysisStep(
                title: "Apply KVL around \(word) \(k + 1)",
                summary: "Walk clockwise with \(meshSymbols[k]); the drops add up to zero",
                equations: lines,
                explanation: explanation,
                result: collected,
                focus: focus
            ))
        }

        // 4. Solve, narrated
        let unknownMeshes = (0..<L).filter { knownMesh[$0] == nil }
        let unknownSymbols = unknownMeshes.map { meshSymbols[$0] } + extendedSources.map { context.elementVoltageSymbol(components[$0].id) }
        if !unknownSymbols.isEmpty {
            var equations = systemEquations
            var focuses = equationFocus
            for (constraint, focus) in constraintEquations {
                equations.append(constraint)
                focuses.append(focus)
            }
            let meshOf = Dictionary(uniqueKeysWithValues: unknownMeshes.map { (meshSymbols[$0], $0) })
            var expected: [String: Double] = [:]
            for k in unknownMeshes { expected[meshSymbols[k]] = meshCurrents[k] }
            for index in extendedSources { expected[context.elementVoltageSymbol(components[index].id)] = sourceVoltages[index] ?? 0 }
            let allMeshCurrents = Dictionary(uniqueKeysWithValues: (0..<L).map { ($0, meshCurrents[$0]) })
            let options = SystemNarrator.Options(
                unknowns: unknownSymbols,
                unit: extendedSources.isEmpty ? "A" : "A",
                formatter: f,
                systemFocus: StepFocus(loops: Array(0..<L), meshCurrents: knownMesh, showMeshArrows: true),
                equationFocus: focuses,
                solvedFocus: { symbol, value in
                    var partial = knownMesh
                    if let k = meshOf[symbol] { partial[k] = value }
                    return StepFocus(loops: meshOf[symbol].map { [$0] } ?? [], zoom: true, meshCurrents: partial, showMeshArrows: true)
                },
                describe: { symbol in meshOf[symbol].map { "the current circulating clockwise in \(word) \($0 + 1)" } ?? "the voltage across a current source" }
            )
            if extendedSources.isEmpty,
               let narrated = SystemNarrator.narrate(equations, options: options),
               unknownSymbols.allSatisfy({ symbol in
                   guard let want = expected[symbol], let got = narrated.solution[symbol] else { return false }
                   return abs(want - got) <= 1e-6 * max(1, abs(want))
               }) {
                steps.append(contentsOf: narrated.steps)
                if unknownMeshes.count > 1 {
                    let negatives = unknownMeshes.filter { meshCurrents[$0] < 0 }
                    if !negatives.isEmpty {
                        steps.append(AnalysisStep(
                            title: "Read the signs",
                            summary: "\(negatives.map { meshSymbols[$0] }.joined(separator: ", ")) came out negative",
                            equations: negatives.map { "\(meshSymbols[$0]) = \(context.amps(meshCurrents[$0])) → \(context.amps(abs(meshCurrents[$0]))) counter-clockwise" },
                            explanation: "A negative mesh current is not a mistake: it means the current actually circulates the other way round from the clockwise direction we assumed. Keep the sign in the algebra; use the direction when describing the answer.",
                            result: "Negative means counter-clockwise",
                            focus: StepFocus(loops: negatives, zoom: true, meshCurrents: allMeshCurrents, showMeshArrows: true, animateCurrents: true)
                        ))
                    }
                }
            } else {
                let lines = equations.map { $0.rendered(with: f, order: unknownSymbols) }
                let solution = unknownSymbols.map { "\($0) = \(f.format(expected[$0] ?? 0, $0.hasPrefix("V") ? "V" : "A"))" }
                steps.append(AnalysisStep(
                    title: "Solve the system of equations",
                    summary: "\(equations.count) equations, \(unknownSymbols.count) unknowns",
                    equations: lines + ["→ " + solution.joined(separator: ", ")],
                    explanation: "Solved as a linear system; all mesh currents come out together.",
                    result: solution.joined(separator: ", "),
                    focus: StepFocus(loops: Array(0..<L), meshCurrents: allMeshCurrents, showMeshArrows: true)
                ))
            }
        }

        // 5. Element currents
        var currentLines: [String] = []
        for (index, e) in elements.enumerated() {
            if e.kind == .currentSource {
                currentLines.append("\(context.currentSymbol(e.id)) = \(context.amps(e.value)) (given)")
                continue
            }
            // "I₁ − I₂ = 1.923 A − (−384.6 mA) = 2.308 A": the mesh currents substituted with their own signs.
            var symbolic = TermList()
            var numeric = TermList()
            var count = 0
            for (j, loop) in loops.enumerated() {
                let sj = loop.sign(of: index)
                guard sj != 0 else { continue }
                symbolic.add(meshSymbols[j], negative: sj < 0)
                numeric.add(f.preciseTerm(meshCurrents[j], "A"), negative: sj < 0)
                count += 1
            }
            let substituted = count > 1 ? numeric.renderedLeftSide() + " = " : ""
            let suffix = e.kind == .voltageSource
                ? "  (\(e.id) \(-e.current >= 0 ? "delivers" : "absorbs") \(context.amps(abs(e.current))))"
                : "  (\(Answers.flowWords(e)))"
            currentLines.append("\(context.currentSymbol(e.id)) = \(symbolic.renderedLeftSide()) = \(substituted)\(context.amps(e.current))\(suffix)")
        }
        let currents = Dictionary(uniqueKeysWithValues: elements.map { ($0.id, $0.current) })
        steps.append(AnalysisStep(
            title: "Find the current through each element",
            summary: "Combine the \(word) currents",
            equations: currentLines,
            explanation: (windows
                ? "An element on the edge of the drawing lies in one mesh and simply carries that mesh current. An element between two meshes carries both, running in opposite directions, so its current is the difference. "
                : "An element in one loop simply carries that loop current. An element shared by two loops carries both, each with the sign of that loop's direction through it. ")
                + "Each current is given from the element's first terminal to its second; the words say which way it really flows.",
            result: currentLines.count == 1 ? currentLines[0] : "\(currentLines.count) currents found",
            focus: StepFocus(elementCurrents: currents, animateCurrents: true)
        ))

        // 6. Voltages, 7. Check, 8. Answer
        steps.append(SharedSteps.elementVoltages(context: context, elements: elements, voltages: voltages))
        steps.append(SharedSteps.checkStep(context: context, elements: elements, voltages: voltages))
        steps.append(SharedSteps.answerStep(context: context, answers: answers, elements: elements, voltages: voltages))
        return steps
    }
}
