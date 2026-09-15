import Foundation

/// Turns a finger stroke into a guess about what was drawn, handwriting-keyboard style.
enum StrokeGuess: Equatable {
    case tap(CGPoint)
    case wire(from: CGPoint, to: CGPoint)
    /// A wire with corners: consecutive points of an axis-aligned polyline (raw, not yet snapped).
    case wirePath([CGPoint])
    case resistor(center: CGPoint, horizontal: Bool)
    /// A row of humps all on one side of the stroke's chord (a coil).
    case inductor(center: CGPoint, horizontal: Bool)
    case roundShape(center: CGPoint, size: CGSize)
    /// A box (IEC resistor). `horizontal` is nil for a square: the surroundings decide.
    case rectangle(center: CGPoint, horizontal: Bool?)
    /// A closed outline big enough to be a loop of wires rather than a part.
    case loop(CGRect)
    /// A shape the user taught the recognizer (a capacitor, a switch, …).
    case part(kind: SketchElement.Kind, center: CGPoint, horizontal: Bool)
    case shortMark(center: CGPoint)
    case unknown(bounds: CGRect)
}

/// A guess plus how sure it is and what else it could be. The canvas commits a confident guess,
/// asks with `ranked` when it is not, and offers `ranked` as the "not a …?" alternatives afterwards.
struct StrokeRecognition: Equatable {
    var guess: StrokeGuess
    var ranked: [SketchElement.Kind]
    var confident: Bool
}

enum StrokeClassifier {
    /// Closest template may be at most this far for a confident match (cloud distance, ~ fraction of the shape size).
    static let confidentDistance = 0.30
    /// The runner-up family must be at least this much farther (absolute) or this many times farther (relative).
    static let confidentMargin = 0.05
    static let confidentRatio = 1.2
    /// Nothing closer than this: the stroke is not one of the known shapes at all.
    static let strangerDistance = 0.55

    /// `loopExtent`: closed strokes at least this big (same units as the points) are wire loops, not parts.
    static func classify(_ raw: [CGPoint], loopExtent: CGFloat = .infinity, library: StrokeLibrary = .shared) -> StrokeGuess {
        recognize(raw, loopExtent: loopExtent, library: library).guess
    }

    static func recognize(_ raw: [CGPoint], loopExtent: CGFloat = .infinity, library: StrokeLibrary = .shared) -> StrokeRecognition {
        let points = resample(raw, spacing: 3)
        guard let first = points.first, let last = points.last else {
            return StrokeRecognition(guess: .tap(raw.first ?? .zero), ranked: [], confident: true)
        }
        let bounds = boundingBox(points)
        let extent = max(bounds.width, bounds.height)
        let pathLength = zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        let chord = hypot(last.x - first.x, last.y - first.y)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        func sure(_ guess: StrokeGuess) -> StrokeRecognition { StrokeRecognition(guess: guess, ranked: [], confident: true) }

        if extent < 10, pathLength < 16 { return sure(.tap(first)) }

        // Straight line: little deviation from the chord, and no real side-to-side swinging (a flat
        // zigzag stays a part). Short ones are marks (a plate, a tap).
        let deviation = maxDeviation(points, from: first, to: last)
        let swings = chord > 24 ? sidewaysReversals(points, from: first, to: last, threshold: max(5, 0.04 * chord)) : 0
        if chord >= 0.6 * extent, deviation <= max(6, 0.09 * chord), swings < 3 {
            if chord > 18 { return sure(.wire(from: first, to: last)) }
            return sure(.shortMark(center: center))
        }

        // Closed: the ends meet, or the stroke came back onto its own beginning (an overshoot).
        let closed = chord < max(0.32 * extent, 14) || returnsToStart(points, extent: extent)
        if closed, extent > 18, extent >= loopExtent { return sure(.loop(bounds)) }

        // A wire that turns: a few long, axis-aligned segments meeting at real corners, ends apart.
        // Something that keeps swinging from side to side of its chord is a zigzag or a coil, a
        // rounded outline is a shape, and a stroke that retraces one of its own sides is a box.
        if chord >= 14 {
            let corners = withoutShortSegments(withoutShallowCorners(simplifyPath(points, epsilon: max(7, 0.05 * extent)), minimumTurn: 25 * .pi / 180), minimum: 16)
            // Four or more segments whose ends come back near each other outline a shape, not a route.
            let endsApart = corners.count <= 4 || chord >= 0.35 * extent
            if swings < 3, endsApart, corners.count >= 3, corners.count <= 7, isWirePath(corners, minimumSegment: 16) {
                return sure(.wirePath(corners))
            }
        }

        // A part. Templates say what it looks like; a few scale-free shape facts settle the classic
        // confusions (zigzag or coil, circle or box) before the closest family wins.
        let features = ShapeFeatures(points: points, closed: closed, chord: chord, first: first, last: last)
        var distances: [String: Double] = [:]
        for match in StrokeRecognizer.matches(raw, templates: library.templates) { distances[match.label] = match.distance }
        adjust(&distances, with: features)

        var families: [(family: Family, distance: Double)] = []
        for (label, distance) in distances {
            let family = Family(label: label)
            if let index = families.firstIndex(where: { $0.family == family }) {
                families[index].distance = min(families[index].distance, distance)
            } else {
                families.append((family, distance))
            }
        }
        families.sort { $0.distance < $1.distance }
        let ranked = rankedKinds(families, library: library)

        guard let top = families.first, top.distance < strangerDistance else {
            if extent < 30 { return StrokeRecognition(guess: .shortMark(center: center), ranked: ranked, confident: false) }
            return StrokeRecognition(guess: .unknown(bounds: bounds), ranked: ranked, confident: false)
        }
        let runnerUp = families.dropFirst().first?.distance ?? .infinity
        let confident = top.distance <= confidentDistance
            && (runnerUp - top.distance >= confidentMargin || runnerUp / max(top.distance, 1e-9) >= confidentRatio)
        let horizontal = bounds.width >= bounds.height
        let aspect = bounds.width / max(bounds.height, 1)

        let guess: StrokeGuess
        switch top.family {
        case .round:
            guess = .roundShape(center: center, size: bounds.size)
        case .resistor:
            let zigzag = distances[StrokeLibrary.zigzag] ?? .infinity
            let box = distances[StrokeLibrary.box] ?? .infinity
            if box < zigzag || closed {
                guess = .rectangle(center: center, horizontal: aspect > 1.25 ? true : (aspect < 0.8 ? false : nil))
            } else {
                guess = .resistor(center: center, horizontal: horizontal)
            }
        case .inductor:
            guess = .inductor(center: center, horizontal: horizontal)
        case .kind(let kind):
            guess = .part(kind: kind, center: center, horizontal: horizontal)
        }
        if !confident {
            // Not sure: ask, with the likely answers first.
            if extent < 30 { return StrokeRecognition(guess: .shortMark(center: center), ranked: ranked, confident: false) }
            if case .roundShape = guess { return StrokeRecognition(guess: guess, ranked: ranked, confident: false) }
            return StrokeRecognition(guess: .unknown(bounds: bounds), ranked: ranked, confident: false)
        }
        return StrokeRecognition(guess: guess, ranked: ranked, confident: true)
    }

    // MARK: Families and ranking

    /// What a template label stands for on the canvas.
    enum Family: Equatable {
        case resistor, inductor, round
        case kind(SketchElement.Kind)

        init(label: String) {
            switch label {
            case StrokeLibrary.zigzag, StrokeLibrary.box: self = .resistor
            case StrokeLibrary.coil: self = .inductor
            case StrokeLibrary.circle: self = .round
            default:
                if let kind = SketchElement.Kind(rawValue: label) {
                    switch kind {
                    case .resistor: self = .resistor
                    case .inductor: self = .inductor
                    case .voltageSource, .currentSource, .lamp, .battery: self = .round
                    default: self = .kind(kind)
                    }
                } else {
                    self = .round
                }
            }
        }
    }

    static let roundKinds: [SketchElement.Kind] = [.voltageSource, .currentSource, .lamp, .battery]

    /// Kinds in order of likelihood, every part present so a chooser built from it is complete.
    static func rankedKinds(_ families: [(family: Family, distance: Double)], library: StrokeLibrary) -> [SketchElement.Kind] {
        var result: [SketchElement.Kind] = []
        func add(_ kind: SketchElement.Kind) { if !result.contains(kind) { result.append(kind) } }
        let taughtRound = library.taughtKinds.filter { roundKinds.contains($0) }
        for entry in families {
            switch entry.family {
            case .resistor: add(.resistor)
            case .inductor: add(.inductor)
            case .round:
                for kind in (taughtRound + roundKinds).prefix(2) { add(kind) }
            case .kind(let kind): add(kind)
            }
        }
        for entry in families {
            if case .round = entry.family { for kind in taughtRound + roundKinds { add(kind) } }
        }
        for kind in SketchElement.Kind.parts { add(kind) }
        return result
    }

    // MARK: Shape features

    /// Scale-free facts about a stroke used to settle template ties.
    struct ShapeFeatures {
        let closed: Bool
        /// Share of all turning that happens in the sharpest quarter of the samples: corners (a
        /// zigzag, a box) concentrate it; arcs (humps, loops, circles) spread it out.
        let turnConcentration: CGFloat
        /// Times the stroke crosses its own track (cursive coil loops cross, zigzags never do).
        let crossings: Int
        /// Skewness of the sideways offsets about the stroke's own axis: an arch of humps piles its
        /// points near the tops with a tail down to the baseline (|skew| ≈ 0.4–0.9), while a zigzag
        /// or a sine wave is balanced (≈ 0). Robust to one hump being taller than the rest.
        let sideAsymmetry: CGFloat
        /// Where the sharp turns are: 1 when every cusp lies on one side of the axis (humps touch
        /// their baseline between arcs), 0 when they alternate sides (zigzag corners). nil without
        /// enough sharp turns to say (a smooth sine).
        let cuspImbalance: CGFloat?
        /// How much the stroke bows between consecutive extremes, as a fraction of the chord and
        /// signed toward one side: the quarter arcs of humps all bow away from the baseline (≈0.2),
        /// a zigzag's diagonals are straight (≈0) and a sine's S-curves cancel (≈0). nil without
        /// enough extremes.
        let arcBulge: CGFloat?
        /// Where the stroke's points sit within their sideways range: 0.5 for anything that spends
        /// as much time high as low (a zigzag, a sine), ≈0.64 for arcs standing on a baseline
        /// (a semicircle's points crowd near its top), well below 0.5 for humps with long leads.
        let offsetBalance: CGFloat
        /// Side-to-side reversals along the chord.
        let reversals: Int
        let circularity: CGFloat
        let straight: CGFloat
        /// Area of the outline over the area of its tightest axis box (searched over a few small
        /// tilts): π/4 ≈ 0.79 for a circle or oval, ≈ 0.95 for a box, even with rounded corners.
        let fill: CGFloat

        init(points: [CGPoint], closed: Bool, chord: CGFloat, first: CGPoint, last: CGPoint) {
            self.closed = closed
            let sixtyFour = StrokeRecognizer.resample(StrokeClassifier.smoothed(points, window: 3), count: 64)
            turnConcentration = StrokeClassifier.turnConcentration(sixtyFour)
            crossings = StrokeClassifier.selfCrossings(sixtyFour)
            sideAsymmetry = StrokeClassifier.sideAsymmetry(points, first: first, last: last)
            // Cusp shapes are read off the raw offsets at finer resolution: smoothing would round
            // the very cusps that tell humps from a zigzag.
            let ninetySix = StrokeRecognizer.resample(points, count: 96)
            cuspImbalance = StrokeClassifier.cuspImbalance(ninetySix, first: first, last: last)
            arcBulge = StrokeClassifier.arcBulge(ninetySix, first: first, last: last)
            offsetBalance = StrokeClassifier.offsetBalance(StrokeClassifier.smoothed(points, window: 5), first: first, last: last)
            reversals = chord > 24 ? StrokeClassifier.sidewaysReversals(points, from: first, to: last, threshold: 4) : 0
            let smooth = StrokeClassifier.smoothed(points, window: 5)
            if closed {
                let area = abs(StrokeClassifier.shoelace(smooth))
                let length = zip(smooth, smooth.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
                circularity = length > 0 ? 4 * .pi * area / (length * length) : 0
                straight = StrokeClassifier.straightFraction(smooth)
                fill = StrokeClassifier.fillRatio(smooth, area: area)
            } else {
                circularity = 0
                straight = 0
                fill = 0
            }
        }
    }

    /// Nudges template distances with the shape facts (multiplying keeps the ranking coherent).
    static func adjust(_ distances: inout [String: Double], with f: ShapeFeatures) {
        func scale(_ label: String, _ factor: Double) { if let d = distances[label] { distances[label] = d * factor } }
        if f.closed {
            scale(StrokeLibrary.zigzag, 1.6)
            scale(StrokeLibrary.coil, 1.6)
            if f.fill >= 0.84 { scale(StrokeLibrary.box, 0.5); scale(StrokeLibrary.circle, 1.6) }
            else if f.fill <= 0.80 { scale(StrokeLibrary.circle, 0.6); scale(StrokeLibrary.box, 1.5) }
            else if f.straight > 0.35 { scale(StrokeLibrary.box, 0.8) }
            if f.turnConcentration > 0.7 { scale(StrokeLibrary.box, 0.85) }
            if f.turnConcentration < 0.4 { scale(StrokeLibrary.circle, 0.85) }
        } else {
            scale(StrokeLibrary.box, 1.3)
            scale(StrokeLibrary.circle, 1.3)
            if f.reversals < 2 {
                // No side-to-side motion: neither a zigzag nor a coil.
                scale(StrokeLibrary.zigzag, 1.5)
                scale(StrokeLibrary.coil, 1.5)
            } else if f.crossings >= 2 {
                // The pen crossed its own track: cursive coil loops.
                scale(StrokeLibrary.coil, 0.5); scale(StrokeLibrary.zigzag, 1.6)
            } else if let cusps = f.cuspImbalance, cusps >= 0.3 {
                // Cusps on one side, arcs on the other: humps standing on a baseline.
                scale(StrokeLibrary.coil, 0.5); scale(StrokeLibrary.zigzag, 1.6)
            } else if let bulge = f.arcBulge, bulge >= 0.06 {
                // Every stretch between extremes bows the same way: arcs, not diagonals.
                scale(StrokeLibrary.coil, 0.5); scale(StrokeLibrary.zigzag, 1.6)
            } else if let cusps = f.cuspImbalance, cusps <= 0.15 {
                // Both sides shaped alike: a zigzag (or a sine, which most people draw for a resistor).
                scale(StrokeLibrary.zigzag, 0.6); scale(StrokeLibrary.coil, 1.5)
            } else if let bulge = f.arcBulge, bulge <= 0.03 {
                // Straight (or S-shaped) between extremes: a zigzag or a sine.
                scale(StrokeLibrary.zigzag, 0.7); scale(StrokeLibrary.coil, 1.4)
            }
        }
    }

    /// Share of the total turning carried by the sharpest quarter of the samples.
    static func turnConcentration(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 8 else { return 0 }
        var turns: [CGFloat] = []
        for i in 1..<(points.count - 1) {
            let p = points[i - 1], q = points[i], r = points[i + 1]
            let inbound = atan2(q.y - p.y, q.x - p.x), outbound = atan2(r.y - q.y, r.x - q.x)
            var turn = abs(outbound - inbound)
            if turn > .pi { turn = 2 * .pi - turn }
            turns.append(turn)
        }
        let total = turns.reduce(0, +)
        guard total > 0 else { return 0 }
        let quarter = turns.sorted(by: >).prefix(max(turns.count / 4, 1)).reduce(0, +)
        return quarter / total
    }

    /// Number of times non-neighbouring segments of the polyline cross.
    static func selfCrossings(_ points: [CGPoint]) -> Int {
        guard points.count >= 4 else { return 0 }
        func orientation(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat { (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) }
        var count = 0
        for i in 0..<(points.count - 3) {
            let a = points[i], b = points[i + 1]
            for j in (i + 2)..<(points.count - 1) {
                let c = points[j], d = points[j + 1]
                let o1 = orientation(a, b, c), o2 = orientation(a, b, d), o3 = orientation(c, d, a), o4 = orientation(c, d, b)
                if o1 * o2 < 0, o3 * o4 < 0 { count += 1 }
            }
        }
        return count
    }

    /// How much sharper the stroke's extremes are on one side of its axis than on the other. At
    /// each interior extreme of the sideways offset the profile a quarter of the way toward the
    /// neighbouring extremes is compared with the extreme itself: a cusp (a V) has already climbed
    /// ~40% of the way back, an arc top only ~8%, a zigzag corner ~25%, a sine crest ~15%. Humps
    /// have cusps on one side and arcs on the other (≈0.6); anything symmetric gives ≈0. nil with
    /// fewer than three clear extremes. Works on offsets, so finger jitter hardly moves it.
    static func cuspImbalance(_ points: [CGPoint], first: CGPoint, last: CGPoint) -> CGFloat? {
        guard points.count >= 12 else { return nil }
        let dx = last.x - first.x, dy = last.y - first.y
        let length: CGFloat = max(CGFloat(hypot(dx, dy)), 0.001)
        let n = CGFloat(points.count)
        let cx = points.map(\.x).reduce(0, +) / n, cy = points.map(\.y).reduce(0, +) / n
        let o = points.map { (($0.x - cx) * dy - ($0.y - cy) * dx) / length }
        guard let lo = o.min(), let hi = o.max(), hi - lo > 2 else { return nil }
        let prominence = 0.2 * (hi - lo)
        // Alternating extremes with at least `prominence` between them.
        var extremes: [Int] = []
        var direction = 0
        var candidate = 0
        for i in 1..<o.count {
            if direction == 0 {
                if abs(o[i] - o[candidate]) > prominence { direction = o[i] > o[candidate] ? 1 : -1; candidate = i }
            } else if (direction > 0 && o[i] > o[candidate]) || (direction < 0 && o[i] < o[candidate]) {
                candidate = i
            } else if abs(o[i] - o[candidate]) > prominence {
                extremes.append(candidate)
                direction = -direction
                candidate = i
            }
        }
        guard extremes.count >= 3 else { return nil }
        var highSum: CGFloat = 0, highCount: CGFloat = 0, lowSum: CGFloat = 0, lowCount: CGFloat = 0
        for k in 1..<(extremes.count - 1) {
            let e = extremes[k], before = extremes[k - 1], after = extremes[k + 1]
            let reach = max(1, min(e - before, after - e) / 4)
            let neighbours = (o[before] + o[after]) / 2
            let depth = neighbours - o[e]
            guard abs(depth) > 1 else { continue }
            let climbed = ((o[e - reach] + o[e + reach]) / 2 - o[e]) / depth
            if o[e] >= neighbours { highSum += max(climbed, 0); highCount += 1 } else { lowSum += max(climbed, 0); lowCount += 1 }
        }
        guard highCount > 0, lowCount > 0 else { return nil }
        let high = highSum / highCount, low = lowSum / lowCount
        guard high + low > 0.05 else { return nil }
        return abs(high - low) / (high + low)
    }

    /// Outline area over the smallest bounding box found among small tilts (−20°…20°), so a hand
    /// that draws its boxes slightly askew still gets a box.
    static func fillRatio(_ points: [CGPoint], area: CGFloat) -> CGFloat {
        guard points.count >= 4, area > 0 else { return 0 }
        var smallest = CGFloat.infinity
        for degrees in stride(from: -20.0, through: 20.0, by: 5.0) {
            let angle = CGFloat(degrees) * .pi / 180
            let c = cos(angle), s = sin(angle)
            var minX = CGFloat.infinity, minY = CGFloat.infinity, maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
            for p in points {
                let x = p.x * c - p.y * s, y = p.x * s + p.y * c
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
            smallest = min(smallest, (maxX - minX) * (maxY - minY))
        }
        return smallest > 0 ? min(area / smallest, 1) : 0
    }

    /// Interior extremes of the sideways offset with at least 20% of the range between them.
    static func offsetExtremes(_ o: [CGFloat]) -> [Int] {
        guard let lo = o.min(), let hi = o.max(), hi - lo > 2 else { return [] }
        let prominence = 0.2 * (hi - lo)
        var extremes: [Int] = []
        var direction = 0
        var candidate = 0
        for i in 1..<o.count {
            if direction == 0 {
                if abs(o[i] - o[candidate]) > prominence { direction = o[i] > o[candidate] ? 1 : -1; candidate = i }
            } else if (direction > 0 && o[i] > o[candidate]) || (direction < 0 && o[i] < o[candidate]) {
                candidate = i
            } else if abs(o[i] - o[candidate]) > prominence {
                extremes.append(candidate)
                direction = -direction
                candidate = i
            }
        }
        return extremes
    }

    /// Mean signed bow of the stroke between consecutive extremes (midpoint's distance from the
    /// chord over the chord length, positive toward increasing offset), as an absolute value.
    static func arcBulge(_ points: [CGPoint], first: CGPoint, last: CGPoint) -> CGFloat? {
        guard points.count >= 12 else { return nil }
        let dx = last.x - first.x, dy = last.y - first.y
        let length = max(CGFloat(hypot(dx, dy)), 0.001)
        let n = CGFloat(points.count)
        let cx = points.map(\.x).reduce(0, +) / n, cy = points.map(\.y).reduce(0, +) / n
        let o = points.map { (($0.x - cx) * dy - ($0.y - cy) * dx) / length }
        let extremes = offsetExtremes(o)
        guard extremes.count >= 3 else { return nil }
        let normal = CGPoint(x: dy / length, y: -dx / length)   // the direction offsets grow in
        var sum: CGFloat = 0
        var count: CGFloat = 0
        for k in 0..<(extremes.count - 1) {
            let a = points[extremes[k]], b = points[extremes[k + 1]]
            let m = points[(extremes[k] + extremes[k + 1]) / 2]
            let chord = max(CGFloat(hypot(b.x - a.x, b.y - a.y)), 0.001)
            let ux = (b.x - a.x) / chord, uy = (b.y - a.y) / chord
            // Signed distance of the midpoint from the chord, sign taken along `normal`.
            let deviation = (m.x - a.x) * uy - (m.y - a.y) * ux
            let side: CGFloat = (-uy * normal.x + ux * normal.y) >= 0 ? 1 : -1
            sum += side * deviation / chord
            count += 1
        }
        return count > 0 ? abs(sum / count) : nil
    }

    /// Mean position of the points within their sideways range about the axis through the centroid
    /// (0 = everything at one extreme, 0.5 = evenly spread).
    static func offsetBalance(_ points: [CGPoint], first: CGPoint, last: CGPoint) -> CGFloat {
        let dx = last.x - first.x, dy = last.y - first.y
        let length: CGFloat = max(CGFloat(hypot(dx, dy)), 0.001)
        let n = CGFloat(points.count)
        guard n >= 8 else { return 0.5 }
        let cx = points.map(\.x).reduce(0, +) / n, cy = points.map(\.y).reduce(0, +) / n
        let offsets = points.map { (($0.x - cx) * dy - ($0.y - cy) * dx) / length }
        guard let lo = offsets.min(), let hi = offsets.max(), hi - lo > 2 else { return 0.5 }
        return (offsets.reduce(0, +) / n - lo) / (hi - lo)
    }

    /// Absolute skewness of the sideways offsets about the axis through the centroid (direction of
    /// the chord): 0 for anything symmetric about its axis, larger the more one-sided the stroke is.
    static func sideAsymmetry(_ points: [CGPoint], first: CGPoint, last: CGPoint) -> CGFloat {
        let dx = last.x - first.x, dy = last.y - first.y
        let length: CGFloat = max(CGFloat(hypot(dx, dy)), 0.001)
        let n = CGFloat(points.count)
        guard n >= 8 else { return 0 }
        let cx = points.map(\.x).reduce(0, +) / n, cy = points.map(\.y).reduce(0, +) / n
        let offsets = points.map { (($0.x - cx) * dy - ($0.y - cy) * dx) / length }
        let mean = offsets.reduce(0, +) / n
        let variance = offsets.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n
        guard variance > 0.25 else { return 0 }
        let third = offsets.reduce(0) { $0 + ($1 - mean) * ($1 - mean) * ($1 - mean) } / n
        return abs(third) / pow(variance, 1.5)
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
        let length: CGFloat = max(CGFloat(hypot(dx, dy)), 0.001)
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

    /// RDP for a route: split first at the point farthest from the start, so a U's far corner is
    /// a vertex from the outset and its other corners stand well clear of the sub-chords (plain RDP
    /// starts from the start–end chord, which runs almost parallel to a U's bottom, and then a
    /// jitter bump can outrank the real corner beside it).
    static func simplifyPath(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 3, let first = points.first else { return simplify(points, epsilon: epsilon) }
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

    /// True when the end of the stroke lands back on its beginning (or the start on its end): an
    /// outline drawn past its starting point.
    static func returnsToStart(_ points: [CGPoint], extent: CGFloat) -> Bool {
        guard points.count >= 12 else { return false }
        let tolerance = max(0.1 * extent, 5)
        let head = points[0..<(points.count * 3 / 10)]
        let tail = points[(points.count * 7 / 10)...]
        func near(_ p: CGPoint, _ group: ArraySlice<CGPoint>) -> Bool { group.contains { hypot($0.x - p.x, $0.y - p.y) <= tolerance } }
        return near(points[points.count - 1], head) || near(points[0], tail)
    }

    /// Drops interior corners that barely turn: RDP keeps whichever point of a flat side bulges
    /// most from the first chord, which is no corner at all.
    static func withoutShallowCorners(_ corners: [CGPoint], minimumTurn: CGFloat) -> [CGPoint] {
        guard corners.count > 2 else { return corners }
        var result = [corners[0]]
        for i in 1..<(corners.count - 1) {
            let p = result[result.count - 1], q = corners[i], r = corners[i + 1]
            let inbound = atan2(q.y - p.y, q.x - p.x), outbound = atan2(r.y - q.y, r.x - q.x)
            var turn = abs(outbound - inbound)
            if turn > .pi { turn = 2 * .pi - turn }
            if turn >= minimumTurn { result.append(q) }
        }
        result.append(corners[corners.count - 1])
        return result
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

    /// An orthogonal polyline that reads as wiring: segments on average close to the axes (a steep
    /// zigzag leans the same way everywhere), corners that really turn (an open circle's chords
    /// only bend a little), and no segment running back over another (an overshooting box).
    static func isWirePath(_ corners: [CGPoint], minimumSegment: CGFloat) -> Bool {
        guard isOrthogonalPolyline(corners, minimumSegment: minimumSegment) else { return false }
        var leanSum: CGFloat = 0
        for (a, b) in zip(corners, corners.dropFirst()) {
            let dx = abs(b.x - a.x), dy = abs(b.y - a.y)
            leanSum += atan2(min(dx, dy), max(dx, dy))
        }
        guard leanSum / CGFloat(corners.count - 1) <= 20 * .pi / 180 else { return false }
        for i in 1..<(corners.count - 1) {
            let p = corners[i - 1], q = corners[i], r = corners[i + 1]
            let inbound = atan2(q.y - p.y, q.x - p.x), outbound = atan2(r.y - q.y, r.x - q.x)
            var turn = abs(outbound - inbound)
            if turn > .pi { turn = 2 * .pi - turn }
            if turn < 70 * .pi / 180 { return false }
        }
        // Collinear segments that overlap along their shared line: the stroke came back over itself.
        let segments = Array(zip(corners, corners.dropFirst()))
        for i in segments.indices {
            for j in (i + 1)..<segments.count {
                let (a, b) = segments[i], (c, d) = segments[j]
                let horizontalI = abs(b.x - a.x) >= abs(b.y - a.y), horizontalJ = abs(d.x - c.x) >= abs(d.y - c.y)
                guard horizontalI == horizontalJ else { continue }
                let lineI = horizontalI ? (a.y + b.y) / 2 : (a.x + b.x) / 2
                let lineJ = horizontalJ ? (c.y + d.y) / 2 : (c.x + d.x) / 2
                guard abs(lineI - lineJ) <= 10 else { continue }
                let (lo1, hi1) = horizontalI ? (min(a.x, b.x), max(a.x, b.x)) : (min(a.y, b.y), max(a.y, b.y))
                let (lo2, hi2) = horizontalJ ? (min(c.x, d.x), max(c.x, d.x)) : (min(c.y, d.y), max(c.y, d.y))
                if min(hi1, hi2) - max(lo1, lo2) > 10 { return false }
            }
        }
        return true
    }

    /// True when the stroke never crosses more than `tolerance` to the other side of its chord.
    static func isOneSided(_ points: [CGPoint], from a: CGPoint, to b: CGPoint, tolerance: CGFloat) -> Bool {
        let dx = b.x - a.x, dy = b.y - a.y
        let length: CGFloat = max(CGFloat(hypot(dx, dy)), 0.001)
        let offsets = points.map { (($0.x - a.x) * dy - ($0.y - a.y) * dx) / length }
        guard let lo = offsets.min(), let hi = offsets.max() else { return false }
        return lo >= -tolerance || hi <= tolerance
    }

    static func sidewaysReversals(_ points: [CGPoint], from a: CGPoint, to b: CGPoint, threshold: CGFloat) -> Int {
        let dx = b.x - a.x, dy = b.y - a.y
        let length: CGFloat = max(CGFloat(hypot(dx, dy)), 0.001)
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
