import Foundation

/// Everything the moving-current animation needs, worked out once per layout and step rather than
/// on every frame: one track per conductor the current flows along, oriented the way the current
/// really goes, with its speed and the electric potential at either end. Frames then only place
/// dots along the tracks.
///
/// What the picture teaches: dot speed is proportional to the current, so dots move at the same
/// speed before and after a resistor in series (current is not used up) and split at a junction;
/// dot colour follows the potential, fading across a resistor (energy given up) and jumping back
/// up across a source. A capacitor at DC carries no current, so its track is empty and the static
/// drawing shows the charge sitting on its plates instead.
struct FlowField: Equatable {
    struct Track: Equatable {
        /// Polyline in layout units, first point where the current enters.
        var points: [SPoint]
        /// Arc length at every point of `points`.
        var cumulative: [Double]
        var length: Double { cumulative.last ?? 0 }
        /// Layout units per second.
        var speed: Double
        /// Potential (V) at the first and last point when the step knows the node voltages.
        var potentialStart: Double?
        var potentialEnd: Double?
        /// The element the track runs through (nil for a wire).
        var elementId: String?
        /// Outside the step's focus: drawn fainter.
        var dim: Bool

        init(points: [SPoint], speed: Double, potentialStart: Double? = nil, potentialEnd: Double? = nil, elementId: String? = nil, dim: Bool = false) {
            self.points = points
            var cumulative: [Double] = [0]
            for (a, b) in zip(points, points.dropFirst()) { cumulative.append(cumulative[cumulative.count - 1] + a.distance(to: b)) }
            self.cumulative = cumulative
            self.speed = speed
            self.potentialStart = potentialStart
            self.potentialEnd = potentialEnd
            self.elementId = elementId
            self.dim = dim
        }

        /// Point and potential at arc length `s`.
        func sample(at s: Double) -> (point: SPoint, potential: Double?) {
            guard points.count >= 2, length > 0 else { return (points.first ?? SPoint(x: 0, y: 0), potentialStart) }
            let clamped = min(max(s, 0), length)
            var index = 1
            while index < cumulative.count - 1, cumulative[index] < clamped { index += 1 }
            let a = points[index - 1], b = points[index]
            let segment = cumulative[index] - cumulative[index - 1]
            let t = segment > 0 ? (clamped - cumulative[index - 1]) / segment : 0
            let point = SPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            var potential: Double?
            if let p0 = potentialStart, let p1 = potentialEnd { potential = p0 + (p1 - p0) * (clamped / length) }
            return (point, potential)
        }
    }

    var tracks: [Track] = []
    /// Lowest and highest potential in the picture, for colouring.
    var lowestPotential: Double?
    var highestPotential: Double?
    /// Layout units between consecutive dots.
    static let spacing = 30.0

    static let empty = FlowField()

    var isEmpty: Bool { tracks.isEmpty }

    /// Speed for a current: a floor so the smallest current still visibly moves, then proportional.
    static func speed(_ current: Double, largest: Double) -> Double {
        20 + 80 * min(1, abs(current) / max(largest, 1e-12))
    }

    static func build(layout: SchematicLayout, focus: StepFocus, loops: [LoopPath], focusedElements: Set<String>) -> FlowField {
        var field = FlowField()
        let voltages = focus.nodeVoltages
        if !voltages.isEmpty {
            field.lowestPotential = voltages.values.min()
            field.highestPotential = voltages.values.max()
        }
        let elementCurrents = focus.elementCurrents
        if !elementCurrents.isEmpty {
            let largest = elementCurrents.values.map(abs).max() ?? 1
            let dimmed = !focusedElements.isEmpty
            for (index, current) in layout.wireCurrents(elementCurrents: elementCurrents) {
                guard abs(current) > 1e-9 * largest, index < layout.wires.count else { continue }
                let wire = layout.wires[index]
                let (start, end) = current >= 0 ? (wire.from, wire.to) : (wire.to, wire.from)
                guard start.distance(to: end) > 4 else { continue }
                let v = voltages[wire.node]
                field.tracks.append(Track(points: [start, end], speed: speed(current, largest: largest), potentialStart: v, potentialEnd: v, elementId: nil, dim: dimmed))
            }
            let wireFlows = layout.wireCurrents(elementCurrents: elementCurrents)
            for symbol in layout.symbols {
                // A step may publish currents for some elements only (the resistors, say); the
                // others carry whatever their wires deliver, by conservation at the terminal.
                let current = elementCurrents[symbol.id] ?? inferredCurrent(of: symbol, layout: layout, wireFlows: wireFlows) ?? 0
                guard abs(current) > 1e-9 * largest else { continue }
                var points = polyline(through: symbol)
                var vStart = voltages[symbol.nodeA], vEnd = voltages[symbol.nodeB]
                if current < 0 { points.reverse(); swap(&vStart, &vEnd) }
                let bright = focusedElements.isEmpty || focusedElements.contains(symbol.id)
                field.tracks.append(Track(points: points, speed: speed(current, largest: largest), potentialStart: vStart, potentialEnd: vEnd, elementId: symbol.id, dim: !bright))
            }
            return field
        }
        // Mesh currents only: circulate around each window.
        let meshCurrents = focus.meshCurrents
        guard !meshCurrents.isEmpty else { return field }
        let largest = meshCurrents.values.map(abs).max() ?? 1
        for (index, current) in meshCurrents where index < loops.count {
            var polygon = layout.polygon(forLoopElements: loops[index].elementIds)
            guard polygon.count >= 2 else { continue }
            if current < 0 { polygon.reverse() }
            polygon.append(polygon[0])
            let bright = focus.loops.isEmpty || focus.loops.contains(index)
            field.tracks.append(Track(points: polygon, speed: speed(current, largest: largest), elementId: nil, dim: !bright))
        }
        return field
    }

    /// Current entering a symbol at terminal `a`, read from the wires that meet that terminal
    /// (positive from a to b), when no other terminal shares the point.
    static func inferredCurrent(of symbol: SchematicLayout.Symbol, layout: SchematicLayout, wireFlows: [Int: Double]) -> Double? {
        func key(_ p: SPoint) -> String { "\(Int((p.x * 4).rounded())),\(Int((p.y * 4).rounded()))" }
        let terminal = symbol.a
        let others = layout.symbols.filter { $0.id != symbol.id && (key($0.a) == key(terminal) || key($0.b) == key(terminal)) }
        guard others.isEmpty else { return nil }
        var total = 0.0
        var touched = false
        for (index, flow) in wireFlows where index < layout.wires.count {
            let wire = layout.wires[index]
            guard wire.node == symbol.nodeA else { continue }
            if key(wire.to) == key(terminal) { total += flow; touched = true }
            else if key(wire.from) == key(terminal) { total -= flow; touched = true }
        }
        return touched ? total : nil
    }

    /// The route the current takes through a symbol, following what is drawn: the zigzag of a
    /// resistor, the humps of a coil, straight through everything else.
    static func polyline(through symbol: SchematicLayout.Symbol) -> [SPoint] {
        let a = symbol.a, b = symbol.b
        let length = max(symbol.length, 1)
        let u = SPoint(x: (b.x - a.x) / length, y: (b.y - a.y) / length)
        let n = SPoint(x: -u.y, y: u.x)
        switch symbol.kind {
        case .resistor:
            let iec = UserDefaults.standard.string(forKey: SettingsKeys.resistorStyle) == ResistorStyle.iec.rawValue
            guard !iec else { return [a, b] }
            let lead = length * 0.2
            let start = a + u * lead, end = b - u * lead
            let amp = min(max(length * 0.11, 6), 14)
            let peaks = 6
            let segment = (length - 2 * lead) / Double(peaks + 1)
            var points = [a, start]
            for i in 1...peaks {
                let side: Double = i % 2 == 1 ? 1 : -1
                points.append(start + u * (segment * Double(i)) + n * (amp * side))
            }
            points.append(end)
            points.append(b)
            return points
        case .inductor:
            let lead = length * 0.2
            let start = a + u * lead, end = b - u * lead
            let humps = 4
            let width = (length - 2 * lead) / Double(humps)
            var points = [a, start]
            for i in 0..<humps {
                let from = start + u * (width * Double(i))
                let to = start + u * (width * Double(i + 1))
                let c1 = from + n * (width * 1.1), c2 = to + n * (width * 1.1)
                for k in 1...8 {
                    let t = Double(k) / 8
                    let mt = 1 - t
                    let x = mt * mt * mt * from.x + 3 * mt * mt * t * c1.x + 3 * mt * t * t * c2.x + t * t * t * to.x
                    let y = mt * mt * mt * from.y + 3 * mt * mt * t * c1.y + 3 * mt * t * t * c2.y + t * t * t * to.y
                    points.append(SPoint(x: x, y: y))
                }
            }
            points.append(end)
            points.append(b)
            return points
        default:
            return [a, b]
        }
    }
}
