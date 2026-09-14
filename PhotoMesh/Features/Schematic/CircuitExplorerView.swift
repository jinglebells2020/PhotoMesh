import SwiftUI

/// Full-screen schematic: pinch to zoom, drag to pan, double-tap to reset,
/// tap a wire or component to read about it in the floating card below.
struct CircuitExplorerView: View {
    let analysis: CircuitAnalysis
    var initialFocus = StepFocus()

    private struct PinchState {
        var magnification: CGFloat
        var anchor: CGPoint
    }

    @State private var committed = SchematicCamera()
    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var pinch: PinchState? = nil
    @State private var selection: SchematicLayout.Hit?
    @State private var showDetails = false
    @State private var viewSize: CGSize = .zero
    @State private var showsValues = true

    private var layout: SchematicLayout? { analysis.layout }
    private var primary: MethodSolution? { analysis.methods.first }
    private let minScale: CGFloat = 0.08
    private let maxScale: CGFloat = 6

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea()

            if let layout {
                GeometryReader { geo in
                    ZStack {
                        DotGrid()
                        SchematicView(layout: layout, style: style, camera: liveCamera)
                    }
                    .contentShape(Rectangle())
                    .gesture(SimultaneousGesture(dragGesture, magnifyGesture))
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            committed = .fitting(layout.bounds, in: geo.size)
                        }
                    }
                    .onTapGesture { location in
                        let point = liveCamera.convertToLayout(location)
                        let hit = layout.hitTest(point, tolerance: 22 / max(liveCamera.scale, 0.01))
                        Haptics.selection()
                        withAnimation(.easeOut(duration: 0.15)) { selection = hit }
                    }
                    .onAppear {
                        viewSize = geo.size
                        committed = initialCamera(in: geo.size, layout: layout)
                    }
                    .onChange(of: geo.size) { _, newSize in
                        viewSize = newSize
                    }
                }
                .ignoresSafeArea(edges: .bottom)
            } else {
                ContentUnavailableView("No drawing", systemImage: "scribble", description: Text("The recognizer did not return positions for this circuit."))
            }

            annotationCard
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .navigationTitle("Circuit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {
                    Button {
                        showsValues.toggle()
                    } label: {
                        Image(systemName: showsValues ? "textformat.123" : "textformat")
                    }
                    .accessibilityLabel(showsValues ? "Hide results" : "Show results")
                    Button("Details") { showDetails = true }
                }
                .foregroundStyle(PMTheme.accent)
            }
        }
        .sheet(isPresented: $showDetails) {
            NavigationStack {
                CircuitDetailView(analysis: analysis)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Close") { showDetails = false }
                        }
                    }
            }
        }
    }

    // MARK: Camera

    private var liveCamera: SchematicCamera {
        var camera = committed
        if let pinch {
            let newScale = min(max(camera.scale * pinch.magnification, minScale), maxScale)
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

    private func initialCamera(in size: CGSize, layout: SchematicLayout) -> SchematicCamera {
        if initialFocus.zoom {
            let region = SchematicRenderer.focusBounds(initialFocus, loops: primary?.loops ?? [], layout: layout)
            if !region.isEmpty { return .fitting(region.insetBy(90), in: size, padding: 24) }
        }
        return .fitting(layout.bounds, in: size, padding: 28)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($dragTranslation) { value, state, _ in state = value.translation }
            .onEnded { value in
                committed.offset.width += value.translation.width
                committed.offset.height += value.translation.height
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in
                state = PinchState(magnification: value.magnification, anchor: value.startLocation)
            }
            .onEnded { value in
                let newScale = min(max(committed.scale * value.magnification, minScale), maxScale)
                let ratio = newScale / committed.scale
                committed.offset = CGSize(
                    width: value.startLocation.x - (value.startLocation.x - committed.offset.width) * ratio,
                    height: value.startLocation.y - (value.startLocation.y - committed.offset.height) * ratio
                )
                committed.scale = newScale
            }
    }

    // MARK: Style

    private var style: SchematicStyle {
        var focus = StepFocus()
        if showsValues, let primary {
            focus.nodeVoltages = primary.nodeVoltages
            focus.elementCurrents = Dictionary(uniqueKeysWithValues: primary.elements.map { ($0.id, $0.current) })
        }
        return SchematicStyle(focus: focus, loops: primary?.loops ?? [], selection: selection, formatter: FormattingPreferences.formatter())
    }

    // MARK: Annotation

    private var annotationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch selection {
            case .element(let id):
                elementAnnotation(id)
            case .node(let node):
                nodeAnnotation(node)
            case nil:
                Text("Tap a component or a wire to inspect it")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(PMTheme.ink)
                Text("Pinch to zoom, drag to pan, double-tap to fit the whole circuit.")
                    .font(.system(size: 13))
                    .foregroundStyle(PMTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.14), radius: 14, y: 4)
        )
        .animation(.easeOut(duration: 0.15), value: selection)
    }

    @ViewBuilder
    private func elementAnnotation(_ id: String) -> some View {
        let formatter = FormattingPreferences.formatter()
        let component = analysis.circuit?.component(id)
        let result = primary?.elements.first { $0.id == id }
        HStack {
            Text(id)
                .font(.system(size: 17, weight: .bold, design: .rounded))
            Text(component?.kind.displayName ?? "")
                .font(.system(size: 13))
                .foregroundStyle(PMTheme.secondaryText)
            Spacer()
            if let component {
                Text(component.kind.valueText(component.value, formatter: formatter))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
        }
        .foregroundStyle(PMTheme.ink)
        if let component {
            Text(terminalText(component))
                .font(.system(size: 13))
                .foregroundStyle(PMTheme.secondaryText)
        }
        if let result {
            let context = AnalysisContext(circuit: analysis.circuit ?? SampleCircuitSolver.sample, formatter: formatter)
            VStack(alignment: .leading, spacing: 3) {
                Text("I = \(Answers.currentDescription(result, context: context))")
                Text("V = \(Answers.voltageDescription(result, context: context))")
                Text("P = \(formatter.format(abs(result.power), "W")) \(result.kind == .resistor ? "dissipated" : (result.power < 0 ? "delivered" : "absorbed"))")
            }
            .font(.system(size: 14, design: .rounded))
            .foregroundStyle(PMTheme.ink)
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func nodeAnnotation(_ node: String) -> some View {
        let formatter = FormattingPreferences.formatter()
        let connected = analysis.circuit?.components(at: node).map(\.id) ?? []
        HStack {
            Text(node == analysis.circuit?.groundNode ? "Node \(node) · reference" : "Node \(node)")
                .font(.system(size: 17, weight: .bold, design: .rounded))
            Spacer()
            if let v = primary?.nodeVoltages[node] {
                Text(formatter.format(v, "V"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(PMTheme.accent)
            }
        }
        .foregroundStyle(PMTheme.ink)
        Text("Connects " + connected.joined(separator: ", "))
            .font(.system(size: 13))
            .foregroundStyle(PMTheme.secondaryText)
        Text(node == analysis.circuit?.groundNode
             ? "All other node voltages are measured relative to this node (0 V)."
             : "Every point on this wire is at the same potential.")
            .font(.system(size: 13))
            .foregroundStyle(PMTheme.secondaryText)
    }

    private func terminalText(_ component: Component) -> String {
        switch component.kind.dcRole {
        case .voltageSource: return "+ terminal on \(component.nodeA), − terminal on \(component.nodeB)"
        case .currentSource: return "Pushes current from \(component.nodeA) into \(component.nodeB)"
        case .open: return "Between \(component.nodeA) and \(component.nodeB) (open at DC)"
        case .short: return "Between \(component.nodeA) and \(component.nodeB) (a short at DC)"
        case .resistor: return "Between \(component.nodeA) and \(component.nodeB)"
        }
    }
}

#Preview {
    NavigationStack {
        if let analysis = try? CircuitAnalyzer.analyze(SampleCircuitSolver.sample) {
            CircuitExplorerView(analysis: analysis)
        }
    }
}
