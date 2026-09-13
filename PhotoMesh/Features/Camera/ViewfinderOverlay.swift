import SwiftUI

/// The scan area. Symmetric around `center`, like Photomath's viewfinder.
struct ScanRegion: Equatable {
    var center: CGPoint
    var size: CGSize

    static let minimumSize = CGSize(width: 120, height: 72)

    var rect: CGRect {
        CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }

    /// Default placement for a given screen: 86% wide, a short band a third of the way down.
    static func standard(in size: CGSize) -> ScanRegion {
        ScanRegion(
            center: CGPoint(x: size.width / 2, y: size.height * 0.355),
            size: CGSize(width: size.width * 0.86, height: 116)
        )
    }

    func clamped(to bounds: CGRect) -> ScanRegion {
        var region = self
        region.size.width = min(max(region.size.width, Self.minimumSize.width), bounds.width)
        region.size.height = min(max(region.size.height, Self.minimumSize.height), bounds.height)
        let halfW = region.size.width / 2
        let halfH = region.size.height / 2
        region.center.x = min(max(region.center.x, bounds.minX + halfW), bounds.maxX - halfW)
        region.center.y = min(max(region.center.y, bounds.minY + halfH), bounds.maxY - halfH)
        return region
    }
}

/// Four white corner brackets plus a centre crosshair. Corners resize symmetrically,
/// dragging the interior moves the whole area.
struct ViewfinderOverlay: View {
    @Binding var region: ScanRegion
    let bounds: CGRect
    var isDimmed = false

    @State private var dragOrigin: ScanRegion?

    private enum Corner: CaseIterable, Identifiable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
        var id: Self { self }

        var xSign: CGFloat { (self == .topTrailing || self == .bottomTrailing) ? 1 : -1 }
        var ySign: CGFloat { (self == .bottomLeading || self == .bottomTrailing) ? 1 : -1 }

        func point(in rect: CGRect) -> CGPoint {
            CGPoint(x: xSign > 0 ? rect.maxX : rect.minX, y: ySign > 0 ? rect.maxY : rect.minY)
        }

        var rotation: Angle {
            switch self {
            case .topLeading: return .degrees(0)
            case .topTrailing: return .degrees(90)
            case .bottomTrailing: return .degrees(180)
            case .bottomLeading: return .degrees(270)
            }
        }
    }

    var body: some View {
        let rect = region.rect
        ZStack {
            // Move handle (interior)
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .frame(width: max(rect.width - 56, 20), height: max(rect.height - 56, 20))
                .position(region.center)
                .gesture(moveGesture)

            Crosshair()
                .position(region.center)
                .allowsHitTesting(false)

            ForEach(Corner.allCases) { corner in
                CornerBracket()
                    .rotationEffect(corner.rotation)
                    .frame(width: 26, height: 26)
                    .frame(width: 60, height: 60)
                    .contentShape(Rectangle())
                    .position(corner.point(in: rect))
                    .gesture(resizeGesture(for: corner))
            }
        }
        .opacity(isDimmed ? 0.55 : 1)
        .animation(.easeOut(duration: 0.15), value: isDimmed)
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let origin = dragOrigin ?? region
                if dragOrigin == nil { dragOrigin = origin }
                var next = origin
                next.center.x += value.translation.width
                next.center.y += value.translation.height
                region = next.clamped(to: bounds)
            }
            .onEnded { _ in
                dragOrigin = nil
                Haptics.selection()
            }
    }

    private func resizeGesture(for corner: Corner) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let origin = dragOrigin ?? region
                if dragOrigin == nil { dragOrigin = origin }
                var next = origin
                next.size.width = origin.size.width + 2 * value.translation.width * corner.xSign
                next.size.height = origin.size.height + 2 * value.translation.height * corner.ySign
                // Keep the area symmetric around its centre and inside the allowed bounds.
                let maxW = 2 * min(origin.center.x - bounds.minX, bounds.maxX - origin.center.x)
                let maxH = 2 * min(origin.center.y - bounds.minY, bounds.maxY - origin.center.y)
                next.size.width = min(max(next.size.width, ScanRegion.minimumSize.width), maxW)
                next.size.height = min(max(next.size.height, ScanRegion.minimumSize.height), maxH)
                region = next
            }
            .onEnded { _ in
                dragOrigin = nil
                Haptics.selection()
            }
    }
}

/// One rounded "L" bracket drawn for the top-leading corner; rotate for the others.
struct CornerBracket: View {
    var body: some View {
        BracketShape()
            .stroke(.white, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
            .shadow(color: .black.opacity(0.35), radius: 1.5)
    }

    private struct BracketShape: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            let r: CGFloat = 8
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            return p
        }
    }
}

struct Crosshair: View {
    var body: some View {
        ZStack {
            Rectangle().frame(width: 18, height: 1.4)
            Rectangle().frame(width: 1.4, height: 18)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.35), radius: 1.2)
    }
}

#Preview {
    ZStack {
        Color.gray.ignoresSafeArea()
        ViewfinderOverlay(
            region: .constant(ScanRegion.standard(in: CGSize(width: 393, height: 852))),
            bounds: CGRect(x: 16, y: 120, width: 361, height: 500)
        )
    }
}
