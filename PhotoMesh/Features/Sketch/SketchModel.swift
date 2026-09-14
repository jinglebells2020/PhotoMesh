import SwiftUI

/// One thing drawn on the canvas. Points are canvas coordinates snapped to the dot grid.
struct SketchElement: Identifiable, Equatable {
    enum Kind: String, Hashable, CaseIterable {
        case wire, resistor, capacitor, inductor, lamp, voltageSource, currentSource, battery, switchOpen, switchClosed, ground

        var componentKind: ComponentKind? {
            switch self {
            case .resistor: return .resistor
            case .capacitor: return .capacitor
            case .inductor: return .inductor
            case .lamp: return .lamp
            case .voltageSource: return .voltageSource
            case .currentSource: return .currentSource
            case .battery: return .battery
            case .switchOpen: return .switchOpen
            case .switchClosed: return .switchClosed
            case .wire, .ground: return nil
            }
        }

        static func from(_ kind: ComponentKind) -> Kind {
            allCases.first { $0.componentKind == kind } ?? .resistor
        }

        /// Kinds a drawn part can be changed into.
        static let parts: [Kind] = [.resistor, .capacitor, .inductor, .lamp, .voltageSource, .currentSource, .battery, .switchOpen]

        var prefix: String {
            switch self {
            case .resistor: return "R"
            case .capacitor: return "C"
            case .inductor: return "L"
            case .lamp: return "LP"
            case .voltageSource: return "V"
            case .currentSource: return "I"
            case .battery: return "B"
            case .switchOpen, .switchClosed: return "S"
            case .wire: return "W"
            case .ground: return "G"
            }
        }

        var title: String {
            switch self {
            case .wire: return "Wire"
            case .ground: return "Ground"
            default: return componentKind?.displayName ?? "Part"
            }
        }

        /// A value the user must enter (switches have a state instead).
        var needsValue: Bool { componentKind?.hasValue ?? false }
        var isSwitch: Bool { self == .switchOpen || self == .switchClosed }
        var isComponent: Bool { componentKind != nil }
        /// Flip swaps polarity or direction; for a switch it toggles open/closed.
        var canFlip: Bool { isSwitch || (componentKind.map { $0.hasPolarity || $0 == .currentSource } ?? false) }
    }

    let id: UUID
    var kind: Kind
    var a: CGPoint
    var b: CGPoint
    var value: Double?
    var label: String
    /// Sources: swap polarity / arrow direction.
    var flipped = false
    /// Marked as the quantity the user wants to find.
    var asked = false

    init(kind: Kind, a: CGPoint, b: CGPoint, label: String, value: Double? = nil) {
        id = UUID()
        self.kind = kind
        self.a = a
        self.b = b
        self.label = label
        self.value = value
    }

    var isComponent: Bool { kind.componentKind != nil }
    var isHorizontal: Bool { abs(b.x - a.x) >= abs(b.y - a.y) }
    var center: CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
    var length: CGFloat { hypot(b.x - a.x, b.y - a.y) }
    /// Coordinate along the element's own axis (x for horizontal, y for vertical).
    func along(_ p: CGPoint) -> CGFloat { isHorizontal ? p.x : p.y }
    /// Coordinate across the element's axis: the line it lies on.
    var line: CGFloat { isHorizontal ? a.y : a.x }
    var lowerEnd: CGFloat { min(along(a), along(b)) }
    var upperEnd: CGFloat { max(along(a), along(b)) }

    /// Terminal that acts as `nodeA` of the component (positive terminal / current entry).
    var terminalA: CGPoint { flipped ? b : a }
    var terminalB: CGPoint { flipped ? a : b }

    /// Turns a component a quarter turn around its centre (geometry only; `SketchDocument.rotate`
    /// also re-seats it in the surrounding wires).
    mutating func rotate() {
        guard isComponent else { return }
        let c = SketchGrid.snap(center)
        let half = SketchGrid.step * SketchGrid.componentSteps / 2
        if isHorizontal {
            a = CGPoint(x: c.x, y: c.y - half)
            b = CGPoint(x: c.x, y: c.y + half)
        } else {
            a = CGPoint(x: c.x - half, y: c.y)
            b = CGPoint(x: c.x + half, y: c.y)
        }
    }
}

enum SketchGrid {
    static let step: CGFloat = 22
    /// Components span this many grid steps.
    static let componentSteps: CGFloat = 4

    static func snap(_ p: CGPoint) -> CGPoint {
        CGPoint(x: snap(p.x), y: snap(p.y))
    }

    static func snap(_ v: CGFloat) -> CGFloat {
        (v / step).rounded() * step
    }

    static func key(_ p: CGPoint) -> String {
        "\(Int((p.x / step).rounded())),\(Int((p.y / step).rounded()))"
    }
}

/// The drawing plus everything derived from it: connectivity, the `Circuit`, and its layout.
struct SketchDocument: Equatable {
    var elements: [SketchElement] = []

    private var counters: [SketchElement.Kind: Int] {
        var counts: [SketchElement.Kind: Int] = [:]
        for element in elements { counts[element.kind, default: 0] += 1 }
        return counts
    }

    func nextLabel(for kind: SketchElement.Kind) -> String {
        var index = (counters[kind] ?? 0) + 1
        let used = Set(elements.map(\.label))
        while used.contains("\(kind.prefix)\(index)") { index += 1 }
        return "\(kind.prefix)\(index)"
    }

    /// Re-numbers a component when its kind changes (a "V1" that turns out to be a resistor).
    /// Kinds that share a prefix (a switch opening or closing) keep their label.
    mutating func relabel(_ id: UUID, as kind: SketchElement.Kind) {
        guard let index = elements.firstIndex(where: { $0.id == id }), elements[index].kind != kind else { return }
        if elements[index].kind.prefix == kind.prefix {
            elements[index].kind = kind
            return
        }
        elements[index].kind = kind
        var copy = self
        copy.elements.remove(at: index)
        elements[index].label = copy.nextLabel(for: kind)
    }

    var hasSource: Bool { elements.contains { $0.kind == .voltageSource || $0.kind == .currentSource } }
    var hasResistor: Bool { elements.contains { $0.kind == .resistor } }
    var missingValues: [SketchElement] { elements.filter { $0.isComponent && $0.kind.needsValue && $0.value == nil } }
    var isSolvable: Bool { hasSource && hasResistor }

    /// Area the drawing occupies (canvas points), padded; used to normalise geometry and to fit the view.
    var contentFrame: CGRect {
        var minX = CGFloat.infinity, minY = CGFloat.infinity, maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for element in elements {
            for p in [element.a, element.b] {
                minX = min(minX, p.x); minY = min(minY, p.y)
                maxX = max(maxX, p.x); maxY = max(maxY, p.y)
            }
        }
        guard minX.isFinite else { return CGRect(x: 0, y: 0, width: SketchGrid.step * 16, height: SketchGrid.step * 12) }
        let pad = SketchGrid.step * 3
        var rect = CGRect(x: minX - pad, y: minY - pad, width: maxX - minX + 2 * pad, height: maxY - minY + 2 * pad)
        let minWidth = SketchGrid.step * 12, minHeight = SketchGrid.step * 9
        if rect.width < minWidth { rect = rect.insetBy(dx: (rect.width - minWidth) / 2, dy: 0) }
        if rect.height < minHeight { rect = rect.insetBy(dx: 0, dy: (rect.height - minHeight) / 2) }
        return rect
    }

    // MARK: Connectivity

    /// Node id for every connection point, computed with union-find over wires and overlaps.
    func nodeAssignment() -> [String: String] {
        var parent: [String: String] = [:]
        func find(_ k: String) -> String {
            var current = k
            while let p = parent[current], p != current { current = p }
            if parent[k] == nil { parent[k] = k }
            return current
        }
        func union(_ a: String, _ b: String) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }

        var points: [(key: String, point: CGPoint)] = []
        func register(_ p: CGPoint) {
            let k = SketchGrid.key(p)
            if parent[k] == nil {
                parent[k] = k
                points.append((k, p))
            }
        }
        for element in elements {
            register(element.a)
            register(element.b)
        }
        let wires = elements.filter { $0.kind == .wire }
        for wire in wires {
            union(SketchGrid.key(wire.a), SketchGrid.key(wire.b))
        }
        // A point lying on the interior of a wire joins that wire (T-junction).
        for wire in wires {
            for (key, point) in points where key != SketchGrid.key(wire.a) && key != SketchGrid.key(wire.b) {
                if SketchDocument.point(point, liesOn: wire) { union(key, SketchGrid.key(wire.a)) }
            }
        }

        // Name the groups: ground first, then left-to-right.
        var groups: [String: [CGPoint]] = [:]
        for (key, point) in points { groups[find(key), default: []].append(point) }
        let groundRoots = Set(elements.filter { $0.kind == .ground }.map { find(SketchGrid.key($0.a)) })
        let ordered = groups.keys.sorted { lhs, rhs in
            let lg = groundRoots.contains(lhs), rg = groundRoots.contains(rhs)
            if lg != rg { return lg }
            let lp = centroid(groups[lhs]!), rp = centroid(groups[rhs]!)
            return lp.x != rp.x ? lp.x < rp.x : lp.y < rp.y
        }
        var names: [String: String] = [:]
        var index = 1
        for root in ordered {
            if groundRoots.contains(root) {
                names[root] = "0"
            } else {
                names[root] = "n\(index)"
                index += 1
            }
        }
        var assignment: [String: String] = [:]
        for (key, _) in points { assignment[key] = names[find(key)] }
        return assignment
    }

    static func point(_ p: CGPoint, liesOn wire: SketchElement) -> Bool {
        let minX = min(wire.a.x, wire.b.x) - 0.5, maxX = max(wire.a.x, wire.b.x) + 0.5
        let minY = min(wire.a.y, wire.b.y) - 0.5, maxY = max(wire.a.y, wire.b.y) + 0.5
        guard p.x >= minX, p.x <= maxX, p.y >= minY, p.y <= maxY else { return false }
        if abs(wire.a.y - wire.b.y) < 0.5 { return abs(p.y - wire.a.y) < 0.5 }
        if abs(wire.a.x - wire.b.x) < 0.5 { return abs(p.x - wire.a.x) < 0.5 }
        return false
    }

    private func centroid(_ points: [CGPoint]) -> CGPoint {
        let n = CGFloat(max(points.count, 1))
        return CGPoint(x: points.map(\.x).reduce(0, +) / n, y: points.map(\.y).reduce(0, +) / n)
    }

    // MARK: Circuit + geometry

    /// Builds the netlist. Components without a value get 0 so the layout still works; `validated()` catches them.
    func circuit() -> Circuit {
        let nodes = nodeAssignment()
        let frame = contentFrame
        var components: [Component] = []
        var placements: [String: CircuitGeometry.Placement] = [:]
        var nodePointSums: [String: (CGPoint, Int)] = [:]
        let w = max(frame.width, 1), h = max(frame.height, 1)
        func norm(_ p: CGPoint) -> SPoint { SPoint(x: Double((p.x - frame.minX) / w), y: Double((p.y - frame.minY) / h)) }

        for element in elements {
            guard let kind = element.kind.componentKind else { continue }
            let nodeA = nodes[SketchGrid.key(element.terminalA)] ?? "?"
            let nodeB = nodes[SketchGrid.key(element.terminalB)] ?? "?"
            components.append(Component(id: element.label, kind: kind, value: element.value ?? 0, nodeA: nodeA, nodeB: nodeB))
            let pad: CGFloat = 10
            let lo = norm(CGPoint(x: min(element.a.x, element.b.x) - (element.isHorizontal ? 0 : pad), y: min(element.a.y, element.b.y) - (element.isHorizontal ? pad : 0)))
            let hi = norm(CGPoint(x: max(element.a.x, element.b.x) + (element.isHorizontal ? 0 : pad), y: max(element.a.y, element.b.y) + (element.isHorizontal ? pad : 0)))
            placements[element.label] = CircuitGeometry.Placement(box: SRect(minX: lo.x, minY: lo.y, maxX: hi.x, maxY: hi.y), isHorizontal: element.isHorizontal)
        }
        for element in elements {
            for p in [element.a, element.b] {
                guard let node = nodes[SketchGrid.key(p)] else { continue }
                let sum = nodePointSums[node] ?? (.zero, 0)
                nodePointSums[node] = (CGPoint(x: sum.0.x + p.x, y: sum.0.y + p.y), sum.1 + 1)
            }
        }
        var nodePoints: [String: SPoint] = [:]
        for (node, sum) in nodePointSums {
            nodePoints[node] = norm(CGPoint(x: sum.0.x / CGFloat(sum.1), y: sum.0.y / CGFloat(sum.1)))
        }
        let wires = elements.filter { $0.kind == .wire }.map { wire in
            CircuitGeometry.Wire(node: nodes[SketchGrid.key(wire.a)] ?? "?", from: norm(wire.a), to: norm(wire.b))
        }
        let groundPoint = elements.first { $0.kind == .ground }.map { norm($0.a) }
        let geometry = CircuitGeometry(placements: placements, nodePoints: nodePoints, aspectRatio: Double(w / h), wires: wires, alignmentTolerance: 0, groundPoint: groundPoint)
        let unknowns = elements.filter { $0.asked && $0.isComponent }.map { Unknown(kind: .current, element: $0.label) }
        let hasGround = elements.contains { $0.kind == .ground }
        return Circuit(
            components: components,
            groundNode: hasGround ? "0" : "",
            meshes: [],
            unknowns: unknowns,
            question: unknowns.isEmpty ? nil : "Find the current through " + unknowns.compactMap(\.element).joined(separator: ", ") + ".",
            notes: nil,
            unsupported: [],
            geometry: geometry
        )
    }

    /// Live drawing of the current sketch.
    func layout() -> SchematicLayout {
        let c = circuit()
        guard let geometry = c.geometry, !elements.isEmpty else {
            return SchematicLayout(symbols: [], wires: [], junctions: [], nodeLabels: [], groundNode: "", groundPoint: nil, bounds: .empty)
        }
        return SchematicLayoutEngine.layout(circuit: c, geometry: geometry)
    }

    /// Camera that maps layout units onto canvas points, then onto the view (zoom + pan).
    func schematicCamera(zoom: CGFloat, pan: CGSize) -> SchematicCamera {
        let frame = contentFrame
        let unitsToCanvas = frame.height / CGFloat(SchematicLayoutEngine.canvasHeight)
        return SchematicCamera(
            scale: zoom * unitsToCanvas,
            offset: CGSize(width: frame.minX * zoom + pan.width, height: frame.minY * zoom + pan.height)
        )
    }
}
