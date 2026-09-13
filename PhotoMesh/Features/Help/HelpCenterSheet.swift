import SwiftUI

/// "How to use" – dark sheet with illustrated cards.
struct HelpCenterSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PMTheme.darkSheet.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("How to use")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.top, 58)

                    HelpCard(
                        title: "Camera adjustment",
                        caption: "Capture your entire circuit within the white lines by adjusting the viewfinder size."
                    ) {
                        CameraAdjustmentIllustration()
                    }

                    HelpCard(
                        title: "Advanced calculator",
                        caption: "Explore additional keyboard options by tapping any key with a green dot."
                    ) {
                        KeyboardIllustration()
                    }

                    HelpCard(
                        title: "Solving steps",
                        caption: "Tap Next Step to walk through the analysis one step at a time, or open the circuit card to inspect every value."
                    ) {
                        StepsIllustration()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }

            PMCloseButton { dismiss() }
                .padding(.top, 14)
                .padding(.trailing, 16)
        }
    }
}

private struct HelpCard<Illustration: View>: View {
    let title: String
    let caption: String
    @ViewBuilder let illustration: () -> Illustration

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(PMTheme.ink)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)

            illustration()
                .aspectRatio(1, contentMode: .fit)
                .clipped()

            Text(caption)
                .font(.system(size: 17))
                .foregroundStyle(PMTheme.ink)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
        }
        .background(RoundedRectangle(cornerRadius: PMTheme.cardRadius, style: .continuous).fill(Color.white))
    }
}

// MARK: - Illustrations

private struct PlayBadge: View {
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

private struct GridPaper: View {
    var spacing: CGFloat = 14
    var color: Color = Color(white: 0.72)

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += spacing }
            var y: CGFloat = 0
            while y <= size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += spacing }
            context.stroke(path, with: .color(color), lineWidth: 0.8)
        }
        .background(Color(white: 0.86))
    }
}

/// Hand-drawn style series loop used across the help cards.
private struct CircuitSketchGlyph: View {
    var body: some View {
        ZStack {
            MeshLoopGlyph()
                .stroke(PMTheme.ink, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            // battery on the left edge
            HStack(spacing: 3) {
                Rectangle().frame(width: 2.2, height: 18)
                Rectangle().frame(width: 2.2, height: 10)
            }
            .foregroundStyle(PMTheme.ink)
            .background(Color(white: 0.86).frame(width: 12, height: 22))
            .offset(x: -50)
        }
    }
}

private struct CameraAdjustmentIllustration: View {
    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            ZStack {
                PMTheme.accent

                // Paper behind the phone
                GridPaper()
                    .frame(width: side * 0.78, height: side * 0.86)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .rotationEffect(.degrees(-9))
                    .offset(x: side * 0.06, y: side * 0.08)

                // Phone
                ZStack {
                    RoundedRectangle(cornerRadius: 36, style: .continuous).fill(Color.white)
                    GridPaper()
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .padding(9)
                    VStack(spacing: 0) {
                        Spacer()
                        ZStack {
                            CircuitSketchGlyph()
                                .frame(width: 118, height: 62)
                            ViewfinderMiniature()
                                .frame(width: 150, height: 92)
                        }
                        Spacer()
                        ZStack {
                            Circle().stroke(Color.white, lineWidth: 2).frame(width: 34, height: 34)
                            Circle().fill(PMTheme.accent).frame(width: 28, height: 28)
                        }
                        .padding(.bottom, 26)
                    }
                    .padding(9)
                }
                .frame(width: side * 0.46, height: side * 0.86)
                .rotationEffect(.degrees(-12))
                .shadow(color: .black.opacity(0.25), radius: 14, y: 8)

                PlayBadge()
            }
        }
    }
}

private struct ViewfinderMiniature: View {
    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                CornerBracket()
                    .rotationEffect(.degrees(Double(index) * 90))
                    .frame(width: 14, height: 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(for: index))
            }
            Crosshair().scaleEffect(0.6)
        }
    }

    private func alignment(for index: Int) -> Alignment {
        switch index {
        case 0: return .topLeading
        case 1: return .topTrailing
        case 2: return .bottomTrailing
        default: return .bottomLeading
        }
    }
}

private struct KeyboardIllustration: View {
    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
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

                PlayBadge()
            }
        }
    }
}

private struct StepsIllustration: View {
    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            ZStack {
                PMTheme.darkSheet

                VStack(alignment: .leading, spacing: 10) {
                    Text("SOLVING STEPS")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(PMTheme.secondaryText)
                    Text("Find the loop current")
                        .font(.system(size: 15, weight: .bold))
                    Text("Rₑq = R₁ + R₂ = 320 Ω")
                        .font(.system(size: 13))
                    HStack(spacing: 0) {
                        Rectangle().fill(PMTheme.accent).frame(width: 3)
                        Text("I = 37.5 mA")
                            .font(.system(size: 18, weight: .bold))
                            .padding(.leading, 10)
                    }
                    .padding(.leading, -14)
                    HStack {
                        Spacer()
                        HStack(spacing: 6) {
                            Text("Next Step").font(.system(size: 12, weight: .semibold))
                            Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Capsule().fill(PMTheme.accent))
                        Spacer()
                    }
                    .padding(.top, 4)
                }
                .padding(14)
                .frame(width: side * 0.68)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                .rotationEffect(.degrees(-6))
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)

                PlayBadge()
            }
        }
    }
}

#Preview {
    HelpCenterSheet()
}
