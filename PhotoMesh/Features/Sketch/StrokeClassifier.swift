import SwiftUI

/// Turns a finger stroke into a guess about what was drawn, handwriting-keyboard style.
enum StrokeGuess: Equatable {
    case tap(CGPoint)
    case wire(from: CGPoint, to: CGPoint)
    /// A wire with corners: consecutive points of an axis-aligned polyline (raw, not yet snapped).
    case wirePath([CGPoint])
    case resistor(center: CGPoint, horizontal: Bool)
    case roundShape(center: CGPoint, size: CGSize)
    /// A box (IEC resistor). `horizontal` is nil for a square: the surroundings decide.
    case rectangle(center: CGPoint, horizontal: Bool?)
    /// A closed outline big enough to be a loop of wires rather than a part.
    case loop(CGRect)
    case shortMark(center: CGPoint)
    case unknown(bounds: CGRect)
}

enum StrokeClassifier {
    /// `loopExtent`: closed strokes at least this big (same units as the points) are wire loops, not parts.
    static func classify(_ raw: [CGPoint], loopExtent: CGFloat = .infinity) -> StrokeGuess {
        let points = resample(raw, spacing: 3)
        guard let first = points.first, let last = points.last else { return .tap(raw.first ?? .zero) }
        let bounds = boundingBox(points)
        let extent = max(bounds.width, bounds.height)
        let pathLength = zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        let chord = hypot(last.x - first.x, last.y - first.y)

        if extent < 10, pathLength < 16 { return .tap(first) }

        // Straight line: little deviation from the chord.
        if chord > 18 {
            let deviation = maxDeviation(points, from: first, to: last)
            if deviation <= max(6, 0.09 * chord) {
                return .wire(from: first, to: last)
            }
        }

        let closed = chord < max(0.32 * extent, 14)
        if closed, extent > 18 {
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            if extent >= loopExtent { return .loop(bounds) }
            let smooth = smoothed(points, window: 5)
            let area = abs(shoelace(smooth))
            let smoothLength = zip(smooth, smooth.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
            let circularity = smoothLength > 0 ? 4 * .pi * area / (smoothLength * smoothLength) : 0
            let smoothBounds = boundingBox(smooth)
            let fill = area / max(smoothBounds.width * smoothBounds.height, 1)
            let aspect = bounds.width / max(bounds.height, 1)
            // A box turns sharply in a few places and runs straight elsewhere; a circle turns evenly all
            // the way round. When in doubt call it round: a round shape asks what it is, a box would
            // silently become a resistor.
            let straight = straightFraction(smooth)
            let isBox = fill > 0.84 || straight > 0.3
            if isBox {
                let horizontal: Bool? = aspect > 1.25 ? true : (aspect < 0.8 ? false : nil)
                return .rectangle(center: center, horizontal: horizontal)
            }
            if circularity > 0.55, aspect > 0.55, aspect < 1.8 {
                return .roundShape(center: center, size: bounds.size)
            }
            if aspect > 1.5 || aspect < 0.66 {
                return .rectangle(center: center, horizontal: bounds.width >= bounds.height)
            }
            return .unknown(bounds: bounds)
        }

        // A wire that turns: a few long, axis-aligned segments.
        let corners = withoutShortSegments(simplify(points, epsilon: max(7, 0.05 * extent)), minimum: 16)
        if corners.count >= 3, corners.count <= 7, isOrthogonalPolyline(corners, minimumSegment: 16) {
            return .wirePath(corners)
        }

        // Zigzag: several reversals of the sideways offset along the chord.
        if chord > 24 {
            let reversals = sidewaysReversals(points, from: first, to: last, threshold: 4)
            if reversals >= 3 {
                let horizontal = abs(last.x - first.x) >= abs(last.y - first.y)
                return .resistor(center: CGPoint(x: bounds.midX, y: bounds.midY), horizontal: horizontal)
            }
        }

        if extent < 30 { return .shortMark(center: CGPoint(x: bounds.midX, y: bounds.midY)) }
        return .unknown(bounds: bounds)
    }

    // MARK: Geometry helpers

    static func resample(_ points: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        guard var previous = points.first else { return [] }
        var result = [previous]
        var carry: CGFloat = 0
        for point in points.dropFirst() {
            var segment = hypot(point.x - previous.x, point.y - previous.y)
            var from = previous
            while carry + segment >= spacing {
                let t = (spacing - carry) / segment
                let p = CGPoint(x: from.x + (point.x - from.x) * t, y: from.y + (point.y - from.y) * t)
                result.append(p)
                segment -= spacing - carry
                carry = 0
                from = p
            }
            carry += segment
            previous = point
        }
        if let last = points.last, result.last != last { result.append(last) }
        return result
    }

    static func boundingBox(_ points: [CGPoint]) -> CGRect {
        var minX = CGFloat.infinity, minY = CGFloat.infinity, maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for p in points {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func maxDeviation(_ points: [CGPoint], from a: CGPoint, to b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = max(hypot(dx, dy), 0.001)
        return points.map { abs(($0.x - a.x) * dy - ($0.y - a.y) * dx) / length }.max() ?? 0
    }

    static func shoelace(_ points: [CGPoint]) -> CGFloat {
        var area: CGFloat = 0
        for i in points.indices {
            let p = points[i], q = points[(i + 1) % points.count]
            area += p.x * q.y - q.x * p.y
        }
        return area / 2
    }

    /// Ramer–Douglas–Peucker: keeps only the corners of a stroke.
    static func simplify(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack = [(0, points.count - 1)]
        while let (start, end) = stack.popLast() {
            guard end > start + 1 else { continue }
            var farthest = start
            var largest: CGFloat = 0
            let a = points[start], b = points[end]
            for i in (start + 1)..<end {
                let d = maxDeviation([points[i]], from: a, to: b)
                if d > largest { largest = d; farthest = i }
            }
            if largest > epsilon {
                keep[farthest] = true
                stack.append((start, farthest))
                stack.append((farthest, end))
            }
        }
        return points.indices.filter { keep[$0] }.map { points[$0] }
    }

    /// Share of a closed outline that runs straight: samples turning less than 40% of the average
    /// turn. A circle turns evenly, so almost nothing counts as straight (≈0.05); a square is mostly
    /// straight sides (≈0.6 even with rounded corners). Independent of size and sampling.
    static func straightFraction(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 8 else { return 0 }
        let stride = 2
        var turns: [CGFloat] = []
        for i in stride..<(points.count - stride) {
            let p = points[i - stride], q = points[i], r = points[i + stride]
            let inbound = atan2(q.y - p.y, q.x - p.x), outbound = atan2(r.y - q.y, r.x - q.x)
            var turn = abs(outbound - inbound)
            if turn > .pi { turn = 2 * .pi - turn }
            turns.append(turn)
        }
        let mean = turns.reduce(0, +) / CGFloat(max(turns.count, 1))
        guard mean > 0 else { return 0 }
        return CGFloat(turns.filter { $0 < 0.4 * mean }.count) / CGFloat(turns.count)
    }

    /// Moving average that takes the finger jitter out before measuring a shape.
    static func smoothed(_ points: [CGPoint], window: Int) -> [CGPoint] {
        guard points.count > window, window > 1 else { return points }
        let half = window / 2
        return points.indices.map { i in
            let lo = max(0, i - half), hi = min(points.count - 1, i + half)
            var sum = CGPoint.zero
            for j in lo...hi { sum.x += points[j].x; sum.y += points[j].y }
            let n = CGFloat(hi - lo + 1)
            return CGPoint(x: sum.x / n, y: sum.y / n)
        }
    }

    /// RDP for a closed outline: split at the point farthest from the start so both halves have a real chord.
    static func simplifyClosed(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 3, let first = points.first else { return points }
        var farthest = 0
        var largest: CGFloat = 0
        for (i, p) in points.enumerated() {
            let d = hypot(p.x - first.x, p.y - first.y)
            if d > largest { largest = d; farthest = i }
        }
        guard farthest > 0, farthest < points.count - 1 else { return simplify(points, epsilon: epsilon) }
        let head = simplify(Array(points[0...farthest]), epsilon: epsilon)
        let tail = simplify(Array(points[farthest...]), epsilon: epsilon)
        return head + tail.dropFirst()
    }

    /// Corners of a closed outline where the direction turns by at least `minimumTurn`.
    static func sharpCorners(_ corners: [CGPoint], minimumTurn: CGFloat) -> Int {
        var ring = corners
        if let first = ring.first, let last = ring.last, ring.count > 2, hypot(last.x - first.x, last.y - first.y) < 1 { ring.removeLast() }
        guard ring.count >= 3 else { return 0 }
        var count = 0
        for i in ring.indices {
            let p = ring[(i + ring.count - 1) % ring.count], q = ring[i], r = ring[(i + 1) % ring.count]
            let inbound = atan2(q.y - p.y, q.x - p.x), outbound = atan2(r.y - q.y, r.x - q.x)
            var turn = abs(outbound - inbound)
            if turn > .pi { turn = 2 * .pi - turn }
            if turn >= minimumTurn { count += 1 }
        }
        return count
    }

    /// Drops corners that sit right next to another one (a wobble at a real corner), keeping both ends.
    static func withoutShortSegments(_ corners: [CGPoint], minimum: CGFloat) -> [CGPoint] {
        guard corners.count > 2 else { return corners }
        var result = [corners[0]]
        for (index, corner) in corners.enumerated().dropFirst() {
            let previous = result[result.count - 1]
            if hypot(corner.x - previous.x, corner.y - previous.y) >= minimum {
                result.append(corner)
            } else if index == corners.count - 1 {
                // Keep the true end of the stroke rather than the wobble before it.
                if result.count > 1 { result[result.count - 1] = corner } else { result.append(corner) }
            }
        }
        return result
    }

    /// Every segment long enough and within ~35° of horizontal or vertical.
    static func isOrthogonalPolyline(_ corners: [CGPoint], minimumSegment: CGFloat) -> Bool {
        for (a, b) in zip(corners, corners.dropFirst()) {
            let dx = abs(b.x - a.x), dy = abs(b.y - a.y)
            let length = hypot(dx, dy)
            guard length >= minimumSegment else { return false }
            let angle = atan2(min(dx, dy), max(dx, dy))   // 0 = axis aligned, π/4 = diagonal
            if angle > 35 * .pi / 180 { return false }
        }
        return true
    }

    static func sidewaysReversals(_ points: [CGPoint], from a: CGPoint, to b: CGPoint, threshold: CGFloat) -> Int {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = max(hypot(dx, dy), 0.001)
        let offsets = points.map { (($0.x - a.x) * dy - ($0.y - a.y) * dx) / length }
        var reversals = 0
        var lastExtreme = offsets[0]
        var direction = 0
        for offset in offsets.dropFirst() {
            let delta = offset - lastExtreme
            if direction == 0 {
                if abs(delta) > threshold { direction = delta > 0 ? 1 : -1; lastExtreme = offset }
            } else if (direction > 0 && offset > lastExtreme) || (direction < 0 && offset < lastExtreme) {
                lastExtreme = offset
            } else if abs(delta) > threshold {
                reversals += 1
                direction = -direction
                lastExtreme = offset
            }
        }
        return reversals
    }
}
