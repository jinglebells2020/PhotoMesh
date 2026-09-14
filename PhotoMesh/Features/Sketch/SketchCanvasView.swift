import SwiftUI
import UIKit

/// Hand-drawn circuit entry. Every stroke is recognized on the spot: a line is a wire (corners are
/// fine), a zigzag or a box is a resistor, a circle asks which source it is, a big closed outline is a
/// loop of wires. A part drawn on a wire slots into it. Tap a part for its actions, double-tap to
/// rotate, two fingers move and zoom, the eraser rubs things out.
struct SketchCanvasView: View {
    let onSolve: (Circuit) -> Void

    private struct PendingStroke: Equatable {
        var options: [SketchElement.Kind]
        /// Canvas-space bounds of the stroke, so the bubble follows pans and zooms.
        var bounds: CGRect
        var guess: StrokeGuess
        /// The finger stroke (view points): picking a part teaches the recognizer this shape.
        var points: [CGPoint]
    }

    /// The stroke behind the newest part: correcting its type teaches the recognizer what it should have been.
    private struct LastStroke {
        var id: UUID
        var points: [CGPoint]
        var ranked: [SketchElement.Kind]
    }

    /// A short mark just drawn: a second one beside it makes a capacitor.
    private struct RecentMark {
        var center: CGPoint
        var vertical: Bool
        var time: Date
    }

    private struct TransformSession {
        var zoomBase: CGFloat
        var panBase: CGSize
        var scale: CGFloat = 1
        var anchor: CGPoint
        var translation: CGSize = .zero
        var active: Set<String> = []
    }

    private enum BubbleMode { case actions, kind }

    /// What one finger does: draw strokes, rub things out, or place the ground tap.
    private enum Tool { case draw, erase, ground }

    private struct DragSession {
        var id: UUID
        var start: CGPoint          // canvas point where the hold began
        var originalA: CGPoint
        var originalB: CGPoint
    }

    @AppStorage(SettingsKeys.hasSeenSketchTips) private var hasSeenTips = false

    @State private var document = SketchDocument()
    @State private var history: [[SketchElement]] = []
    @State private var future: [[SketchElement]] = []
    @State private var lastStroke: LastStroke?
    @State private var recentMark: RecentMark?
    @State private var chooserSize: CGSize = .zero
    @State private var actionSize: CGSize = .zero
    @State private var stroke: [CGPoint] = []
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var transform: TransformSession?
    @State private var pending: PendingStroke?
    @State private var selectedId: UUID?
    @State private var bubbleMode: BubbleMode = .actions
    @State private var editing: SketchElement?
    @State private var tool: Tool = .draw
    @State private var eraserPoint: CGPoint?
    @State private var eraseStrokeStarted = false
    @State private var drag: DragSession?
    @State private var showTips = false
    @State private var showParts = false
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var viewSize: CGSize = .zero

    private let minZoom: CGFloat = 0.35
    private let maxZoom: CGFloat = 3
    private let eraserRadius: CGFloat = 14

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    Color.white
                    DotGrid(spacing: SketchGrid.step * zoom, dotRadius: 1.2, origin: CGPoint(x: pan.width, y: pan.height))
                    SchematicView(layout: document.layout(), style: liveStyle, camera: document.schematicCamera(zoom: zoom, pan: pan))
                        .allowsHitTesting(false)
                    StrokeOverlay(points: stroke)
                    if let eraserPoint {
                        Circle()
                            .stroke(PMTheme.ink.opacity(0.55), lineWidth: 1.5)
                            .background(Circle().fill(Color.white.opacity(0.6)))
                            .frame(width: eraserRadius * 2, height: eraserRadius * 2)
                            .position(eraserPoint)
                            .allowsHitTesting(false)
                    }

                    SketchGestureHost(
                        onStrokeBegan: { point in strokeBegan(at: point) },
                        onStrokeMoved: { point in strokeMoved(to: point) },
                        onStrokeEnded: { cancelled in strokeEnded(cancelled: cancelled) },
                        onTap: { point in tapped(at: canvasPoint(point)) },
                        onDoubleTap: { point in doubleTapped(at: canvasPoint(point)) },
                        onPan: { translation, state in
                            updateTransform(gesture: "pan", state: state) { session in session.translation = translation }
                        },
                        onPinch: { scale, location, state in
                            updateTransform(gesture: "pinch", state: state, anchor: location) { session in session.scale = scale }
                        },
                        canHold: { point in tool == .draw && hit(at: canvasPoint(point)) != nil },
                        onHoldBegan: { point in holdBegan(at: point) },
                        onHoldMoved: { point in holdMoved(to: point) },
                        onHoldEnded: { cancelled in holdEnded(cancelled: cancelled) }
                    )

                    if document.elements.isEmpty, stroke.isEmpty, pending == nil {
                        emptyHint
                            .frame(width: geo.size.width, height: geo.size.height)
                    }

                    if drag != nil {
                        banner("Drag to move · release to drop", systemImage: "hand.draw")
                    } else if tool == .ground {
                        banner("Tap the wire or terminal the ground connects to", systemImage: "arrowtriangle.down")
                    } else if tool == .erase {
                        banner("Rub over parts and wires to erase", systemImage: "eraser")
                    } else if let toast {
                        banner(toast, systemImage: "info.circle")
                    }

                    if let pending {
                        ChooserBubble(options: pending.options, maxWidth: geo.size.width - 24, onPick: { kind in choose(kind, for: pending) }, onCancel: { self.pending = nil })
                            .onGeometryChange(for: CGSize.self) { $0.size } action: { chooserSize = $0 }
                            .position(bubblePosition(for: screenRect(pending.bounds), bubble: chooserSize, in: geo.size))
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }

                    if let element = selectedElement {
                        Group {
                            if bubbleMode == .kind {
                                ChooserBubble(options: alternatives(for: element).filter { $0 != element.kind }, maxWidth: geo.size.width - 24, onPick: { kind in changeKind(of: element, to: kind) }, onCancel: { bubbleMode = .actions })
                            } else {
                                ActionBubble(
                                    element: element,
                                    onValue: { editing = element },
                                    onRotate: { rotate(element) },
                                    onFlip: { flip(element) },
                                    onAsk: { update(element.id) { $0.asked.toggle() } },
                                    onKind: { bubbleMode = .kind },
                                    onDelete: { delete(element) }
                                )
                            }
                        }
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { actionSize = $0 }
                        .position(bubblePosition(for: screenRect(elementBounds(element)), bubble: actionSize, in: geo.size))
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }

                    tipsButton
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                    if showTips {
                        SketchTipsOverlay {
                            withAnimation(.easeOut(duration: 0.2)) { showTips = false }
                            hasSeenTips = true
                        }
                        .transition(.opacity)
                    }
                }
                .onAppear {
                    viewSize = geo.size
                    if !hasSeenTips { showTips = true }
                }
                .onChange(of: geo.size) { _, newSize in viewSize = newSize }
            }
            .clipped()

            toolbar
        }
        .background(Color.white)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: pending)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selectedId)
        .sheet(item: $editing) { element in
            ValueEntrySheet(
                element: element,
                alternatives: alternatives(for: element),
                justPlaced: lastStroke?.id == element.id,
                onSave: { kind, value in applyEdit(element.id, kind: kind, value: value) },
                onRemove: { removeMisrecognized(element) }
            )
            .presentationDetents([.height(460), .large])
        }
        .sheet(isPresented: $showParts) {
            PartsPaletteSheet { kind in
                showParts = false
                addPart(kind)
            }
            .presentationDetents([.height(360)])
        }
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
            Text("Lines are wires, a zigzag or a box is a resistor, humps are a coil, a circle is a source. Draw a part on a wire to slot it in.")
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

    private var tipsButton: some View {
        Button {
            Haptics.selection()
            withAnimation(.easeOut(duration: 0.2)) { showTips = true }
        } label: {
            Image(systemName: "questionmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(PMTheme.secondaryText)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white).shadow(color: .black.opacity(0.12), radius: 4, y: 1))
                .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(10)
        .accessibilityLabel("Drawing tips")
        .opacity(showTips ? 0 : 1)
    }

    private var toolbar: some View {
        HStack(spacing: 0) {
            toolButton("pencil.tip", label: "Draw", disabled: false, active: tool == .draw) { setTool(.draw) }
            toolButton("eraser", label: "Erase", disabled: document.elements.isEmpty && tool != .erase, active: tool == .erase) { setTool(tool == .erase ? .draw : .erase) }
            toolButton("arrowtriangle.down", label: "Ground", disabled: document.elements.isEmpty && tool != .ground, active: tool == .ground) { setTool(tool == .ground ? .draw : .ground) }
            toolButton("plus.square", label: "Parts", disabled: false) {
                dismissPopups()
                showParts = true
            }
            Divider().frame(height: 26).padding(.horizontal, 3)
            toolButton("arrow.uturn.backward", label: "Undo", disabled: history.isEmpty) { undo() }
            toolButton("arrow.uturn.forward", label: "Redo", disabled: future.isEmpty) { redo() }
            toolButton("trash", label: "Clear", disabled: document.elements.isEmpty) { clear() }

            Spacer(minLength: 4)

            Button(action: solve) {
                HStack(spacing: 6) {
                    Text("Solve")
                    Image(systemName: "arrow.right").font(.system(size: 15, weight: .semibold))
                }
            }
            .buttonStyle(PMPrimaryButtonStyle())
            .disabled(!document.isSolvable)
            .opacity(document.isSolvable ? 1 : 0.5)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(Color.white)
        .overlay(alignment: .top) { Divider() }
    }

    private func setTool(_ newTool: Tool) {
        withAnimation { tool = newTool }
        dismissPopups()
        Haptics.selection()
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
            .frame(width: 37, height: 40)
            .background(RoundedRectangle(cornerRadius: 9).fill(active ? PMTheme.accentSoft : Color.clear))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .accessibilityLabel(label)
    }

    private var liveStyle: SchematicStyle {
        var style = SchematicStyle(formatter: FormattingPreferences.formatter())
        style.pendingValueIds = Set(document.missingValues.map(\.label))
        style.askedIds = Set(document.elements.filter(\.asked).map(\.label))
        style.showsOpenTerminals = true
        if let element = selectedElement, element.isComponent {
            style.selection = .element(element.label)
        }
        return style
    }

    private var selectedElement: SketchElement? {
        guard let selectedId else { return nil }
        return document.elements.first { $0.id == selectedId }
    }

    // MARK: Coordinates

    private func canvasPoint(_ viewPoint: CGPoint) -> CGPoint {
        CGPoint(x: (viewPoint.x - pan.width) / zoom, y: (viewPoint.y - pan.height) / zoom)
    }

    private func screenPoint(_ canvas: CGPoint) -> CGPoint {
        CGPoint(x: canvas.x * zoom + pan.width, y: canvas.y * zoom + pan.height)
    }

    private func screenRect(_ canvas: CGRect) -> CGRect {
        let origin = screenPoint(canvas.origin)
        return CGRect(x: origin.x, y: origin.y, width: canvas.width * zoom, height: canvas.height * zoom)
    }

    private func elementBounds(_ element: SketchElement) -> CGRect {
        if element.kind == .ground {
            return CGRect(x: element.a.x - 14, y: element.a.y, width: 28, height: 26)
        }
        let pad: CGFloat = element.isComponent ? 14 : 4
        return CGRect(x: min(element.a.x, element.b.x), y: min(element.a.y, element.b.y),
                      width: abs(element.b.x - element.a.x), height: abs(element.b.y - element.a.y))
            .insetBy(dx: -pad, dy: -pad)
    }

    /// Puts a bubble just above what it refers to, or below when there is no room, and always fully
    /// inside the view whatever its measured size.
    private func bubblePosition(for rect: CGRect, bubble: CGSize, in size: CGSize) -> CGPoint {
        let halfWidth = max(bubble.width, 120) / 2, halfHeight = max(bubble.height, 56) / 2
        let x = min(max(rect.midX, halfWidth + 8), max(size.width - halfWidth - 8, halfWidth + 8))
        let above = rect.minY - halfHeight - 14
        let y = above >= halfHeight + 52 ? above : min(rect.maxY + halfHeight + 14, size.height - halfHeight - 8)
        return CGPoint(x: x, y: y)
    }

    /// Kinds offered when a part is questioned: what it is now, then what the recognizer thought
    /// it could be, then everything else.
    private func alternatives(for element: SketchElement) -> [SketchElement.Kind] {
        var result: [SketchElement.Kind] = [element.kind]
        func add(_ kind: SketchElement.Kind) { if !result.contains(kind) { result.append(kind) } }
        if let last = lastStroke, last.id == element.id { last.ranked.forEach(add) }
        SketchElement.Kind.parts.forEach(add)
        if element.kind.isSwitch { result.removeAll { $0.isSwitch && $0 != element.kind } }
        return result
    }

    /// Recognized in view points (finger geometry), placed in canvas points.
    private func toCanvas(_ guess: StrokeGuess) -> StrokeGuess {
        func rect(_ r: CGRect) -> CGRect {
            let o = canvasPoint(r.origin)
            return CGRect(x: o.x, y: o.y, width: r.width / zoom, height: r.height / zoom)
        }
        switch guess {
        case .tap(let p): return .tap(canvasPoint(p))
        case .wire(let from, let to): return .wire(from: canvasPoint(from), to: canvasPoint(to))
        case .wirePath(let corners): return .wirePath(corners.map(canvasPoint))
        case .resistor(let center, let horizontal): return .resistor(center: canvasPoint(center), horizontal: horizontal)
        case .inductor(let center, let horizontal): return .inductor(center: canvasPoint(center), horizontal: horizontal)
        case .roundShape(let center, let size): return .roundShape(center: canvasPoint(center), size: CGSize(width: size.width / zoom, height: size.height / zoom))
        case .rectangle(let center, let horizontal): return .rectangle(center: canvasPoint(center), horizontal: horizontal)
        case .part(let kind, let center, let horizontal): return .part(kind: kind, center: canvasPoint(center), horizontal: horizontal)
        case .loop(let r): return .loop(rect(r))
        case .shortMark(let center): return .shortMark(center: canvasPoint(center))
        case .unknown(let bounds): return .unknown(bounds: rect(bounds))
        }
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
            pan = CGSize(width: viewSize.width / 2 - c.x * zoom, height: viewSize.height * 0.45 - c.y * zoom)
        }
    }

    // MARK: Strokes

    private func strokeBegan(at point: CGPoint) {
        dismissPopups()
        if tool == .erase {
            if !eraseStrokeStarted {
                commit()
                eraseStrokeStarted = true
            }
            eraserPoint = point
            erase(from: point, to: point)
        } else {
            stroke = [point]
        }
    }

    private func strokeMoved(to point: CGPoint) {
        if tool == .erase {
            let previous = eraserPoint ?? point
            eraserPoint = point
            erase(from: previous, to: point)
        } else {
            stroke.append(point)
        }
    }

    private func strokeEnded(cancelled: Bool) {
        if tool == .erase {
            eraserPoint = nil
            eraseStrokeStarted = false
            return
        }
        let points = stroke
        stroke = []
        guard !cancelled, points.count > 1 else { return }
        // Shapes are judged by finger geometry; the loop threshold lives on the grid.
        let recognition = StrokeClassifier.recognize(points, loopExtent: SketchGrid.step * 5.5 * zoom)
        handle(toCanvas(recognition.guess), recognition: recognition, points: points)
    }

    /// Erases everything under the eraser between two view points, dense enough that a fast swipe
    /// cannot jump over a thin wire.
    private func erase(from: CGPoint, to: CGPoint) {
        let distance = hypot(to.x - from.x, to.y - from.y)
        let steps = max(1, Int(distance / (eraserRadius * 0.6)))
        let points = (0...steps).map { i -> CGPoint in
            let t = CGFloat(i) / CGFloat(steps)
            return canvasPoint(CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
        }
        let before = document.elements.count
        let removed = document.erase(along: points, radius: eraserRadius / zoom)
        if !removed.isEmpty || document.elements.count != before { Haptics.selection() }
    }

    private func handle(_ guess: StrokeGuess, recognition: StrokeRecognition, points: [CGPoint]) {
        let ranked = recognition.ranked
        switch guess {
        case .tap(let point):
            tapped(at: point)
        case .wire(let from, let to):
            commit()
            if document.addWire(from: from, to: to) {
                Haptics.impact(.light)
            } else {
                history.removeLast()
            }
        case .wirePath(let corners):
            commit()
            document.addWirePath(corners)
            Haptics.impact(.light)
        case .loop(let rect):
            commit()
            document.addLoop(rect)
            Haptics.impact(.light)
        case .resistor(let center, let horizontal):
            place(.resistor, center: center, horizontal: horizontal, stroke: points, ranked: ranked)
        case .inductor(let center, let horizontal):
            place(.inductor, center: center, horizontal: horizontal, stroke: points, ranked: ranked)
        case .rectangle(let center, let horizontal):
            place(.resistor, center: center, horizontal: horizontal ?? document.inferHorizontal(around: center), stroke: points, ranked: ranked)
        case .part(let kind, let center, let horizontal):
            place(kind, center: center, horizontal: horizontal, stroke: points, ranked: ranked)
        case .roundShape(let center, let size):
            Haptics.impact(.light)
            // Sure it is round: offer the round parts (the ones this hand tends to draw first).
            // Not sure: offer everything, likeliest first.
            let roundOnes = ranked.filter { StrokeClassifier.roundKinds.contains($0) }
            let options = recognition.confident ? (roundOnes.isEmpty ? StrokeClassifier.roundKinds : roundOnes) : ranked
            pending = PendingStroke(options: options,
                                    bounds: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height),
                                    guess: guess, points: points)
        case .shortMark(let center):
            let bounds = StrokeClassifier.boundingBox(points)
            let vertical = bounds.height > bounds.width
            if let mark = recentMark, Date().timeIntervalSince(mark.time) < 2.5, mark.vertical == vertical,
               abs(vertical ? center.y - mark.center.y : center.x - mark.center.x) <= SketchGrid.step,
               abs(vertical ? center.x - mark.center.x : center.y - mark.center.y) <= SketchGrid.step * 2.2 {
                // Two short parallel marks side by side: the plates of a capacitor.
                recentMark = nil
                pending = nil
                let middle = CGPoint(x: (center.x + mark.center.x) / 2, y: (center.y + mark.center.y) / 2)
                place(.capacitor, center: middle, horizontal: vertical)
                return
            }
            recentMark = RecentMark(center: center, vertical: vertical, time: Date())
            var options: [SketchElement.Kind] = [.ground, .wire, .capacitor, .switchOpen]
            for kind in ranked where !options.contains(kind) { options.append(kind) }
            pending = PendingStroke(options: options, bounds: CGRect(x: center.x - 12, y: center.y - 12, width: 24, height: 24), guess: guess, points: points)
        case .unknown(let bounds):
            Haptics.notify(.warning)
            var options = ranked.isEmpty ? SketchElement.Kind.parts : ranked
            for kind in [SketchElement.Kind.wire, .ground] where !options.contains(kind) { options.append(kind) }
            pending = PendingStroke(options: options, bounds: bounds, guess: guess, points: points)
        }
    }

    private func choose(_ kind: SketchElement.Kind, for pending: PendingStroke) {
        self.pending = nil
        recentMark = nil
        let bounds = pending.bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        switch kind {
        case .wire:
            commit()
            let added: Bool
            if bounds.width >= bounds.height {
                added = document.addWire(from: CGPoint(x: bounds.minX, y: bounds.midY), to: CGPoint(x: bounds.maxX, y: bounds.midY))
            } else {
                added = document.addWire(from: CGPoint(x: bounds.midX, y: bounds.minY), to: CGPoint(x: bounds.midX, y: bounds.maxY))
            }
            if !added {
                // Too small for a wire: give it one grid step.
                document.addWire(from: CGPoint(x: center.x - SketchGrid.step / 2, y: center.y), to: CGPoint(x: center.x + SketchGrid.step / 2, y: center.y))
            }
            Haptics.impact(.light)
        case .ground:
            commit()
            document.placeGround(at: center)
            Haptics.impact(.light)
        default:
            let horizontal: Bool
            switch pending.guess {
            case .roundShape, .shortMark:
                horizontal = document.inferHorizontal(around: center)
            default:
                let aspect = bounds.width / max(bounds.height, 1)
                horizontal = aspect > 1.25 ? true : (aspect < 0.8 ? false : document.inferHorizontal(around: center))
            }
            // The user has just said what this shape is: remember it for next time.
            StrokeLibrary.shared.learn(pending.points, as: kind)
            place(kind, center: center, horizontal: horizontal, stroke: pending.points, ranked: pending.options)
        }
    }

    /// Adds a part and asks for its value straight away (switches have none). `stroke` is the
    /// finger stroke that produced it, kept so a correction can teach the recognizer.
    private func place(_ kind: SketchElement.Kind, center: CGPoint, horizontal: Bool, stroke: [CGPoint]? = nil, ranked: [SketchElement.Kind] = []) {
        commit()
        let element = document.addComponent(kind, center: center, horizontal: horizontal)
        Haptics.impact(.medium)
        selectedId = nil
        lastStroke = stroke.map { LastStroke(id: element.id, points: $0, ranked: ranked) }
        if kind.needsValue { editing = element } else { selectedId = element.id }
    }

    /// The value sheet's result: a new type (the recognizer learns the stroke), a value, or both.
    private func applyEdit(_ id: UUID, kind: SketchElement.Kind, value: Double?) {
        guard let current = document.elements.first(where: { $0.id == id }) else { return }
        commit()
        if kind != current.kind {
            document.setKind(id, kind)
            teach(id, kind)
        }
        if let value, let index = document.elements.firstIndex(where: { $0.id == id }) {
            document.elements[index].value = value
        }
    }

    /// "That is not what I drew": a part recognized a moment ago is taken back together with
    /// everything its placement did to the wires; any other part is simply removed.
    private func removeMisrecognized(_ element: SketchElement) {
        if lastStroke?.id == element.id {
            undo()
            lastStroke = nil
        } else {
            delete(element)
        }
        showToast("Removed \(element.label)")
    }

    /// Adds the stroke behind `id` to the recognizer's library as an example of `kind`.
    private func teach(_ id: UUID, _ kind: SketchElement.Kind) {
        guard let last = lastStroke, last.id == id else { return }
        if StrokeLibrary.shared.learn(last.points, as: kind) {
            showToast("Learned: that shape is a \(kind.title.lowercased())")
        }
    }

    /// From the parts palette: drop the part in the middle of the view, ready to be dragged.
    private func addPart(_ kind: SketchElement.Kind) {
        let center = canvasPoint(CGPoint(x: viewSize.width / 2, y: viewSize.height * 0.45))
        switch kind {
        case .wire:
            commit()
            document.addWire(from: CGPoint(x: center.x - SketchGrid.step * 2, y: center.y), to: CGPoint(x: center.x + SketchGrid.step * 2, y: center.y))
        case .ground:
            commit()
            document.placeGround(at: center)
        default:
            place(kind, center: center, horizontal: true)
        }
        showToast("Hold the part and drag it into place")
    }

    /// Sources swap polarity or direction; a switch toggles between open and closed.
    private func flip(_ element: SketchElement) {
        if element.kind.isSwitch {
            commit()
            document.setKind(element.id, element.kind == .switchOpen ? .switchClosed : .switchOpen)
            Haptics.selection()
        } else {
            update(element.id) { $0.flipped.toggle() }
        }
    }

    // MARK: Taps and part actions

    private func hit(at point: CGPoint) -> SketchElement? {
        document.element(at: point, wireTolerance: 14 / max(zoom, 0.5), partTolerance: 22 / max(zoom, 0.5))
    }

    private func tapped(at point: CGPoint) {
        let hit = hit(at: point)
        if tool == .ground {
            commit()
            document.placeGround(at: point)
            withAnimation { tool = .draw }
            Haptics.impact(.light)
            return
        }
        if tool == .erase {
            if let hit {
                commit()
                document.remove(hit.id, heal: false)
                Haptics.selection()
            }
            return
        }
        pending = nil
        if let hit {
            if selectedId == hit.id {
                selectedId = nil
            } else {
                selectedId = hit.id
                bubbleMode = .actions
                Haptics.selection()
            }
        } else {
            selectedId = nil
        }
    }

    private func doubleTapped(at point: CGPoint) {
        if let hit = document.element(at: point, wireTolerance: 0, partTolerance: 22 / max(zoom, 0.5)), hit.isComponent {
            rotate(hit)
        } else {
            fitToContent()
        }
    }

    // MARK: Hold to move

    private func holdBegan(at viewPoint: CGPoint) {
        let point = canvasPoint(viewPoint)
        guard let element = hit(at: point) else { return }
        dismissPopups()
        commit()
        drag = DragSession(id: element.id, start: point, originalA: element.a, originalB: element.b)
        selectedId = nil
        Haptics.impact(.medium)
    }

    private func holdMoved(to viewPoint: CGPoint) {
        guard let drag else { return }
        let point = canvasPoint(viewPoint)
        let dx = point.x - drag.start.x, dy = point.y - drag.start.y
        document.moveLive(drag.id, a: CGPoint(x: drag.originalA.x + dx, y: drag.originalA.y + dy), b: CGPoint(x: drag.originalB.x + dx, y: drag.originalB.y + dy))
    }

    private func holdEnded(cancelled: Bool) {
        guard let session = drag else { return }
        drag = nil
        guard let current = document.elements.first(where: { $0.id == session.id }) else { return }
        let translation = CGSize(width: current.a.x - session.originalA.x, height: current.a.y - session.originalA.y)
        if cancelled {
            document.moveLive(session.id, a: session.originalA, b: session.originalB)
            history.removeLast()
            return
        }
        document.finishMove(session.id, originalA: session.originalA, originalB: session.originalB, translation: translation)
        Haptics.impact(.light)
    }

    private func rotate(_ element: SketchElement) {
        commit()
        document.rotate(element.id)
        Haptics.impact(.medium)
    }

    private func delete(_ element: SketchElement) {
        commit()
        document.remove(element.id, heal: true)
        selectedId = nil
        Haptics.impact(.light)
    }

    private func changeKind(of element: SketchElement, to kind: SketchElement.Kind) {
        commit()
        document.setKind(element.id, kind)
        teach(element.id, kind)
        bubbleMode = .actions
        Haptics.selection()
        if kind.needsValue, let updated = document.elements.first(where: { $0.id == element.id }) { editing = updated }
    }

    private func dismissPopups() {
        pending = nil
        selectedId = nil
        bubbleMode = .actions
    }

    // MARK: History

    private func commit() {
        history.append(document.elements)
        if history.count > 60 { history.removeFirst() }
        future.removeAll()
    }

    private func undo() {
        guard let previous = history.popLast() else { return }
        future.append(document.elements)
        document.elements = previous
        dismissPopups()
        Haptics.impact(.light)
    }

    private func redo() {
        guard let next = future.popLast() else { return }
        history.append(document.elements)
        document.elements = next
        dismissPopups()
        Haptics.impact(.light)
    }

    private func clear() {
        commit()
        document.elements.removeAll()
        dismissPopups()
        withAnimation { tool = .draw }
    }

    private func update(_ id: UUID, _ change: (inout SketchElement) -> Void) {
        guard let index = document.elements.firstIndex(where: { $0.id == id }) else { return }
        commit()
        change(&document.elements[index])
    }

    // MARK: Solve

    private func solve() {
        if let missing = document.missingValues.first {
            selectedId = missing.id
            bubbleMode = .actions
            center(on: missing)
            showToast("\(missing.label) needs a value")
            editing = missing
            return
        }
        do {
            let validated = try document.circuit().validated()
            Haptics.impact(.medium)
            onSolve(validated)
        } catch {
            errorMessage = error.localizedDescription
        }
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

/// Icon + label buttons in a floating pill, shared by "what did you draw?" and "change type".
/// Long lists scroll sideways inside the pill, which never grows wider than the canvas.
private struct ChooserBubble: View {
    let options: [SketchElement.Kind]
    var maxWidth: CGFloat = .infinity
    let onPick: (SketchElement.Kind) -> Void
    let onCancel: () -> Void

    private let cell: CGFloat = 54

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(options, id: \.self) { kind in
                        Button {
                            onPick(kind)
                        } label: {
                            VStack(spacing: 3) {
                                PartGlyph(kind: kind)
                                    .frame(width: 34, height: 18)
                                Text(shortTitle(kind))
                                    .font(.system(size: 9.5, weight: .medium))
                            }
                            .foregroundStyle(PMTheme.ink)
                            .frame(width: cell, height: 50)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(kind.title)
                    }
                }
                .padding(.leading, 4)
            }
            .frame(width: min(CGFloat(options.count) * (cell + 2) + 4, max(maxWidth - 42, cell)))
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PMTheme.secondaryText)
                    .frame(width: 30, height: 50)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 4)
        .background(BubbleBackground())
    }

    private func shortTitle(_ kind: SketchElement.Kind) -> String {
        switch kind {
        case .voltageSource: return "Voltage"
        case .currentSource: return "Current"
        case .switchOpen: return "Switch"
        case .switchClosed: return "Switch"
        default: return kind.title
        }
    }
}

/// The schematic symbol of a part, drawn small: the same shapes the circuit is drawn with.
struct PartGlyph: View {
    let kind: SketchElement.Kind
    var color: Color = PMTheme.ink

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            var path = Path()
            switch kind {
            case .wire:
                path.move(to: CGPoint(x: 2, y: midY)); path.addLine(to: CGPoint(x: size.width - 2, y: midY))
            case .ground:
                let x = size.width / 2
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: midY - 2))
                for (i, half) in [9.0, 6.0, 3.0].enumerated() {
                    let y = midY - 2 + CGFloat(i) * 4
                    path.move(to: CGPoint(x: x - half, y: y)); path.addLine(to: CGPoint(x: x + half, y: y))
                }
            default:
                guard let componentKind = kind.componentKind else { return }
                // Draw the real symbol at layout scale, then squeeze it into the glyph box.
                let symbol = SchematicLayout.Symbol(id: "", kind: componentKind, value: 0, nodeA: "", nodeB: "", a: SPoint(x: 0, y: 0), b: SPoint(x: 100, y: 0), labelSide: SPoint(x: 0, y: -1))
                let raw = SchematicRenderer.symbolPath(symbol)
                let box = raw.boundingRect
                let scale = min((size.width - 2) / max(box.width, 1), (size.height - 2) / max(box.height, 1))
                path = raw.applying(CGAffineTransform(translationX: -box.midX, y: -box.midY).concatenating(CGAffineTransform(scaleX: scale, y: scale)).concatenating(CGAffineTransform(translationX: size.width / 2, y: midY)))
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }
    }
}

/// Every part, one tap away: dropped in the middle of the canvas to be dragged into place.
private struct PartsPaletteSheet: View {
    let onPick: (SketchElement.Kind) -> Void
    @Environment(\.dismiss) private var dismiss

    private let kinds: [SketchElement.Kind] = SketchElement.Kind.parts + [.switchClosed, .wire, .ground]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(kinds, id: \.self) { kind in
                        Button {
                            Haptics.selection()
                            onPick(kind)
                        } label: {
                            VStack(spacing: 8) {
                                PartGlyph(kind: kind)
                                    .frame(width: 64, height: 26)
                                Text(kind.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(PMTheme.ink)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(PMTheme.groupedBackground))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Add a part")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } }
            }
        }
        .tint(PMTheme.accent)
    }
}

/// What you can do with a tapped part.
private struct ActionBubble: View {
    let element: SketchElement
    let onValue: () -> Void
    let onRotate: () -> Void
    let onFlip: () -> Void
    let onAsk: () -> Void
    let onKind: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Text(element.label)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(PMTheme.ink)
                .padding(.leading, 8)
                .padding(.trailing, 4)
            if element.isComponent {
                BubbleButton(systemImage: "pencil", title: "Value", action: onValue)
                BubbleButton(systemImage: "rotate.right", title: "Rotate", action: onRotate)
                if element.kind.canFlip {
                    BubbleButton(systemImage: element.kind.isSwitch ? "switch.2" : "arrow.left.arrow.right", title: element.kind.isSwitch ? "Toggle" : "Flip", action: onFlip)
                }
                BubbleButton(systemImage: element.asked ? "questionmark.circle.fill" : "questionmark.circle", title: "Find I", tint: element.asked ? PMTheme.whyOrange : PMTheme.ink, action: onAsk)
                BubbleButton(systemImage: "arrow.triangle.2.circlepath", title: "Type", action: onKind)
            }
            BubbleButton(systemImage: "trash", title: "Delete", tint: Color(red: 0.8, green: 0.2, blue: 0.2), action: onDelete)
        }
        .padding(.horizontal, 4)
        .background(BubbleBackground())
    }
}

private struct BubbleButton: View {
    let systemImage: String
    let title: String
    var tint: Color = PMTheme.ink
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
            }
            .foregroundStyle(tint)
            .frame(width: 50, height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct BubbleBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white)
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.black.opacity(0.06), lineWidth: 0.5))
    }
}

// MARK: - Tips

/// First-run walkthrough of the gestures, also behind the "?" button.
private struct SketchTipsOverlay: View {
    let onDismiss: () -> Void

    private struct Tip: Identifiable {
        let id = UUID()
        let glyph: TipGlyph
        let title: String
        let detail: String
    }

    private let tips: [Tip] = [
        Tip(glyph: .line, title: "Draw a line", detail: "It becomes a wire. Corners and big loops work too."),
        Tip(glyph: .zigzag, title: "Zigzag or box", detail: "A resistor. Humps are a coil, two short marks a capacitor. Draw a part on a wire and it slots in."),
        Tip(glyph: .circle, title: "Circle", detail: "A source: you pick voltage, current, lamp or battery."),
        Tip(glyph: .symbol("hand.tap"), title: "Tap, double-tap, hold", detail: "Tap a part for value, rotate, flip, type, delete. Double-tap rotates. Hold and drag to move it."),
        Tip(glyph: .symbol("hand.draw"), title: "Two fingers", detail: "Move and zoom the canvas; double-tap empty space to fit. Erase rubs things out, Ground marks the reference, Undo and Redo step through your changes."),
        Tip(glyph: .symbol("sparkles"), title: "Wrong guess?", detail: "Change the type or remove the part right in the value sheet. Every correction teaches the recognizer your way of drawing. Red rings mark ends that are not connected yet."),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 0) {
                Text("How to draw")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(PMTheme.ink)
                    .padding(.bottom, 14)
                ForEach(tips) { tip in
                    HStack(alignment: .center, spacing: 14) {
                        TipGlyphView(glyph: tip.glyph)
                            .frame(width: 54, height: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tip.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(PMTheme.ink)
                            Text(tip.detail)
                                .font(.system(size: 13))
                                .foregroundStyle(PMTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)
                }
                Button(action: onDismiss) {
                    Text("Start drawing")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PMPrimaryButtonStyle())
                .padding(.top, 14)
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white).shadow(color: .black.opacity(0.2), radius: 20, y: 8))
            .padding(.horizontal, 22)
        }
    }
}

private enum TipGlyph {
    case line, zigzag, circle
    case symbol(String)
}

private struct TipGlyphView: View {
    let glyph: TipGlyph

    var body: some View {
        switch glyph {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(PMTheme.accent)
        default:
            Canvas { context, size in
                var path = Path()
                let midY = size.height / 2
                switch glyph {
                case .line:
                    path.move(to: CGPoint(x: 4, y: midY))
                    path.addLine(to: CGPoint(x: size.width - 4, y: midY))
                case .zigzag:
                    path.move(to: CGPoint(x: 2, y: midY))
                    path.addLine(to: CGPoint(x: 10, y: midY))
                    let peaks = 6
                    let segment = (size.width - 20) / CGFloat(peaks + 1)
                    for i in 1...peaks {
                        path.addLine(to: CGPoint(x: 10 + segment * CGFloat(i), y: midY + (i % 2 == 1 ? -9 : 9)))
                    }
                    path.addLine(to: CGPoint(x: size.width - 10, y: midY))
                    path.addLine(to: CGPoint(x: size.width - 2, y: midY))
                case .circle:
                    path.addEllipse(in: CGRect(x: size.width / 2 - 14, y: midY - 14, width: 28, height: 28))
                    path.move(to: CGPoint(x: 2, y: midY)); path.addLine(to: CGPoint(x: size.width / 2 - 14, y: midY))
                    path.move(to: CGPoint(x: size.width / 2 + 14, y: midY)); path.addLine(to: CGPoint(x: size.width - 2, y: midY))
                case .symbol:
                    break
                }
                context.stroke(path, with: .color(PMTheme.accent), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: - Value entry

/// Value + SI prefix entry, shown right after a part is drawn and from the part's "Value" action.
/// The type can be changed here too (a zigzag read as a coil, say) and a wrong guess removed.
private struct ValueEntrySheet: View {
    let element: SketchElement
    /// Kinds to offer, the current one first.
    let alternatives: [SketchElement.Kind]
    /// Just recognized from a stroke: removing it undoes the whole placement.
    let justPlaced: Bool
    let onSave: (SketchElement.Kind, Double?) -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind: SketchElement.Kind = .resistor
    @State private var text = ""
    @State private var multiplier: Double = 1
    @FocusState private var focused: Bool

    private struct Prefix: Identifiable {
        let symbol: String
        let multiplier: Double
        var id: String { symbol }
    }

    private static func prefixes(for kind: SketchElement.Kind) -> [Prefix] {
        switch kind {
        case .resistor, .lamp: return [Prefix(symbol: "Ω", multiplier: 1), Prefix(symbol: "kΩ", multiplier: 1e3), Prefix(symbol: "MΩ", multiplier: 1e6)]
        case .voltageSource, .battery: return [Prefix(symbol: "mV", multiplier: 1e-3), Prefix(symbol: "V", multiplier: 1), Prefix(symbol: "kV", multiplier: 1e3)]
        case .currentSource: return [Prefix(symbol: "µA", multiplier: 1e-6), Prefix(symbol: "mA", multiplier: 1e-3), Prefix(symbol: "A", multiplier: 1)]
        case .capacitor: return [Prefix(symbol: "pF", multiplier: 1e-12), Prefix(symbol: "nF", multiplier: 1e-9), Prefix(symbol: "µF", multiplier: 1e-6)]
        case .inductor: return [Prefix(symbol: "µH", multiplier: 1e-6), Prefix(symbol: "mH", multiplier: 1e-3), Prefix(symbol: "H", multiplier: 1)]
        default: return [Prefix(symbol: "", multiplier: 1)]
        }
    }

    private var prefixes: [Prefix] { ValueEntrySheet.prefixes(for: kind) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(alternatives, id: \.self) { option in
                                Button {
                                    select(option)
                                } label: {
                                    VStack(spacing: 4) {
                                        PartGlyph(kind: option, color: option == kind ? .white : PMTheme.ink)
                                            .frame(width: 40, height: 18)
                                        Text(option.title)
                                            .font(.system(size: 10.5, weight: .medium))
                                            .lineLimit(1)
                                    }
                                    .foregroundStyle(option == kind ? .white : PMTheme.ink)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(option == kind ? PMTheme.accent : PMTheme.groupedBackground))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(option.title)
                                .accessibilityAddTraits(option == kind ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                } header: {
                    Text(justPlaced ? "Recognized as \(element.kind.title.lowercased()) · tap to change" : "Type")
                }
                if kind.needsValue {
                    Section {
                        HStack {
                            TextField("Value", text: $text)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                                .focused($focused)
                                .submitLabel(.done)
                            Picker("Unit", selection: $multiplier) {
                                ForEach(prefixes) { prefix in
                                    Text(prefix.symbol).tag(prefix.multiplier)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 160)
                        }
                    } footer: {
                        Text(footer)
                    }
                } else {
                    Section { Text("A switch has no value: use Toggle from its menu to open or close it.").font(.system(size: 13)).foregroundStyle(PMTheme.secondaryText) }
                }
                Section {
                    Button(role: .destructive) {
                        onRemove()
                        dismiss()
                    } label: {
                        Label(justPlaced ? "Not a part, remove it" : "Remove \(element.label)", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("\(element.label) · \(kind.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Later") {
                        if kind != element.kind { onSave(kind, nil) }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { save() }
                        .font(.system(size: 17, weight: .semibold))
                        .disabled(kind.needsValue && parsedValue == nil)
                }
            }
            .onAppear {
                kind = element.kind
                if let value = element.value {
                    let best = prefixes.min { abs(log10(value / $0.multiplier)) < abs(log10(value / $1.multiplier)) } ?? prefixes[0]
                    multiplier = best.multiplier
                    text = QuantityFormatter().number(value / best.multiplier)
                } else if let defaultPrefix = prefixes.first(where: { $0.multiplier == 1 }) ?? prefixes.last {
                    multiplier = defaultPrefix.multiplier
                }
                focused = kind.needsValue
            }
        }
        .tint(PMTheme.accent)
    }

    private func select(_ option: SketchElement.Kind) {
        guard option != kind else { return }
        Haptics.selection()
        kind = option
        text = ""
        let defaults = ValueEntrySheet.prefixes(for: option)
        multiplier = (defaults.first { $0.multiplier == 1 } ?? defaults.last)?.multiplier ?? 1
        focused = option.needsValue
    }

    private var footer: String {
        switch kind {
        case .voltageSource, .battery: return "The + terminal is at the top (or left). Use Flip from the part's menu to turn it around."
        case .currentSource: return "The arrow points down (or right). Use Flip from the part's menu to turn it around."
        case .capacitor: return "At DC a capacitor blocks current; the value is kept for the drawing."
        case .inductor: return "At DC an inductor is a plain wire; the value is kept for the drawing."
        default: return "Tap the part later to change this."
        }
    }

    private var parsedValue: Double? {
        guard let number = Double(text.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "−", with: "-")), number > 0 else { return nil }
        return number * multiplier
    }

    private func save() {
        if kind.needsValue {
            guard let value = parsedValue else { return }
            onSave(kind, value)
        } else {
            onSave(kind, nil)
        }
        dismiss()
    }
}

#Preview {
    SketchCanvasView { _ in }
}
