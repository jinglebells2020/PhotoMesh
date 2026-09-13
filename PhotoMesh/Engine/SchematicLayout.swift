import Foundation

// MARK: - Geometry primitives (kept free of CoreGraphics so the engine builds anywhere)

struct SPoint: Hashable, Codable {
    var x: Double
    var y: Double

    static let zero = SPoint(x: 0, y: 0)

    func distance(to other: SPoint) -> Double {
        ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot()
    }

    static func + (l: SPoint, r: SPoint) -> SPoint { SPoint(x: l.x + r.x, y: l.y + r.y) }
    static func - (l: SPoint, r: SPoint) -> SPoint { SPoint(x: l.x - r.x, y: l.y - r.y) }
    static func * (l: SPoint, r: Double) -> SPoint { SPoint(x: l.x * r, y: l.y * r) }
    static func mid(_ a: SPoint, _ b: SPoint) -> SPoint { SPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
}

struct SRect: Hashable, Codable {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    static let empty = SRect(minX: .infinity, minY: .infinity, maxX: -.infinity, maxY: -.infinity)

    var isEmpty: Bool { minX > maxX || minY > maxY }
    var width: Double { max(0, maxX - minX) }
    var height: Double { max(0, maxY - minY) }
    var center: SPoint { SPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2) }

    mutating func include(_ p: SPoint) {
        minX = min(minX, p.x); minY = min(minY, p.y)
        maxX = max(maxX, p.x); maxY = max(maxY, p.y)
    }

    mutating func include(_ r: SRect) {
        guard !r.isEmpty else { return }
        include(SPoint(x: r.minX, y: r.minY))
        include(SPoint(x: r.maxX, y: r.maxY))
    }

    func insetBy(_ d: Double) -> SRect {
        SRect(minX: minX - d, minY: minY - d, maxX: maxX + d, maxY: maxY + d)
    }

    static func around(_ points: [SPoint]) -> SRect {
        var r = SRect.empty
        for p in points { r.include(p) }
        return r
    }
}

/// Distance from `p` to segment `a`–`b`.
func distanceToSegment(_ p: SPoint, _ a: SPoint, _ b: SPoint) -> Double {
    let ab = b - a
    let lengthSquared = ab.x * ab.x + ab.y * ab.y
    if lengthSquared < 1e-9 { return p.distance(to: a) }
    let t = max(0, min(1, ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / lengthSquared))
    return p.distance(to: a + ab * t)
}

// MARK: - Input: where things sit

/// Placement of the symbols in normalized picture coordinates (0…1, y down).
/// Comes from the recognizer (bounding boxes) or from the sketch canvas (exact).
struct CircuitGeometry: Hashable, Codable {
    struct Placement: Hashable, Codable {
        var box: SRect
        var isHorizontal: Bool
    }

    struct Wire: Hashable, Codable {
        var node: String
        var from: SPoint
        var to: SPoint
    }

    var placements: [String: Placement]
    var nodePoints: [String: SPoint] = [:]
    /// Width / height of the source picture, used to keep proportions.
    var aspectRatio: Double = 1.4
    /// Explicit wires (sketch canvas). When nil, wires are routed automatically.
    var wires: [Wire]? = nil
    /// Fraction of the canvas within which nearly-equal coordinates are merged (0 = exact input).
    var alignmentTolerance: Double = 0.025
    /// Where the ground symbol was drawn (sketch canvas); derived from the ground rail when nil.
    var groundPoint: SPoint? = nil
}

// MARK: - Output: drawing primitives in layout units (y down)

struct SchematicLayout: Hashable {
    struct Symbol: Identifiable, Hashable {
        let id: String
        var kind: ComponentKind
        var value: Double
        var nodeA: String
        var nodeB: String
        /// Terminal positions. Current inside the element flows a → b.
        var a: SPoint
        var b: SPoint
        /// Unit vector pointing to the side where the label goes.
        var labelSide: SPoint

        var center: SPoint { SPoint.mid(a, b) }
        var length: Double { a.distance(to: b) }
        var isHorizontal: Bool { abs(b.x - a.x) >= abs(b.y - a.y) }
        var bounds: SRect { SRect.around([a, b]).insetBy(isHorizontal ? 14 : 18) }
    }

    struct Wire: Hashable {
        var node: String
        var from: SPoint
        var to: SPoint
    }

    struct Junction: Hashable {
        var node: String
        var point: SPoint
    }

    struct NodeLabel: Hashable {
        var node: String
        var point: SPoint
    }

    var symbols: [Symbol]
    var wires: [Wire]
    var junctions: [Junction]
    var nodeLabels: [NodeLabel]
    var groundNode: String
    var groundPoint: SPoint?
    /// Everything, including room for labels.
    var bounds: SRect

    func symbol(_ id: String) -> Symbol? { symbols.first { $0.id == id } }

    /// Region covered by a node's wires and terminals.
    func bounds(ofNode node: String) -> SRect {
        var r = SRect.empty
        for w in wires where w.node == node { r.include(w.from); r.include(w.to) }
        for s in symbols {
            if s.nodeA == node { r.include(s.a) }
            if s.nodeB == node { r.include(s.b) }
        }
        return r
    }

    func bounds(ofElements ids: [String]) -> SRect {
        var r = SRect.empty
        for id in ids { if let s = symbol(id) { r.include(s.bounds) } }
        return r
    }

    /// Junction point between two consecutive elements of a loop (shared node), used to trace mesh polygons.
    func polygon(forLoopElements ids: [String]) -> [SPoint] {
        guard ids.count >= 2 else { return [] }
        var points: [SPoint] = []
        for (index, id) in ids.enumerated() {
            let next = ids[(index + 1) % ids.count]
            guard let s = symbol(id), let n = symbol(next) else { continue }
            let shared = [s.nodeA, s.nodeB].first { $0 == n.nodeA || $0 == n.nodeB }
            guard let node = shared else { continue }
            points.append(s.nodeA == node ? s.a : s.b)
        }
        return points
    }

    enum Hit: Hashable {
        case element(String)
        case node(String)
    }

    /// Nearest element or node within `tolerance` layout units.
    func hitTest(_ p: SPoint, tolerance: Double) -> Hit? {
        var best: (Hit, Double)?
        for s in symbols {
            let d = distanceToSegment(p, s.a, s.b)
            if d <= tolerance, best == nil || d < best!.1 { best = (.element(s.id), d) }
        }
        for w in wires {
            let d = distanceToSegment(p, w.from, w.to)
            if d <= tolerance, best == nil || d < best!.1 { best = (.node(w.node), d) }
        }
        for j in junctions {
            let d = p.distance(to: j.point)
            if d <= tolerance, best == nil || d < best!.1 - 4 { best = (.node(j.node), d) }
        }
        return best?.0
    }
}

// MARK: - Layout engine

enum SchematicLayoutEngine {
    static let canvasHeight: Double = 1000

    /// Builds the drawing from the recognizer's / sketch's geometry, or from a fallback when there is none.
    static func layout(for circuit: Circuit) -> SchematicLayout {
        if let geometry = circuit.geometry, geometry.placements.count == circuit.components.count {
            return layout(circuit: circuit, geometry: geometry)
        }
        return ringLayout(circuit: circuit)
    }

    static func layout(circuit: Circuit, geometry: CircuitGeometry) -> SchematicLayout {
        let width = canvasHeight * max(0.5, min(3, geometry.aspectRatio))
        let height = canvasHeight
        func toCanvas(_ p: SPoint) -> SPoint { SPoint(x: p.x * width, y: p.y * height) }

        // 1. Raw terminals per component
        struct Raw { var component: Component; var e1: SPoint; var e2: SPoint; var horizontal: Bool }
        var raws: [Raw] = []
        for component in circuit.components {
            guard let placement = geometry.placements[component.id] else { continue }
            let b = placement.box
            let e1: SPoint, e2: SPoint
            if placement.isHorizontal {
                e1 = toCanvas(SPoint(x: b.minX, y: (b.minY + b.maxY) / 2))
                e2 = toCanvas(SPoint(x: b.maxX, y: (b.minY + b.maxY) / 2))
            } else {
                e1 = toCanvas(SPoint(x: (b.minX + b.maxX) / 2, y: b.minY))
                e2 = toCanvas(SPoint(x: (b.minX + b.maxX) / 2, y: b.maxY))
            }
            raws.append(Raw(component: component, e1: e1, e2: e2, horizontal: placement.isHorizontal))
        }

        // 2. Which end belongs to which node: start from node points (or centroids), refine twice.
        var reference: [String: SPoint] = geometry.nodePoints.mapValues(toCanvas)
        for node in circuit.nodes where reference[node] == nil {
            let centers = raws.filter { $0.component.touches(node) }.map { SPoint.mid($0.e1, $0.e2) }
            if !centers.isEmpty {
                reference[node] = SPoint(x: centers.map(\.x).reduce(0, +) / Double(centers.count), y: centers.map(\.y).reduce(0, +) / Double(centers.count))
            }
        }
        var assigned: [(component: Component, a: SPoint, b: SPoint, horizontal: Bool)] = []
        for _ in 0..<3 {
            assigned = raws.map { raw in
                let pa = reference[raw.component.nodeA] ?? SPoint.mid(raw.e1, raw.e2)
                let pb = reference[raw.component.nodeB] ?? SPoint.mid(raw.e1, raw.e2)
                let straight = raw.e1.distance(to: pa) + raw.e2.distance(to: pb)
                let swapped = raw.e2.distance(to: pa) + raw.e1.distance(to: pb)
                return straight <= swapped
                    ? (raw.component, raw.e1, raw.e2, raw.horizontal)
                    : (raw.component, raw.e2, raw.e1, raw.horizontal)
            }
            var sums: [String: (SPoint, Int)] = [:]
            for item in assigned {
                let sa = sums[item.component.nodeA] ?? (.zero, 0)
                sums[item.component.nodeA] = (sa.0 + item.a, sa.1 + 1)
                let sb = sums[item.component.nodeB] ?? (.zero, 0)
                sums[item.component.nodeB] = (sb.0 + item.b, sb.1 + 1)
            }
            for (node, sum) in sums where geometry.nodePoints[node] == nil {
                reference[node] = sum.0 * (1 / Double(sum.1))
            }
        }

        // 3. Align nearly-equal coordinates so wires come out straight.
        var xs = assigned.flatMap { [$0.a.x, $0.b.x] }
        var ys = assigned.flatMap { [$0.a.y, $0.b.y] }
        xs = cluster(xs, tolerance: width * geometry.alignmentTolerance)
        ys = cluster(ys, tolerance: height * geometry.alignmentTolerance)
        var symbols: [SchematicLayout.Symbol] = []
        for (index, item) in assigned.enumerated() {
            var a = SPoint(x: xs[index * 2], y: ys[index * 2])
            var b = SPoint(x: xs[index * 2 + 1], y: ys[index * 2 + 1])
            // Keep the symbol perfectly axis-aligned.
            if item.horizontal { let y = (a.y + b.y) / 2; a.y = y; b.y = y } else { let x = (a.x + b.x) / 2; a.x = x; b.x = x }
            if a.distance(to: b) < 30 {   // degenerate box: give it a visible length
                if item.horizontal { a.x = b.x - 60 } else { a.y = b.y - 60 }
            }
            let side: SPoint
            if item.horizontal {
                side = a.y < height * 0.12 ? SPoint(x: 0, y: 1) : SPoint(x: 0, y: -1)
            } else {
                side = a.x > width * 0.88 ? SPoint(x: -1, y: 0) : SPoint(x: 1, y: 0)
            }
            symbols.append(SchematicLayout.Symbol(id: item.component.id, kind: item.component.kind, value: item.component.value, nodeA: item.component.nodeA, nodeB: item.component.nodeB, a: a, b: b, labelSide: side))
        }

        // 4. Wires
        var wires: [SchematicLayout.Wire] = []
        var junctions: [SchematicLayout.Junction] = []
        var nodeLabels: [SchematicLayout.NodeLabel] = []
        let drawnGround = geometry.groundPoint.map(toCanvas)
        if let explicit = geometry.wires {
            wires = explicit.map { SchematicLayout.Wire(node: $0.node, from: toCanvas($0.from), to: toCanvas($0.to)) }
            junctions = junctionsFromExplicitWires(wires, symbols: symbols, extraPoints: drawnGround.map { [(node: circuit.groundNode, point: $0)] } ?? [])
        } else {
            for node in circuit.nodes {
                let routed = routeNode(node, symbols: symbols, hint: reference[node], canvas: SPoint(x: width, y: height))
                wires += routed.wires
                junctions += routed.junctions
            }
        }
        for node in circuit.nodes {
            let hint = reference[node]
            nodeLabels.append(SchematicLayout.NodeLabel(node: node, point: labelPoint(for: node, hint: hint, wires: wires, symbols: symbols)))
        }

        // 5. Ground symbol on the reference node
        let groundPoint = drawnGround ?? groundAttachment(node: circuit.groundNode, wires: wires, symbols: symbols, hint: reference[circuit.groundNode])

        var bounds = SRect.empty
        for s in symbols { bounds.include(s.bounds) }
        for w in wires { bounds.include(w.from); bounds.include(w.to) }
        if let groundPoint { bounds.include(SPoint(x: groundPoint.x, y: groundPoint.y + 40)) }
        bounds = bounds.insetBy(70)

        return SchematicLayout(symbols: symbols, wires: wires, junctions: junctions, nodeLabels: nodeLabels, groundNode: circuit.groundNode, groundPoint: groundPoint, bounds: bounds)
    }

    // MARK: Node routing (rail with perpendicular drops)

    private struct Terminal {
        var point: SPoint
        var horizontalExit: Bool
        /// Unit vector pointing away from the component body.
        var exit: SPoint
    }

    /// Connects all terminals of a node with a straight rail plus perpendicular drops, the way
    /// textbook schematics do. The recognizer's node point tells where the rail is when the
    /// terminals do not line up on their own.
    private static func routeNode(_ node: String, symbols: [SchematicLayout.Symbol], hint: SPoint?, canvas: SPoint) -> (wires: [SchematicLayout.Wire], junctions: [SchematicLayout.Junction]) {
        var terminals: [Terminal] = []
        for s in symbols {
            let center = s.center
            if s.nodeA == node { terminals.append(Terminal(point: s.a, horizontalExit: s.isHorizontal, exit: unit(s.a - center))) }
            if s.nodeB == node { terminals.append(Terminal(point: s.b, horizontalExit: s.isHorizontal, exit: unit(s.b - center))) }
        }
        guard terminals.count >= 2 else { return ([], []) }
        let eps = 0.5
        let tolerance = min(canvas.x, canvas.y) * 0.03

        let allSameX = terminals.allSatisfy { abs($0.point.x - terminals[0].point.x) < eps }
        let allSameY = terminals.allSatisfy { abs($0.point.y - terminals[0].point.y) < eps }
        if allSameX && allSameY { return ([], []) }

        let horizontalExits = terminals.filter(\.horizontalExit)
        let verticalExits = terminals.filter { !$0.horizontalExit }
        let hYsAgree = horizontalExits.allSatisfy { abs($0.point.y - horizontalExits[0].point.y) < eps }

        enum Rail { case horizontal(Double), vertical(Double) }
        let rail: Rail
        if allSameY {
            rail = .horizontal(terminals[0].point.y)
        } else if allSameX {
            rail = .vertical(terminals[0].point.x)
        } else if !horizontalExits.isEmpty, !verticalExits.isEmpty || hYsAgree {
            // Wires continue horizontally out of these terminals: the rail passes through them.
            var y = mostCommon(horizontalExits.map(\.point.y), tolerance: eps)
            if let hint, let match = horizontalExits.map(\.point.y).first(where: { abs($0 - hint.y) < tolerance }) { y = match }
            rail = .horizontal(y)
        } else if !horizontalExits.isEmpty {
            // Only horizontal exits at different heights: a vertical rail off to one side.
            rail = .vertical(railCoordinate(terminals.map { ($0.point.x, $0.exit.x) }, hint: hint?.x, tolerance: tolerance, span: canvas.x))
        } else {
            // Only vertical exits: a horizontal rail above or below (typically the ground rail).
            rail = .horizontal(railCoordinate(terminals.map { ($0.point.y, $0.exit.y) }, hint: hint?.y, tolerance: tolerance, span: canvas.y))
        }

        var wires: [SchematicLayout.Wire] = []
        var meeting: [SPoint: Int] = [:]
        switch rail {
        case .horizontal(let railY):
            let xs = terminals.map(\.point.x)
            let start = SPoint(x: xs.min()!, y: railY), end = SPoint(x: xs.max()!, y: railY)
            if start.distance(to: end) > eps { wires.append(.init(node: node, from: start, to: end)) }
            for t in terminals {
                let foot = SPoint(x: t.point.x, y: railY)
                if abs(t.point.y - railY) > eps { wires.append(.init(node: node, from: t.point, to: foot)) }
                let interior = foot.x > start.x + eps && foot.x < end.x - eps
                meeting[foot, default: interior ? 2 : 1] += 1
            }
        case .vertical(let railX):
            let ys = terminals.map(\.point.y)
            let start = SPoint(x: railX, y: ys.min()!), end = SPoint(x: railX, y: ys.max()!)
            if start.distance(to: end) > eps { wires.append(.init(node: node, from: start, to: end)) }
            for t in terminals {
                let foot = SPoint(x: railX, y: t.point.y)
                if abs(t.point.x - railX) > eps { wires.append(.init(node: node, from: t.point, to: foot)) }
                let interior = foot.y > start.y + eps && foot.y < end.y - eps
                meeting[foot, default: interior ? 2 : 1] += 1
            }
        }
        let junctions = meeting.filter { $0.value >= 3 }.map { SchematicLayout.Junction(node: node, point: $0.key) }
        return (wires, junctions)
    }

    /// Picks where a rail goes for terminals that all exit along the same axis:
    /// the recognizer's hint when it lies on the exit side of every terminal, else the far edge.
    private static func railCoordinate(_ terminals: [(coordinate: Double, exit: Double)], hint: Double?, tolerance: Double, span: Double) -> Double {
        let coordinates = terminals.map(\.coordinate)
        if let hint {
            let consistent = terminals.allSatisfy { t in
                if t.exit > 0.5 { return hint >= t.coordinate - tolerance }
                if t.exit < -0.5 { return hint <= t.coordinate + tolerance }
                return true
            }
            let nearest = coordinates.map { abs($0 - hint) }.min() ?? .infinity
            if consistent, nearest < span * 0.35 { return hint }
        }
        let outward = terminals.map(\.exit).reduce(0, +)
        return outward >= 0 ? coordinates.max()! : coordinates.min()!
    }

    private static func unit(_ v: SPoint) -> SPoint {
        let length = (v.x * v.x + v.y * v.y).squareRoot()
        return length > 1e-9 ? v * (1 / length) : SPoint(x: 0, y: 1)
    }

    /// Junction dots for explicit (sketch) wires: three or more things meeting at one point.
    static func junctionsFromExplicitWires(_ wires: [SchematicLayout.Wire], symbols: [SchematicLayout.Symbol], extraPoints: [(node: String, point: SPoint)] = []) -> [SchematicLayout.Junction] {
        // Quantise so that points equal up to floating-point noise share a key.
        func key(_ p: SPoint) -> SPoint { SPoint(x: (p.x * 4).rounded() / 4, y: (p.y * 4).rounded() / 4) }
        var degree: [String: [SPoint: Int]] = [:]
        func bump(_ node: String, _ p: SPoint, by amount: Int = 1) {
            degree[node, default: [:]][key(p), default: 0] += amount
        }
        for w in wires {
            bump(w.node, w.from)
            bump(w.node, w.to)
        }
        for s in symbols {
            bump(s.nodeA, s.a)
            bump(s.nodeB, s.b)
        }
        for extra in extraPoints { bump(extra.node, extra.point) }
        // A point in the middle of a wire (T-junction) counts as two extra.
        for w in wires {
            for (point, _) in degree[w.node] ?? [:] {
                guard point.distance(to: w.from) > 1, point.distance(to: w.to) > 1 else { continue }
                if distanceToSegment(point, w.from, w.to) < 0.5 { degree[w.node]![point]! += 2 }
            }
        }
        var junctions: [SchematicLayout.Junction] = []
        for (node, points) in degree {
            for (point, count) in points where count >= 3 { junctions.append(.init(node: node, point: point)) }
        }
        return junctions
    }

    private static func labelPoint(for node: String, hint: SPoint?, wires: [SchematicLayout.Wire], symbols: [SchematicLayout.Symbol]) -> SPoint {
        let nodeWires = wires.filter { $0.node == node }
        if let hint, !nodeWires.isEmpty {
            // Project the hint onto the nearest wire of the node.
            var best: (SPoint, Double)?
            for w in nodeWires {
                let ab = w.to - w.from
                let len2 = ab.x * ab.x + ab.y * ab.y
                let t = len2 < 1e-9 ? 0 : max(0, min(1, ((hint.x - w.from.x) * ab.x + (hint.y - w.from.y) * ab.y) / len2))
                let p = w.from + ab * t
                let d = p.distance(to: hint)
                if best == nil || d < best!.1 { best = (p, d) }
            }
            if let best { return best.0 }
        }
        if let longest = nodeWires.max(by: { $0.from.distance(to: $0.to) < $1.from.distance(to: $1.to) }) {
            return SPoint.mid(longest.from, longest.to)
        }
        for s in symbols {
            if s.nodeA == node { return s.a }
            if s.nodeB == node { return s.b }
        }
        return hint ?? .zero
    }

    private static func groundAttachment(node: String, wires: [SchematicLayout.Wire], symbols: [SchematicLayout.Symbol], hint: SPoint?) -> SPoint? {
        let horizontal = wires.filter { $0.node == node && abs($0.from.y - $0.to.y) < 0.5 }
        if let bottom = horizontal.max(by: { ($0.from.y, $0.from.distance(to: $0.to)) < ($1.from.y, $1.from.distance(to: $1.to)) }) {
            let mid = SPoint.mid(bottom.from, bottom.to)
            // Avoid sitting exactly under a junction dot or a terminal.
            return mid
        }
        return labelPointFallback(node: node, wires: wires, symbols: symbols, hint: hint)
    }

    private static func labelPointFallback(node: String, wires: [SchematicLayout.Wire], symbols: [SchematicLayout.Symbol], hint: SPoint?) -> SPoint? {
        let nodeWires = wires.filter { $0.node == node }
        if let w = nodeWires.first { return SPoint.mid(w.from, w.to) }
        for s in symbols {
            if s.nodeA == node { return s.a }
            if s.nodeB == node { return s.b }
        }
        return hint
    }

    // MARK: Helpers

    /// Replaces values that lie within `tolerance` of each other by their mean.
    static func cluster(_ values: [Double], tolerance: Double) -> [Double] {
        let order = values.indices.sorted { values[$0] < values[$1] }
        var result = values
        var groupStart = 0
        while groupStart < order.count {
            var groupEnd = groupStart
            while groupEnd + 1 < order.count, values[order[groupEnd + 1]] - values[order[groupEnd]] <= tolerance { groupEnd += 1 }
            let members = order[groupStart...groupEnd]
            let mean = members.map { values[$0] }.reduce(0, +) / Double(members.count)
            for i in members { result[i] = mean }
            groupStart = groupEnd + 1
        }
        return result
    }

    private static func mostCommon(_ values: [Double], tolerance: Double) -> Double {
        var best = values[0]
        var bestCount = 0
        for v in values {
            let count = values.filter { abs($0 - v) <= tolerance }.count
            if count > bestCount { best = v; bestCount = count }
        }
        return best
    }

    // MARK: Fallback: nodes on a ring

    /// Used when no geometry is available: nodes around a circle, elements as straight symbols between them.
    static func ringLayout(circuit: Circuit) -> SchematicLayout {
        let nodes = circuit.nodes
        let radius = 360.0
        let center = SPoint(x: 500, y: 500)
        var positions: [String: SPoint] = [:]
        for (index, node) in nodes.enumerated() {
            let angle = Double.pi / 2 + 2 * Double.pi * Double(index) / Double(max(nodes.count, 1))   // ground at the bottom
            positions[node] = SPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
        var symbols: [SchematicLayout.Symbol] = []
        var parallelCount: [String: Int] = [:]
        for component in circuit.components {
            guard let pa = positions[component.nodeA], let pb = positions[component.nodeB] else { continue }
            let key = [component.nodeA, component.nodeB].sorted().joined(separator: "|")
            let n = parallelCount[key, default: 0]
            parallelCount[key] = n + 1
            let dir = pb - pa
            let length = pa.distance(to: pb)
            let unit = length > 0 ? dir * (1 / length) : SPoint(x: 1, y: 0)
            let perp = SPoint(x: -unit.y, y: unit.x)
            let offset = perp * (Double(n) * 44 - Double(n) * 22)
            let a = pa + unit * (length * 0.32) + offset
            let b = pa + unit * (length * 0.68) + offset
            symbols.append(SchematicLayout.Symbol(id: component.id, kind: component.kind, value: component.value, nodeA: component.nodeA, nodeB: component.nodeB, a: a, b: b, labelSide: perp))
        }
        var wires: [SchematicLayout.Wire] = []
        for s in symbols {
            if let pa = positions[s.nodeA] { wires.append(.init(node: s.nodeA, from: pa, to: s.a)) }
            if let pb = positions[s.nodeB] { wires.append(.init(node: s.nodeB, from: pb, to: s.b)) }
        }
        let junctions = nodes.compactMap { node -> SchematicLayout.Junction? in
            guard let p = positions[node], circuit.components(at: node).count >= 3 else { return nil }
            return .init(node: node, point: p)
        }
        let labels = nodes.compactMap { node -> SchematicLayout.NodeLabel? in
            guard let p = positions[node] else { return nil }
            return .init(node: node, point: p)
        }
        var bounds = SRect.empty
        for s in symbols { bounds.include(s.bounds) }
        for w in wires { bounds.include(w.from); bounds.include(w.to) }
        return SchematicLayout(symbols: symbols, wires: wires, junctions: junctions, nodeLabels: labels, groundNode: circuit.groundNode, groundPoint: positions[circuit.groundNode], bounds: bounds.insetBy(80))
    }
}
