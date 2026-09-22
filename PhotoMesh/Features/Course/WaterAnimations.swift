import SwiftUI

/// The water-in-pipes pictures the course opens with: a pump pushing water round a loop of pipe
/// through a narrow section. Pressure stands for voltage, flow rate for current, the narrow pipe
/// for resistance and the pump for the battery. Same 320 × 230 canvas as the other concept drawings.
extension ConceptDrawing {
    static let water = Color(red: 0.16, green: 0.47, blue: 0.86)
    static let waterLight = Color(red: 0.70, green: 0.84, blue: 0.98)
    static let pipeWall = Color(red: 0.58, green: 0.60, blue: 0.65)

    // MARK: Plumbing parts

    /// A pipe along a polyline: grey walls with pale water inside. `bore` is the inside width.
    static func pipe(_ ctx: inout GraphicsContext, _ points: [CGPoint], bore: CGFloat = 12) {
        guard let first = points.first else { return }
        var p = Path()
        p.move(to: first)
        for point in points.dropFirst() { p.addLine(to: point) }
        ctx.stroke(p, with: .color(pipeWall), style: StrokeStyle(lineWidth: bore + 4, lineCap: .butt, lineJoin: .round))
        ctx.stroke(p, with: .color(waterLight), style: StrokeStyle(lineWidth: bore, lineCap: .butt, lineJoin: .round))
    }

    /// Replaces part of a standard pipe (bore 12) with a narrow one (bore 6), shoulders included.
    /// `a` and `b` must lie on one horizontal or one vertical line.
    static func narrowSection(_ ctx: inout GraphicsContext, from a: CGPoint, to b: CGPoint) {
        let horizontal = abs(b.y - a.y) < 0.5
        let rect = horizontal
            ? CGRect(x: min(a.x, b.x), y: a.y - 10, width: abs(b.x - a.x), height: 20)
            : CGRect(x: a.x - 10, y: min(a.y, b.y), width: 20, height: abs(b.y - a.y))
        ctx.fill(Path(rect), with: .color(.white))
        pipe(&ctx, [a, b], bore: 6)
        for end in [a, b] {
            for side: CGFloat in [-1, 1] {
                if horizontal {
                    line(&ctx, CGPoint(x: end.x, y: end.y + side * 8), CGPoint(x: end.x, y: end.y + side * 5), pipeWall, 3)
                } else {
                    line(&ctx, CGPoint(x: end.x + side * 8, y: end.y), CGPoint(x: end.x + side * 5, y: end.y), pipeWall, 3)
                }
            }
        }
    }

    /// A pump: a round housing with a three-bladed impeller turned to `angle` radians.
    static func pump(_ ctx: inout GraphicsContext, at c: CGPoint, angle: Double, label: String? = "pump") {
        dot(&ctx, c, 17, Color.white)
        ring(&ctx, c, 17, orange, 3)
        for k in 0..<3 {
            let a = angle + Double(k) * 2 * Double.pi / 3
            line(&ctx, c, CGPoint(x: c.x + 12 * cos(a), y: c.y + 12 * sin(a)), orange, 3)
        }
        dot(&ctx, c, 3, orange)
        if let label {
            text(&ctx, label, at: CGPoint(x: c.x, y: c.y + 29), size: 10, weight: .semibold, color: orange)
        }
    }

    /// A pressure gauge: a dial whose needle sits at `value` (0 … 1), sweeping over the top.
    static func gauge(_ ctx: inout GraphicsContext, at c: CGPoint, value: Double, label: String? = nil) {
        dot(&ctx, c, 14, Color.white)
        ring(&ctx, c, 14, ink, 1.8)
        var arc: [CGPoint] = []
        for i in 0...24 {
            let a = (150 + 240 * Double(i) / 24) * Double.pi / 180
            arc.append(CGPoint(x: c.x + 9.5 * cos(a), y: c.y + 9.5 * sin(a)))
        }
        polyline(&ctx, arc, faint, 3)
        let a = (150 + 240 * max(0, min(value, 1))) * Double.pi / 180
        line(&ctx, c, CGPoint(x: c.x + 10 * cos(a), y: c.y + 10 * sin(a)), orange, 2)
        dot(&ctx, c, 2, ink)
        if let label {
            text(&ctx, label, at: CGPoint(x: c.x, y: c.y + 23), size: 9, weight: .semibold, color: grey)
        }
    }

    /// A valve on a horizontal pipe: handle along the pipe when open, across it when closed.
    static func valve(_ ctx: inout GraphicsContext, at c: CGPoint, open: Bool) {
        var body = Path()
        body.move(to: CGPoint(x: c.x - 12, y: c.y - 9))
        body.addLine(to: CGPoint(x: c.x + 12, y: c.y + 9))
        body.addLine(to: CGPoint(x: c.x + 12, y: c.y - 9))
        body.addLine(to: CGPoint(x: c.x - 12, y: c.y + 9))
        body.closeSubpath()
        ctx.fill(body, with: .color(.white))
        stroke(&ctx, body, ink, 2)
        line(&ctx, c, CGPoint(x: c.x, y: c.y - 16), ink, 2)
        if open {
            line(&ctx, CGPoint(x: c.x - 10, y: c.y - 16), CGPoint(x: c.x + 10, y: c.y - 16), orange, 3.5)
        } else {
            line(&ctx, CGPoint(x: c.x, y: c.y - 26), CGPoint(x: c.x, y: c.y - 6), orange, 3.5)
            line(&ctx, CGPoint(x: c.x, y: c.y - 9), CGPoint(x: c.x, y: c.y + 9), orange, 3)
        }
    }

    /// An open-topped tank filled to `level` (0 … 1).
    static func tank(_ ctx: inout GraphicsContext, _ rect: CGRect, level: Double, label: String? = nil) {
        let h = rect.height * CGFloat(max(0, min(level, 1)))
        ctx.fill(Path(CGRect(x: rect.minX, y: rect.maxY - h, width: rect.width, height: h)), with: .color(waterLight))
        if h > 1 {
            line(&ctx, CGPoint(x: rect.minX, y: rect.maxY - h), CGPoint(x: rect.maxX, y: rect.maxY - h), water, 1.5)
        }
        polyline(&ctx, [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY),
                        CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.minY)], pipeWall, 3)
        if let label {
            text(&ctx, label, at: CGPoint(x: rect.midX, y: rect.minY - 9), size: 10, weight: .semibold, color: grey)
        }
    }

    /// Water arcing out of a spout and falling to `ground`; `reach` is how far it lands.
    static func stream(_ ctx: inout GraphicsContext, from spout: CGPoint, ground: CGFloat, reach: CGFloat, phase: Double) {
        pipe(&ctx, [CGPoint(x: spout.x - 1, y: spout.y), CGPoint(x: spout.x + 9, y: spout.y)], bore: 5)
        let start = CGPoint(x: spout.x + 9, y: spout.y)
        let drop = ground - start.y
        var points: [CGPoint] = []
        for i in 0...16 {
            let t = CGFloat(i) / 16
            points.append(CGPoint(x: start.x + reach * t, y: start.y + drop * t * t))
        }
        polyline(&ctx, points, waterLight, 4)
        flow(&ctx, along: points, phase: phase, speed: 70, color: water, spacing: 14, radius: 2.4)
    }

    /// A paddle wheel in a round housing, turned to `angle` radians.
    static func wheel(_ ctx: inout GraphicsContext, at c: CGPoint, angle: Double) {
        dot(&ctx, c, 30, Color.white)
        ring(&ctx, c, 30, pipeWall, 3)
        for k in 0..<6 {
            let a = angle + Double(k) * Double.pi / 3
            let tip = CGPoint(x: c.x + 24 * cos(a), y: c.y + 24 * sin(a))
            line(&ctx, c, tip, ink, 2.5)
            let n = CGPoint(x: -sin(a), y: cos(a))
            line(&ctx, CGPoint(x: tip.x - n.x * 7, y: tip.y - n.y * 7), CGPoint(x: tip.x + n.x * 7, y: tip.y + n.y * 7), ink, 3)
        }
        dot(&ctx, c, 5, ink)
    }

    // MARK: The map

    /// The whole water system: pump, loop of pipe, one narrow section, a gauge.
    static func waterLoop(_ ctx: inout GraphicsContext, _ phase: Double) {
        let loop = [CGPoint(x: 60, y: 55), CGPoint(x: 260, y: 55), CGPoint(x: 260, y: 175), CGPoint(x: 60, y: 175), CGPoint(x: 60, y: 55)]
        pipe(&ctx, loop)
        narrowSection(&ctx, from: CGPoint(x: 260, y: 85), to: CGPoint(x: 260, y: 145))
        flow(&ctx, along: loop, phase: phase, speed: 55, color: water, spacing: 20)
        pump(&ctx, at: CGPoint(x: 60, y: 115), angle: phase * 4, label: nil)
        gauge(&ctx, at: CGPoint(x: 120, y: 55), value: 0.8)
        text(&ctx, "pump", at: CGPoint(x: 24, y: 115), size: 10, weight: .semibold, color: orange)
        text(&ctx, "pressure", at: CGPoint(x: 120, y: 30), size: 10, weight: .semibold, color: grey)
        arrow(&ctx, from: CGPoint(x: 165, y: 40), to: CGPoint(x: 225, y: 40), water)
        text(&ctx, "flow", at: CGPoint(x: 195, y: 28), size: 10, weight: .semibold, color: water)
        text(&ctx, "narrow", at: CGPoint(x: 293, y: 108), size: 10, weight: .semibold)
        text(&ctx, "pipe", at: CGPoint(x: 293, y: 121), size: 10, weight: .semibold)
        text(&ctx, "the same water goes round and round: nothing is used up", at: CGPoint(x: 160, y: 208), size: 11, weight: .semibold)
    }

    /// Two tanks: the deeper the water, the harder it pushes.
    static func waterPressure(_ ctx: inout GraphicsContext, _ phase: Double) {
        let ground: CGFloat = 196
        line(&ctx, CGPoint(x: 10, y: ground), CGPoint(x: 310, y: ground), grey, 1.2)
        let tall = CGRect(x: 40, y: 45, width: 56, height: 140)
        let short = CGRect(x: 185, y: 130, width: 56, height: 55)
        tank(&ctx, tall, level: 0.94, label: "tall tank")
        tank(&ctx, short, level: 0.9, label: "short tank")
        stream(&ctx, from: CGPoint(x: tall.maxX, y: tall.maxY - 9), ground: ground, reach: 62, phase: phase)
        stream(&ctx, from: CGPoint(x: short.maxX, y: short.maxY - 9), ground: ground, reach: 26, phase: phase)
        gauge(&ctx, at: CGPoint(x: tall.minX - 18, y: tall.maxY - 14), value: 0.9)
        gauge(&ctx, at: CGPoint(x: short.minX - 18, y: short.maxY - 14), value: 0.35)
        text(&ctx, "high pressure", at: CGPoint(x: 68, y: 210), size: 10, weight: .semibold, color: water)
        text(&ctx, "low pressure", at: CGPoint(x: 213, y: 210), size: 10, weight: .semibold, color: water)
        text(&ctx, "deeper water pushes harder", at: CGPoint(x: 200, y: 50), size: 12, weight: .semibold)
        text(&ctx, "pressure = how hard the water is pushed", at: CGPoint(x: 200, y: 68), size: 10, color: grey)
    }

    /// A flow meter: buckets passing a line every second.
    static func waterFlowRate(_ ctx: inout GraphicsContext, _ phase: Double) {
        let y: CGFloat = 115
        let run = [CGPoint(x: 20, y: y), CGPoint(x: 300, y: y)]
        pipe(&ctx, run, bore: 14)
        flow(&ctx, along: run, phase: phase, speed: 66, color: water, spacing: 22, radius: 3.6)
        line(&ctx, CGPoint(x: 160, y: 82), CGPoint(x: 160, y: 148), orange, 2, dash: [5, 4])
        text(&ctx, "counting line", at: CGPoint(x: 160, y: 70), size: 10, weight: .semibold, color: orange)
        arrow(&ctx, from: CGPoint(x: 40, y: 92), to: CGPoint(x: 100, y: 92), water)
        let passed = Int(phase * 3)
        text(&ctx, "\(passed) buckets have passed the line", at: CGPoint(x: 160, y: 170), size: 12, weight: .semibold)
        text(&ctx, "3 buckets every second: that is the flow rate", at: CGPoint(x: 160, y: 190), size: 11, color: grey)
        text(&ctx, "flow rate = how much passes a point each second", at: CGPoint(x: 160, y: 40), size: 11, weight: .semibold)
    }

    /// Same pump, two pipes: the narrow one lets only a trickle through.
    static func waterNarrowPipe(_ ctx: inout GraphicsContext, _ phase: Double) {
        let t = phase / 6
        func row(_ y: CGFloat, bore: CGFloat, speed: Double, spacing: Double, fill: Double, label: String) {
            let run = [CGPoint(x: 62, y: y), CGPoint(x: 252, y: y)]
            pipe(&ctx, run, bore: bore)
            flow(&ctx, along: run, phase: phase, speed: speed, color: water, spacing: spacing, radius: min(3.2, bore / 2 - 0.5))
            pump(&ctx, at: CGPoint(x: 45, y: y), angle: phase * 4, label: nil)
            tank(&ctx, CGRect(x: 258, y: y - 22, width: 40, height: 44), level: fill)
            text(&ctx, label, at: CGPoint(x: 157, y: y + 30), size: 11, weight: .semibold)
        }
        row(66, bore: 14, speed: 80, spacing: 16, fill: t, label: "wide pipe: a lot gets through")
        row(160, bore: 6, speed: 30, spacing: 30, fill: t * 0.3, label: "narrow pipe: only a trickle")
        text(&ctx, "same pump, same push", at: CGPoint(x: 157, y: 120), size: 11, weight: .semibold, color: grey)
    }

    /// The pump lifts water into an upper tank; it runs back down a narrow pipe. Then the pump stops.
    static func waterPump(_ ctx: inout GraphicsContext, _ phase: Double) {
        let running = phase < 4
        let since = max(0, phase - 4)
        let drain = min(since, 1.5)
        let level = running ? 1.0 : 1 - drain / 1.5
        let upDist = running ? 60 * phase : 240.0
        let downDist = running ? 60 * phase : 240 + 60 * (drain - drain * drain / 3)
        tank(&ctx, CGRect(x: 30, y: 170, width: 260, height: 32), level: 0.8)
        tank(&ctx, CGRect(x: 30, y: 46, width: 80, height: 40), level: 0.15 + 0.75 * level, label: "upper tank")
        let riser = [CGPoint(x: 55, y: 170), CGPoint(x: 55, y: 86)]
        let down = [CGPoint(x: 110, y: 72), CGPoint(x: 150, y: 72), CGPoint(x: 245, y: 170)]
        pipe(&ctx, riser)
        pipe(&ctx, down, bore: 7)
        flow(&ctx, along: riser, phase: upDist, speed: 1, color: water, spacing: 20)
        flow(&ctx, along: down, phase: downDist, speed: 1, color: water, spacing: 20)
        pump(&ctx, at: CGPoint(x: 55, y: 130), angle: running ? phase * 4 : 16, label: running ? "pump on" : "pump off")
        text(&ctx, "the pump does not make water: it lifts it back up", at: CGPoint(x: 190, y: 40), size: 11, weight: .semibold)
        if running {
            text(&ctx, "lifted on the left, it runs back down on the right", at: CGPoint(x: 195, y: 120), size: 10, color: grey)
        } else {
            text(&ctx, "pump off: the level falls and the flow dies away", at: CGPoint(x: 195, y: 120), size: 10, weight: .semibold, color: orange)
        }
        text(&ctx, "lower tank", at: CGPoint(x: 160, y: 217), size: 10, weight: .semibold, color: grey)
    }

    /// A valve in the loop: open, water moves everywhere; closed, it stops everywhere at once.
    static func waterValve(_ ctx: inout GraphicsContext, _ phase: Double) {
        let open = phase < 3
        let dist = min(phase, 3) * 55
        let loop = [CGPoint(x: 60, y: 60), CGPoint(x: 260, y: 60), CGPoint(x: 260, y: 175), CGPoint(x: 60, y: 175), CGPoint(x: 60, y: 60)]
        pipe(&ctx, loop)
        narrowSection(&ctx, from: CGPoint(x: 260, y: 90), to: CGPoint(x: 260, y: 145))
        flow(&ctx, along: loop, phase: dist, speed: 1, color: water, spacing: 20)
        pump(&ctx, at: CGPoint(x: 60, y: 118), angle: phase * 4, label: nil)
        valve(&ctx, at: CGPoint(x: 160, y: 60), open: open)
        text(&ctx, open ? "valve open" : "valve closed", at: CGPoint(x: 160, y: 22), size: 12, weight: .bold, color: open ? green : orange)
        if open {
            text(&ctx, "water moves everywhere in the loop at once", at: CGPoint(x: 160, y: 118), size: 11, weight: .semibold)
        } else {
            text(&ctx, "it stops everywhere at once,", at: CGPoint(x: 160, y: 110), size: 11, weight: .semibold)
            text(&ctx, "not just at the valve", at: CGPoint(x: 160, y: 126), size: 11, weight: .semibold)
        }
        text(&ctx, "in a circuit, the valve is a switch", at: CGPoint(x: 160, y: 208), size: 11, color: grey)
    }

    /// Turn the pressure up and the flow rises in step: the water version of Ohm's law.
    static func waterOhm(_ ctx: inout GraphicsContext, _ phase: Double) {
        let p = phase / 8
        let dist = 5 * phase * phase
        let run = [CGPoint(x: 62, y: 130), CGPoint(x: 195, y: 130)]
        pipe(&ctx, run, bore: 9)
        flow(&ctx, along: run, phase: dist, speed: 1, color: water, spacing: 18, radius: 3)
        pump(&ctx, at: CGPoint(x: 45, y: 130), angle: dist / 6, label: "pump")
        gauge(&ctx, at: CGPoint(x: 110, y: 130), value: p, label: nil)
        text(&ctx, "pressure \(Int((p * 100).rounded()))%", at: CGPoint(x: 110, y: 102), size: 10, weight: .semibold, color: grey)
        text(&ctx, "flow \(Int((p * 100).rounded()))%", at: CGPoint(x: 175, y: 155), size: 10, weight: .semibold, color: water)
        let map = plot(&ctx, frame: CGRect(x: 225, y: 55, width: 80, height: 100), xMax: 1, yMin: 0, yMax: 1,
                       xLabel: "pressure", yLabel: "flow", curve: { $0 }, color: water, upTo: p)
        dot(&ctx, map(p, p), 4, orange)
        text(&ctx, "turning the pump up slowly", at: CGPoint(x: 110, y: 50), size: 12, weight: .semibold)
        text(&ctx, "the same pipe all along", at: CGPoint(x: 110, y: 66), size: 10, color: grey)
        text(&ctx, "double the pressure, double the flow", at: CGPoint(x: 160, y: 208), size: 11, weight: .semibold, color: green)
    }

    /// A junction: what flows in flows out.
    static func waterJunction(_ ctx: inout GraphicsContext, _ phase: Double) {
        let inlet = [CGPoint(x: 20, y: 115), CGPoint(x: 150, y: 115)]
        let up = [CGPoint(x: 150, y: 115), CGPoint(x: 190, y: 75), CGPoint(x: 298, y: 75)]
        let down = [CGPoint(x: 150, y: 115), CGPoint(x: 190, y: 155), CGPoint(x: 298, y: 155)]
        pipe(&ctx, up)
        pipe(&ctx, down)
        pipe(&ctx, inlet)
        flow(&ctx, along: inlet, phase: phase, speed: 75, color: water, spacing: 15)
        flow(&ctx, along: up, phase: phase, speed: 60, color: water, spacing: 20)
        flow(&ctx, along: down, phase: phase, speed: 40, color: water, spacing: 20)
        text(&ctx, "5 buckets/s in", at: CGPoint(x: 80, y: 95), size: 11, weight: .semibold, color: water)
        text(&ctx, "3 out", at: CGPoint(x: 250, y: 58), size: 11, weight: .semibold, color: water)
        text(&ctx, "2 out", at: CGPoint(x: 250, y: 176), size: 11, weight: .semibold, color: water)
        text(&ctx, "water cannot pile up at a junction", at: CGPoint(x: 160, y: 32), size: 11, weight: .semibold)
        text(&ctx, "what flows in must flow out:  5 = 3 + 2", at: CGPoint(x: 160, y: 208), size: 12, weight: .semibold, color: green)
    }

    /// One pipe with two narrow sections: the same flow through both, the pressure used up in shares.
    static func waterSeries(_ ctx: inout GraphicsContext, _ phase: Double) {
        let y: CGFloat = 125
        let run = [CGPoint(x: 20, y: y), CGPoint(x: 300, y: y)]
        pipe(&ctx, run)
        narrowSection(&ctx, from: CGPoint(x: 85, y: y), to: CGPoint(x: 135, y: y))
        narrowSection(&ctx, from: CGPoint(x: 190, y: y), to: CGPoint(x: 240, y: y))
        flow(&ctx, along: run, phase: phase, speed: 50, color: water, spacing: 20, radius: 2.8)
        gauge(&ctx, at: CGPoint(x: 52, y: 82), value: 1.0, label: "100%")
        gauge(&ctx, at: CGPoint(x: 162, y: 82), value: 0.6, label: "60%")
        gauge(&ctx, at: CGPoint(x: 272, y: 82), value: 0.0, label: "0%")
        for x in [52.0, 162.0, 272.0] { line(&ctx, CGPoint(x: x, y: 96), CGPoint(x: x, y: y - 8), grey, 1) }
        text(&ctx, "one path: the same flow through both narrow sections", at: CGPoint(x: 160, y: 36), size: 11, weight: .semibold)
        text(&ctx, "pressure left", at: CGPoint(x: 160, y: 52), size: 10, color: grey)
        text(&ctx, "each narrow section uses up a share of the push: 100 → 60 → 0", at: CGPoint(x: 160, y: 190), size: 10.5, weight: .semibold, color: green)
        text(&ctx, "pump end", at: CGPoint(x: 30, y: 150), size: 9, color: grey)
        text(&ctx, "return", at: CGPoint(x: 290, y: 150), size: 9, color: grey)
    }

    /// Two pipes side by side: the same push on both, the flow shared, more through the wide one.
    static func waterParallel(_ ctx: inout GraphicsContext, _ phase: Double) {
        let inlet = [CGPoint(x: 20, y: 115), CGPoint(x: 90, y: 115)]
        let top = [CGPoint(x: 90, y: 115), CGPoint(x: 90, y: 68), CGPoint(x: 230, y: 68), CGPoint(x: 230, y: 115)]
        let bottom = [CGPoint(x: 90, y: 115), CGPoint(x: 90, y: 162), CGPoint(x: 230, y: 162), CGPoint(x: 230, y: 115)]
        let outlet = [CGPoint(x: 230, y: 115), CGPoint(x: 300, y: 115)]
        pipe(&ctx, top)
        pipe(&ctx, bottom)
        pipe(&ctx, inlet)
        pipe(&ctx, outlet)
        narrowSection(&ctx, from: CGPoint(x: 108, y: 162), to: CGPoint(x: 212, y: 162))
        flow(&ctx, along: inlet, phase: phase, speed: 75, color: water, spacing: 15)
        flow(&ctx, along: top, phase: phase, speed: 60, color: water, spacing: 15)
        flow(&ctx, along: bottom, phase: phase, speed: 25, color: water, spacing: 25, radius: 2.6)
        flow(&ctx, along: outlet, phase: phase, speed: 75, color: water, spacing: 15)
        text(&ctx, "5 in", at: CGPoint(x: 50, y: 96), size: 11, weight: .semibold, color: water)
        text(&ctx, "4 through the wide pipe", at: CGPoint(x: 160, y: 50), size: 11, weight: .semibold, color: water)
        text(&ctx, "1 through the narrow pipe", at: CGPoint(x: 160, y: 184), size: 11, weight: .semibold, color: water)
        text(&ctx, "5 out", at: CGPoint(x: 268, y: 96), size: 11, weight: .semibold, color: water)
        text(&ctx, "both pipes feel the same push", at: CGPoint(x: 160, y: 24), size: 11, weight: .semibold)
        text(&ctx, "two paths let more through than either alone", at: CGPoint(x: 160, y: 210), size: 11, weight: .semibold, color: green)
    }

    /// A tank with a stretchy wall across it: it fills, pushes back, and never lets water through.
    static func waterTank(_ ctx: inout GraphicsContext, _ phase: Double) {
        let t = min(phase, 5)
        let d = 1 - exp(-t / 1.5)
        let dist = 70 * 1.5 * d
        let chamber = CGRect(x: 150, y: 80, width: 100, height: 80)
        let inlet = [CGPoint(x: 62, y: 120), CGPoint(x: 150, y: 120)]
        let outlet = [CGPoint(x: 250, y: 120), CGPoint(x: 300, y: 120)]
        pipe(&ctx, inlet, bore: 9)
        pipe(&ctx, outlet, bore: 9)
        // Chamber, left compartment filled up to the bulging wall.
        ctx.fill(Path(chamber), with: .color(waterLight.opacity(0.5)))
        var left = Path()
        left.move(to: CGPoint(x: chamber.minX, y: chamber.minY))
        left.addLine(to: CGPoint(x: chamber.midX, y: chamber.minY))
        left.addQuadCurve(to: CGPoint(x: chamber.midX, y: chamber.maxY), control: CGPoint(x: chamber.midX + 70 * d, y: chamber.midY))
        left.addLine(to: CGPoint(x: chamber.minX, y: chamber.maxY))
        left.closeSubpath()
        ctx.fill(left, with: .color(water.opacity(0.35)))
        var membrane = Path()
        membrane.move(to: CGPoint(x: chamber.midX, y: chamber.minY))
        membrane.addQuadCurve(to: CGPoint(x: chamber.midX, y: chamber.maxY), control: CGPoint(x: chamber.midX + 70 * d, y: chamber.midY))
        stroke(&ctx, membrane, orange, 3.5)
        stroke(&ctx, Path(chamber), pipeWall, 3)
        flow(&ctx, along: inlet, phase: dist, speed: 1, color: water, spacing: 18, radius: 3)
        flow(&ctx, along: outlet, phase: dist, speed: 1, color: water, spacing: 18, radius: 3)
        pump(&ctx, at: CGPoint(x: 45, y: 120), angle: dist / 6, label: "pump")
        gauge(&ctx, at: CGPoint(x: 110, y: 120), value: d)
        text(&ctx, "stretchy wall", at: CGPoint(x: 200, y: 66), size: 10, weight: .semibold, color: orange)
        text(&ctx, "the water pushes the wall; the further it stretches,", at: CGPoint(x: 160, y: 186), size: 10.5, weight: .semibold)
        text(&ctx, "the harder it pushes back and the less flows in", at: CGPoint(x: 160, y: 201), size: 10.5, weight: .semibold)
        text(&ctx, t >= 4.5 ? "full: the pressure matches the pump, the flow has stopped" : "filling: flow \(Int(((1 - d) * 100).rounded()))%", at: CGPoint(x: 160, y: 40), size: 11, weight: .semibold, color: t >= 4.5 ? orange : water)
        text(&ctx, "no water ever gets through the wall", at: CGPoint(x: 160, y: 218), size: 10, color: grey)
    }

    /// A heavy paddle wheel in the pipe: slow to get going, and it keeps pushing when the pump stops.
    static func waterWheel(_ ctx: inout GraphicsContext, _ phase: Double) {
        let running = phase < 5
        let tau1 = 1.5, tau2 = 1.2
        let omega5 = 1 - exp(-5 / tau1)
        let turns: Double
        if running {
            turns = phase - tau1 * (1 - exp(-phase / tau1))
        } else {
            turns = 5 - tau1 * (1 - exp(-5 / tau1)) + omega5 * tau2 * (1 - exp(-(phase - 5) / tau2))
        }
        let speedNow = running ? 1 - exp(-phase / tau1) : omega5 * exp(-(phase - 5) / tau2)
        let run = [CGPoint(x: 62, y: 120), CGPoint(x: 300, y: 120)]
        pipe(&ctx, run, bore: 10)
        flow(&ctx, along: run, phase: 70 * turns, speed: 1, color: water, spacing: 18, radius: 3)
        wheel(&ctx, at: CGPoint(x: 175, y: 120), angle: 5 * turns)
        pump(&ctx, at: CGPoint(x: 45, y: 120), angle: running ? phase * 4 : 20, label: running ? "pump on" : "pump off")
        gauge(&ctx, at: CGPoint(x: 265, y: 120), value: speedNow, label: "flow")
        text(&ctx, "a heavy wheel sits in the pipe", at: CGPoint(x: 160, y: 40), size: 12, weight: .semibold)
        if running {
            text(&ctx, "pump on: the wheel is slow to get going, so the flow builds up gradually", at: CGPoint(x: 160, y: 190), size: 10.5, weight: .semibold, color: water)
        } else {
            text(&ctx, "pump off: the spinning wheel keeps pushing water for a moment", at: CGPoint(x: 160, y: 190), size: 10.5, weight: .semibold, color: orange)
        }
        text(&ctx, "it resists any change in the flow", at: CGPoint(x: 160, y: 210), size: 11, weight: .semibold, color: green)
    }
}
