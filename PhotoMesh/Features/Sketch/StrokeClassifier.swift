import SwiftUI

/// Turns a finger stroke into a guess about what was drawn, handwriting-keyboard style.
enum StrokeGuess: Equatable {
    case tap(CGPoint)
    case wire(from: CGPoint, to: CGPoint)
    case resistor(center: CGPoint, horizontal: Bool)
    case roundShape(center: CGPoint, size: CGSize)
    case rectangle(center: CGPoint, horizontal: Bool)
    case shortMark(center: CGPoint)
    case unknown(bounds: CGRect)
}

enum StrokeClassifier {
    static func classify(_ raw: [CGPoint]) -> StrokeGuess {
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
            let area = abs(shoelace(points))
            let circularity = pathLength > 0 ? 4 * .pi * area / (pathLength * pathLength) : 0
            let aspect = bounds.width / max(bounds.height, 1)
            if circularity > 0.68, aspect > 0.6, aspect < 1.65 {
                return .roundShape(center: CGPoint(x: bounds.midX, y: bounds.midY), size: bounds.size)
            }
            if aspect > 1.5 || aspect < 0.66 {
                return .rectangle(center: CGPoint(x: bounds.midX, y: bounds.midY), horizontal: bounds.width >= bounds.height)
            }
            return .unknown(bounds: bounds)
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
