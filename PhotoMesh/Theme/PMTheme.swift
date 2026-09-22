import SwiftUI
import UIKit

/// Design tokens. Photomath's crimson is swapped for a deep green everywhere.
enum PMTheme {
    // MARK: Colors
    static let accent = Color(red: 0.071, green: 0.420, blue: 0.239)          // #126B3D
    static let accentPressed = Color(red: 0.055, green: 0.330, blue: 0.188)
    static let accentSoft = Color(red: 0.071, green: 0.420, blue: 0.239).opacity(0.12)
    static let plusOrange = Color(red: 0.925, green: 0.455, blue: 0.129)
    static let whyOrange = Color(red: 0.965, green: 0.545, blue: 0.161)
    static let graphTeal = Color(red: 0.0, green: 0.502, blue: 0.565)

    static let ink = Color(red: 0.10, green: 0.10, blue: 0.10)
    static let secondaryText = Color(red: 0.52, green: 0.52, blue: 0.52)
    static let tertiaryText = Color(red: 0.70, green: 0.70, blue: 0.70)

    static let darkSheet = Color(red: 0.165, green: 0.165, blue: 0.165)
    static let groupedBackground = Color(red: 0.949, green: 0.949, blue: 0.969)
    static let cardBackground = Color.white
    static let keyboardBackground = Color(red: 0.965, green: 0.965, blue: 0.965)
    static let keyBackground = Color.white
    static let keyPressed = Color(red: 0.88, green: 0.88, blue: 0.88)
    static let keySeparator = Color(red: 0.85, green: 0.85, blue: 0.85)
    static let chipBorder = Color(red: 0.80, green: 0.80, blue: 0.80)
    static let toolbarChipActive = Color(red: 0.90, green: 0.90, blue: 0.91)
    static let hintPill = Color.black.opacity(0.55)

    // MARK: Metrics
    static let cardRadius: CGFloat = 16
    static let shutterDiameter: CGFloat = 66
    static let shutterRingDiameter: CGFloat = 78
    static let menuWidthFraction: CGFloat = 0.80

    // MARK: Animation
    static let menuAnimation: Animation = .spring(response: 0.36, dampingFraction: 0.88)
}

// MARK: - Reusable pieces

/// The green "Show Solution →" style pill.
struct PMPrimaryButtonStyle: ButtonStyle {
    var fillsWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 26)
            .padding(.vertical, 15)
            .frame(maxWidth: fillsWidth ? CGFloat.infinity : nil)
            .background(
                Capsule().fill(configuration.isPressed ? PMTheme.accentPressed : PMTheme.accent)
            )
            .shadow(color: PMTheme.accent.opacity(configuration.isPressed ? 0.15 : 0.32), radius: 10, y: 5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Black "Unlock Plus" style pill.
struct PMBlackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Capsule().fill(configuration.isPressed ? Color(white: 0.2) : .black))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// App logo mark: a rounded green square with a white mesh loop.
struct PMLogoMark: View {
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(PMTheme.accent)
            MeshLoopGlyph()
                .stroke(.white, style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round, lineJoin: .round))
                .padding(size * 0.24)
        }
        .frame(width: size, height: size)
    }
}

/// A rectangular loop with a resistor zigzag on the top edge.
struct MeshLoopGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(rect.width, rect.height) * 0.16
        let cut = rect.width * 0.46
        let cx = rect.midX
        let amp = rect.height * 0.11

        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addLine(to: CGPoint(x: cx - cut / 2, y: rect.minY))
        let n = 4
        let seg = cut / CGFloat(n + 1)
        for i in 1...n {
            let x = cx - cut / 2 + seg * CGFloat(i)
            let y = rect.minY + (i % 2 == 1 ? amp : -amp)
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.addLine(to: CGPoint(x: cx + cut / 2, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        return p
    }
}

/// Lowercase wordmark used in the drawer and Plus screen.
struct PMWordmark: View {
    var size: CGFloat = 24
    var showsPlus = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("photocircuits")
                .font(.system(size: size, weight: .medium, design: .rounded))
                .kerning(0.4)
                .foregroundStyle(PMTheme.ink)
            if showsPlus {
                Text("PLUS")
                    .font(.system(size: size * 0.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(PMTheme.accent)
            }
        }
    }
}

/// Grey circular close button used on dark sheets.
struct PMCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(white: 0.15))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color(white: 0.88)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }
}

extension View {
    /// Applies a corner radius only to selected corners.
    func pmCornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(PMRoundedCorner(radius: radius, corners: corners))
    }
}

struct PMRoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}
