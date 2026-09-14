import Foundation

/// Point-cloud template recognizer for part strokes (the "$P" family: stroke direction, start point
/// and drawing speed do not matter), with a library the user teaches. A stroke is resampled to a
/// fixed number of points, turned horizontal when it is taller than wide, scaled uniformly (so a
/// long zigzag and a round circle stay different) and centred; matching is the greedy cloud
/// distance against every template. Built-in templates are synthesized for the shapes people draw
/// for parts; every correction the user makes adds their own stroke as a template, so the
/// recognizer adapts to each person's hand.
enum StrokeRecognizer {
    /// Points per normalized stroke.
    static let sampleCount = 32

    struct Match: Equatable {
        let label: String
        let distance: Double
    }

    // MARK: Normalization

    /// Resampled, oriented, scaled and centred point cloud, or nil for a degenerate stroke.
    static func normalized(_ raw: [CGPoint]) -> [CGPoint]? {
        guard raw.count >= 2 else { return nil }
        // Finger jitter is averaged out over ~5% of the stroke's length before sampling, so the
        // cloud describes the shape, not the tremor. Templates go through the same steps.
        let dense = StrokeClassifier.resample(raw, spacing: max(pathLength(raw) / 200, 0.25))
        let smooth = StrokeClassifier.smoothed(dense, window: 11)
        var points = resample(smooth, count: sampleCount)
        guard points.count == sampleCount else { return nil }
        let bounds = StrokeClassifier.boundingBox(points)
        guard max(bounds.width, bounds.height) > 0.5 else { return nil }
        if bounds.height > bounds.width * 1.25 {
            points = points.map { CGPoint(x: -$0.y, y: $0.x) }   // stand it up: templates are horizontal
        }
        // Stretch to the unit square (each axis on its own, as $P does): the sideways detail of a
        // long flat zigzag is what tells it from a coil, and it must count as much as its length.
        // Very thin strokes keep their proportions so jitter is not blown up into a shape.
        let oriented = StrokeClassifier.boundingBox(points)
        let major = max(oriented.width, oriented.height)
        let sx = 1 / max(oriented.width, 0.08 * major)
        let sy = 1 / max(oriented.height, 0.08 * major)
        var cx: CGFloat = 0, cy: CGFloat = 0
        for p in points { cx += p.x; cy += p.y }
        cx /= CGFloat(points.count); cy /= CGFloat(points.count)
        return points.map { CGPoint(x: ($0.x - cx) * sx, y: ($0.y - cy) * sy) }
    }

    /// Exactly `count` points spread evenly along the path.
    static func resample(_ points: [CGPoint], count: Int) -> [CGPoint] {
        guard points.count >= 2, count >= 2 else { return points }
        let total = pathLength(points)
        guard total > 0 else { return Array(repeating: points[0], count: count) }
        let interval = total / CGFloat(count - 1)
        var result = [points[0]]
        var carry: CGFloat = 0
        var previous = points[0]
        for point in points.dropFirst() {
            var segment = hypot(point.x - previous.x, point.y - previous.y)
            var from = previous
            while segment > 0, carry + segment >= interval, result.count < count - 1 {
                let t = (interval - carry) / segment
                let p = CGPoint(x: from.x + (point.x - from.x) * t, y: from.y + (point.y - from.y) * t)
                result.append(p)
                segment -= interval - carry
                carry = 0
                from = p
            }
            carry += segment
            previous = point
        }
        while result.count < count { result.append(points[points.count - 1]) }
        return result
    }

    static func pathLength(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    // MARK: Matching

    /// Best distance per label, closest first.
    static func matches(_ raw: [CGPoint], templates: [StrokeTemplate]) -> [Match] {
        guard let cloud = normalized(raw) else { return [] }
        return matches(cloud: cloud, templates: templates)
    }

    static func matches(cloud: [CGPoint], templates: [StrokeTemplate]) -> [Match] {
        var best: [String: Double] = [:]
        for template in templates {
            let d = cloudDistance(cloud, template.cloud)
            if d < best[template.label] ?? .infinity { best[template.label] = d }
        }
        return best.map { Match(label: $0.key, distance: $0.value) }.sorted { $0.distance < $1.distance }
    }

    /// Greedy cloud distance ($P): every point of one cloud is matched to its nearest unmatched
    /// point of the other, from several starting points and in both directions; the smallest
    /// weighted sum wins. Normalized so that 1.0 ≈ every point a full shape-size away.
    static func cloudDistance(_ a: [CGPoint], _ b: [CGPoint]) -> Double {
        let n = min(a.count, b.count)
        guard n > 0 else { return .infinity }
        let step = max(Int(Double(n).squareRoot().rounded(.down)), 1)
        var smallest = Double.infinity
        var start = 0
        while start < n {
            smallest = min(smallest, directedDistance(a, b, start: start, n: n), directedDistance(b, a, start: start, n: n))
            start += step
        }
        return smallest / (Double(n) * 0.5)
    }

    private static func directedDistance(_ a: [CGPoint], _ b: [CGPoint], start: Int, n: Int) -> Double {
        var matched = [Bool](repeating: false, count: n)
        var sum = 0.0
        var i = start
        repeat {
            var index = -1
            var nearest = Double.infinity
            for j in 0..<n where !matched[j] {
                let dx = Double(a[i].x - b[j].x), dy = Double(a[i].y - b[j].y)
                let d = dx * dx + dy * dy
                if d < nearest { nearest = d; index = j }
            }
            if index >= 0 { matched[index] = true }
            let weight = 1 - Double((i - start + n) % n) / Double(n)
            sum += weight * nearest.squareRoot()
            i = (i + 1) % n
        } while i != start
        return sum
    }
}

/// One normalized point cloud with the label it stands for: a built-in shape ("zigzag", "box",
/// "coil", "circle") or the raw value of the `SketchElement.Kind` the user taught.
struct StrokeTemplate: Codable, Equatable {
    var label: String
    /// Interleaved x, y of the normalized points (a plain array so it stores anywhere).
    var coords: [Double]

    init(label: String, cloud: [CGPoint]) {
        self.label = label
        coords = cloud.flatMap { [Double($0.x), Double($0.y)] }
    }

    var cloud: [CGPoint] {
        stride(from: 0, to: coords.count - 1, by: 2).map { CGPoint(x: coords[$0], y: coords[$0 + 1]) }
    }
}

/// Built-in shapes plus everything the user has taught, kept on the device.
final class StrokeLibrary {
    static let shared = StrokeLibrary()

    /// Built-in shape labels.
    static let zigzag = "zigzag", box = "box", coil = "coil", circle = "circle"
    static let builtInLabels: Set<String> = [zigzag, box, coil, circle]
    /// Taught templates kept per kind: the newest replace the oldest.
    static let perKindLimit = 16

    private(set) var taught: [StrokeTemplate] = []
    private let builtIn: [StrokeTemplate]
    private let url: URL?

    init(url: URL? = StrokeLibrary.defaultURL) {
        self.url = url
        builtIn = StrokeTemplateFactory.builtIn()
        if let url, let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([StrokeTemplate].self, from: data) {
            taught = saved.filter { $0.coords.count == StrokeRecognizer.sampleCount * 2 }
        }
    }

    static var defaultURL: URL? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("PhotoMesh", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("stroke-templates.json")
    }

    var templates: [StrokeTemplate] { builtIn + taught }
    var taughtCount: Int { taught.count }

    /// Kinds the user has taught, most taught first.
    var taughtKinds: [SketchElement.Kind] {
        var counts: [String: Int] = [:]
        for t in taught { counts[t.label, default: 0] += 1 }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.compactMap { SketchElement.Kind(rawValue: $0.key) }
    }

    /// Remembers a stroke as an example of `kind`. Only parts are worth teaching.
    @discardableResult
    func learn(_ raw: [CGPoint], as kind: SketchElement.Kind) -> Bool {
        guard kind.isComponent, let cloud = StrokeRecognizer.normalized(raw) else { return false }
        // A stroke that already matches this kind closely teaches nothing new.
        let own = taught.filter { $0.label == kind.rawValue }
        if own.contains(where: { StrokeRecognizer.cloudDistance(cloud, $0.cloud) < 0.06 }) { return false }
        if own.count >= StrokeLibrary.perKindLimit, let oldest = taught.firstIndex(where: { $0.label == kind.rawValue }) {
            taught.remove(at: oldest)
        }
        taught.append(StrokeTemplate(label: kind.rawValue, cloud: cloud))
        save()
        return true
    }

    func forgetAll() {
        taught.removeAll()
        save()
    }

    private func save() {
        guard let url else { return }
        if let data = try? JSONEncoder().encode(taught) { try? data.write(to: url, options: .atomic) }
    }
}

/// Synthesized examples of how people draw parts, several variants each so the cloud distance has
/// something close to any reasonable hand: zigzags with 3–7 peaks (sharp and rounded, with and
/// without lead lines), coils as humps or cursive loops, boxes of several aspects with rounded
/// corners, circles and ovals (closed, left open, or overshooting).
enum StrokeTemplateFactory {
    static func builtIn() -> [StrokeTemplate] {
        var result: [StrokeTemplate] = []
        func add(_ label: String, _ points: [CGPoint]) {
            if let cloud = StrokeRecognizer.normalized(points) { result.append(StrokeTemplate(label: label, cloud: cloud)) }
        }
        for peaks in 3...7 {
            for amplitude in [0.08, 0.14, 0.22] {
                for lead in [0.0, 0.15] {
                    add(StrokeLibrary.zigzag, zigzag(peaks: peaks, amplitude: amplitude, lead: lead, rounded: false))
                    add(StrokeLibrary.zigzag, zigzag(peaks: peaks, amplitude: amplitude, lead: lead, rounded: true))
                }
            }
        }
        for count in 3...6 {
            for height in [0.18, 0.28] {
                for lead in [0.0, 0.15] {
                    add(StrokeLibrary.coil, humps(count: count, height: height, lead: lead))
                }
            }
            add(StrokeLibrary.coil, loops(count: count, lead: 0))
            add(StrokeLibrary.coil, loops(count: count, lead: 0.12))
        }
        for aspect in [1.0, 1.4, 2.0, 2.8] {
            for radius in [0.0, 0.12, 0.25] {
                add(StrokeLibrary.box, box(aspect: aspect, cornerRadius: radius, overshoot: 0))
            }
            add(StrokeLibrary.box, box(aspect: aspect, cornerRadius: 0.08, overshoot: 0.12))
        }
        for aspect in [1.0, 1.25, 1.6] {
            add(StrokeLibrary.circle, ellipse(aspect: aspect, gap: 0, overshoot: 0))
            add(StrokeLibrary.circle, ellipse(aspect: aspect, gap: 0.12, overshoot: 0))
            add(StrokeLibrary.circle, ellipse(aspect: aspect, gap: 0.22, overshoot: 0))
            add(StrokeLibrary.circle, ellipse(aspect: aspect, gap: 0, overshoot: 0.15))
        }
        return result
    }

    /// Length 100 along x. `amplitude` and `lead` are fractions of the length.
    static func zigzag(peaks: Int, amplitude: Double, lead: Double, rounded: Bool) -> [CGPoint] {
        let length = 100.0
        let start = lead * length, end = length - lead * length
        let segment = (end - start) / Double(peaks + 1)
        var corners: [CGPoint] = [CGPoint(x: 0, y: 0)]
        if lead > 0 { corners.append(CGPoint(x: start, y: 0)) }
        for i in 1...peaks {
            corners.append(CGPoint(x: start + segment * Double(i), y: (i % 2 == 1 ? -1 : 1) * amplitude * length))
        }
        corners.append(CGPoint(x: end, y: 0))
        if lead > 0 { corners.append(CGPoint(x: length, y: 0)) }
        let dense = StrokeClassifier.resample(polyline(corners), spacing: 1)
        return rounded ? StrokeClassifier.smoothed(dense, window: 9) : dense
    }

    /// Semicircular humps all on one side, touching a baseline between them.
    static func humps(count: Int, height: Double, lead: Double) -> [CGPoint] {
        let length = 100.0
        let start = lead * length, end = length - lead * length
        let width = (end - start) / Double(count)
        var points: [CGPoint] = []
        if lead > 0 { points += polyline([CGPoint(x: 0, y: 0), CGPoint(x: start, y: 0)]) }
        for i in 0..<count {
            let cx = start + width * (Double(i) + 0.5)
            for k in 0...24 {
                let t = Double.pi - Double.pi * Double(k) / 24
                points.append(CGPoint(x: cx + (width / 2) * cos(t), y: -height * length * sin(t)))
            }
        }
        if lead > 0 { points += polyline([CGPoint(x: end, y: 0), CGPoint(x: length, y: 0)]) }
        return points
    }

    /// Cursive loops (a prolate cycloid): the pen keeps crossing its own track.
    static func loops(count: Int, lead: Double) -> [CGPoint] {
        let length = 100.0
        let start = lead * length, end = length - lead * length
        let advance = (end - start) / Double(count)
        let radius = advance * 0.42
        var points: [CGPoint] = []
        if lead > 0 { points += polyline([CGPoint(x: 0, y: 0), CGPoint(x: start, y: 0)]) }
        let steps = count * 30
        for k in 0...steps {
            let t = 2 * Double.pi * Double(count) * Double(k) / Double(steps)
            points.append(CGPoint(x: start + advance * t / (2 * Double.pi) - radius * sin(t), y: -radius * (1 - cos(t))))
        }
        if lead > 0 { points += polyline([CGPoint(x: end, y: 0), CGPoint(x: length, y: 0)]) }
        return points
    }

    /// Rectangle `aspect` wide for 1 tall, corners rounded by `cornerRadius` (fraction of the height).
    static func box(aspect: Double, cornerRadius: Double, overshoot: Double) -> [CGPoint] {
        let h = 40.0, w = h * aspect
        let r = min(cornerRadius * h, min(w, h) / 2)
        var outline: [CGPoint] = []
        func arc(_ cx: Double, _ cy: Double, from: Double, to: Double) {
            for k in 0...8 {
                let t = from + (to - from) * Double(k) / 8
                outline.append(CGPoint(x: cx + r * cos(t), y: cy + r * sin(t)))
            }
        }
        outline.append(CGPoint(x: r, y: 0))
        outline.append(CGPoint(x: w - r, y: 0))
        if r > 0 { arc(w - r, r, from: -.pi / 2, to: 0) }
        outline.append(CGPoint(x: w, y: h - r))
        if r > 0 { arc(w - r, h - r, from: 0, to: .pi / 2) }
        outline.append(CGPoint(x: r, y: h))
        if r > 0 { arc(r, h - r, from: .pi / 2, to: .pi) }
        outline.append(CGPoint(x: 0, y: r))
        if r > 0 { arc(r, r, from: .pi, to: 1.5 * .pi) }
        outline.append(CGPoint(x: r, y: 0))
        var dense = StrokeClassifier.resample(polyline(outline), spacing: 1)
        if overshoot > 0 {
            let extra = Int(Double(dense.count) * overshoot)
            dense += dense.prefix(extra)
        }
        return dense
    }

    /// Ellipse `aspect` wide for 1 tall; `gap` leaves a fraction of the turn undrawn, `overshoot` draws past the start.
    static func ellipse(aspect: Double, gap: Double, overshoot: Double) -> [CGPoint] {
        let ry = 20.0, rx = ry * aspect
        let turn = 2 * Double.pi * (1 - gap + overshoot)
        let steps = 90
        return (0...steps).map { k in
            let t = -Double.pi / 2 + turn * Double(k) / Double(steps)
            return CGPoint(x: rx * cos(t), y: ry * sin(t))
        }
    }

    private static func polyline(_ corners: [CGPoint]) -> [CGPoint] {
        var points: [CGPoint] = []
        for (a, b) in zip(corners, corners.dropFirst()) {
            let n = max(Int(hypot(b.x - a.x, b.y - a.y)), 1)
            for k in 0..<n {
                let t = CGFloat(k) / CGFloat(n)
                points.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        if let last = corners.last { points.append(last) }
        return points
    }
}
