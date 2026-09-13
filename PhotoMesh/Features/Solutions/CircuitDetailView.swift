import SwiftUI

/// Analogue of Photomath's Graph screen: a zoomable schematic with a property panel.
struct CircuitDetailView: View {
    let solution: Solution

    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    private var detail: CircuitDetail? { solution.detail }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    CircuitSketchView(kind: detail?.sketch ?? .blank, showsGrid: true)
                        .scaleEffect(scale * pinch)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .contentShape(Rectangle())
                        .gesture(
                            MagnifyGesture()
                                .updating($pinch) { value, state, _ in state = value.magnification }
                                .onEnded { value in
                                    scale = min(max(scale * value.magnification, 0.6), 3)
                                }
                        )

                    Button {
                        Haptics.selection()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { scale = 1 }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "scope").font(.system(size: 13, weight: .medium))
                            Text("Re-center").font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(PMTheme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white).shadow(color: .black.opacity(0.15), radius: 8, y: 3))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 18)
                    .padding(.bottom, 14)
                }
                Color.clear.frame(height: 300)
            }

            propertyPanel
        }
        .navigationTitle("Circuit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private var propertyPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Color(white: 0.80))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 12)

            HStack(spacing: 10) {
                Rectangle().fill(PMTheme.graphTeal).frame(width: 14, height: 4)
                Text(detail?.subtitle ?? solution.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(PMTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Image(systemName: "hand.raised")
                    .font(.system(size: 18))
                    .foregroundStyle(PMTheme.ink)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            Divider()

            HStack(spacing: 0) {
                Rectangle().fill(PMTheme.graphTeal).frame(width: 3)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(detail?.properties ?? []) { property in
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(property.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(PMTheme.plusOrange)
                                .underline(true, pattern: .solid, color: PMTheme.plusOrange.opacity(0.7))
                            Text(property.value)
                                .font(.system(size: 15))
                                .foregroundStyle(PMTheme.ink)
                        }
                    }
                }
                .padding(.leading, 14)
                .padding(.vertical, 16)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(
            PMRoundedCorner(radius: 18, corners: [.topLeft, .topRight])
                .fill(Color.white)
                .shadow(color: .black.opacity(0.12), radius: 14, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

/// Draws the recognized circuit with `Canvas`. Respects the resistor-symbol setting.
struct CircuitSketchView: View {
    let kind: CircuitSketchKind
    var showsGrid = false

    @AppStorage(SettingsKeys.resistorStyle) private var resistorStyle: ResistorStyle = .ansi

    var body: some View {
        Canvas { context, size in
            if showsGrid {
                var grid = Path()
                let step: CGFloat = 28
                var x: CGFloat = 0
                while x <= size.width { grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height)); x += step }
                var y: CGFloat = 0
                while y <= size.height { grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y)); y += step }
                context.stroke(grid, with: .color(Color(white: 0.92)), lineWidth: 1)
            }
            guard kind == .seriesTwoResistors else { return }
            drawSeriesLoop(in: &context, size: size)
        }
    }

    private func drawSeriesLoop(in context: inout GraphicsContext, size: CGSize) {
        let inset: CGFloat = min(size.width, size.height) * 0.16
        let rect = CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
        let ink = PMTheme.ink
        let stroke = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)

        var wires = Path()
        // Left side with a battery gap in the middle
        let batteryGap: CGFloat = 16
        wires.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        wires.addLine(to: CGPoint(x: rect.minX, y: rect.midY + batteryGap / 2))
        wires.move(to: CGPoint(x: rect.minX, y: rect.midY - batteryGap / 2))
        wires.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        // Top: wire → R1 → wire
        wires.move(to: CGPoint(x: rect.minX, y: rect.minY))
        wires.addLine(to: CGPoint(x: rect.midX - 36, y: rect.minY))
        wires.move(to: CGPoint(x: rect.midX + 36, y: rect.minY))
        wires.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Right: wire → R2 → wire
        wires.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        wires.addLine(to: CGPoint(x: rect.maxX, y: rect.midY - 30))
        wires.move(to: CGPoint(x: rect.maxX, y: rect.midY + 30))
        wires.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        // Bottom
        wires.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
        wires.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        context.stroke(wires, with: .color(ink), style: stroke)

        // Battery plates
        var battery = Path()
        battery.move(to: CGPoint(x: rect.minX - 12, y: rect.midY - batteryGap / 2))
        battery.addLine(to: CGPoint(x: rect.minX + 12, y: rect.midY - batteryGap / 2))
        battery.move(to: CGPoint(x: rect.minX - 6, y: rect.midY + batteryGap / 2))
        battery.addLine(to: CGPoint(x: rect.minX + 6, y: rect.midY + batteryGap / 2))
        context.stroke(battery, with: .color(ink), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))

        // Resistors
        let r1 = resistorPath(from: CGPoint(x: rect.midX - 36, y: rect.minY), to: CGPoint(x: rect.midX + 36, y: rect.minY))
        let r2 = resistorPath(from: CGPoint(x: rect.maxX, y: rect.midY - 30), to: CGPoint(x: rect.maxX, y: rect.midY + 30))
        context.stroke(r1, with: .color(ink), style: stroke)
        context.stroke(r2, with: .color(ink), style: stroke)

        // Current arrow along the bottom wire
        var arrow = Path()
        let ay = rect.maxY + 16
        arrow.move(to: CGPoint(x: rect.midX + 22, y: ay))
        arrow.addLine(to: CGPoint(x: rect.midX - 22, y: ay))
        arrow.move(to: CGPoint(x: rect.midX - 14, y: ay - 6))
        arrow.addLine(to: CGPoint(x: rect.midX - 22, y: ay))
        arrow.addLine(to: CGPoint(x: rect.midX - 14, y: ay + 6))
        context.stroke(arrow, with: .color(PMTheme.accent), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

        // Labels
        func label(_ text: String, at point: CGPoint, color: Color? = nil, weight: Font.Weight = .medium) {
            context.draw(
                Text(text).font(.system(size: 13, weight: weight, design: .rounded)).foregroundStyle(color ?? ink),
                at: point
            )
        }
        label("12 V", at: CGPoint(x: rect.minX - 34, y: rect.midY))
        label("+", at: CGPoint(x: rect.minX - 20, y: rect.midY - batteryGap / 2 - 10), weight: .bold)
        label("R₁ = 100 Ω", at: CGPoint(x: rect.midX, y: rect.minY - 20))
        label("R₂ = 220 Ω", at: CGPoint(x: rect.maxX + 42, y: rect.midY))
        label("I = 37.5 mA", at: CGPoint(x: rect.midX, y: ay + 16), color: PMTheme.accent)
    }

    /// Resistor between two points: ANSI zigzag or IEC rectangle, with short leads.
    private func resistorPath(from a: CGPoint, to b: CGPoint) -> Path {
        var path = Path()
        let dx = b.x - a.x, dy = b.y - a.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return path }
        let ux = dx / length, uy = dy / length        // along
        let px = -uy, py = ux                          // perpendicular
        let lead = length * 0.12
        let bodyStart = CGPoint(x: a.x + ux * lead, y: a.y + uy * lead)
        let bodyEnd = CGPoint(x: b.x - ux * lead, y: b.y - uy * lead)
        let amp: CGFloat = 7

        path.move(to: a)
        path.addLine(to: bodyStart)

        switch resistorStyle {
        case .ansi:
            let peaks = 6
            let bodyLength = length - lead * 2
            let segment = bodyLength / CGFloat(peaks + 1)
            for i in 1...peaks {
                let along = segment * CGFloat(i)
                let side: CGFloat = (i % 2 == 1) ? 1 : -1
                path.addLine(to: CGPoint(
                    x: bodyStart.x + ux * along + px * amp * side,
                    y: bodyStart.y + uy * along + py * amp * side
                ))
            }
            path.addLine(to: bodyEnd)
        case .iec:
            let corners = [
                CGPoint(x: bodyStart.x + px * amp, y: bodyStart.y + py * amp),
                CGPoint(x: bodyEnd.x + px * amp, y: bodyEnd.y + py * amp),
                CGPoint(x: bodyEnd.x - px * amp, y: bodyEnd.y - py * amp),
                CGPoint(x: bodyStart.x - px * amp, y: bodyStart.y - py * amp),
            ]
            path.move(to: corners[0])
            path.addLine(to: corners[1])
            path.addLine(to: corners[2])
            path.addLine(to: corners[3])
            path.closeSubpath()
            path.move(to: bodyEnd)
        }
        path.addLine(to: b)
        return path
    }
}

#Preview {
    NavigationStack {
        CircuitDetailView(solution: MockCircuitSolver.seriesLoop)
    }
}
