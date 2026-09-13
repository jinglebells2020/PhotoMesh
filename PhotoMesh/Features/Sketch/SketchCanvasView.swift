import SwiftUI

/// Hand-drawn circuit entry: strokes snap to a dot grid and become wires, resistors and sources,
/// the way a handwriting keyboard turns strokes into characters.
struct SketchCanvasView: View {
    let onSolve: (Circuit) -> Void

    private struct PendingStroke: Equatable {
        var guess: StrokeGuess
        var bounds: CGRect
        var options: [SketchElement.Kind]
    }

    @State private var document = SketchDocument()
    @State private var history: [[SketchElement]] = []
    @State private var stroke: [CGPoint] = []
    @State private var pending: PendingStroke?
    @State private var editing: SketchElement?
    @State private var menuElement: SketchElement?
    @State private var errorMessage: String?
    @State private var selectedId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Color.white
                    DotGrid(spacing: SketchGrid.step, dotRadius: 1.2)
                    SchematicView(layout: document.layout(), style: liveStyle, camera: document.canvasCamera)
                        .allowsHitTesting(false)
                    StrokeOverlay(points: stroke)

                    if document.elements.isEmpty, stroke.isEmpty, pending == nil {
                        emptyHint
                            .frame(width: geo.size.width, height: geo.size.height)
                    }

                    if let pending {
                        ChooserBubble(options: pending.options, onPick: { kind in place(kind, for: pending) }, onCancel: { self.pending = nil })
                            .position(bubblePosition(for: pending.bounds, in: geo.size))
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
                .contentShape(Rectangle())
                .gesture(drawGesture)
                .onAppear { document.canvasSize = geo.size }
                .onChange(of: geo.size) { _, newSize in document.canvasSize = newSize }
            }
            .clipped()

            toolbar
        }
        .background(Color.white)
        .sheet(item: $editing) { element in
            ValueEntrySheet(element: element) { value in
                update(element.id) { $0.value = value }
            }
            .presentationDetents([.height(320)])
        }
        .confirmationDialog(menuTitle, isPresented: Binding(get: { menuElement != nil }, set: { if !$0 { menuElement = nil } }), titleVisibility: .visible, presenting: menuElement) { element in
            if element.isComponent {
                Button("Edit value") { editing = element }
                Button(element.asked ? "Stop asking for its current" : "Find the current here") { update(element.id) { $0.asked.toggle() } }
            }
            if element.kind == .voltageSource {
                Button("Flip polarity") { update(element.id) { $0.flipped.toggle() } }
            }
            if element.kind == .currentSource {
                Button("Flip direction") { update(element.id) { $0.flipped.toggle() } }
            }
            Button("Delete", role: .destructive) { remove(element.id) }
            Button("Cancel", role: .cancel) {}
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
            Text("A straight stroke becomes a wire, a zigzag a resistor, a circle a source. Tap a part to edit it.")
                .font(.system(size: 13))
                .foregroundStyle(PMTheme.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .allowsHitTesting(false)
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Button {
                undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 40, height: 40)
            }
            .disabled(history.isEmpty)
            Button {
                commit()
                document.elements.removeAll()
                selectedId = nil
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 40, height: 40)
            }
            .disabled(document.elements.isEmpty)

            Spacer()

            Text(statusText)
                .font(.system(size: 12))
                .foregroundStyle(PMTheme.secondaryText)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)

            Button(action: solve) {
                HStack(spacing: 8) {
                    Text("Solve")
                    Image(systemName: "arrow.right").font(.system(size: 15, weight: .semibold))
                }
            }
            .buttonStyle(PMPrimaryButtonStyle())
            .disabled(!(document.hasSource && document.hasResistor))
            .opacity(document.hasSource && document.hasResistor ? 1 : 0.5)
        }
        .foregroundStyle(PMTheme.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white)
        .overlay(alignment: .top) { Divider() }
    }

    private var statusText: String {
        let resistors = document.elements.filter { $0.kind == .resistor }.count
        let sources = document.elements.filter { $0.kind == .voltageSource || $0.kind == .currentSource }.count
        if document.elements.isEmpty { return "" }
        if !document.hasSource { return "Add a source (draw a circle)" }
        if !document.hasResistor { return "Add a resistor (draw a zigzag)" }
        if !document.missingValues.isEmpty { return "\(document.missingValues.first!.label) needs a value" }
        return "\(resistors) resistor\(resistors == 1 ? "" : "s"), \(sources) source\(sources == 1 ? "" : "s")"
    }

    private var menuTitle: String {
        guard let element = menuElement else { return "" }
        if let kind = element.kind.componentKind, let value = element.value {
            return "\(element.label) · \(FormattingPreferences.formatter().format(value, kind.unitSymbol))"
        }
        return element.kind == .wire ? "Wire" : element.label
    }

    private var liveStyle: SchematicStyle {
        var style = SchematicStyle(formatter: FormattingPreferences.formatter())
        style.pendingValueIds = Set(document.missingValues.map(\.label))
        style.askedIds = Set(document.elements.filter(\.asked).map(\.label))
        if let selectedId, let element = document.elements.first(where: { $0.id == selectedId }) {
            style.selection = element.isComponent ? .element(element.label) : nil
        }
        return style
    }

    private func bubblePosition(for bounds: CGRect, in size: CGSize) -> CGPoint {
        let width: CGFloat = 300
        let x = min(max(bounds.midX, width / 2 + 8), size.width - width / 2 - 8)
        let y = bounds.minY > 90 ? bounds.minY - 48 : bounds.maxY + 48
        return CGPoint(x: x, y: min(max(y, 40), size.height - 40))
    }

    // MARK: Drawing

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if pending != nil { withAnimation { pending = nil } }
                if stroke.isEmpty { stroke = [value.startLocation] }
                stroke.append(value.location)
            }
            .onEnded { value in
                let points = stroke.isEmpty ? [value.location] : stroke
                stroke = []
                handle(StrokeClassifier.classify(points), points: points)
            }
    }

    private func handle(_ guess: StrokeGuess, points: [CGPoint]) {
        let bounds = StrokeClassifier.boundingBox(points)
        switch guess {
        case .tap(let point):
            if let element = element(at: point) {
                selectedId = element.id
                Haptics.selection()
                menuElement = element
            } else {
                selectedId = nil
            }
        case .wire(let from, let to):
            addWire(from: from, to: to)
        case .resistor(let center, let horizontal), .rectangle(let center, let horizontal):
            addComponent(.resistor, center: center, horizontal: horizontal)
        case .roundShape:
            Haptics.impact(.light)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                pending = PendingStroke(guess: guess, bounds: bounds, options: [.voltageSource, .currentSource, .resistor])
            }
        case .shortMark:
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                pending = PendingStroke(guess: guess, bounds: bounds, options: [.ground, .wire])
            }
        case .unknown:
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                pending = PendingStroke(guess: guess, bounds: bounds, options: [.wire, .resistor, .voltageSource, .currentSource, .ground])
            }
        }
    }

    private func place(_ kind: SketchElement.Kind, for pending: PendingStroke) {
        withAnimation { self.pending = nil }
        let bounds = pending.bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        switch kind {
        case .wire:
            if bounds.width >= bounds.height {
                addWire(from: CGPoint(x: bounds.minX, y: bounds.midY), to: CGPoint(x: bounds.maxX, y: bounds.midY))
            } else {
                addWire(from: CGPoint(x: bounds.midX, y: bounds.minY), to: CGPoint(x: bounds.midX, y: bounds.maxY))
            }
        case .ground:
            addGround(at: center)
        case .resistor, .voltageSource, .currentSource:
            let horizontal: Bool
            if case .roundShape = pending.guess {
                horizontal = inferHorizontal(around: center)
            } else {
                horizontal = bounds.width >= bounds.height
            }
            addComponent(kind, center: center, horizontal: horizontal)
        }
    }

    // MARK: Mutations

    private func commit() {
        history.append(document.elements)
        if history.count > 40 { history.removeFirst() }
    }

    private func undo() {
        guard let previous = history.popLast() else { return }
        document.elements = previous
        selectedId = nil
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
        // Magnet the ends onto nearby terminals or wire ends.
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

    private func addComponent(_ kind: SketchElement.Kind, center rawCenter: CGPoint, horizontal: Bool) {
        let center = SketchGrid.snap(rawCenter)
        let half = SketchGrid.step * SketchGrid.componentSteps / 2
        var a = horizontal ? CGPoint(x: center.x - half, y: center.y) : CGPoint(x: center.x, y: center.y - half)
        var b = horizontal ? CGPoint(x: center.x + half, y: center.y) : CGPoint(x: center.x, y: center.y + half)
        // Line the component up with a wire it was drawn next to.
        if let near = nearestConnectionPoint(to: center, within: SketchGrid.step * 1.6) {
            if horizontal { a.y = near.y; b.y = near.y } else { a.x = near.x; b.x = near.x }
        }
        commit()
        var element = SketchElement(kind: kind, a: a, b: b, label: document.nextLabel(for: kind))
        element.asked = false
        document.elements.append(element)
        attachWires(to: element)
        selectedId = element.id
        Haptics.impact(.medium)
        editing = element
    }

    private func addGround(at rawPoint: CGPoint) {
        var point = SketchGrid.snap(rawPoint)
        if let near = nearestConnectionPoint(to: point, within: SketchGrid.step * 1.6) { point = near }
        commit()
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
                d = hypot(element.a.x - point.x, element.a.y - point.y + 12)
            } else {
                d = CGFloat(distanceToSegment(SPoint(x: point.x, y: point.y), SPoint(x: element.a.x, y: element.a.y), SPoint(x: element.b.x, y: element.b.y)))
            }
            let tolerance: CGFloat = element.kind == .wire ? 14 : 22
            if d <= tolerance, best == nil || d < best!.1 { best = (element, d) }
        }
        return best?.0
    }

    // MARK: Solve

    private func solve() {
        if let missing = document.missingValues.first {
            editing = missing
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

/// "What did you draw?" options shown next to an ambiguous stroke.
private struct ChooserBubble: View {
    let options: [SketchElement.Kind]
    let onPick: (SketchElement.Kind) -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { kind in
                Button {
                    onPick(kind)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: icon(for: kind))
                            .font(.system(size: 17, weight: .medium))
                        Text(title(for: kind))
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(PMTheme.ink)
                    .frame(width: 58, height: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PMTheme.secondaryText)
                    .frame(width: 34, height: 50)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        )
    }

    private func icon(for kind: SketchElement.Kind) -> String {
        switch kind {
        case .wire: return "minus"
        case .resistor: return "waveform.path"
        case .voltageSource: return "plusminus.circle"
        case .currentSource: return "arrow.up.circle"
        case .ground: return "arrowtriangle.down"
        }
    }

    private func title(for kind: SketchElement.Kind) -> String {
        switch kind {
        case .wire: return "Wire"
        case .resistor: return "Resistor"
        case .voltageSource: return "Voltage"
        case .currentSource: return "Current"
        case .ground: return "Ground"
        }
    }
}

/// Value + SI prefix entry for a freshly drawn component.
private struct ValueEntrySheet: View {
    let element: SketchElement
    let onSave: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var multiplier: Double = 1
    @FocusState private var focused: Bool

    private struct Prefix: Identifiable {
        let symbol: String
        let multiplier: Double
        var id: String { symbol }
    }

    private var prefixes: [Prefix] {
        switch element.kind {
        case .resistor: return [Prefix(symbol: "Ω", multiplier: 1), Prefix(symbol: "kΩ", multiplier: 1e3), Prefix(symbol: "MΩ", multiplier: 1e6)]
        case .voltageSource: return [Prefix(symbol: "mV", multiplier: 1e-3), Prefix(symbol: "V", multiplier: 1), Prefix(symbol: "kV", multiplier: 1e3)]
        case .currentSource: return [Prefix(symbol: "µA", multiplier: 1e-6), Prefix(symbol: "mA", multiplier: 1e-3), Prefix(symbol: "A", multiplier: 1)]
        default: return [Prefix(symbol: "", multiplier: 1)]
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Value", text: $text)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .focused($focused)
                        Picker("Unit", selection: $multiplier) {
                            ForEach(prefixes) { prefix in
                                Text(prefix.symbol).tag(prefix.multiplier)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }
                } footer: {
                    Text(element.kind == .voltageSource ? "The + terminal is at the top (or left). Use Flip polarity from the part's menu to turn it around."
                         : element.kind == .currentSource ? "The arrow points down (or right). Use Flip direction from the part's menu to turn it around."
                         : "")
                }
            }
            .navigationTitle("\(element.label) value")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { save() }
                        .font(.system(size: 17, weight: .semibold))
                        .disabled(parsedValue == nil)
                }
            }
            .onAppear {
                if let value = element.value {
                    let best = prefixes.min { abs(log10(value / $0.multiplier)) < abs(log10(value / $1.multiplier)) } ?? prefixes[0]
                    multiplier = best.multiplier
                    text = QuantityFormatter().number(value / best.multiplier)
                } else if let defaultPrefix = prefixes.first(where: { $0.multiplier == 1 }) {
                    multiplier = defaultPrefix.multiplier
                }
                focused = true
            }
        }
        .tint(PMTheme.accent)
    }

    private var parsedValue: Double? {
        guard let number = Double(text.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "−", with: "-")), number > 0 else { return nil }
        return number * multiplier
    }

    private func save() {
        guard let value = parsedValue else { return }
        onSave(value)
        dismiss()
    }
}

#Preview {
    SketchCanvasView { _ in }
}
