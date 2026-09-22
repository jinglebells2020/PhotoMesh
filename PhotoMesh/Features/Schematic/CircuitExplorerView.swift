import SwiftUI

/// Full-screen schematic with three ways of looking at a circuit:
/// - Inspect: pinch, pan, tap a part or a wire to read about it.
/// - Tweak (Plus): drag any value or flip a switch; the DC solution and the moving currents follow.
/// - Simulate (Plus): play the circuit in time from the moment it is switched on.
struct CircuitExplorerView: View {
    let analysis: CircuitAnalysis
    var initialFocus = StepFocus()

    private struct PinchState {
        var magnification: CGFloat
        var anchor: CGPoint
    }

    @State private var model: ExplorerModel
    @State private var committed = SchematicCamera()
    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var pinch: PinchState? = nil
    @State private var selection: SchematicLayout.Hit?
    @State private var showDetails = false
    @State private var showExport = false
    @State private var showPaywall = false
    @State private var schematicSize: CGSize = .zero
    @State private var showsValues = true

    private let minScale: CGFloat = 0.08
    private let maxScale: CGFloat = 6

    init(analysis: CircuitAnalysis, initialFocus: StepFocus = StepFocus()) {
        self.analysis = analysis
        self.initialFocus = initialFocus
        _model = State(initialValue: ExplorerModel(analysis: analysis))
    }

    private var layout: SchematicLayout? { model.layout ?? analysis.layout }
    private var primary: MethodSolution? { model.displayedAnalysis.methods.first }

    var body: some View {
        GeometryReader { geo in
            let panelHeight: CGFloat = model.mode == .inspect ? 176 : min(geo.size.height * 0.52, 460)
            let area = CGSize(width: geo.size.width, height: max(120, geo.size.height - panelHeight))
            VStack(spacing: 0) {
                if let layout {
                    schematic(layout, area: area)
                        .frame(height: area.height)
                } else {
                    ContentUnavailableView("No drawing", systemImage: "scribble", description: Text("The recognizer did not return positions for this circuit."))
                        .frame(height: area.height)
                }
                panel
                    .frame(height: panelHeight)
            }
        }
        .background(Color.white.ignoresSafeArea())
        .navigationTitle("Circuit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {
                    if model.mode == .inspect {
                        Button {
                            showsValues.toggle()
                        } label: {
                            Image(systemName: showsValues ? "textformat.123" : "textformat")
                        }
                        .accessibilityLabel(showsValues ? "Hide results" : "Show results")
                    }
                    Button {
                        if PlusAccess.allows(.exports) {
                            showExport = true
                        } else {
                            PlusAccess.notedLockedTap(.exports)
                            showPaywall = true
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export to LTspice")
                    Button("Details") { showDetails = true }
                }
                .foregroundStyle(PMTheme.accent)
            }
        }
        .sheet(isPresented: $showDetails) {
            NavigationStack {
                CircuitDetailView(analysis: model.displayedAnalysis)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Close") { showDetails = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showExport) {
            ExportSheet(kind: .ltspice(analysis: model.displayedAnalysis))
        }
        .sheet(isPresented: $showPaywall) {
            PlusSheet()
        }
        .onDisappear { model.pause() }
        .onChange(of: model.mode) { _, mode in
            Analytics.shared.track("explorer_mode", ["mode": .string(mode.rawValue)])
            if mode == .simulate, model.simulation == nil { model.simulate() }
            if mode != .simulate { model.pause() }
        }
    }

    // MARK: Schematic

    private func schematic(_ layout: SchematicLayout, area: CGSize) -> some View {
        ZStack {
            DotGrid()
            SchematicView(layout: layout, style: style, camera: liveCamera)
        }
        .contentShape(Rectangle())
        .clipped()
        .gesture(SimultaneousGesture(dragGesture, magnifyGesture))
        .onTapGesture(count: 2) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                committed = .fitting(layout.bounds, in: area, padding: 28)
            }
        }
        .onTapGesture { location in
            handleTap(at: location, layout: layout)
        }
        .onAppear {
            schematicSize = area
            committed = initialCamera(in: area, layout: layout)
        }
        .onChange(of: area) { _, newArea in
            schematicSize = newArea
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                committed = .fitting(layout.bounds, in: newArea, padding: 28)
            }
        }
    }

    private func handleTap(at location: CGPoint, layout: SchematicLayout) {
        let point = liveCamera.convertToLayout(location)
        let hit = layout.hitTest(point, tolerance: 22 / max(liveCamera.scale, 0.01))
        Haptics.selection()
        if model.mode != .inspect, case .element(let id)? = hit, let component = model.baseCircuit.component(id), component.kind.isSwitch, PlusAccess.allows(.lab) {
            model.toggleSwitch(id)
            return
        }
        withAnimation(.easeOut(duration: 0.15)) { selection = hit }
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
        let focus = model.schematicFocus(showsValues: showsValues)
        return SchematicStyle(focus: focus, loops: primary?.loops ?? [], selection: selection, formatter: FormattingPreferences.formatter())
    }

    // MARK: Panel

    private var panel: some View {
        VStack(spacing: 0) {
            ModePicker(mode: $model.mode)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 8)
            Divider()
            Group {
                switch model.mode {
                case .inspect:
                    ScrollView(showsIndicators: false) {
                        annotation
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                case .tweak:
                    if PlusAccess.allows(.lab) {
                        TweakPanel(model: model)
                    } else {
                        ScrollView(showsIndicators: false) {
                            PlusLockCard(feature: .lab, compact: true).padding(16)
                        }
                    }
                case .simulate:
                    if PlusAccess.allows(.lab) {
                        SimulatePanel(model: model)
                    } else {
                        ScrollView(showsIndicators: false) {
                            PlusLockCard(feature: .lab, compact: true).padding(16)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(
            Color.white
                .shadow(color: .black.opacity(0.10), radius: 12, y: -3)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: Annotation

    @ViewBuilder
    private var annotation: some View {
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
                Text("Pinch to zoom, drag to pan, double-tap to fit. Tweak lets you change any value; Simulate plays the circuit in time.")
                    .font(.system(size: 13))
                    .foregroundStyle(PMTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.15), value: selection)
    }

    @ViewBuilder
    private func elementAnnotation(_ id: String) -> some View {
        let formatter = FormattingPreferences.formatter()
        let circuit = model.displayedAnalysis.circuit
        let component = circuit?.component(id)
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
            let context = AnalysisContext(circuit: circuit ?? SampleCircuitSolver.sample, formatter: formatter)
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
        let circuit = model.displayedAnalysis.circuit
        let connected = circuit?.components(at: node).map(\.id) ?? []
        HStack {
            Text(node == circuit?.groundNode ? "Node \(node) · reference" : "Node \(node)")
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
        Text(node == circuit?.groundNode
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

/// Inspect · Tweak · Simulate, with a lock on the Plus modes for free users.
private struct ModePicker: View {
    @Binding var mode: ExplorerModel.Mode

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ExplorerModel.Mode.allCases) { candidate in
                let selected = candidate == mode
                let locked = candidate != .inspect && !PlusAccess.hasPlus
                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { mode = candidate }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: locked ? "lock.fill" : candidate.systemImage)
                            .font(.system(size: 12, weight: .semibold))
                        Text(candidate.title)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(selected ? .white : PMTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Capsule().fill(selected ? PMTheme.accent : PMTheme.groupedBackground))
                }
                .buttonStyle(.plain)
            }
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
