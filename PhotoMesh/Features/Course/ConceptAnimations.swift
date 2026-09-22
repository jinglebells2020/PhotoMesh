import SwiftUI

/// Drawn explanations for the lessons: charge moving in a wire, voltage as height, Kirchhoff's
/// laws as counting and climbing, energy storing up in capacitors and coils, phasors turning.
/// Each is a clock-driven Canvas on a 320 × 230 logical canvas, scaled to fit.
struct ConceptAnimationView: View {
    let kind: ConceptAnimation

    var body: some View {
        DemoPlayer(duration: ConceptAnimationView.duration(kind), autoplay: true) { phase, _ in
            Canvas { context, size in
                let scale = min(size.width / 320, size.height / 230)
                context.translateBy(x: (size.width - 320 * scale) / 2, y: (size.height - 230 * scale) / 2)
                context.scaleBy(x: scale, y: scale)
                context.fill(Path(CGRect(x: 0, y: 0, width: 320, height: 230)), with: .color(.white))
                ConceptDrawing.draw(kind, phase: phase, in: &context)
            }
            .background(Color.white)
        }
    }

    static func duration(_ kind: ConceptAnimation) -> Double {
        switch kind {
        case .waterJunction, .kclJunction, .seriesBulbs, .parallelBulbs: return 5
        case .waterTank: return 7
        case .waterOhm, .waterWheel: return 8
        case .superposition: return 9
        case .theveninBox: return 7
        default: return 6
        }
    }
}

// MARK: - Drawing helpers

enum ConceptDrawing {
    static let ink = Color(red: 0.12, green: 0.12, blue: 0.14)
    static let green = PMTheme.accent
    static let blue = Color(red: 0.18, green: 0.46, blue: 0.92)
    static let orange = Color(red: 0.96, green: 0.42, blue: 0.16)
    static let grey = Color(red: 0.62, green: 0.62, blue: 0.66)
    static let faint = Color(red: 0.85, green: 0.86, blue: 0.9)

    static func stroke(_ ctx: inout GraphicsContext, _ path: Path, _ color: Color, _ width: CGFloat = 2, dash: [CGFloat] = []) {
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash))
    }

    static func line(_ ctx: inout GraphicsContext, _ a: CGPoint, _ b: CGPoint, _ color: Color = ink, _ width: CGFloat = 2, dash: [CGFloat] = []) {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        stroke(&ctx, p, color, width, dash: dash)
    }

    static func polyline(_ ctx: inout GraphicsContext, _ points: [CGPoint], _ color: Color = ink, _ width: CGFloat = 2, closed: Bool = false) {
        guard let first = points.first else { return }
        var p = Path()
        p.move(to: first)
        for point in points.dropFirst() { p.addLine(to: point) }
        if closed { p.closeSubpath() }
        stroke(&ctx, p, color, width)
    }

    static func dot(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ color: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
    }

    static func ring(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ color: Color, _ width: CGFloat = 2) {
        stroke(&ctx, Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), color, width)
    }

    static func text(_ ctx: inout GraphicsContext, _ s: String, at p: CGPoint, size: CGFloat = 11, weight: Font.Weight = .medium, color: Color = ink, anchor: UnitPoint = .center) {
        ctx.draw(Text(s).font(.system(size: size, weight: weight, design: .rounded)).foregroundStyle(color), at: p, anchor: anchor)
    }

    static func arrow(_ ctx: inout GraphicsContext, from a: CGPoint, to b: CGPoint, _ color: Color, _ width: CGFloat = 2) {
        line(&ctx, a, b, color, width)
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max((dx * dx + dy * dy).squareRoot(), 0.001)
        let u = CGPoint(x: dx / len, y: dy / len), n = CGPoint(x: -u.y, y: u.x)
        var head = Path()
        head.move(to: b)
        head.addLine(to: CGPoint(x: b.x - u.x * 8 + n.x * 4.5, y: b.y - u.y * 8 + n.y * 4.5))
        head.addLine(to: CGPoint(x: b.x - u.x * 8 - n.x * 4.5, y: b.y - u.y * 8 - n.y * 4.5))
        head.closeSubpath()
        ctx.fill(head, with: .color(color))
    }

    /// Resistor zigzag between two points.
    static func resistor(_ ctx: inout GraphicsContext, _ a: CGPoint, _ b: CGPoint, _ color: Color = ink) {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max((dx * dx + dy * dy).squareRoot(), 0.001)
        let u = CGPoint(x: dx / len, y: dy / len), n = CGPoint(x: -u.y, y: u.x)
        let lead = len * 0.22
        var points = [a, CGPoint(x: a.x + u.x * lead, y: a.y + u.y * lead)]
        let peaks = 6
        let seg = (len - 2 * lead) / CGFloat(peaks + 1)
        for i in 1...peaks {
            let side: CGFloat = i % 2 == 1 ? 1 : -1
            let along = lead + seg * CGFloat(i)
            points.append(CGPoint(x: a.x + u.x * along + n.x * 7 * side, y: a.y + u.y * along + n.y * 7 * side))
        }
        points.append(CGPoint(x: b.x - u.x * lead, y: b.y - u.y * lead))
        points.append(b)
        polyline(&ctx, points, color)
    }

    /// Battery plates centred on `c`, plates perpendicular to the direction from `c` toward `plus`.
    static func battery(_ ctx: inout GraphicsContext, at c: CGPoint, vertical: Bool, color: Color = ink) {
        if vertical {
            line(&ctx, CGPoint(x: c.x - 14, y: c.y - 4), CGPoint(x: c.x + 14, y: c.y - 4), color, 2.5)
            line(&ctx, CGPoint(x: c.x - 7, y: c.y + 4), CGPoint(x: c.x + 7, y: c.y + 4), color, 2.5)
            text(&ctx, "+", at: CGPoint(x: c.x + 20, y: c.y - 7), size: 10, weight: .bold, color: color)
            text(&ctx, "−", at: CGPoint(x: c.x + 20, y: c.y + 7), size: 10, weight: .bold, color: color)
        } else {
            line(&ctx, CGPoint(x: c.x - 4, y: c.y - 14), CGPoint(x: c.x - 4, y: c.y + 14), color, 2.5)
            line(&ctx, CGPoint(x: c.x + 4, y: c.y - 7), CGPoint(x: c.x + 4, y: c.y + 7), color, 2.5)
        }
    }

    static func capacitor(_ ctx: inout GraphicsContext, at c: CGPoint, color: Color = ink) {
        line(&ctx, CGPoint(x: c.x - 14, y: c.y - 5), CGPoint(x: c.x + 14, y: c.y - 5), color, 2.5)
        line(&ctx, CGPoint(x: c.x - 14, y: c.y + 5), CGPoint(x: c.x + 14, y: c.y + 5), color, 2.5)
    }

    static func coil(_ ctx: inout GraphicsContext, _ a: CGPoint, _ b: CGPoint, color: Color = ink) {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max((dx * dx + dy * dy).squareRoot(), 0.001)
        let u = CGPoint(x: dx / len, y: dy / len), n = CGPoint(x: -u.y, y: u.x)
        let lead = len * 0.2
        var p = Path()
        p.move(to: a)
        let start = CGPoint(x: a.x + u.x * lead, y: a.y + u.y * lead)
        p.addLine(to: start)
        let humps = 4
        let w = (len - 2 * lead) / CGFloat(humps)
        for i in 0..<humps {
            let from = CGPoint(x: start.x + u.x * w * CGFloat(i), y: start.y + u.y * w * CGFloat(i))
            let to = CGPoint(x: from.x + u.x * w, y: from.y + u.y * w)
            p.addCurve(to: to, control1: CGPoint(x: from.x + n.x * w * 1.2, y: from.y + n.y * w * 1.2), control2: CGPoint(x: to.x + n.x * w * 1.2, y: to.y + n.y * w * 1.2))
        }
        p.addLine(to: b)
        stroke(&ctx, p, color)
    }

    static func bulb(_ ctx: inout GraphicsContext, at c: CGPoint, glow: Double, color: Color = ink) {
        if glow > 0.02 {
            for k in stride(from: 3, through: 1, by: -1) {
                let r = 12 + CGFloat(k) * 6 * CGFloat(glow)
                dot(&ctx, c, r, Color(red: 1, green: 0.78, blue: 0.2).opacity(0.12 * glow))
            }
        }
        ring(&ctx, c, 12, color)
        line(&ctx, CGPoint(x: c.x - 8, y: c.y - 8), CGPoint(x: c.x + 8, y: c.y + 8), color, 1.5)
        line(&ctx, CGPoint(x: c.x + 8, y: c.y - 8), CGPoint(x: c.x - 8, y: c.y + 8), color, 1.5)
    }

    /// Dots moving along a polyline, `speed` logical units per second, positive from the first point on.
    static func flow(_ ctx: inout GraphicsContext, along points: [CGPoint], phase: Double, speed: Double, color: Color, spacing: Double = 22, radius: CGFloat = 3.2) {
        guard points.count >= 2 else { return }
        var cumulative: [Double] = [0]
        for (a, b) in zip(points, points.dropFirst()) {
            let d = Double(((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot())
            cumulative.append(cumulative[cumulative.count - 1] + d)
        }
        let length = cumulative[cumulative.count - 1]
        guard length > 1 else { return }
        var s = (phase * speed).truncatingRemainder(dividingBy: spacing)
        if s < 0 { s += spacing }
        while s < length {
            var index = 1
            while index < cumulative.count - 1, cumulative[index] < s { index += 1 }
            let a = points[index - 1], b = points[index]
            let seg = cumulative[index] - cumulative[index - 1]
            let t = seg > 0 ? CGFloat((s - cumulative[index - 1]) / seg) : 0
            dot(&ctx, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), radius, color)
            s += spacing
        }
    }

    /// Axes with a plotted function; returns the mapping used so a cursor can be drawn.
    static func plot(_ ctx: inout GraphicsContext, frame: CGRect, xMax: Double, yMin: Double, yMax: Double, xLabel: String, yLabel: String, curve: (Double) -> Double, color: Color, upTo: Double? = nil) -> (Double, Double) -> CGPoint {
        func map(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: frame.minX + CGFloat(x / xMax) * frame.width, y: frame.maxY - CGFloat((y - yMin) / (yMax - yMin)) * frame.height)
        }
        line(&ctx, CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.maxY), grey, 1.2)
        line(&ctx, CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.minX, y: frame.minY), grey, 1.2)
        text(&ctx, xLabel, at: CGPoint(x: frame.maxX, y: frame.maxY + 10), size: 9, color: grey, anchor: .topTrailing)
        text(&ctx, yLabel, at: CGPoint(x: frame.minX + 2, y: frame.minY - 2), size: 9, color: grey, anchor: .bottomLeading)
        let limit = upTo ?? xMax
        var p = Path()
        let steps = 120
        for i in 0...steps {
            let x = limit * Double(i) / Double(steps)
            let point = map(x, curve(x))
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        stroke(&ctx, p, color, 2.2)
        return map
    }

    // MARK: - Dispatch

    static func draw(_ kind: ConceptAnimation, phase: Double, in ctx: inout GraphicsContext) {
        switch kind {
        case .waterLoop: waterLoop(&ctx, phase)
        case .waterPressure: waterPressure(&ctx, phase)
        case .waterFlowRate: waterFlowRate(&ctx, phase)
        case .waterNarrowPipe: waterNarrowPipe(&ctx, phase)
        case .waterPump: waterPump(&ctx, phase)
        case .waterValve: waterValve(&ctx, phase)
        case .waterOhm: waterOhm(&ctx, phase)
        case .waterJunction: waterJunction(&ctx, phase)
        case .waterSeries: waterSeries(&ctx, phase)
        case .waterParallel: waterParallel(&ctx, phase)
        case .waterTank: waterTank(&ctx, phase)
        case .waterWheel: waterWheel(&ctx, phase)
        case .chargeFlow: chargeFlow(&ctx, phase)
        case .potentialHill: potentialHill(&ctx, phase)
        case .powerBalance: powerBalance(&ctx, phase)
        case .ohmLine: ohmLine(&ctx, phase)
        case .kclJunction: kclJunction(&ctx, phase)
        case .kvlStaircase: kvlStaircase(&ctx, phase)
        case .seriesBulbs: bulbs(&ctx, phase, series: true)
        case .parallelBulbs: bulbs(&ctx, phase, series: false)
        case .voltageDivider: voltageDivider(&ctx, phase)
        case .capacitorCharging: capacitor(&ctx, phase, charging: true)
        case .capacitorDischarging: capacitor(&ctx, phase, charging: false)
        case .inductorRise: inductorRise(&ctx, phase)
        case .rlcRinging: rlcRinging(&ctx, phase)
        case .timeConstant: timeConstant(&ctx, phase)
        case .superposition: superposition(&ctx, phase)
        case .theveninBox: theveninBox(&ctx, phase)
        case .maxPower: maxPower(&ctx, phase)
        case .sineWave: sineWave(&ctx, phase)
        case .phasor: phasor(&ctx, phase)
        case .impedanceTriangle: impedanceTriangle(&ctx, phase)
        case .wyeDelta: wyeDelta(&ctx, phase)
        }
    }

    // MARK: - Basic concepts

    /// A loop with a battery and a resistor: conventional current one way, electrons the other.
    static func chargeFlow(_ ctx: inout GraphicsContext, _ phase: Double) {
        let loop = [CGPoint(x: 50, y: 50), CGPoint(x: 270, y: 50), CGPoint(x: 270, y: 175), CGPoint(x: 50, y: 175), CGPoint(x: 50, y: 50)]
        // Wires with gaps for the battery (left) and the resistor (right).
        line(&ctx, CGPoint(x: 50, y: 50), CGPoint(x: 270, y: 50))
        line(&ctx, CGPoint(x: 50, y: 175), CGPoint(x: 270, y: 175))
        line(&ctx, CGPoint(x: 50, y: 50), CGPoint(x: 50, y: 98))
        line(&ctx, CGPoint(x: 50, y: 126), CGPoint(x: 50, y: 175))
        battery(&ctx, at: CGPoint(x: 50, y: 112), vertical: true)
        line(&ctx, CGPoint(x: 270, y: 50), CGPoint(x: 270, y: 80))
        resistor(&ctx, CGPoint(x: 270, y: 80), CGPoint(x: 270, y: 145))
        line(&ctx, CGPoint(x: 270, y: 145), CGPoint(x: 270, y: 175))
        // Conventional current: out of +, clockwise.
        flow(&ctx, along: loop, phase: phase, speed: 60, color: green)
        // Electrons: the other way, fewer and fainter.
        flow(&ctx, along: Array(loop.reversed()), phase: phase, speed: 36, color: blue.opacity(0.55), spacing: 34, radius: 2.4)
        arrow(&ctx, from: CGPoint(x: 120, y: 38), to: CGPoint(x: 200, y: 38), green)
        text(&ctx, "conventional current I", at: CGPoint(x: 160, y: 26), size: 10, color: green)
        arrow(&ctx, from: CGPoint(x: 200, y: 190), to: CGPoint(x: 120, y: 190), blue)
        text(&ctx, "electrons drift the other way", at: CGPoint(x: 160, y: 204), size: 10, color: blue)
        let coulombs = Int(phase)
        text(&ctx, "I = 1 A: one coulomb passes every second", at: CGPoint(x: 160, y: 100), size: 11, weight: .semibold)
        text(&ctx, "\(coulombs) C have passed the resistor", at: CGPoint(x: 160, y: 118), size: 11, color: grey)
        text(&ctx, "R", at: CGPoint(x: 290, y: 112), size: 11, weight: .semibold)
        text(&ctx, "9 V", at: CGPoint(x: 20, y: 112), size: 11, weight: .semibold)
    }

    /// Voltage as height: the source lifts each coulomb, the resistor lets it fall.
    static func potentialHill(_ ctx: inout GraphicsContext, _ phase: Double) {
        let top: CGFloat = 60, bottom: CGFloat = 185
        // Ground level and 9 V level
        line(&ctx, CGPoint(x: 30, y: bottom), CGPoint(x: 300, y: bottom), faint, 1, dash: [4, 4])
        line(&ctx, CGPoint(x: 30, y: top), CGPoint(x: 300, y: top), faint, 1, dash: [4, 4])
        text(&ctx, "0 V", at: CGPoint(x: 305, y: bottom), size: 10, color: grey, anchor: .leading)
        text(&ctx, "9 V", at: CGPoint(x: 305, y: top), size: 10, color: grey, anchor: .leading)
        // Path: up the source, across the top, down the resistor slope, back along the bottom.
        let path = [CGPoint(x: 60, y: bottom), CGPoint(x: 60, y: top), CGPoint(x: 190, y: top), CGPoint(x: 250, y: bottom), CGPoint(x: 60, y: bottom)]
        line(&ctx, CGPoint(x: 60, y: top), CGPoint(x: 190, y: top), ink, 2.5)
        line(&ctx, CGPoint(x: 250, y: bottom), CGPoint(x: 60, y: bottom), ink, 2.5)
        arrow(&ctx, from: CGPoint(x: 60, y: bottom - 6), to: CGPoint(x: 60, y: top + 6), green, 3)
        resistor(&ctx, CGPoint(x: 190, y: top), CGPoint(x: 250, y: bottom))
        text(&ctx, "source: lifts every coulomb by 9 J", at: CGPoint(x: 62, y: 122), size: 10, color: green, anchor: .leading)
        text(&ctx, "resistor: 9 J per coulomb", at: CGPoint(x: 258, y: 118), size: 10, anchor: .leading)
        text(&ctx, "becomes heat", at: CGPoint(x: 258, y: 131), size: 10, anchor: .leading)
        // Two charges on their way round.
        for offset in [0.0, 0.5] {
            let t = ((phase / 6) + offset).truncatingRemainder(dividingBy: 1)
            let total = 125.0 + 130.0 + 139.0 + 190.0
            var s = t * total
            var pos = path[0]
            for (a, b) in zip(path, path.dropFirst()) {
                let d = Double(((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot())
                if s <= d { let k = CGFloat(s / d); pos = CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k); break }
                s -= d
            }
            dot(&ctx, pos, 6, orange)
            text(&ctx, "+", at: pos, size: 9, weight: .bold, color: .white)
        }
        text(&ctx, "voltage = energy per coulomb, like height", at: CGPoint(x: 160, y: 212), size: 11, weight: .semibold)
    }

    /// The source delivers what the resistor absorbs.
    static func powerBalance(_ ctx: inout GraphicsContext, _ phase: Double) {
        let current = 0.5 + 0.5 * sin(phase * 2 * .pi / 6)
        let v = 12.0, r = 12.0
        let i = max(0.05, current)
        let p = v * i
        // Small circuit
        line(&ctx, CGPoint(x: 40, y: 60), CGPoint(x: 130, y: 60))
        line(&ctx, CGPoint(x: 40, y: 160), CGPoint(x: 130, y: 160))
        line(&ctx, CGPoint(x: 40, y: 60), CGPoint(x: 40, y: 96))
        line(&ctx, CGPoint(x: 40, y: 124), CGPoint(x: 40, y: 160))
        battery(&ctx, at: CGPoint(x: 40, y: 110), vertical: true)
        line(&ctx, CGPoint(x: 130, y: 60), CGPoint(x: 130, y: 80))
        resistor(&ctx, CGPoint(x: 130, y: 80), CGPoint(x: 130, y: 140))
        line(&ctx, CGPoint(x: 130, y: 140), CGPoint(x: 130, y: 160))
        flow(&ctx, along: [CGPoint(x: 40, y: 60), CGPoint(x: 130, y: 60), CGPoint(x: 130, y: 160), CGPoint(x: 40, y: 160), CGPoint(x: 40, y: 60)], phase: phase, speed: 30 + 60 * i, color: green)
        text(&ctx, "12 V", at: CGPoint(x: 14, y: 110), size: 10, weight: .semibold)
        text(&ctx, String(format: "I = %.2f A", i), at: CGPoint(x: 85, y: 48), size: 10, color: green)
        // Bars
        let base: CGFloat = 190, maxHeight: CGFloat = 120
        for (index, (label, value, color)) in [("delivered by the source", p, green), ("absorbed by the resistor", i * i * r, orange)].enumerated() {
            let x: CGFloat = 200 + CGFloat(index) * 60
            let h = CGFloat(value / 12) * maxHeight
            ctx.fill(Path(roundedRect: CGRect(x: x - 18, y: base - h, width: 36, height: h), cornerRadius: 4), with: .color(color.opacity(0.85)))
            text(&ctx, String(format: "%.1f W", value), at: CGPoint(x: x, y: base - h - 10), size: 10, weight: .semibold, color: color)
            text(&ctx, label, at: CGPoint(x: x, y: base + 12), size: 8.5, color: grey)
        }
        text(&ctx, "P = V · I = I² · R", at: CGPoint(x: 230, y: 40), size: 12, weight: .semibold)
    }

    /// I against V is a straight line through the origin; the slope is 1/R.
    static func ohmLine(_ ctx: inout GraphicsContext, _ phase: Double) {
        let frame = CGRect(x: 50, y: 30, width: 220, height: 150)
        let map = plot(&ctx, frame: frame, xMax: 12, yMin: 0, yMax: 0.12, xLabel: "V (volts)", yLabel: "I (amps)", curve: { $0 / 100 }, color: green)
        let faintMap = plot(&ctx, frame: frame, xMax: 12, yMin: 0, yMax: 0.12, xLabel: "", yLabel: "", curve: { $0 / 200 }, color: faint)
        text(&ctx, "R = 200 Ω", at: faintMap(12, 0.06), size: 9, color: grey, anchor: .bottomTrailing)
        text(&ctx, "R = 100 Ω", at: map(9, 0.09), size: 10, weight: .semibold, color: green, anchor: .bottomTrailing)
        let v = 6 + 6 * sin(phase * 2 * .pi / 6)
        let point = map(v, v / 100)
        line(&ctx, CGPoint(x: point.x, y: frame.maxY), point, grey, 1, dash: [3, 3])
        line(&ctx, CGPoint(x: frame.minX, y: point.y), point, grey, 1, dash: [3, 3])
        dot(&ctx, point, 5, orange)
        text(&ctx, String(format: "%.1f V", v), at: CGPoint(x: point.x, y: frame.maxY + 10), size: 10, weight: .semibold, color: orange)
        text(&ctx, String(format: "%.0f mA", v * 10), at: CGPoint(x: frame.minX - 4, y: point.y), size: 10, weight: .semibold, color: orange, anchor: .trailing)
        text(&ctx, "double the voltage, double the current: I = V / R", at: CGPoint(x: 160, y: 210), size: 11, weight: .semibold)
    }

    /// What flows in flows out.
    static func kclJunction(_ ctx: inout GraphicsContext, _ phase: Double) {
        let node = CGPoint(x: 150, y: 120)
        let inA = [CGPoint(x: 30, y: 60), CGPoint(x: 110, y: 120), node]
        let inB = [CGPoint(x: 30, y: 180), CGPoint(x: 110, y: 120), node]
        let out = [node, CGPoint(x: 290, y: 120)]
        polyline(&ctx, inA)
        polyline(&ctx, inB)
        polyline(&ctx, out)
        dot(&ctx, node, 5, ink)
        flow(&ctx, along: inA, phase: phase, speed: 40, color: green, spacing: 24)
        flow(&ctx, along: inB, phase: phase, speed: 60, color: green, spacing: 16)
        flow(&ctx, along: out, phase: phase, speed: 100, color: green, spacing: 10)
        text(&ctx, "2 A in", at: CGPoint(x: 40, y: 45), size: 11, weight: .semibold, color: green, anchor: .leading)
        text(&ctx, "3 A in", at: CGPoint(x: 40, y: 197), size: 11, weight: .semibold, color: green, anchor: .leading)
        text(&ctx, "5 A out", at: CGPoint(x: 250, y: 104), size: 11, weight: .semibold, color: green)
        text(&ctx, "charge cannot pile up at a node", at: CGPoint(x: 160, y: 30), size: 11, weight: .semibold)
        text(&ctx, "Σ I in = Σ I out:   2 A + 3 A = 5 A", at: CGPoint(x: 160, y: 212), size: 12, weight: .semibold, color: green)
    }

    /// Around a loop the potential climbs at the source and drops across each resistor, back to where it started.
    static func kvlStaircase(_ ctx: inout GraphicsContext, _ phase: Double) {
        // Loop on the left
        let a = CGPoint(x: 30, y: 60), b = CGPoint(x: 130, y: 60), c = CGPoint(x: 130, y: 180), d = CGPoint(x: 30, y: 180)
        line(&ctx, a, CGPoint(x: 55, y: 60)); resistor(&ctx, CGPoint(x: 55, y: 60), CGPoint(x: 105, y: 60)); line(&ctx, CGPoint(x: 105, y: 60), b)
        line(&ctx, b, CGPoint(x: 130, y: 90)); resistor(&ctx, CGPoint(x: 130, y: 90), CGPoint(x: 130, y: 150)); line(&ctx, CGPoint(x: 130, y: 150), c)
        line(&ctx, c, d)
        line(&ctx, d, CGPoint(x: 30, y: 134)); battery(&ctx, at: CGPoint(x: 30, y: 120), vertical: true); line(&ctx, CGPoint(x: 30, y: 106), a)
        text(&ctx, "12 V", at: CGPoint(x: 8, y: 120), size: 9, weight: .semibold)
        text(&ctx, "4 V", at: CGPoint(x: 80, y: 46), size: 9, weight: .semibold)
        text(&ctx, "8 V", at: CGPoint(x: 150, y: 120), size: 9, weight: .semibold)
        // Walker around the loop, starting at the battery's − end (d), clockwise: d → a → b → c → d
        let route = [d, a, b, c, d]
        let lengths: [Double] = [120, 100, 120, 100]
        let total = lengths.reduce(0, +)
        let t = (phase / 6).truncatingRemainder(dividingBy: 1)
        var s = t * total
        var pos = d
        var segment = 0
        for (i, (p, q)) in zip(route, route.dropFirst()).enumerated() {
            if s <= lengths[i] { let k = CGFloat(s / lengths[i]); pos = CGPoint(x: p.x + (q.x - p.x) * k, y: p.y + (q.y - p.y) * k); segment = i; break }
            s -= lengths[i]
        }
        dot(&ctx, pos, 5, orange)
        // Staircase on the right: potential against position along the walk.
        let frame = CGRect(x: 180, y: 40, width: 120, height: 140)
        func map(_ fraction: Double, _ volts: Double) -> CGPoint {
            CGPoint(x: frame.minX + CGFloat(fraction) * frame.width, y: frame.maxY - CGFloat(volts / 12) * frame.height)
        }
        line(&ctx, CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.maxY), grey, 1.2)
        // Profile: the battery is crossed in the first segment (rise), R1 in the second (drop 4), R2 in the third (drop 8), wire in the fourth.
        let profile: [(Double, Double)] = [(0, 0), (0.10, 0), (0.15, 12), (0.27, 12), (0.33, 12), (0.42, 8), (0.55, 8), (0.62, 8), (0.72, 0), (1.0, 0)]
        var path = Path()
        for (index, point) in profile.enumerated() {
            let p = map(point.0, point.1)
            if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        stroke(&ctx, path, green, 2.2)
        text(&ctx, "+12", at: map(0.13, 13.4), size: 9, weight: .semibold, color: green)
        text(&ctx, "−4", at: map(0.40, 10.6), size: 9, weight: .semibold, color: orange)
        text(&ctx, "−8", at: map(0.69, 4.4), size: 9, weight: .semibold, color: orange)
        text(&ctx, "0 V", at: CGPoint(x: frame.minX - 4, y: frame.maxY), size: 9, color: grey, anchor: .trailing)
        text(&ctx, "12 V", at: CGPoint(x: frame.minX - 4, y: frame.minY), size: 9, color: grey, anchor: .trailing)
        // Cursor on the profile
        let fraction = t
        var volts = 0.0
        for (p, q) in zip(profile, profile.dropFirst()) where fraction >= p.0 && fraction <= q.0 {
            let k = (fraction - p.0) / max(q.0 - p.0, 1e-9)
            volts = p.1 + (q.1 - p.1) * k
        }
        dot(&ctx, map(fraction, volts), 5, orange)
        _ = segment
        text(&ctx, "+12 − 4 − 8 = 0: back where it started", at: CGPoint(x: 160, y: 212), size: 11, weight: .semibold)
    }

    /// Two bulbs in series share the voltage and glow dimly; in parallel each gets the full voltage.
    static func bulbs(_ ctx: inout GraphicsContext, _ phase: Double, series: Bool) {
        line(&ctx, CGPoint(x: 40, y: 60), CGPoint(x: 40, y: 96)); line(&ctx, CGPoint(x: 40, y: 124), CGPoint(x: 40, y: 170))
        battery(&ctx, at: CGPoint(x: 40, y: 110), vertical: true)
        text(&ctx, "12 V", at: CGPoint(x: 14, y: 110), size: 10, weight: .semibold)
        if series {
            let loop = [CGPoint(x: 40, y: 60), CGPoint(x: 280, y: 60), CGPoint(x: 280, y: 170), CGPoint(x: 40, y: 170), CGPoint(x: 40, y: 60)]
            polyline(&ctx, loop)
            bulb(&ctx, at: CGPoint(x: 130, y: 60), glow: 0.35)
            bulb(&ctx, at: CGPoint(x: 210, y: 60), glow: 0.35)
            flow(&ctx, along: loop, phase: phase, speed: 40, color: green)
            text(&ctx, "6 V each · half the current · a quarter of the brightness", at: CGPoint(x: 160, y: 200), size: 10, weight: .semibold)
            text(&ctx, "I = 0.5 A everywhere", at: CGPoint(x: 160, y: 115), size: 11, color: green)
        } else {
            let outer = [CGPoint(x: 40, y: 60), CGPoint(x: 260, y: 60), CGPoint(x: 260, y: 170), CGPoint(x: 40, y: 170), CGPoint(x: 40, y: 60)]
            polyline(&ctx, outer)
            line(&ctx, CGPoint(x: 160, y: 60), CGPoint(x: 160, y: 170))
            dot(&ctx, CGPoint(x: 160, y: 60), 4, ink); dot(&ctx, CGPoint(x: 160, y: 170), 4, ink)
            bulb(&ctx, at: CGPoint(x: 160, y: 115), glow: 1)
            bulb(&ctx, at: CGPoint(x: 260, y: 115), glow: 1)
            flow(&ctx, along: [CGPoint(x: 40, y: 60), CGPoint(x: 160, y: 60)], phase: phase, speed: 80, color: green, spacing: 14)
            flow(&ctx, along: [CGPoint(x: 160, y: 60), CGPoint(x: 160, y: 170)], phase: phase, speed: 40, color: green, spacing: 22)
            flow(&ctx, along: [CGPoint(x: 160, y: 60), CGPoint(x: 260, y: 60), CGPoint(x: 260, y: 170)], phase: phase, speed: 40, color: green, spacing: 22)
            flow(&ctx, along: [CGPoint(x: 260, y: 170), CGPoint(x: 160, y: 170)], phase: phase, speed: 40, color: green, spacing: 22)
            flow(&ctx, along: [CGPoint(x: 160, y: 170), CGPoint(x: 40, y: 170), CGPoint(x: 40, y: 60)], phase: phase, speed: 80, color: green, spacing: 14)
            text(&ctx, "12 V across each · the current splits, 1 A + 1 A", at: CGPoint(x: 160, y: 200), size: 10, weight: .semibold)
            text(&ctx, "2 A", at: CGPoint(x: 100, y: 48), size: 10, color: green)
            text(&ctx, "1 A", at: CGPoint(x: 174, y: 90), size: 10, color: green)
            text(&ctx, "1 A", at: CGPoint(x: 274, y: 90), size: 10, color: green)
        }
    }

    /// Two resistors in series: the voltage divides in proportion to resistance.
    static func voltageDivider(_ ctx: inout GraphicsContext, _ phase: Double) {
        let r1 = 2.0
        let r2 = 1 + 4 * (0.5 - 0.5 * cos(phase * 2 * .pi / 6))   // 1 kΩ … 5 kΩ and back
        let v2 = 12 * r2 / (r1 + r2), v1 = 12 - v2
        line(&ctx, CGPoint(x: 50, y: 40), CGPoint(x: 50, y: 96)); line(&ctx, CGPoint(x: 50, y: 124), CGPoint(x: 50, y: 190))
        battery(&ctx, at: CGPoint(x: 50, y: 110), vertical: true)
        text(&ctx, "12 V", at: CGPoint(x: 24, y: 110), size: 10, weight: .semibold)
        line(&ctx, CGPoint(x: 50, y: 40), CGPoint(x: 150, y: 40))
        line(&ctx, CGPoint(x: 150, y: 40), CGPoint(x: 150, y: 50)); resistor(&ctx, CGPoint(x: 150, y: 50), CGPoint(x: 150, y: 105)); line(&ctx, CGPoint(x: 150, y: 105), CGPoint(x: 150, y: 125))
        resistor(&ctx, CGPoint(x: 150, y: 125), CGPoint(x: 150, y: 180)); line(&ctx, CGPoint(x: 150, y: 180), CGPoint(x: 150, y: 190))
        line(&ctx, CGPoint(x: 150, y: 190), CGPoint(x: 50, y: 190))
        text(&ctx, "R1 = 2 kΩ", at: CGPoint(x: 165, y: 78), size: 10, weight: .semibold, anchor: .leading)
        text(&ctx, String(format: "R2 = %.1f kΩ", r2), at: CGPoint(x: 165, y: 152), size: 10, weight: .semibold, anchor: .leading)
        // Bars of the two voltages
        let base: CGFloat = 190, full: CGFloat = 150
        let h1 = CGFloat(v1 / 12) * full, h2 = CGFloat(v2 / 12) * full
        ctx.fill(Path(roundedRect: CGRect(x: 262, y: base - h2, width: 30, height: h2), cornerRadius: 3), with: .color(green.opacity(0.85)))
        ctx.fill(Path(roundedRect: CGRect(x: 262, y: base - h2 - h1, width: 30, height: h1), cornerRadius: 3), with: .color(orange.opacity(0.85)))
        text(&ctx, String(format: "V2 = %.1f V", v2), at: CGPoint(x: 258, y: base - h2 / 2), size: 10, weight: .semibold, color: green, anchor: .trailing)
        text(&ctx, String(format: "V1 = %.1f V", v1), at: CGPoint(x: 258, y: base - h2 - h1 / 2), size: 10, weight: .semibold, color: orange, anchor: .trailing)
        text(&ctx, "V2 = 12 V · R2 / (R1 + R2)", at: CGPoint(x: 160, y: 214), size: 11, weight: .semibold)
    }

    // MARK: - Energy storage and transients

    static func capacitor(_ ctx: inout GraphicsContext, _ phase: Double, charging: Bool) {
        let tau = 1.0
        let t = max(0, phase - 0.5)
        let fraction = charging ? 1 - exp(-t / tau) : exp(-t / tau)
        // Circuit: source (or wire) on the left, resistor on top, capacitor on the right
        let loop = [CGPoint(x: 40, y: 60), CGPoint(x: 150, y: 60), CGPoint(x: 150, y: 170), CGPoint(x: 40, y: 170), CGPoint(x: 40, y: 60)]
        line(&ctx, CGPoint(x: 40, y: 60), CGPoint(x: 60, y: 60)); resistor(&ctx, CGPoint(x: 60, y: 60), CGPoint(x: 130, y: 60)); line(&ctx, CGPoint(x: 130, y: 60), CGPoint(x: 150, y: 60))
        line(&ctx, CGPoint(x: 150, y: 60), CGPoint(x: 150, y: 110)); capacitor(&ctx, at: CGPoint(x: 150, y: 115)); line(&ctx, CGPoint(x: 150, y: 120), CGPoint(x: 150, y: 170))
        line(&ctx, CGPoint(x: 150, y: 170), CGPoint(x: 40, y: 170))
        if charging {
            line(&ctx, CGPoint(x: 40, y: 60), CGPoint(x: 40, y: 96)); line(&ctx, CGPoint(x: 40, y: 124), CGPoint(x: 40, y: 170))
            battery(&ctx, at: CGPoint(x: 40, y: 110), vertical: true)
            text(&ctx, "V", at: CGPoint(x: 20, y: 110), size: 10, weight: .semibold)
        } else {
            line(&ctx, CGPoint(x: 40, y: 60), CGPoint(x: 40, y: 170))
        }
        // Charge on the plates
        let marks = Int((fraction * 6).rounded())
        for k in 0..<marks {
            let x = 150 - 12 + CGFloat(k) * 4.8
            text(&ctx, "+", at: CGPoint(x: x, y: 104), size: 8, weight: .bold, color: orange)
            text(&ctx, "−", at: CGPoint(x: x, y: 128), size: 8, weight: .bold, color: blue)
        }
        // Current dies away as the capacitor fills / empties
        let current = charging ? exp(-t / tau) : exp(-t / tau)
        if current > 0.03 {
            flow(&ctx, along: charging ? loop : Array(loop.reversed()), phase: phase, speed: 20 + 70 * current, color: green.opacity(0.4 + 0.6 * current))
        }
        text(&ctx, "C", at: CGPoint(x: 170, y: 115), size: 10, weight: .semibold)
        text(&ctx, "R", at: CGPoint(x: 95, y: 46), size: 10, weight: .semibold)
        // Plot
        let frame = CGRect(x: 195, y: 45, width: 110, height: 120)
        let map = plot(&ctx, frame: frame, xMax: 5, yMin: 0, yMax: 1.05, xLabel: "t", yLabel: charging ? "v_C" : "v_C", curve: { charging ? 1 - exp(-$0 / tau) : exp(-$0 / tau) }, color: green, upTo: min(t, 5))
        let tauPoint = map(1, charging ? 0.632 : 0.368)
        line(&ctx, CGPoint(x: tauPoint.x, y: frame.maxY), tauPoint, grey, 1, dash: [3, 3])
        text(&ctx, "τ", at: CGPoint(x: tauPoint.x, y: frame.maxY + 9), size: 9, color: grey)
        text(&ctx, charging ? "63%" : "37%", at: CGPoint(x: tauPoint.x + 4, y: tauPoint.y), size: 8, color: grey, anchor: .leading)
        if t <= 5 { dot(&ctx, map(t, fraction), 4, orange) }
        text(&ctx, charging ? "the capacitor fills, the current fades" : "the capacitor empties through R", at: CGPoint(x: 160, y: 205), size: 11, weight: .semibold)
        text(&ctx, "τ = R · C", at: CGPoint(x: 160, y: 220), size: 10, color: grey)
    }

    static func inductorRise(_ ctx: inout GraphicsContext, _ phase: Double) {
        let tau = 1.0
        let t = max(0, phase - 0.5)
        let fraction = 1 - exp(-t / tau)
        let loop = [CGPoint(x: 40, y: 60), CGPoint(x: 150, y: 60), CGPoint(x: 150, y: 170), CGPoint(x: 40, y: 170), CGPoint(x: 40, y: 60)]
        line(&ctx, CGPoint(x: 40, y: 60), CGPoint(x: 60, y: 60)); resistor(&ctx, CGPoint(x: 60, y: 60), CGPoint(x: 130, y: 60)); line(&ctx, CGPoint(x: 130, y: 60), CGPoint(x: 150, y: 60))
        line(&ctx, CGPoint(x: 150, y: 60), CGPoint(x: 150, y: 80)); coil(&ctx, CGPoint(x: 150, y: 80), CGPoint(x: 150, y: 150)); line(&ctx, CGPoint(x: 150, y: 150), CGPoint(x: 150, y: 170))
        line(&ctx, CGPoint(x: 150, y: 170), CGPoint(x: 40, y: 170))
        line(&ctx, CGPoint(x: 40, y: 60), CGPoint(x: 40, y: 96)); line(&ctx, CGPoint(x: 40, y: 124), CGPoint(x: 40, y: 170))
        battery(&ctx, at: CGPoint(x: 40, y: 110), vertical: true)
        // Magnetic field lines grow with the current
        for k in 1...3 {
            let r = CGFloat(10 + k * 9)
            ring(&ctx, CGPoint(x: 150, y: 115), r, blue.opacity(0.5 * fraction), 1.2)
        }
        flow(&ctx, along: loop, phase: phase, speed: 15 + 80 * fraction, color: green)
        text(&ctx, "L", at: CGPoint(x: 178, y: 115), size: 10, weight: .semibold)
        text(&ctx, "R", at: CGPoint(x: 95, y: 46), size: 10, weight: .semibold)
        let frame = CGRect(x: 195, y: 45, width: 110, height: 120)
        let map = plot(&ctx, frame: frame, xMax: 5, yMin: 0, yMax: 1.05, xLabel: "t", yLabel: "i", curve: { 1 - exp(-$0 / tau) }, color: green, upTo: min(t, 5))
        let tauPoint = map(1, 0.632)
        line(&ctx, CGPoint(x: tauPoint.x, y: frame.maxY), tauPoint, grey, 1, dash: [3, 3])
        text(&ctx, "τ", at: CGPoint(x: tauPoint.x, y: frame.maxY + 9), size: 9, color: grey)
        if t <= 5 { dot(&ctx, map(t, fraction), 4, orange) }
        text(&ctx, "the coil lets the current grow only gradually", at: CGPoint(x: 160, y: 205), size: 11, weight: .semibold)
        text(&ctx, "τ = L / R  ·  i → V/R", at: CGPoint(x: 160, y: 220), size: 10, color: grey)
    }

    static func rlcRinging(_ ctx: inout GraphicsContext, _ phase: Double) {
        let alpha = 0.9, wd = 6.0
        let t = max(0, phase - 0.4)
        func vc(_ x: Double) -> Double { 1 - exp(-alpha * x) * (cos(wd * x) + (alpha / wd) * sin(wd * x)) }
        let frame = CGRect(x: 40, y: 35, width: 250, height: 120)
        let map = plot(&ctx, frame: frame, xMax: 5, yMin: 0, yMax: 1.8, xLabel: "t", yLabel: "v_C", curve: vc, color: green, upTo: min(t, 5))
        // Envelope and final value
        var upper = Path(), lower = Path()
        for i in 0...60 {
            let x = 5 * Double(i) / 60
            let e = exp(-alpha * x) * 1.15
            let pu = map(x, 1 + e), pl = map(x, max(0, 1 - e))
            if i == 0 { upper.move(to: pu); lower.move(to: pl) } else { upper.addLine(to: pu); lower.addLine(to: pl) }
        }
        stroke(&ctx, upper, faint, 1, dash: [3, 3])
        stroke(&ctx, lower, faint, 1, dash: [3, 3])
        line(&ctx, map(0, 1), map(5, 1), grey, 1, dash: [4, 4])
        text(&ctx, "final value V", at: CGPoint(x: frame.maxX + 2, y: map(5, 1).y), size: 8.5, color: grey, anchor: .leading)
        if t <= 5 { dot(&ctx, map(t, vc(t)), 4, orange) }
        // Energy sloshing between C and L
        let e = exp(-2 * alpha * t)
        let ec = e * 0.5 * (1 + cos(2 * wd * t)), el = e * 0.5 * (1 - cos(2 * wd * t))
        for (index, (label, value, color)) in [("in C", ec, orange), ("in L", el, blue)].enumerated() {
            let x: CGFloat = 110 + CGFloat(index) * 100
            let h = CGFloat(value) * 40
            ctx.fill(Path(roundedRect: CGRect(x: x - 30, y: 205 - h, width: 60, height: max(h, 0.5)), cornerRadius: 3), with: .color(color.opacity(0.8)))
            text(&ctx, "energy \(label)", at: CGPoint(x: x, y: 216), size: 9, color: grey)
        }
        text(&ctx, "underdamped: it overshoots and rings before settling", at: CGPoint(x: 160, y: 168), size: 10.5, weight: .semibold)
    }

    static func timeConstant(_ ctx: inout GraphicsContext, _ phase: Double) {
        let t = max(0, phase - 0.4) * 5 / 5.2
        let frame = CGRect(x: 45, y: 35, width: 250, height: 140)
        let map = plot(&ctx, frame: frame, xMax: 5, yMin: 0, yMax: 1.05, xLabel: "time", yLabel: "fraction of the final value", curve: { 1 - exp(-$0) }, color: green, upTo: min(t, 5))
        for k in 1...5 {
            let value = 1 - exp(-Double(k))
            let p = map(Double(k), value)
            line(&ctx, CGPoint(x: p.x, y: frame.maxY), p, faint, 1, dash: [3, 3])
            text(&ctx, "\(k)τ", at: CGPoint(x: p.x, y: frame.maxY + 9), size: 9, color: grey)
            text(&ctx, "\(Int((value * 100).rounded()))%", at: CGPoint(x: p.x, y: p.y - 9), size: 8.5, weight: .semibold, color: t >= Double(k) ? green : faint)
        }
        line(&ctx, map(0, 1), map(5, 1), grey, 1, dash: [4, 4])
        if t <= 5 { dot(&ctx, map(t, 1 - exp(-t)), 4, orange) }
        text(&ctx, "every time constant closes 63% of what is left", at: CGPoint(x: 160, y: 205), size: 11, weight: .semibold)
    }

    // MARK: - Theorems

    static func superposition(_ ctx: inout GraphicsContext, _ phase: Double) {
        let stage = Int(phase / 3) % 3   // 0: V1 alone, 1: V2 alone, 2: both
        func scene(_ origin: CGPoint, v1On: Bool, v2On: Bool, label: String, current: String, dim: Bool) {
            let o = origin
            let color = dim ? grey : ink
            // Two sources on the outside, a resistor in the middle branch
            let left = CGPoint(x: o.x, y: o.y), right = CGPoint(x: o.x + 120, y: o.y), mid = CGPoint(x: o.x + 60, y: o.y)
            line(&ctx, left, right, color)
            line(&ctx, CGPoint(x: left.x, y: o.y + 80), CGPoint(x: right.x, y: o.y + 80), color)
            // V1 (left), V2 (right), R (middle)
            if v1On {
                line(&ctx, left, CGPoint(x: left.x, y: o.y + 28), color); line(&ctx, CGPoint(x: left.x, y: o.y + 52), CGPoint(x: left.x, y: o.y + 80), color)
                battery(&ctx, at: CGPoint(x: left.x, y: o.y + 40), vertical: true, color: color)
            } else {
                line(&ctx, left, CGPoint(x: left.x, y: o.y + 80), color)
                text(&ctx, "wire", at: CGPoint(x: left.x - 14, y: o.y + 40), size: 8, color: grey)
            }
            if v2On {
                line(&ctx, right, CGPoint(x: right.x, y: o.y + 28), color); line(&ctx, CGPoint(x: right.x, y: o.y + 52), CGPoint(x: right.x, y: o.y + 80), color)
                battery(&ctx, at: CGPoint(x: right.x, y: o.y + 40), vertical: true, color: color)
            } else {
                line(&ctx, right, CGPoint(x: right.x, y: o.y + 80), color)
                text(&ctx, "wire", at: CGPoint(x: right.x + 14, y: o.y + 40), size: 8, color: grey)
            }
            line(&ctx, mid, CGPoint(x: mid.x, y: o.y + 15), color); resistor(&ctx, CGPoint(x: mid.x, y: o.y + 15), CGPoint(x: mid.x, y: o.y + 65), color); line(&ctx, CGPoint(x: mid.x, y: o.y + 65), CGPoint(x: mid.x, y: o.y + 80), color)
            dot(&ctx, mid, 3, color); dot(&ctx, CGPoint(x: mid.x, y: o.y + 80), 3, color)
            text(&ctx, label, at: CGPoint(x: o.x + 60, y: o.y - 12), size: 10, weight: .semibold, color: dim ? grey : ink)
            text(&ctx, current, at: CGPoint(x: o.x + 60, y: o.y + 96), size: 10, weight: .bold, color: dim ? grey : green)
        }
        scene(CGPoint(x: 30, y: 40), v1On: true, v2On: false, label: "V1 alone", current: "I′ = 2 A ↓", dim: stage != 0)
        scene(CGPoint(x: 170, y: 40), v1On: false, v2On: true, label: "V2 alone", current: "I″ = −0.5 A", dim: stage != 1)
        text(&ctx, stage == 2 ? "both on: I = I′ + I″ = 2 A − 0.5 A = 1.5 A" : "switch one source off at a time (a voltage source off = a wire)", at: CGPoint(x: 160, y: 190), size: 10.5, weight: .semibold, color: stage == 2 ? green : ink)
        text(&ctx, "only works because the circuit is linear", at: CGPoint(x: 160, y: 210), size: 10, color: grey)
    }

    static func theveninBox(_ ctx: inout GraphicsContext, _ phase: Double) {
        let blend = min(max((phase - 2.5) / 1.5, 0), 1)   // 0: network, 1: equivalent
        let networkAlpha = 1 - blend, boxAlpha = blend
        // The network: battery 12 V, R 4 Ω series, R 4 Ω shunt → Vth 6 V, Rth 2 Ω
        let n = ink.opacity(networkAlpha)
        line(&ctx, CGPoint(x: 40, y: 60), CGPoint(x: 40, y: 96), n); line(&ctx, CGPoint(x: 40, y: 124), CGPoint(x: 40, y: 170), n)
        battery(&ctx, at: CGPoint(x: 40, y: 110), vertical: true, color: n)
        line(&ctx, CGPoint(x: 40, y: 60), CGPoint(x: 60, y: 60), n); resistor(&ctx, CGPoint(x: 60, y: 60), CGPoint(x: 120, y: 60), n); line(&ctx, CGPoint(x: 120, y: 60), CGPoint(x: 200, y: 60), n)
        line(&ctx, CGPoint(x: 130, y: 60), CGPoint(x: 130, y: 80), n); resistor(&ctx, CGPoint(x: 130, y: 80), CGPoint(x: 130, y: 150), n); line(&ctx, CGPoint(x: 130, y: 150), CGPoint(x: 130, y: 170), n)
        line(&ctx, CGPoint(x: 40, y: 170), CGPoint(x: 200, y: 170), n)
        dot(&ctx, CGPoint(x: 130, y: 60), 3, n); dot(&ctx, CGPoint(x: 130, y: 170), 3, n)
        text(&ctx, "12 V", at: CGPoint(x: 16, y: 110), size: 9, weight: .semibold, color: n)
        text(&ctx, "4 Ω", at: CGPoint(x: 90, y: 46), size: 9, weight: .semibold, color: n)
        text(&ctx, "4 Ω", at: CGPoint(x: 148, y: 115), size: 9, weight: .semibold, color: n)
        // The equivalent: Vth in series with Rth
        let b = ink.opacity(boxAlpha)
        ctx.fill(Path(roundedRect: CGRect(x: 30, y: 45, width: 150, height: 140), cornerRadius: 10), with: .color(green.opacity(0.06 * boxAlpha)))
        stroke(&ctx, Path(roundedRect: CGRect(x: 30, y: 45, width: 150, height: 140), cornerRadius: 10), green.opacity(boxAlpha), 1.5, dash: [6, 4])
        line(&ctx, CGPoint(x: 70, y: 60), CGPoint(x: 70, y: 96), b); line(&ctx, CGPoint(x: 70, y: 124), CGPoint(x: 70, y: 170), b)
        battery(&ctx, at: CGPoint(x: 70, y: 110), vertical: true, color: b)
        line(&ctx, CGPoint(x: 70, y: 60), CGPoint(x: 100, y: 60), b); resistor(&ctx, CGPoint(x: 100, y: 60), CGPoint(x: 160, y: 60), b); line(&ctx, CGPoint(x: 160, y: 60), CGPoint(x: 200, y: 60), b)
        line(&ctx, CGPoint(x: 70, y: 170), CGPoint(x: 200, y: 170), b)
        text(&ctx, "Vth = 6 V", at: CGPoint(x: 66, y: 195), size: 10, weight: .semibold, color: green.opacity(boxAlpha))
        text(&ctx, "Rth = 2 Ω", at: CGPoint(x: 130, y: 46), size: 10, weight: .semibold, color: green.opacity(boxAlpha))
        // Terminals a, b and a load that sees no difference
        ring(&ctx, CGPoint(x: 200, y: 60), 4, ink); ring(&ctx, CGPoint(x: 200, y: 170), 4, ink)
        text(&ctx, "a", at: CGPoint(x: 212, y: 60), size: 11, weight: .semibold)
        text(&ctx, "b", at: CGPoint(x: 212, y: 170), size: 11, weight: .semibold)
        line(&ctx, CGPoint(x: 204, y: 60), CGPoint(x: 260, y: 60), grey); line(&ctx, CGPoint(x: 260, y: 60), CGPoint(x: 260, y: 80), grey)
        resistor(&ctx, CGPoint(x: 260, y: 80), CGPoint(x: 260, y: 150), grey); line(&ctx, CGPoint(x: 260, y: 150), CGPoint(x: 260, y: 170), grey); line(&ctx, CGPoint(x: 260, y: 170), CGPoint(x: 204, y: 170), grey)
        text(&ctx, "any load", at: CGPoint(x: 285, y: 115), size: 9, color: grey)
        text(&ctx, blend < 0.5 ? "seen from a–b, the whole network is just…" : "…one source and one resistor: same V and I at a–b", at: CGPoint(x: 160, y: 215), size: 10.5, weight: .semibold)
    }

    static func maxPower(_ ctx: inout GraphicsContext, _ phase: Double) {
        let vth = 10.0, rth = 5.0
        func p(_ rl: Double) -> Double { vth * vth * rl / ((rth + rl) * (rth + rl)) }
        let frame = CGRect(x: 45, y: 35, width: 250, height: 140)
        let map = plot(&ctx, frame: frame, xMax: 25, yMin: 0, yMax: 5.5, xLabel: "R_L (Ω)", yLabel: "P_L (W)", curve: p, color: green)
        let rl = 0.3 + 24.7 * (0.5 - 0.5 * cos(phase * 2 * .pi / 6))
        let point = map(rl, p(rl))
        let peak = map(rth, p(rth))
        line(&ctx, CGPoint(x: peak.x, y: frame.maxY), peak, grey, 1, dash: [3, 3])
        text(&ctx, "R_L = R_th = 5 Ω", at: CGPoint(x: peak.x, y: frame.maxY + 10), size: 9, weight: .semibold, color: grey)
        text(&ctx, "5 W", at: CGPoint(x: peak.x + 6, y: peak.y - 8), size: 9, weight: .semibold, color: green, anchor: .leading)
        dot(&ctx, point, 5, orange)
        text(&ctx, String(format: "R_L = %.1f Ω → %.2f W", rl, p(rl)), at: CGPoint(x: 160, y: 200), size: 11, weight: .semibold, color: orange)
        text(&ctx, "the load takes most power when it matches the source's own resistance", at: CGPoint(x: 160, y: 218), size: 9.5, color: grey)
    }

    // MARK: - AC

    static func sineWave(_ ctx: inout GraphicsContext, _ phase: Double) {
        let omega = 2 * Double.pi / 3   // one turn every 3 s
        let angle = omega * phase
        let center = CGPoint(x: 70, y: 110), radius: CGFloat = 45
        ring(&ctx, center, radius, faint, 1.5)
        line(&ctx, CGPoint(x: center.x - radius - 8, y: center.y), CGPoint(x: center.x + radius + 8, y: center.y), faint, 1)
        let tip = CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y - radius * CGFloat(sin(angle)))
        arrow(&ctx, from: center, to: tip, green, 2.5)
        text(&ctx, "Vm", at: CGPoint(x: center.x + 12, y: center.y - 12), size: 9, weight: .semibold, color: green)
        // Trace: the tip's height against time, scrolling
        let frame = CGRect(x: 135, y: 55, width: 170, height: 110)
        line(&ctx, CGPoint(x: frame.minX, y: frame.midY), CGPoint(x: frame.maxX, y: frame.midY), grey, 1)
        line(&ctx, CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.minX, y: frame.maxY), grey, 1)
        var path = Path()
        let window = 6.0
        for i in 0...100 {
            let tt = phase - window + window * Double(i) / 100
            let y = frame.midY - radius * CGFloat(sin(omega * tt))
            let x = frame.minX + frame.width * CGFloat(i) / 100
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        stroke(&ctx, path, green, 2)
        line(&ctx, tip, CGPoint(x: frame.maxX, y: tip.y), orange, 1, dash: [3, 3])
        dot(&ctx, CGPoint(x: frame.maxX, y: tip.y), 4, orange)
        text(&ctx, "v(t) = Vm · sin(ωt)", at: CGPoint(x: 220, y: 40), size: 11, weight: .semibold)
        text(&ctx, "T = 3 s here · f = 1/T · ω = 2πf", at: CGPoint(x: 220, y: 180), size: 9.5, color: grey)
        text(&ctx, "a turning arrow, seen from the side, is a sine wave", at: CGPoint(x: 160, y: 210), size: 10.5, weight: .semibold)
    }

    static func phasor(_ ctx: inout GraphicsContext, _ phase: Double) {
        let omega = 2 * Double.pi / 3
        let lag = Double.pi / 4   // I lags V by 45°
        let angle = omega * phase
        let center = CGPoint(x: 70, y: 110)
        ring(&ctx, center, 50, faint, 1.5)
        let vTip = CGPoint(x: center.x + 50 * CGFloat(cos(angle)), y: center.y - 50 * CGFloat(sin(angle)))
        let iTip = CGPoint(x: center.x + 34 * CGFloat(cos(angle - lag)), y: center.y - 34 * CGFloat(sin(angle - lag)))
        arrow(&ctx, from: center, to: vTip, green, 2.5)
        arrow(&ctx, from: center, to: iTip, orange, 2.5)
        text(&ctx, "V", at: CGPoint(x: vTip.x + 8 * CGFloat(cos(angle)), y: vTip.y - 8 * CGFloat(sin(angle))), size: 10, weight: .bold, color: green)
        text(&ctx, "I", at: CGPoint(x: iTip.x + 8 * CGFloat(cos(angle - lag)), y: iTip.y - 8 * CGFloat(sin(angle - lag))), size: 10, weight: .bold, color: orange)
        let frame = CGRect(x: 135, y: 55, width: 170, height: 110)
        line(&ctx, CGPoint(x: frame.minX, y: frame.midY), CGPoint(x: frame.maxX, y: frame.midY), grey, 1)
        for (amplitude, shift, color) in [(50.0, 0.0, green), (34.0, lag, orange)] {
            var path = Path()
            for i in 0...100 {
                let tt = phase - 6 + 6 * Double(i) / 100
                let y = frame.midY - CGFloat(amplitude * sin(omega * tt - shift))
                let x = frame.minX + frame.width * CGFloat(i) / 100
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            stroke(&ctx, path, color, 2)
        }
        text(&ctx, "the current lags the voltage by 45°", at: CGPoint(x: 220, y: 40), size: 11, weight: .semibold)
        text(&ctx, "same ω, fixed angle between them: a phasor holds amplitude and phase", at: CGPoint(x: 160, y: 200), size: 9.5, color: grey)
        text(&ctx, "V = Vm∠0°,  I = Im∠−45°", at: CGPoint(x: 160, y: 218), size: 11, weight: .semibold)
    }

    static func impedanceTriangle(_ ctx: inout GraphicsContext, _ phase: Double) {
        let r: CGFloat = 130
        let x = CGFloat(70 * (0.5 - 0.5 * cos(phase * 2 * .pi / 6)) + 10)
        let origin = CGPoint(x: 60, y: 170)
        let rEnd = CGPoint(x: origin.x + r, y: origin.y)
        let zEnd = CGPoint(x: origin.x + r, y: origin.y - x)
        arrow(&ctx, from: origin, to: rEnd, ink, 2.5)
        arrow(&ctx, from: rEnd, to: zEnd, blue, 2.5)
        arrow(&ctx, from: origin, to: zEnd, green, 2.5)
        text(&ctx, "R (resistance)", at: CGPoint(x: origin.x + r / 2, y: origin.y + 12), size: 10, weight: .semibold)
        text(&ctx, "X (reactance)", at: CGPoint(x: rEnd.x + 8, y: origin.y - x / 2), size: 10, weight: .semibold, color: blue, anchor: .leading)
        text(&ctx, "|Z|", at: CGPoint(x: origin.x + r / 2 - 10, y: origin.y - x / 2 - 10), size: 11, weight: .bold, color: green)
        let theta = atan2(Double(x), Double(r))
        var arc = Path()
        arc.addArc(center: origin, radius: 30, startAngle: .degrees(0), endAngle: .radians(-theta), clockwise: true)
        stroke(&ctx, arc, orange, 1.5)
        text(&ctx, String(format: "θ = %.0f°", theta * 180 / .pi), at: CGPoint(x: origin.x + 44, y: origin.y - 12), size: 10, weight: .semibold, color: orange, anchor: .leading)
        text(&ctx, "|Z| = √(R² + X²)   θ = arctan(X / R)", at: CGPoint(x: 160, y: 40), size: 11, weight: .semibold)
        text(&ctx, "Z = R + jX: the resistor takes real power, the reactance only borrows it", at: CGPoint(x: 160, y: 210), size: 9.5, color: grey)
    }

    static func wyeDelta(_ ctx: inout GraphicsContext, _ phase: Double) {
        let blend = 0.5 - 0.5 * cos(phase * 2 * .pi / 6)
        let y = ink.opacity(1 - blend), d = ink.opacity(blend)
        // Wye on the left
        let c = CGPoint(x: 80, y: 120)
        let ya = CGPoint(x: 80, y: 45), yb = CGPoint(x: 20, y: 185), yc = CGPoint(x: 140, y: 185)
        resistor(&ctx, c, ya, y); resistor(&ctx, c, yb, y); resistor(&ctx, c, yc, y)
        text(&ctx, "Y", at: CGPoint(x: 80, y: 210), size: 12, weight: .bold, color: y)
        // Delta on the right
        let da = CGPoint(x: 240, y: 45), db = CGPoint(x: 180, y: 185), dc = CGPoint(x: 300, y: 185)
        resistor(&ctx, da, db, d); resistor(&ctx, db, dc, d); resistor(&ctx, dc, da, d)
        text(&ctx, "Δ", at: CGPoint(x: 240, y: 210), size: 12, weight: .bold, color: d)
        for (p, label) in [(ya, "a"), (yb, "b"), (yc, "c")] { text(&ctx, label, at: CGPoint(x: p.x, y: p.y + (p.y < 100 ? -12 : 12)), size: 10, weight: .semibold, color: y) }
        for (p, label) in [(da, "a"), (db, "b"), (dc, "c")] { text(&ctx, label, at: CGPoint(x: p.x, y: p.y + (p.y < 100 ? -12 : 12)), size: 10, weight: .semibold, color: d) }
        arrow(&ctx, from: CGPoint(x: 150, y: 120), to: CGPoint(x: 172, y: 120), green, 2)
        text(&ctx, "same resistance between every pair of terminals", at: CGPoint(x: 160, y: 24), size: 10.5, weight: .semibold)
        text(&ctx, "equal resistors: R_Δ = 3 · R_Y", at: CGPoint(x: 160, y: 228), size: 10, color: grey, anchor: .bottom)
    }
}
