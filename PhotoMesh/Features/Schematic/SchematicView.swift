import SwiftUI

/// Canvas wrapper whose camera animates (scale + offset are interpolated by SwiftUI).
private struct AnimatedSchematic: ViewModifier, Animatable {
    var camera: SchematicCamera
    let layout: SchematicLayout
    let style: SchematicStyle

    var animatableData: SchematicCamera.AnimatableData {
        get { camera.animatableData }
        set { camera.animatableData = newValue }
    }

    func body(content: Content) -> some View {
        Canvas(rendersAsynchronously: false) { context, size in
            SchematicRenderer.draw(layout, camera: camera, style: style, in: &context, size: size)
        }
    }
}

struct SchematicView: View {
    let layout: SchematicLayout
    var style = SchematicStyle()
    var camera = SchematicCamera()

    var body: some View {
        Color.clear.modifier(AnimatedSchematic(camera: camera, layout: layout, style: style))
    }
}

/// Faint dot grid, the paper behind schematics and the sketch canvas.
struct DotGrid: View {
    var spacing: CGFloat = 22
    var dotRadius: CGFloat = 1.1
    var color = Color(red: 0.78, green: 0.80, blue: 0.84)

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    path.addEllipse(in: CGRect(x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
                    x += spacing
                }
                y += spacing
            }
            context.fill(path, with: .color(color))
        }
        .allowsHitTesting(false)
    }
}

/// Fixed schematic panel above the steps: follows the open step, zooms onto what it talks about.
struct SchematicWindow: View {
    let layout: SchematicLayout
    let loops: [LoopPath]
    let focus: StepFocus
    let onExpand: () -> Void

    @State private var camera = SchematicCamera()
    @State private var size: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                Color.white
                DotGrid()
                SchematicView(layout: layout, style: SchematicStyle(focus: focus, loops: loops, formatter: FormattingPreferences.formatter()), camera: camera)
                    .contentShape(Rectangle())
                    .onTapGesture { onExpand() }

                Button(action: onExpand) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PMTheme.ink)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white).shadow(color: .black.opacity(0.15), radius: 6, y: 2))
                }
                .buttonStyle(.plain)
                .padding(10)
                .accessibilityLabel("Open circuit full screen")
            }
            .onAppear {
                size = geo.size
                camera = target(for: focus, in: geo.size)
            }
            .onChange(of: geo.size) { _, newSize in
                size = newSize
                camera = target(for: focus, in: newSize)
            }
            .onChange(of: focus) { _, newFocus in
                withAnimation(.spring(response: 0.7, dampingFraction: 0.86)) {
                    camera = target(for: newFocus, in: size)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.black.opacity(0.08)))
    }

    private func target(for focus: StepFocus, in size: CGSize) -> SchematicCamera {
        let full = layout.bounds
        guard focus.zoom else { return .fitting(full, in: size) }
        var region = SchematicRenderer.focusBounds(focus, loops: loops, layout: layout)
        guard !region.isEmpty else { return .fitting(full, in: size) }
        region = region.insetBy(60)
        // Keep at least ~45% of the circuit in view so the part stays in context.
        let minWidth = full.width * 0.45, minHeight = full.height * 0.45
        if region.width < minWidth {
            let c = region.center.x
            region.minX = c - minWidth / 2; region.maxX = c + minWidth / 2
        }
        if region.height < minHeight {
            let c = region.center.y
            region.minY = c - minHeight / 2; region.maxY = c + minHeight / 2
        }
        // Slide back inside the drawing when the padded region pokes out.
        if region.minX < full.minX { let d = full.minX - region.minX; region.minX += d; region.maxX += d }
        if region.maxX > full.maxX { let d = region.maxX - full.maxX; region.minX -= d; region.maxX -= d }
        if region.minY < full.minY { let d = full.minY - region.minY; region.minY += d; region.maxY += d }
        if region.maxY > full.maxY { let d = region.maxY - full.maxY; region.minY -= d; region.maxY -= d }
        return .fitting(region, in: size, padding: 14)
    }
}
