import Foundation

/// Editing operations on the drawing. Everything works in canvas points on the dot grid and keeps
/// the sketch tidy: wires that overlap merge into one, a component drawn on a wire is inserted into
/// it, a component drawn across a wire lands one terminal on it, removing an inserted component
/// heals the wire, and the eraser cuts wires only where it touched them.
extension SketchDocument {
    private var step: CGFloat { SketchGrid.step }
    private var componentLength: CGFloat { SketchGrid.step * SketchGrid.componentSteps }

    // MARK: Snapping

    /// Terminals, wire ends and ground taps: the points a new stroke can magnet onto.
    var connectionPoints: [CGPoint] {
        elements.flatMap { $0.kind == .ground ? [$0.a] : [$0.a, $0.b] }
    }

    func nearestConnectionPoint(to p: CGPoint, within radius: CGFloat) -> CGPoint? {
        var best: (CGPoint, CGFloat)?
        for point in connectionPoints {
            let d = hypot(point.x - p.x, point.y - p.y)
            if d <= radius, best == nil || d < best!.1 { best = (point, CGFloat(d)) }
        }
        return best?.0
    }

    /// Nearest point on the interior of a wire, on the grid, so strokes can start or end in a T-junction.
    func nearestWirePoint(to p: CGPoint, within radius: CGFloat) -> CGPoint? {
        var best: (CGPoint, CGFloat)?
        for wire in elements where wire.kind == .wire {
            let along = SketchGrid.snap(min(max(wire.along(p), wire.lowerEnd), wire.upperEnd))
            guard along >= wire.lowerEnd - 0.5, along <= wire.upperEnd + 0.5 else { continue }
            let point = wire.isHorizontal ? CGPoint(x: along, y: wire.line) : CGPoint(x: wire.line, y: along)
            let d = hypot(point.x - p.x, point.y - p.y)
            if d <= radius, best == nil || d < best!.1 { best = (point, CGFloat(d)) }
        }
        return best?.0
    }

    /// Where a stroke end lands: a terminal or wire end nearby, else the wire it was drawn onto, else the grid.
    func snapEndpoint(_ raw: CGPoint, radius: CGFloat) -> (point: CGPoint, magnetized: Bool) {
        if let near = nearestConnectionPoint(to: raw, within: radius) { return (near, true) }
        if let onWire = nearestWirePoint(to: raw, within: radius * 0.8) { return (onWire, true) }
        return (SketchGrid.snap(raw), false)
    }

    // MARK: Wires

    /// A straight wire. Slightly slanted strokes straighten; a magnetized end decides the line.
    @discardableResult
    mutating func addWire(from rawFrom: CGPoint, to rawTo: CGPoint) -> Bool {
        let horizontal = abs(rawTo.x - rawFrom.x) >= abs(rawTo.y - rawFrom.y)
        let radius = step * 1.1
        let start = snapEndpoint(rawFrom, radius: radius)
        let end = snapEndpoint(rawTo, radius: radius)
        var from = start.point, to = end.point
        if horizontal {
            let y = start.magnetized ? from.y : (end.magnetized ? to.y : SketchGrid.snap((rawFrom.y + rawTo.y) / 2))
            from.y = y; to.y = y
        } else {
            let x = start.magnetized ? from.x : (end.magnetized ? to.x : SketchGrid.snap((rawFrom.x + rawTo.x) / 2))
            from.x = x; to.x = x
        }
        guard hypot(to.x - from.x, to.y - from.y) >= step - 0.5 else { return false }
        insertWire(from: from, to: to)
        return true
    }

    /// A stroke with corners becomes a chain of axis-aligned wires that meet exactly.
    mutating func addWirePath(_ corners: [CGPoint]) {
        guard corners.count >= 2 else { return }
        let radius = step * 1.1
        var current = snapEndpoint(corners[0], radius: radius).point
        var segments: [(CGPoint, CGPoint)] = []
        for (index, raw) in corners.dropFirst().enumerated() {
            let isLast = index == corners.count - 2
            let target = isLast ? snapEndpoint(raw, radius: radius).point : SketchGrid.snap(raw)
            let horizontal = abs(raw.x - current.x) >= abs(raw.y - current.y)
            var next = horizontal ? CGPoint(x: target.x, y: current.y) : CGPoint(x: current.x, y: target.y)
            if isLast, next != target {
                // Finish with a short perpendicular so the path ends exactly on the target.
                if next != current { segments.append((current, next)) }
                current = next
                next = target
            }
            guard next != current else { continue }
            segments.append((current, next))
            current = next
        }
        for (a, b) in segments where hypot(b.x - a.x, b.y - a.y) >= step - 0.5 {
            insertWire(from: a, to: b)
        }
    }

    /// A closed rectangular stroke becomes four wires.
    mutating func addLoop(_ rect: CGRect) {
        let minX = SketchGrid.snap(rect.minX), maxX = SketchGrid.snap(rect.maxX)
        let minY = SketchGrid.snap(rect.minY), maxY = SketchGrid.snap(rect.maxY)
        guard maxX - minX >= step * 2 - 0.5, maxY - minY >= step * 2 - 0.5 else { return }
        insertWire(from: CGPoint(x: minX, y: minY), to: CGPoint(x: maxX, y: minY))
        insertWire(from: CGPoint(x: maxX, y: minY), to: CGPoint(x: maxX, y: maxY))
        insertWire(from: CGPoint(x: maxX, y: maxY), to: CGPoint(x: minX, y: maxY))
        insertWire(from: CGPoint(x: minX, y: maxY), to: CGPoint(x: minX, y: minY))
    }

    /// Inserts an axis-aligned wire, absorbing collinear wires it overlaps or touches.
    mutating func insertWire(from: CGPoint, to: CGPoint) {
        let probe = SketchElement(kind: .wire, a: from, b: to, label: "")
        let horizontal = probe.isHorizontal
        let line = probe.line
        var lo = probe.lowerEnd, hi = probe.upperEnd
        var absorbed = true
        while absorbed {
            absorbed = false
            elements.removeAll { wire in
                guard wire.kind == .wire, wire.isHorizontal == horizontal, abs(wire.line - line) < 0.5 else { return false }
                guard wire.upperEnd >= lo - 0.5, wire.lowerEnd <= hi + 0.5 else { return false }
                lo = min(lo, wire.lowerEnd)
                hi = max(hi, wire.upperEnd)
                absorbed = true
                return true
            }
        }
        appendLabelled([SketchDocument.wire(horizontal: horizontal, line: line, from: lo, to: hi)])
    }

    /// Unlabelled wire; callers label it once they are done mutating `elements`.
    private static func wire(horizontal: Bool, line: CGFloat, from lo: CGFloat, to hi: CGFloat) -> SketchElement {
        let a = horizontal ? CGPoint(x: lo, y: line) : CGPoint(x: line, y: lo)
        let b = horizontal ? CGPoint(x: hi, y: line) : CGPoint(x: line, y: hi)
        return SketchElement(kind: .wire, a: a, b: b, label: "")
    }

    private mutating func appendLabelled(_ wires: [SketchElement]) {
        for wire in wires {
            var labelled = wire
            labelled.label = nextLabel(for: .wire)
            elements.append(labelled)
        }
    }

    /// Removes the part of every collinear wire that lies under `lo…hi` on `line`, keeping the rest.
    private mutating func cutWires(horizontal: Bool, line: CGFloat, from lo: CGFloat, to hi: CGFloat) {
        var remainders: [SketchElement] = []
        elements.removeAll { wire in
            guard wire.kind == .wire, wire.isHorizontal == horizontal, abs(wire.line - line) < 0.5 else { return false }
            guard wire.upperEnd > lo + 0.5, wire.lowerEnd < hi - 0.5 else { return false }
            if wire.lowerEnd < lo - 0.5 { remainders.append(SketchDocument.wire(horizontal: horizontal, line: line, from: wire.lowerEnd, to: lo)) }
            if wire.upperEnd > hi + 0.5 { remainders.append(SketchDocument.wire(horizontal: horizontal, line: line, from: hi, to: wire.upperEnd)) }
            return true
        }
        appendLabelled(remainders)
    }

    /// Stretches wire ends that stop just short of a component's terminals: only ends that point at
    /// the terminal from outside are pulled, so a wire never collapses or reverses.
    private mutating func attachWires(to element: SketchElement) {
        for terminal in [element.a, element.b] {
            for index in elements.indices where elements[index].kind == .wire {
                var wire = elements[index]
                guard !near(wire.a, terminal), !near(wire.b, terminal) else { continue }
                let onLine = wire.isHorizontal ? abs(terminal.y - wire.line) < 0.5 : abs(terminal.x - wire.line) < 0.5
                guard onLine else { continue }
                let t = wire.along(terminal)
                let gapLower = wire.lowerEnd - t, gapUpper = t - wire.upperEnd
                if gapLower > 0.5, gapLower <= step * 1.6 {
                    if wire.along(wire.a) < wire.along(wire.b) { wire.a = terminal } else { wire.b = terminal }
                } else if gapUpper > 0.5, gapUpper <= step * 1.6 {
                    if wire.along(wire.a) > wire.along(wire.b) { wire.a = terminal } else { wire.b = terminal }
                } else {
                    continue
                }
                elements[index] = wire
            }
        }
    }

    // MARK: Components

    /// Places a new component drawn around `rawCenter`. Drawn on a wire it is inserted into the wire;
    /// drawn across a wire one terminal lands on it; otherwise it lines up with whatever is nearby.
    @discardableResult
    mutating func addComponent(_ kind: SketchElement.Kind, center rawCenter: CGPoint, horizontal: Bool) -> SketchElement {
        var element = SketchElement(kind: kind, a: .zero, b: .zero, label: nextLabel(for: kind))
        seat(&element, center: rawCenter, horizontal: horizontal)
        elements.append(element)
        return element
    }

    /// Quarter turn: the part is lifted out (healing the wire it sat in) and seated again the other way.
    mutating func rotate(_ id: UUID) {
        guard let index = elements.firstIndex(where: { $0.id == id }), elements[index].isComponent else { return }
        var element = elements[index]
        let center = element.center
        let horizontal = element.isHorizontal
        remove(id, heal: true)
        seat(&element, center: center, horizontal: !horizontal)
        elements.append(element)
    }

    /// Changes what a part is; the value no longer applies, so it is cleared.
    mutating func setKind(_ id: UUID, _ kind: SketchElement.Kind) {
        guard let index = elements.firstIndex(where: { $0.id == id }), elements[index].kind != kind else { return }
        relabel(id, as: kind)
        elements[index].value = nil
        elements[index].flipped = false
    }

    /// Removes an element. With `heal`, a component that sat inside a straight wire leaves the wire whole.
    mutating func remove(_ id: UUID, heal: Bool) {
        guard let index = elements.firstIndex(where: { $0.id == id }) else { return }
        let element = elements.remove(at: index)
        guard heal, element.isComponent, isInline(element) else { return }
        insertWire(from: element.a, to: element.b)
    }

    /// Drops the current ground (there is one reference node) and puts it on the nearest wire or terminal.
    mutating func placeGround(at rawPoint: CGPoint) {
        var point = SketchGrid.snap(rawPoint)
        if let near = nearestConnectionPoint(to: rawPoint, within: step * 2) {
            point = near
        } else if let onWire = nearestWirePoint(to: rawPoint, within: step * 2) {
            point = onWire
        }
        elements.removeAll { $0.kind == .ground }
        elements.append(SketchElement(kind: .ground, a: point, b: point, label: nextLabel(for: .ground)))
    }

    private mutating func seat(_ element: inout SketchElement, center rawCenter: CGPoint, horizontal: Bool) {
        let half = componentLength / 2
        var center = SketchGrid.snap(rawCenter)
        var span: (lo: CGFloat, hi: CGFloat)?
        func along(_ p: CGPoint) -> CGFloat { horizontal ? p.x : p.y }
        func setAlong(_ v: CGFloat) { if horizontal { center.x = v } else { center.y = v } }
        func setAcross(_ v: CGFloat) { if horizontal { center.y = v } else { center.x = v } }

        if let host = hostWire(near: rawCenter, horizontal: horizontal) {
            setAcross(host.line)
            if host.length < componentLength - 0.5 {
                // A short wire: the part takes the wire's full extent (down to two grid steps).
                if host.length >= step * 2 - 0.5 { span = (host.lowerEnd, host.upperEnd) }
            } else {
                var c = min(max(along(center), host.lowerEnd + half), host.upperEnd - half)
                c = positionAvoidingJunctions(c, half: half, on: host)
                setAlong(c)
            }
        } else if let crossing = crossingWire(near: rawCenter, horizontal: horizontal) {
            // One terminal lands on the wire the part was drawn across.
            setAlong(crossing.extendsForward ? crossing.wire.line + half : crossing.wire.line - half)
            let across = horizontal ? center.y : center.x
            setAcross(min(max(across, crossing.wire.lowerEnd), crossing.wire.upperEnd))
        } else if let near = nearestConnectionPoint(to: center, within: step * 1.6) {
            setAcross(horizontal ? near.y : near.x)
        }

        let lo = span?.lo ?? (along(center) - half)
        let hi = span?.hi ?? (along(center) + half)
        let line = horizontal ? center.y : center.x
        element.a = horizontal ? CGPoint(x: lo, y: line) : CGPoint(x: line, y: lo)
        element.b = horizontal ? CGPoint(x: hi, y: line) : CGPoint(x: line, y: hi)
        cutWires(horizontal: horizontal, line: line, from: lo, to: hi)
        attachWires(to: element)
    }

    /// The wire a component was drawn on: same direction, on its line, overlapping along it.
    private func hostWire(near raw: CGPoint, horizontal: Bool) -> SketchElement? {
        var best: (SketchElement, CGFloat)?
        for wire in elements where wire.kind == .wire && wire.isHorizontal == horizontal {
            let across = abs((horizontal ? raw.y : raw.x) - wire.line)
            let along = horizontal ? raw.x : raw.y
            guard across <= step * 0.75, along >= wire.lowerEnd - step, along <= wire.upperEnd + step else { continue }
            if best == nil || across < best!.1 { best = (wire, across) }
        }
        return best?.0
    }

    /// A wire running across the component near one of its terminals (or through its middle).
    /// `extendsForward`: the part continues in the positive direction from the wire.
    private func crossingWire(near raw: CGPoint, horizontal: Bool) -> (wire: SketchElement, extendsForward: Bool)? {
        let half = componentLength / 2
        let rawAlong = horizontal ? raw.x : raw.y
        let rawAcross = horizontal ? raw.y : raw.x
        var best: (SketchElement, Bool, CGFloat)?
        for wire in elements where wire.kind == .wire && wire.isHorizontal != horizontal {
            guard rawAcross >= wire.lowerEnd - step * 0.5, rawAcross <= wire.upperEnd + step * 0.5 else { continue }
            let toLower = abs(rawAlong - half - wire.line)
            let toUpper = abs(rawAlong + half - wire.line)
            let toCenter = abs(rawAlong - wire.line)
            let d = min(toLower, toUpper, toCenter)
            guard d <= step * 0.75 else { continue }
            let forward: Bool
            if toCenter <= min(toLower, toUpper) {
                // Drawn straddling the wire: grow toward the rest of the drawing.
                let others = elements.filter { $0.id != wire.id }
                let c = centroid(of: others.isEmpty ? [wire] : others)
                forward = (horizontal ? c.x : c.y) >= wire.line
            } else {
                forward = toLower < toUpper
            }
            if best == nil || d < best!.2 { best = (wire, forward, d) }
        }
        return best.map { ($0.0, $0.1) }
    }

    /// Slides the part along its host wire (up to two steps) so it does not swallow a junction.
    private func positionAvoidingJunctions(_ c: CGFloat, half: CGFloat, on host: SketchElement) -> CGFloat {
        let taps: [CGFloat] = elements.flatMap { element -> [CGFloat] in
            guard element.id != host.id else { return [] }
            let points = element.kind == .ground ? [element.a] : [element.a, element.b]
            return points.compactMap { p -> CGFloat? in
                let across = host.isHorizontal ? p.y : p.x
                guard abs(across - host.line) < 0.5 else { return nil }
                return host.along(p)
            }
        }
        let lower = host.lowerEnd + half, upper = host.upperEnd - half
        for shift in [0, 1, -1, 2, -2] {
            let candidate = c + CGFloat(shift) * step
            guard candidate >= lower - 0.5, candidate <= upper + 0.5 else { continue }
            let swallowed = taps.contains { $0 > candidate - half + 0.5 && $0 < candidate + half - 0.5 }
            if !swallowed { return candidate }
        }
        return c
    }

    /// True when a collinear wire ends at each terminal: the part sits inside a straight run.
    private func isInline(_ element: SketchElement) -> Bool {
        [element.a, element.b].allSatisfy { terminal in
            elements.contains { wire in
                wire.kind == .wire && wire.isHorizontal == element.isHorizontal && abs(wire.line - element.line) < 0.5
                    && (near(wire.a, terminal) || near(wire.b, terminal))
            }
        }
    }

    // MARK: Eraser and hit testing

    /// Rubs out whatever the eraser touched: parts and grounds go entirely, wires lose only the
    /// stretch under the eraser (rounded out to the grid). Returns the ids of parts removed.
    @discardableResult
    mutating func erase(along points: [CGPoint], radius: CGFloat) -> [UUID] {
        guard !points.isEmpty else { return [] }
        let gridStep = step
        var removedIds: [UUID] = []
        var replacements: [SketchElement] = []
        elements.removeAll { element in
            if element.kind == .wire {
                let touching = points.filter { p in
                    abs((element.isHorizontal ? p.y : p.x) - element.line) <= radius
                        && element.along(p) >= element.lowerEnd - radius && element.along(p) <= element.upperEnd + radius
                }
                guard !touching.isEmpty else { return false }
                let alongs = touching.map { element.along($0) }
                let cutLo = SketchGrid.snap(alongs.min()! - radius)
                let cutHi = SketchGrid.snap(alongs.max()! + radius)
                if cutLo - element.lowerEnd >= gridStep - 0.5 {
                    replacements.append(SketchDocument.wire(horizontal: element.isHorizontal, line: element.line, from: element.lowerEnd, to: cutLo))
                }
                if element.upperEnd - cutHi >= gridStep - 0.5 {
                    replacements.append(SketchDocument.wire(horizontal: element.isHorizontal, line: element.line, from: cutHi, to: element.upperEnd))
                }
                return true
            }
            let hit = points.contains { SketchDocument.distance(from: $0, to: element) <= radius }
            if hit { removedIds.append(element.id) }
            return hit
        }
        appendLabelled(replacements)
        return removedIds
    }

    /// The element under a finger. Parts win over the wire they sit on.
    func element(at point: CGPoint, wireTolerance: CGFloat, partTolerance: CGFloat) -> SketchElement? {
        var best: (SketchElement, CGFloat)?
        for element in elements {
            let d = distance(from: point, to: element)
            guard d <= (element.kind == .wire ? wireTolerance : partTolerance) else { continue }
            let score = element.kind == .wire ? d + 6 : d
            if best == nil || score < best!.1 { best = (element, score) }
        }
        return best?.0
    }

    func distance(from p: CGPoint, to element: SketchElement) -> CGFloat {
        SketchDocument.distance(from: p, to: element)
    }

    static func distance(from p: CGPoint, to element: SketchElement) -> CGFloat {
        if element.kind == .ground {
            return hypot(element.a.x - p.x, element.a.y + 14 - p.y)   // the symbol hangs below its tap
        }
        let a = element.a, b = element.b
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared, 0), 1)
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// Wires drawn next to it decide which way a square or circle should face.
    func inferHorizontal(around center: CGPoint) -> Bool {
        var vertical = 0, horizontal = 0
        for point in connectionPoints {
            let dx = point.x - center.x, dy = point.y - center.y
            guard hypot(dx, dy) <= step * 3 else { continue }
            if abs(dy) > abs(dx) { vertical += 1 } else { horizontal += 1 }
        }
        if horizontal == 0, vertical == 0 {
            // Nothing nearby: face the way the closest wire runs.
            if let closest = elements.filter({ $0.kind == .wire }).min(by: { distance(from: center, to: $0) < distance(from: center, to: $1) }) {
                return closest.isHorizontal
            }
            return true
        }
        return horizontal >= vertical
    }

    private func centroid(of elements: [SketchElement]) -> CGPoint {
        var sum = CGPoint.zero
        var count: CGFloat = 0
        for element in elements {
            sum.x += element.a.x + element.b.x
            sum.y += element.a.y + element.b.y
            count += 2
        }
        return count > 0 ? CGPoint(x: sum.x / count, y: sum.y / count) : .zero
    }

    private func near(_ p: CGPoint, _ q: CGPoint) -> Bool {
        abs(p.x - q.x) < 0.5 && abs(p.y - q.y) < 0.5
    }
}
