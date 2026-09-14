import SwiftUI

/// Two layers under one animated camera: the schematic itself, redrawn only when the camera or
/// the step changes, and above it (when the step shows moving currents) a light canvas that
/// places dots along a precomputed `FlowField` ~30 times a second. Keeping the labels and symbols
/// out of the per-frame work is what keeps the motion smooth while zooming.
private struct AnimatedSchematic: ViewModifier, Animatable {
    var camera: SchematicCamera
    let layout: SchematicLayout
    let style: SchematicStyle
    let field: FlowField?

    var animatableData: SchematicCamera.AnimatableData {
        get { camera.animatableData }
        set { camera.animatableData = newValue }
    }

    func body(content: Content) -> some View {
        ZStack {
            Canvas(rendersAsynchronously: false) { context, size in
                SchematicRenderer.draw(layout, camera: camera, style: style, in: &context, size: size)
            }
            if let field, !field.isEmpty {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    Canvas(rendersAsynchronously: false) { context, _ in
                        SchematicRenderer.drawFlow(field, camera: camera, phase: timeline.date.timeIntervalSinceReferenceDate, in: &context)
                    }
                }
                .allowsHitTesting(false)
            }
        }
    }
}

struct SchematicView: View {
    let layout: SchematicLayout
    var style = SchematicStyle()
    var camera = SchematicCamera()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var field: FlowField?

    /// What the flow field depends on; it is rebuilt only when this changes, never per frame or per pinch.
    private struct FieldKey: Hashable {
        var layout: SchematicLayout
        var focus: StepFocus
        var loops: [LoopPath]
    }

    private var fieldKey: FieldKey { FieldKey(layout: layout, focus: style.focus, loops: style.loops) }
    private var animates: Bool { style.focus.animateCurrents && !reduceMotion }

    var body: some View {
        Color.clear
            .modifier(AnimatedSchematic(camera: camera, layout: layout, style: style, field: animates ? field : nil))
            .onAppear { rebuildField() }
            .onChange(of: fieldKey) { _, _ in rebuildField() }
    }

    private func rebuildField() {
        guard style.focus.animateCurrents else { field = nil; return }
        field = FlowField.build(layout: layout, focus: style.focus, loops: style.loops, focusedElements: SchematicRenderer.focusedElementIds(style))
    }
}

/// Faint dot grid, the paper behind schematics and the sketch canvas.
struct DotGrid: View {
    var spacing: CGFloat = 22
    var dotRadius: CGFloat = 1.1
    var color = Color(red: 0.78, green: 0.80, blue: 0.84)
    /// View-space position of one grid dot; others repeat every `spacing`.
    var origin: CGPoint? = nil

    var body: some View {
        Canvas { context, size in
            var step = max(spacing, 1)
            while step < 9 { step *= 2 }   // thin out when zoomed far out
            let base = origin ?? CGPoint(x: step / 2, y: step / 2)
            let startX = base.x - (base.x / step).rounded(.up) * step
            let startY = base.y - (base.y / step).rounded(.up) * step
            var path = Path()
            var y = startY
            while y < size.height + step {
                var x = startX
                while x < size.width + step {
                    path.addEllipse(in: CGRect(x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
                    x += step
                }
                y += step
            }
            context.fill(path, with: .color(color))
        }
        .allowsHitTesting(false)
    }
}

/// Fixed schematic panel above the steps: follows the open step and zooms onto what it talks about.
/// Drag to pan and pinch to zoom in place; the next step's focus takes the camera back over.
struct SchematicWindow: View {
    let layout: SchematicLayout
    let loops: [LoopPath]
    let focus: StepFocus
    let onExpand: () -> Void

    private struct PinchState {
        var magnification: CGFloat
        var anchor: CGPoint
    }

    @State private var committed = SchematicCamera()
    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var pinch: PinchState? = nil
    @State private var size: CGSize = .zero
    @State private var userMoved = false

    /// Space kept free at the top-right for the expand button when fitting.
    private let controlInsets = EdgeInsets(top: 34, leading: 14, bottom: 14, trailing: 14)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                Color.white
                DotGrid()
                SchematicView(layout: layout, style: SchematicStyle(focus: focus, loops: loops, formatter: FormattingPreferences.formatter()), camera: liveCamera)
                    .contentShape(Rectangle())
                    .gesture(SimultaneousGesture(dragGesture, magnifyGesture))
                    .onTapGesture(count: 2) {
                        userMoved = false
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            committed = target(for: focus, in: size)
                        }
                    }

                HStack(spacing: 6) {
                    if userMoved {
                        Button {
                            userMoved = false
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                committed = target(for: focus, in: size)
                            }
                        } label: {
                            Image(systemName: "scope")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(PMTheme.ink)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Color.white.opacity(0.9)).shadow(color: .black.opacity(0.12), radius: 4, y: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Re-centre on this step")
                        .transition(.scale.combined(with: .opacity))
                    }
                    Button(action: onExpand) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(PMTheme.ink)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.white.opacity(0.9)).shadow(color: .black.opacity(0.12), radius: 4, y: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open circuit full screen")
                }
                .padding(6)
                .animation(.easeOut(duration: 0.2), value: userMoved)
            }
            .onAppear {
                size = geo.size
                committed = target(for: focus, in: geo.size)
            }
            .onChange(of: geo.size) { _, newSize in
                size = newSize
                if !userMoved { committed = target(for: focus, in: newSize) }
            }
            .onChange(of: focus) { _, newFocus in
                userMoved = false
                withAnimation(.spring(response: 0.7, dampingFraction: 0.86)) {
                    committed = target(for: newFocus, in: size)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.black.opacity(0.08)))
    }

    // MARK: Camera

    private var liveCamera: SchematicCamera {
        var camera = committed
        if let pinch {
            let newScale = min(max(camera.scale * pinch.magnification, 0.05), 8)
            let ratio = newScale / camera.scale
            camera.offset = CGSize(
                width: pinch.anchor.x - (pinch.anchor.x - camera.offset.width) * ratio,
                height: pinch.anchor.y - (pinch.anchor.y - camera.offset.height) * ratio
            )
            camera.scale = newScale
        }
        camera.offset.width += dragTranslation.width
        camera.offset.height += dragTranslation.height
        return camera
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .updating($dragTranslation) { value, state, _ in state = value.translation }
            .onEnded { value in
                committed.offset.width += value.translation.width
                committed.offset.height += value.translation.height
                userMoved = true
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in
                state = PinchState(magnification: value.magnification, anchor: value.startLocation)
            }
            .onEnded { value in
                let newScale = min(max(committed.scale * value.magnification, 0.05), 8)
                let ratio = newScale / committed.scale
                committed.offset = CGSize(
                    width: value.startLocation.x - (value.startLocation.x - committed.offset.width) * ratio,
                    height: value.startLocation.y - (value.startLocation.y - committed.offset.height) * ratio
                )
                committed.scale = newScale
                userMoved = true
            }
    }

    private func target(for focus: StepFocus, in size: CGSize) -> SchematicCamera {
        let full = layout.bounds
        guard focus.zoom else { return .fitting(full, in: size, insets: controlInsets) }
        var region = SchematicRenderer.focusBounds(focus, loops: loops, layout: layout)
        guard !region.isEmpty else { return .fitting(full, in: size, insets: controlInsets) }
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
        return .fitting(region, in: size, insets: controlInsets)
    }
}
