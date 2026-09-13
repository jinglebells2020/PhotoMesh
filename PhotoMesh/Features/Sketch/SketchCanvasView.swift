import SwiftUI
import UIKit

/// Hand-drawn circuit entry. Keep drawing; every stroke is recognized on the spot without
/// interrupting you. Two fingers pan, pinch zooms, tap a part to edit it, double-tap to rotate.
/// Solve walks through anything that still needs a type or a value.
struct SketchCanvasView: View {
    let onSolve: (Circuit) -> Void

    private struct ReviewSession: Equatable {
        var queue: [UUID]
        var index = 0
        var solveAfter: Bool

        var current: UUID? { index < queue.count ? queue[index] : nil }
        var isLast: Bool { index >= queue.count - 1 }
    }

    private struct TransformSession {
        var zoomBase: CGFloat
        var panBase: CGSize
        var scale: CGFloat = 1
        var anchor: CGPoint
        var translation: CGSize = .zero
        var active: Set<String> = []
    }

    @State private var document = SketchDocument()
    @State private var history: [[SketchElement]] = []
    @State private var stroke: [CGPoint] = []
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var transform: TransformSession?
    @State private var review: ReviewSession?
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var selectedId: UUID?
    @State private var placingGround = false
    @State private var errorMessage: String?
    @State private var viewSize: CGSize = .zero

    private let minZoom: CGFloat = 0.35
    private let maxZoom: CGFloat = 3

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    Color.white
                    DotGrid(spacing: SketchGrid.step * zoom, dotRadius: 1.2, origin: CGPoint(x: pan.width, y: pan.height))
                    SchematicView(layout: document.layout(), style: liveStyle, camera: document.schematicCamera(zoom: zoom, pan: pan))
                        .allowsHitTesting(false)
                    StrokeOverlay(points: stroke)

                    SketchGestureHost(
                        onStrokeBegan: { point in
                            stroke = [point]
                        },
                        onStrokeMoved: { point in
                            stroke.append(point)
                        },
                        onStrokeEnded: { cancelled in
                            let points = stroke
                            stroke = []
                            guard !cancelled, points.count > 1 else { return }
                            handle(StrokeClassifier.classify(points.map(canvasPoint)))
                        },
                        onTap: { point in tapped(at: canvasPoint(point)) },
                        onDoubleTap: { point in doubleTapped(at: canvasPoint(point)) },
                        onPan: { translation, state in
                            updateTransform(gesture: "pan", state: state) { session in session.translation = translation }
                        },
                        onPinch: { scale, location, state in
                            updateTransform(gesture: "pinch", state: state, anchor: location) { session in session.scale = scale }
                        }
                    )

                    if document.elements.isEmpty, stroke.isEmpty {
                        emptyHint
                            .frame(width: geo.size.width, height: geo.size.height)
                    }

                    if placingGround {
                        banner("Tap the wire or terminal the ground connects to", systemImage: "arrowtriangle.down")
                    } else if let toast {
                        banner(toast, systemImage: "info.circle")
                    }
                }
                .onAppear { viewSize = geo.size }
                .onChange(of: geo.size) { _, newSize in viewSize = newSize }
            }
            .clipped()

            if let review, let element = document.elements.first(where: { $0.id == review.current }) {
                ElementPanel(
                    element: element,
                    progress: review.solveAfter ? "\(review.index + 1) of \(review.queue.count)" : nil,
                    primaryTitle: review.solveAfter ? (review.isLast ? "Solve" : "Next") : "Done",
                    onCommit: { kind, value in commit(kind: kind, value: value, for: element) },
                    onSkip: { advanceReview() },
                    onFlip: { update(element.id) { $0.flipped.toggle() } },
                    onAsk: { update(element.id) { $0.asked.toggle() } },
                    onDelete: {
                        remove(element.id)
                        advanceReview()
                    }
                )
                .id(element.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            toolbar
        }
        .background(Color.white)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: review)
        .alert("Not solvable yet", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Pieces

    private var emptyHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "scribble.variable")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(PMTheme.tertiaryText)
            Text("Draw your circuit")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(PMTheme.secondaryText)
            Text("Straight strokes become wires (corners are fine), a zigzag a resistor, a circle a source. Keep going; values come at the end. Two fingers move and zoom.")
                .font(.system(size: 13))
                .foregroundStyle(PMTheme.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .allowsHitTesting(false)
    }

    private func banner(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Capsule().fill(Color.black.opacity(0.72)))
        .padding(.top, 12)
        .allowsHitTesting(false)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            toolButton("arrow.uturn.backward", label: "Undo", disabled: history.isEmpty) { undo() }
            toolButton("trash", label: "Clear", disabled: document.elements.isEmpty) {
                commit()
                document.elements.removeAll()
                selectedId = nil
                review = nil
            }
            toolButton("arrowtriangle.down", label: "Ground", disabled: document.elements.isEmpty, active: placingGround) {
                withAnimation { placingGround.toggle() }
            }
            toolButton("arrow.up.left.and.down.right.magnifyingglass", label: "Fit", disabled: document.elements.isEmpty) {
                fitToContent()
            }

            Spacer(minLength: 4)

            Button(action: solveTapped) {
                HStack(spacing: 8) {
                    Text(document.needingAttention.isEmpty ? "Solve" : "Review & solve")
                    Image(systemName: "arrow.right").font(.system(size: 15, weight: .semibold))
                }
            }
            .buttonStyle(PMPrimaryButtonStyle())
            .disabled(!(document.hasSource && document.hasResistor))
            .opacity(document.hasSource && document.hasResistor ? 1 : 0.5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white)
        .overlay(alignment: .top) { Divider() }
    }

    private func toolButton(_ systemImage: String, label: String, disabled: Bool, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                Text(label)
                    .font(.system(size: 9.5))
            }
            .foregroundStyle(active ? PMTheme.accent : PMTheme.ink)
            .frame(width: 44, height: 40)
            .background(RoundedRectangle(cornerRadius: 9).fill(active ? PMTheme.accentSoft : Color.clear))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .accessibilityLabel(label)
    }

    private var liveStyle: SchematicStyle {
        var style = SchematicStyle(formatter: FormattingPreferences.formatter())
        style.pendingValueIds = Set(document.needingAttention.map(\.label))
        style.askedIds = Set(document.elements.filter(\.asked).map(\.label))
        let highlighted = review?.current ?? selectedId
        if let highlighted, let element = document.elements.first(where: { $0.id == highlighted }), element.isComponent {
            style.selection = .element(element.label)
        }
        return style
    }

    // MARK: Coordinates

    private func canvasPoint(_ viewPoint: CGPoint) -> CGPoint {
        CGPoint(x: (viewPoint.x - pan.width) / zoom, y: (viewPoint.y - pan.height) / zoom)
    }

    private func updateTransform(gesture: String, state: UIGestureRecognizer.State, anchor: CGPoint? = nil, change: (inout TransformSession) -> Void) {
        switch state {
        case .began:
            if transform == nil {
                transform = TransformSession(zoomBase: zoom, panBase: pan, anchor: anchor ?? CGPoint(x: viewSize.width / 2, y: viewSize.height / 2))
            }
            transform?.active.insert(gesture)
            if let anchor { transform?.anchor = anchor }
            fallthrough
        case .changed:
            guard var session = transform else { return }
            change(&session)
            transform = session
            let newZoom = min(max(session.zoomBase * session.scale, minZoom), maxZoom)
            let ratio = newZoom / session.zoomBase
            zoom = newZoom
            pan = CGSize(
                width: session.anchor.x - (session.anchor.x - session.panBase.width) * ratio + session.translation.width,
                height: session.anchor.y - (session.anchor.y - session.panBase.height) * ratio + session.translation.height
            )
        case .ended, .cancelled, .failed:
            transform?.active.remove(gesture)
            if transform?.active.isEmpty ?? true { transform = nil }
        default:
            break
        }
    }

    private func fitToContent() {
        let frame = document.contentFrame
        guard frame.width > 0, frame.height > 0, viewSize.width > 0 else { return }
        let newZoom = min(max(min(viewSize.width / frame.width, viewSize.height / frame.height), minZoom), maxZoom)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            zoom = newZoom
            pan = CGSize(width: viewSize.width / 2 - frame.midX * newZoom, height: viewSize.height / 2 - frame.midY * newZoom)
        }
    }

    private func center(on element: SketchElement) {
        guard viewSize.width > 0 else { return }
        let c = element.center
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            pan = CGSize(width: viewSize.width / 2 - c.x * zoom, height: viewSize.height * 0.42 - c.y * zoom)
        }
    }

    // MARK: Stroke handling

    private func handle(_ guess: StrokeGuess) {
        switch guess {
        case .tap(let point):
            tapped(at: point)
        case .wire(let from, let to):
            addWire(from: from, to: to)
        case .wirePath(let corners):
            addWirePath(corners)
        case .resistor(let center, let horizontal), .rectangle(let center, let horizontal):
            addComponent(.resistor, center: center, horizontal: horizontal, needsKind: false)
        case .roundShape(let center, _):
            addComponent(.voltageSource, center: center, horizontal: inferHorizontal(around: center), needsKind: true)
        case .shortMark(let center):
            addWire(from: CGPoint(x: center.x - SketchGrid.step / 2, y: center.y), to: CGPoint(x: center.x + SketchGrid.step / 2, y: center.y))
        case .unknown:
            showToast("Couldn't read that stroke. Try a straight line, a zigzag or a circle.")
            Haptics.notify(.warning)
        }
    }

    private func tapped(at point: CGPoint) {
        if placingGround {
            addGround(at: point)
            withAnimation { placingGround = false }
            return
        }
        if let element = element(at: point) {
            selectedId = element.id
            Haptics.selection()
            if element.isComponent {
                review = ReviewSession(queue: [element.id], solveAfter: false)
            } else {
                commit()
                document.elements.removeAll { $0.id == element.id }
                showToast("\(element.kind == .wire ? "Wire" : "Ground") removed")
            }
        } else {
            selectedId = nil
            if review?.solveAfter == false { review = nil }
        }
    }

    private func doubleTapped(at point: CGPoint) {
        if let element = element(at: point), element.isComponent {
            update(element.id) { $0.rotate() }
            Haptics.impact(.medium)
        } else {
            fitToContent()
        }
    }

    // MARK: Mutations

    private func commit() {
        history.append(document.elements)
        if history.count > 60 { history.removeFirst() }
    }

    private func undo() {
        guard let previous = history.popLast() else { return }
        document.elements = previous
        selectedId = nil
        review = nil
        Haptics.impact(.light)
    }

    private func update(_ id: UUID, _ change: (inout SketchElement) -> Void) {
        guard let index = document.elements.firstIndex(where: { $0.id == id }) else { return }
        commit()
        change(&document.elements[index])
    }

    private func remove(_ id: UUID) {
        commit()
        document.elements.removeAll { $0.id == id }
        if selectedId == id { selectedId = nil }
    }

    private func addWire(from rawFrom: CGPoint, to rawTo: CGPoint) {
        var from = SketchGrid.snap(rawFrom)
        var to = SketchGrid.snap(rawTo)
        let horizontal = abs(rawTo.x - rawFrom.x) >= abs(rawTo.y - rawFrom.y)
        if horizontal {
            let y = SketchGrid.snap(CGPoint(x: 0, y: (rawFrom.y + rawTo.y) / 2)).y
            from.y = y; to.y = y
        } else {
            let x = SketchGrid.snap(CGPoint(x: (rawFrom.x + rawTo.x) / 2, y: 0)).x
            from.x = x; to.x = x
        }
        if let near = nearestConnectionPoint(to: from, within: SketchGrid.step * 1.1) {
            from = near
            if horizontal { to.y = near.y } else { to.x = near.x }
        }
        if let near = nearestConnectionPoint(to: to, within: SketchGrid.step * 1.1) {
            to = near
            if horizontal { from.y = near.y } else { from.x = near.x }
        }
        guard from != to else { return }
        commit()
        document.elements.append(SketchElement(kind: .wire, a: from, b: to, label: document.nextLabel(for: .wire)))
        Haptics.impact(.light)
    }

    /// A stroke with corners becomes a chain of axis-aligned wires that meet exactly.
    private func addWirePath(_ corners: [CGPoint]) {
        guard corners.count >= 2 else { return }
        var current = SketchGrid.snap(corners[0])
        if let near = nearestConnectionPoint(to: current, within: SketchGrid.step * 1.1) { current = near }
        var segments: [(CGPoint, CGPoint)] = []
        for (index, raw) in corners.dropFirst().enumerated() {
            var target = SketchGrid.snap(raw)
            let isLast = index == corners.count - 2
            if isLast, let near = nearestConnectionPoint(to: target, within: SketchGrid.step * 1.1) { target = near }
            let horizontal = abs(raw.x - current.x) >= abs(raw.y - current.y)
            var next = horizontal ? CGPoint(x: target.x, y: current.y) : CGPoint(x: current.x, y: target.y)
            if isLast, next != target {
                // Finish with a short perpendicular so the path ends exactly on the target.
                if next != current { segments.append((current, next)) }
                current = next
                next = target
            }
            guard next != current else { continue }
            if let last = segments.last, sameAxis(last.0, last.1, current, next) {
                segments[segments.count - 1] = (last.0, next)
            } else {
                segments.append((current, next))
            }
            current = next
        }
        guard !segments.isEmpty else { return }
        commit()
        for (a, b) in segments {
            document.elements.append(SketchElement(kind: .wire, a: a, b: b, label: document.nextLabel(for: .wire)))
        }
        Haptics.impact(.light)
    }

    private func sameAxis(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
        let firstHorizontal = abs(a.y - b.y) < 0.5, secondHorizontal = abs(c.y - d.y) < 0.5
        return firstHorizontal == secondHorizontal && (firstHorizontal ? abs(a.y - c.y) < 0.5 : abs(a.x - c.x) < 0.5)
    }

    private func addComponent(_ kind: SketchElement.Kind, center rawCenter: CGPoint, horizontal: Bool, needsKind: Bool) {
        let center = SketchGrid.snap(rawCenter)
        let half = SketchGrid.step * SketchGrid.componentSteps / 2
        var a = horizontal ? CGPoint(x: center.x - half, y: center.y) : CGPoint(x: center.x, y: center.y - half)
        var b = horizontal ? CGPoint(x: center.x + half, y: center.y) : CGPoint(x: center.x, y: center.y + half)
        if let near = nearestConnectionPoint(to: center, within: SketchGrid.step * 1.6) {
            if horizontal { a.y = near.y; b.y = near.y } else { a.x = near.x; b.x = near.x }
        }
        commit()
        var element = SketchElement(kind: kind, a: a, b: b, label: document.nextLabel(for: kind))
        element.needsKind = needsKind
        document.elements.append(element)
        attachWires(to: element)
        Haptics.impact(.medium)
    }

    private func addGround(at rawPoint: CGPoint) {
        var point = SketchGrid.snap(rawPoint)
        if let near = nearestConnectionPoint(to: point, within: SketchGrid.step * 2) { point = near }
        commit()
        document.elements.removeAll { $0.kind == .ground }   // one reference node
        document.elements.append(SketchElement(kind: .ground, a: point, b: point, label: document.nextLabel(for: .ground)))
        Haptics.impact(.light)
    }

    /// Stretches wire ends that stop just short of a new component's terminals.
    private func attachWires(to element: SketchElement) {
        for terminal in [element.a, element.b] {
            for index in document.elements.indices where document.elements[index].kind == .wire {
                var wire = document.elements[index]
                let wireHorizontal = abs(wire.a.y - wire.b.y) < 0.5
                for keyPath in [\SketchElement.a, \SketchElement.b] {
                    let end = wire[keyPath: keyPath]
                    guard end != terminal, hypot(end.x - terminal.x, end.y - terminal.y) <= SketchGrid.step * 1.6 else { continue }
                    if wireHorizontal, abs(end.y - terminal.y) < 0.5 { wire[keyPath: keyPath] = terminal }
                    if !wireHorizontal, abs(end.x - terminal.x) < 0.5 { wire[keyPath: keyPath] = terminal }
                }
                document.elements[index] = wire
            }
        }
    }

    // MARK: Review

    private func solveTapped() {
        let pending = document.needingAttention.map(\.id)
        if pending.isEmpty {
            finishSolve()
        } else {
            review = ReviewSession(queue: pending, solveAfter: true)
            if let first = document.elements.first(where: { $0.id == pending[0] }) { center(on: first) }
        }
    }

    private func commit(kind: SketchElement.Kind, value: Double?, for element: SketchElement) {
        commit()
        document.relabel(element.id, as: kind)
        if let index = document.elements.firstIndex(where: { $0.id == element.id }) {
            document.elements[index].value = value
            document.elements[index].needsKind = false
        }
        advanceReview()
    }

    private func advanceReview() {
        guard var session = review else { return }
        session.index += 1
        if let next = session.current, let element = document.elements.first(where: { $0.id == next }) {
            review = session
            center(on: element)
        } else {
            review = nil
            if session.solveAfter { finishSolve() }
        }
    }

    private func finishSolve() {
        if let missing = document.needingAttention.first {
            review = ReviewSession(queue: [missing.id], solveAfter: true)
            return
        }
        let circuit = document.circuit()
        do {
            let validated = try circuit.validated()
            Haptics.impact(.medium)
            onSolve(validated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Queries

    private var connectionPoints: [CGPoint] {
        document.elements.flatMap { element -> [CGPoint] in
            element.kind == .ground ? [element.a] : [element.a, element.b]
        }
    }

    private func nearestConnectionPoint(to p: CGPoint, within radius: CGFloat) -> CGPoint? {
        var best: (CGPoint, CGFloat)?
        for point in connectionPoints {
            let d = hypot(point.x - p.x, point.y - p.y)
            if d <= radius, best == nil || d < best!.1 { best = (point, d) }
        }
        return best?.0
    }

    private func inferHorizontal(around center: CGPoint) -> Bool {
        var vertical = 0, horizontal = 0
        for point in connectionPoints {
            let dx = point.x - center.x, dy = point.y - center.y
            guard hypot(dx, dy) <= SketchGrid.step * 3 else { continue }
            if abs(dy) > abs(dx) { vertical += 1 } else { horizontal += 1 }
        }
        return horizontal > vertical
    }

    private func element(at point: CGPoint) -> SketchElement? {
        var best: (SketchElement, CGFloat)?
        for element in document.elements {
            let d: CGFloat
            if element.kind == .ground {
                d = hypot(element.a.x - point.x, element.a.y - point.y - 14)
            } else {
                d = CGFloat(distanceToSegment(SPoint(x: point.x, y: point.y), SPoint(x: element.a.x, y: element.a.y), SPoint(x: element.b.x, y: element.b.y)))
            }
            let tolerance: CGFloat = (element.kind == .wire ? 14 : 22) / max(zoom, 0.5)
            if d <= tolerance, best == nil || d < best!.1 { best = (element, d) }
        }
        return best?.0
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        withAnimation { toast = text }
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation { toast = nil }
        }
    }
}

// MARK: - Overlays

private struct StrokeOverlay: View {
    let points: [CGPoint]

    var body: some View {
        Canvas { context, _ in
            guard points.count > 1 else { return }
            var path = Path()
            path.move(to: points[0])
            for p in points.dropFirst() { path.addLine(to: p) }
            context.stroke(path, with: .color(PMTheme.accent.opacity(0.75)), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        .allowsHitTesting(false)
    }
}

/// Bottom panel that asks what a part is and what its value is, one part at a time.
private struct ElementPanel: View {
    let element: SketchElement
    let progress: String?
    let primaryTitle: String
    let onCommit: (SketchElement.Kind, Double?) -> Void
    let onSkip: () -> Void
    let onFlip: () -> Void
    let onAsk: () -> Void
    let onDelete: () -> Void

    @State private var kind: SketchElement.Kind
    @State private var text: String
    @State private var multiplier: Double
    @FocusState private var focused: Bool

    private struct Prefix: Identifiable {
        let symbol: String
        let multiplier: Double
        var id: String { symbol }
    }

    init(element: SketchElement, progress: String?, primaryTitle: String, onCommit: @escaping (SketchElement.Kind, Double?) -> Void, onSkip: @escaping () -> Void, onFlip: @escaping () -> Void, onAsk: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.element = element
        self.progress = progress
        self.primaryTitle = primaryTitle
        self.onCommit = onCommit
        self.onSkip = onSkip
        self.onFlip = onFlip
        self.onAsk = onAsk
        self.onDelete = onDelete
        let prefixes = ElementPanel.prefixes(for: element.kind)
        var startText = ""
        var startMultiplier = prefixes.first { $0.multiplier == 1 }?.multiplier ?? 1
        if let value = element.value {
            let best = prefixes.min { abs(log10(value / $0.multiplier)) < abs(log10(value / $1.multiplier)) } ?? prefixes[0]
            startMultiplier = best.multiplier
            startText = QuantityFormatter().number(value / best.multiplier)
        }
        _kind = State(initialValue: element.kind)
        _text = State(initialValue: startText)
        _multiplier = State(initialValue: startMultiplier)
    }

    private static func prefixes(for kind: SketchElement.Kind) -> [Prefix] {
        switch kind {
        case .resistor: return [Prefix(symbol: "Ω", multiplier: 1), Prefix(symbol: "kΩ", multiplier: 1e3), Prefix(symbol: "MΩ", multiplier: 1e6)]
        case .voltageSource: return [Prefix(symbol: "mV", multiplier: 1e-3), Prefix(symbol: "V", multiplier: 1), Prefix(symbol: "kV", multiplier: 1e3)]
        case .currentSource: return [Prefix(symbol: "µA", multiplier: 1e-6), Prefix(symbol: "mA", multiplier: 1e-3), Prefix(symbol: "A", multiplier: 1)]
        default: return [Prefix(symbol: "", multiplier: 1)]
        }
    }

    private var prefixes: [Prefix] { ElementPanel.prefixes(for: kind) }

    private var parsedValue: Double? {
        guard let number = Double(text.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "−", with: "-")), number > 0 else { return nil }
        return number * multiplier
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(element.label)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(PMTheme.ink)
                Text(element.needsKind ? "What is this?" : kind.title)
                    .font(.system(size: 13))
                    .foregroundStyle(element.needsKind ? PMTheme.whyOrange : PMTheme.secondaryText)
                Spacer()
                if let progress {
                    Text(progress)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PMTheme.secondaryText)
                }
                if kind == .voltageSource || kind == .currentSource {
                    iconButton("arrow.left.arrow.right", label: kind == .voltageSource ? "Flip polarity" : "Flip direction", action: onFlip)
                }
                iconButton(element.asked ? "questionmark.circle.fill" : "questionmark.circle", label: "Find the current here", tint: element.asked ? PMTheme.whyOrange : PMTheme.ink, action: onAsk)
                iconButton("trash", label: "Delete", action: onDelete)
            }

            if element.needsKind {
                Picker("Type", selection: $kind) {
                    Text("Resistor").tag(SketchElement.Kind.resistor)
                    Text("Voltage source").tag(SketchElement.Kind.voltageSource)
                    Text("Current source").tag(SketchElement.Kind.currentSource)
                }
                .pickerStyle(.segmented)
                .onChange(of: kind) { _, _ in
                    multiplier = prefixes.first { $0.multiplier == 1 }?.multiplier ?? 1
                }
            }

            HStack(spacing: 10) {
                TextField("Value", text: $text)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .focused($focused)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 10).fill(PMTheme.groupedBackground))
                Picker("Unit", selection: $multiplier) {
                    ForEach(prefixes) { prefix in
                        Text(prefix.symbol).tag(prefix.multiplier)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            HStack {
                Button("Skip", action: onSkip)
                    .font(.system(size: 15))
                    .foregroundStyle(PMTheme.secondaryText)
                Spacer()
                Button(primaryTitle) { onCommit(kind, parsedValue) }
                    .buttonStyle(PMPrimaryButtonStyle())
                    .disabled(parsedValue == nil)
                    .opacity(parsedValue == nil ? 0.5 : 1)
            }
        }
        .padding(14)
        .background(Color.white)
        .overlay(alignment: .top) { Divider() }
        .onAppear { focused = true }
    }

    private func iconButton(_ systemImage: String, label: String, tint: Color = PMTheme.ink, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

#Preview {
    SketchCanvasView { _ in }
}
