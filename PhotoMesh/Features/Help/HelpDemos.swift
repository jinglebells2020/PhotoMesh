import SwiftUI

/// Looping demonstrations for the Help cards: real drawings of what the app does, driven by a
/// clock rather than a video file, so they stay crisp at any size and never need downloading.
/// Tap the play badge to start; tap again to pause on the current frame.
struct DemoPlayer<Content: View>: View {
    /// Length of one loop in seconds.
    let duration: Double
    /// Start moving as soon as the player appears (lessons); Help cards wait for a tap.
    var autoplay = false
    @ViewBuilder let content: (_ phase: Double, _ playing: Bool) -> Content

    @State private var playing: Bool
    @State private var startedAt = Date()
    @State private var pausedPhase = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(duration: Double, autoplay: Bool = false, @ViewBuilder content: @escaping (_ phase: Double, _ playing: Bool) -> Content) {
        self.duration = duration
        self.autoplay = autoplay
        self.content = content
        _playing = State(initialValue: autoplay)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playing)) { timeline in
            let phase = playing ? (pausedPhase + timeline.date.timeIntervalSince(startedAt)).truncatingRemainder(dividingBy: duration) : pausedPhase
            ZStack {
                content(phase, playing)
                if !playing {
                    PlayBadge()
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { toggle() }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(playing ? "Pause demonstration" : "Play demonstration")
    }

    private func toggle() {
        if playing {
            pausedPhase = (pausedPhase + Date().timeIntervalSince(startedAt)).truncatingRemainder(dividingBy: duration)
            playing = false
        } else {
            startedAt = Date()
            playing = true
        }
        Haptics.selection()
    }
}

struct PlayBadge: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.55))
            Image(systemName: "play.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: 2)
        }
        .frame(width: 66, height: 66)
    }
}

/// Eased progress of `phase` through the window `from…to` (0 before, 1 after).
func demoProgress(_ phase: Double, _ from: Double, _ to: Double) -> Double {
    guard to > from else { return phase >= to ? 1 : 0 }
    let t = min(max((phase - from) / (to - from), 0), 1)
    return t * t * (3 - 2 * t)
}

// MARK: - Shared sample circuit

enum DemoCircuit {
    static let analysis: CircuitAnalysis? = try? CircuitAnalyzer.analyze(SampleCircuitSolver.sample)

    static var layout: SchematicLayout? { analysis?.layout }

    /// A step that knows currents and voltages, for the moving dots.
    static var flowFocus: StepFocus {
        guard let analysis else { return StepFocus() }
        for method in analysis.methods {
            if let step = method.steps.first(where: { $0.focus.showPolarity }) { return step.focus }
        }
        return analysis.methods.first?.steps.last(where: { $0.focus.animateCurrents })?.focus ?? StepFocus()
    }
}

// MARK: - Scan

/// The viewfinder closes in on a sketched circuit, a scan line passes, the parts are detected
/// one by one and the clean schematic takes the sketch's place.
struct ScanDemo: View {
    let phase: Double
    let playing: Bool

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            let fit = demoProgress(phase, 0.3, 1.5)
            let sweep = demoProgress(phase, 1.7, 2.8)
            let detect = demoProgress(phase, 2.8, 3.8)
            let clean = demoProgress(phase, 4.0, 4.9)
            let boxOffsets: [CGSize] = [CGSize(width: -48, height: -4), CGSize(width: 0, height: -30), CGSize(width: 48, height: -4)]
            let frameWidth: CGFloat = 210 - 50 * CGFloat(fit)
            let frameHeight: CGFloat = 150 - 52 * CGFloat(fit)
            let scanOffset: CGFloat = -50 + 100 * CGFloat(sweep)
            let scanning = sweep > 0 && sweep < 1
            ZStack {
                PMTheme.accent
                ZStack {
                    RoundedRectangle(cornerRadius: 36, style: .continuous).fill(Color.white)
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color(white: 0.86))
                        .padding(9)
                    VStack(spacing: 0) {
                        Spacer()
                        ZStack {
                            // The page: a pencil sketch that becomes a clean drawing.
                            SketchedLoop()
                                .opacity(1 - clean)
                            if let layout = DemoCircuit.layout {
                                SchematicView(layout: layout, style: SchematicStyle(showsNodeLabels: false, formatter: FormattingPreferences.formatter()), camera: .fitting(layout.bounds, in: CGSize(width: 150, height: 90), padding: 6))
                                    .frame(width: 150, height: 90)
                                    .opacity(clean)
                            }
                            // Detection boxes
                            ForEach(0..<3, id: \.self) { index in
                                let on: Double = min(max(detect * 3 - Double(index), 0), 1)
                                let grow: CGFloat = CGFloat(0.6 + 0.4 * on)
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(PMTheme.accent, lineWidth: 2)
                                    .frame(width: 34, height: 22)
                                    .offset(boxOffsets[index])
                                    .opacity(on * (1 - clean))
                                    .scaleEffect(grow)
                            }
                            // Scan line
                            Rectangle()
                                .fill(LinearGradient(colors: [PMTheme.accent.opacity(0), PMTheme.accent, PMTheme.accent.opacity(0)], startPoint: .top, endPoint: .bottom))
                                .frame(width: 160, height: 26)
                                .offset(y: scanOffset)
                                .opacity(scanning ? 0.9 : 0)
                            // Viewfinder brackets close in on the circuit
                            ViewfinderFrame()
                                .frame(width: frameWidth, height: frameHeight)
                        }
                        .frame(height: 170)
                        Spacer()
                        ZStack {
                            Circle().stroke(Color.white, lineWidth: 2).frame(width: 34, height: 34)
                            Circle().fill(PMTheme.accent).frame(width: 28, height: 28)
                                .scaleEffect(sweep > 0 && sweep < 0.3 ? 0.8 : 1.0)
                        }
                        .padding(.bottom, 26)
                    }
                    .padding(9)
                }
                .frame(width: side * 0.56, height: side * 0.92)
                .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
                .rotationEffect(.degrees(-6 + 6 * fit))
            }
        }
    }
}

/// Pencil-style series loop: battery on the left, two resistors, a ground.
private struct SketchedLoop: View {
    var body: some View {
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            var path = Path()
            let w: CGFloat = 130, h: CGFloat = 70
            let x0 = c.x - w / 2, x1 = c.x + w / 2, y0 = c.y - h / 2, y1 = c.y + h / 2
            // Loop with slight hand wobble
            func wobble(_ p: CGPoint, _ k: CGFloat) -> CGPoint { CGPoint(x: p.x + sin(k * 7) * 0.8, y: p.y + cos(k * 5) * 0.8) }
            let corners = [CGPoint(x: x0, y: y1), CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0), CGPoint(x: x1, y: y1), CGPoint(x: x0, y: y1)]
            path.move(to: corners[0])
            for (i, corner) in corners.dropFirst().enumerated() { path.addLine(to: wobble(corner, CGFloat(i))) }
            // Zigzag on the top wire
            let zx = c.x - 22
            path.move(to: CGPoint(x: zx, y: y0))
            for k in 0..<6 {
                let dy: CGFloat = k % 2 == 0 ? -8 : 8
                path.addLine(to: CGPoint(x: zx + CGFloat(k) * 7 + 3.5, y: y0 + dy))
            }
            path.addLine(to: CGPoint(x: zx + 44, y: y0))
            // Zigzag on the right wire
            let zy = c.y - 18
            path.move(to: CGPoint(x: x1, y: zy))
            for k in 0..<5 {
                let dx: CGFloat = k % 2 == 0 ? -8 : 8
                path.addLine(to: CGPoint(x: x1 + dx, y: zy + CGFloat(k) * 7 + 3.5))
            }
            path.addLine(to: CGPoint(x: x1, y: zy + 38))
            context.stroke(path, with: .color(PMTheme.ink.opacity(0.85)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            // Battery plates on the left wire (gap in the wire)
            var plates = Path()
            let by = c.y
            plates.move(to: CGPoint(x: x0 - 9, y: by - 5)); plates.addLine(to: CGPoint(x: x0 + 9, y: by - 5))
            plates.move(to: CGPoint(x: x0 - 5, y: by + 4)); plates.addLine(to: CGPoint(x: x0 + 5, y: by + 4))
            context.fill(Path(CGRect(x: x0 - 3, y: by - 9, width: 6, height: 17)), with: .color(Color(white: 0.86)))
            context.stroke(plates, with: .color(PMTheme.ink.opacity(0.85)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            // Ground under the bottom wire
            var ground = Path()
            ground.move(to: CGPoint(x: c.x + 10, y: y1)); ground.addLine(to: CGPoint(x: c.x + 10, y: y1 + 8))
            for (i, half) in [CGFloat(9), CGFloat(6), CGFloat(3)].enumerated() {
                let yy: CGFloat = y1 + 8 + CGFloat(i) * 4
                ground.move(to: CGPoint(x: c.x + 10 - half, y: yy)); ground.addLine(to: CGPoint(x: c.x + 10 + half, y: yy))
            }
            context.stroke(ground, with: .color(PMTheme.ink.opacity(0.85)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .frame(width: 170, height: 110)
    }
}

private struct ViewfinderFrame: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let l: CGFloat = 16
                var path = Path()
                for (x, y, dx, dy) in [(0, 0, 1, 1), (size.width, 0, -1, 1), (size.width, size.height, -1, -1), (0, size.height, 1, -1)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
                    path.move(to: CGPoint(x: x, y: y + dy * l)); path.addLine(to: CGPoint(x: x, y: y)); path.addLine(to: CGPoint(x: x + dx * l, y: y))
                }
                context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                var cross = Path()
                cross.move(to: CGPoint(x: c.x - 7, y: c.y)); cross.addLine(to: CGPoint(x: c.x + 7, y: c.y))
                cross.move(to: CGPoint(x: c.x, y: c.y - 7)); cross.addLine(to: CGPoint(x: c.x, y: c.y + 7))
                context.stroke(cross, with: .color(.white.opacity(0.9)), lineWidth: 1.5)
            }
        }
    }
}

// MARK: - Draw

/// A finger draws a zigzag on a wire, which snaps into a resistor; then a circle, which asks
/// what it is and becomes a source with a value.
struct DrawDemo: View {
    let phase: Double
    let playing: Bool

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            let stroke1 = demoProgress(phase, 0.4, 1.9)
            let snap1 = demoProgress(phase, 2.0, 2.4)
            let stroke2 = demoProgress(phase, 2.9, 4.1)
            let bubble = demoProgress(phase, 4.2, 4.6)
            let pick = demoProgress(phase, 5.2, 5.5)
            let value = demoProgress(phase, 5.7, 6.2)
            let bubbleScale: CGFloat = CGFloat(0.8 + 0.2 * bubble)
            let bubblePosition = CGPoint(x: side * 0.42, y: side * 0.5 + 30)
            let highlightVoltage = phase > 4.9
            ZStack {
                Color.white
                DotGrid(spacing: 18, dotRadius: 1.2)
                Canvas { context, size in
                    let midY = size.height * 0.5
                    let wireY = midY - 30
                    let x0 = size.width * 0.12, x1 = size.width * 0.88
                    // The loop already drawn
                    var wires = Path()
                    wires.move(to: CGPoint(x: x0, y: wireY)); wires.addLine(to: CGPoint(x: x1, y: wireY))
                    wires.addLine(to: CGPoint(x: x1, y: wireY + 120)); wires.addLine(to: CGPoint(x: x0, y: wireY + 120)); wires.closeSubpath()
                    context.stroke(wires, with: .color(PMTheme.ink), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    // 1. Zigzag stroke on the top wire
                    let zStart = CGPoint(x: size.width * 0.34, y: wireY), zEnd = CGPoint(x: size.width * 0.66, y: wireY)
                    var zig = Path()
                    zig.move(to: zStart)
                    let peaks = 6
                    let seg = (zEnd.x - zStart.x) / CGFloat(peaks + 1)
                    for k in 1...peaks {
                        let dy: CGFloat = k % 2 == 1 ? -13 : 13
                        zig.addLine(to: CGPoint(x: zStart.x + seg * CGFloat(k), y: wireY + dy))
                    }
                    zig.addLine(to: zEnd)
                    if stroke1 > 0, snap1 < 1 {
                        let strokeOpacity: Double = 0.75 * (1 - snap1)
                        context.stroke(zig.trimmedPath(from: 0, to: CGFloat(stroke1)), with: .color(PMTheme.accent.opacity(strokeOpacity)), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }
                    if snap1 > 0 {
                        // The clean resistor seated in the wire
                        let symbol = SchematicLayout.Symbol(id: "R1", kind: .resistor, value: 100, nodeA: "a", nodeB: "b", a: SPoint(x: Double(zStart.x), y: Double(wireY)), b: SPoint(x: Double(zEnd.x), y: Double(wireY)), labelSide: SPoint(x: 0, y: -1))
                        let centerX: CGFloat = (zStart.x + zEnd.x) / 2
                        let grow: CGFloat = CGFloat(0.85 + 0.15 * snap1)
                        var transform = CGAffineTransform(translationX: centerX, y: wireY)
                        transform = transform.scaledBy(x: grow, y: grow)
                        transform = transform.translatedBy(x: -centerX, y: -wireY)
                        let body = SchematicRenderer.symbolPath(symbol).applying(transform)
                        context.fill(Path(CGRect(x: zStart.x, y: wireY - 2, width: zEnd.x - zStart.x, height: 4)), with: .color(.white))
                        context.stroke(body, with: .color(PMTheme.ink.opacity(snap1)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        context.draw(Text("R₁").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(PMTheme.ink.opacity(snap1)), at: CGPoint(x: centerX, y: wireY - 22))
                    }

                    // 2. Circle stroke on the left wire
                    let cc = CGPoint(x: x0, y: wireY + 60)
                    let r: CGFloat = 20
                    var circle = Path()
                    for k in 0...40 {
                        let t: CGFloat = -CGFloat.pi / 2 + 2 * CGFloat.pi * CGFloat(k) / 40
                        let radius: CGFloat = r + sin(t * 3) * 1.2
                        let p = CGPoint(x: cc.x + radius * cos(t), y: cc.y + r * sin(t))
                        if k == 0 { circle.move(to: p) } else { circle.addLine(to: p) }
                    }
                    if stroke2 > 0, pick < 1 {
                        let strokeOpacity: Double = 0.75 * (1 - pick)
                        context.stroke(circle.trimmedPath(from: 0, to: CGFloat(stroke2)), with: .color(PMTheme.accent.opacity(strokeOpacity)), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }
                    if pick > 0 {
                        let source = SchematicLayout.Symbol(id: "V1", kind: .voltageSource, value: 9, nodeA: "a", nodeB: "0", a: SPoint(x: Double(cc.x), y: Double(cc.y - 40)), b: SPoint(x: Double(cc.x), y: Double(cc.y + 40)), labelSide: SPoint(x: -1, y: 0))
                        context.fill(Path(ellipseIn: CGRect(x: cc.x - 24, y: cc.y - 24, width: 48, height: 48)), with: .color(.white))
                        context.stroke(SchematicRenderer.symbolPath(source), with: .color(PMTheme.ink.opacity(pick)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        context.draw(Text("+").font(.system(size: 11, weight: .bold)).foregroundStyle(PMTheme.ink.opacity(pick)), at: CGPoint(x: cc.x + 14, y: cc.y - 12))
                        context.draw(Text("−").font(.system(size: 11, weight: .bold)).foregroundStyle(PMTheme.ink.opacity(pick)), at: CGPoint(x: cc.x + 14, y: cc.y + 12))
                        if value > 0 {
                            context.draw(Text("V₁  9 V").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(PMTheme.ink.opacity(value)), at: CGPoint(x: cc.x - 30, y: cc.y), anchor: .trailing)
                        }
                    }

                    // The finger
                    var finger: CGPoint?
                    if stroke1 > 0, stroke1 < 1 {
                        finger = zig.trimmedPath(from: 0, to: CGFloat(stroke1)).currentPoint
                    } else if stroke2 > 0, stroke2 < 1 {
                        finger = circle.trimmedPath(from: 0, to: CGFloat(stroke2)).currentPoint
                    }
                    if let finger {
                        context.fill(Path(ellipseIn: CGRect(x: finger.x - 11, y: finger.y - 11, width: 22, height: 22)), with: .color(PMTheme.accent.opacity(0.25)))
                        context.fill(Path(ellipseIn: CGRect(x: finger.x - 5, y: finger.y - 5, width: 10, height: 10)), with: .color(PMTheme.accent.opacity(0.9)))
                    }
                }
                // The "what is it?" bubble
                if bubble > 0, pick < 1 {
                    HStack(spacing: 2) {
                        ForEach(Array(["Voltage", "Current", "Lamp", "Battery"].enumerated()), id: \.offset) { index, name in
                            VStack(spacing: 3) {
                                PartGlyph(kind: [.voltageSource, .currentSource, .lamp, .battery][index])
                                    .frame(width: 30, height: 16)
                                Text(name).font(.system(size: 9, weight: .medium))
                            }
                            .foregroundStyle(PMTheme.ink)
                            .frame(width: 50, height: 46)
                            .background(RoundedRectangle(cornerRadius: 8).fill(index == 0 && highlightVoltage ? PMTheme.accentSoft : Color.clear))
                        }
                    }
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white).shadow(color: .black.opacity(0.18), radius: 12, y: 4))
                    .scaleEffect(bubbleScale)
                    .opacity(bubble)
                    .position(bubblePosition)
                }
            }
        }
    }
}

// MARK: - Steps

/// The sample circuit with its currents flowing, and a step card whose lines appear one by one.
struct StepsDemo: View {
    let phase: Double
    let playing: Bool

    private let lines = ["KCL at node b:", "(Vb − 10)/2 + Vb/4 + (Vb − 5)/3 = 0", "× 12:  6·(Vb − 10) + 3·Vb + 4·(Vb − 5) = 0", "→ 13·Vb = 80", "Vb = 6.154 V"]

    /// The sample's voltages-and-currents focus, moving only while the demo plays.
    private func focus(_ playing: Bool) -> StepFocus {
        var focus = DemoCircuit.flowFocus
        focus.animateCurrents = playing
        return focus
    }

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            let revealed: Int = Int(min(Double(lines.count), floor(demoProgress(phase, 0.6, 4.0) * Double(lines.count) + 0.001)))
            let pulse: CGFloat = CGFloat(1 + 0.06 * sin(phase * 4))
            let panel = CGSize(width: side * 0.8, height: side * 0.42)
            ZStack {
                PMTheme.darkSheet
                VStack(spacing: 10) {
                    if let layout = DemoCircuit.layout {
                        ZStack {
                            Color.white
                            DotGrid()
                            SchematicView(layout: layout, style: SchematicStyle(focus: focus(playing), formatter: FormattingPreferences.formatter()), camera: .fitting(layout.bounds, in: panel, padding: 10))
                        }
                        .frame(width: panel.width, height: panel.height)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NODAL ANALYSIS")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(PMTheme.secondaryText)
                        Text("Apply KCL at node b")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(PMTheme.ink)
                        ForEach(Array(lines.prefix(revealed).enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: index == lines.count - 1 ? 14 : 11.5, weight: index == lines.count - 1 ? .bold : .regular, design: .rounded))
                                .foregroundStyle(index == lines.count - 1 ? PMTheme.accent : PMTheme.ink)
                                .transition(.opacity)
                        }
                        HStack {
                            Spacer()
                            HStack(spacing: 6) {
                                Text("Next step").font(.system(size: 12, weight: .semibold))
                                Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(PMTheme.accent))
                            .scaleEffect(revealed == lines.count ? pulse : 1.0)
                            Spacer()
                        }
                        .padding(.top, 2)
                    }
                    .padding(12)
                    .frame(width: side * 0.8, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                }
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
            }
        }
    }
}

// MARK: - Calculator

/// A finger holds a key with a green dot and its extra functions slide out.
struct CalculatorDemo: View {
    let phase: Double
    let playing: Bool

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            let press = demoProgress(phase, 0.6, 1.0)
            let popup = demoProgress(phase, 1.0, 1.4)
            let choose = demoProgress(phase, 2.6, 2.9)
            let fade = demoProgress(phase, 3.4, 3.8)
            let ringOpacity: Double = 0.28 * press * (1 - fade)
            let ringSize: CGFloat = CGFloat(40 * (0.6 + 0.4 * press))
            let popupScale: CGFloat = CGFloat(0.7 + 0.3 * popup)
            let popupOpacity: Double = popup * (1 - fade)
            let key = CGPoint(x: side * 0.31, y: side * 0.56)
            let popupPosition = CGPoint(x: key.x + 60, y: key.y - 48)
            ZStack {
                Color(red: 0.13, green: 0.36, blue: 0.98)
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 44, style: .continuous).fill(Color.black)
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .fill(Color.white)
                        .padding(10)
                    CalculatorKeyboardView(tab: .constant(.basic), isAlpha: .constant(false), isInteractive: false) { _ in }
                        .frame(width: 393)
                        .scaleEffect(side * 0.66 / 393, anchor: .bottom)
                        .frame(width: side * 0.66)
                        .padding(.bottom, 26)
                        .allowsHitTesting(false)
                }
                .frame(width: side * 0.72, height: side * 1.05)
                .offset(y: side * 0.24)

                // Finger on a key, and the extra functions above it
                Circle()
                    .fill(PMTheme.accent.opacity(ringOpacity))
                    .frame(width: ringSize, height: ringSize)
                    .position(key)
                HStack(spacing: 6) {
                    ForEach(Array(["x²", "xʸ", "√", "∛"].enumerated()), id: \.offset) { index, label in
                        Text(label)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(index == 2 && choose > 0 ? .white : PMTheme.ink)
                            .frame(width: 38, height: 38)
                            .background(RoundedRectangle(cornerRadius: 9).fill(index == 2 && choose > 0 ? PMTheme.accent : Color.white))
                    }
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white).shadow(color: .black.opacity(0.22), radius: 10, y: 4))
                .scaleEffect(popupScale, anchor: .bottom)
                .opacity(popupOpacity)
                .position(popupPosition)
            }
        }
    }
}
