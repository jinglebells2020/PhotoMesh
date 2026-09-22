import SwiftUI
import Charts

/// Demonstrations built from the app's own solver, so every number a lesson shows is one the
/// engine computed, and the schematic looks exactly like the one a scanned circuit gets.

/// Solved demo circuits, built once per launch.
@MainActor
enum DemoAnalysisCache {
    private static var cache: [String: CircuitAnalysis] = [:]

    static func analysis(for spec: CircuitDemoSpec) -> CircuitAnalysis? {
        if let hit = cache[spec.id] { return hit }
        guard let circuit = spec.circuit, let analysis = try? CircuitAnalyzer.analyze(circuit, formatter: FormattingPreferences.formatter()) else { return nil }
        cache[spec.id] = analysis
        return analysis
    }
}

// MARK: - Keyframed circuit

/// The circuit lit up keyframe by keyframe: currents move, nodes and parts light up, mesh
/// arrows and supernode boundaries appear as the caption explains them.
struct CircuitDemoView: View {
    let spec: CircuitDemoSpec

    var body: some View {
        if let analysis = DemoAnalysisCache.analysis(for: spec), let layout = analysis.layout {
            DemoPlayer(duration: max(spec.loopSeconds, 1), autoplay: true) { phase, _ in
                let (keyframe, focus) = CircuitDemoView.state(at: phase, spec: spec, analysis: analysis)
                VStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack {
                            Color.white
                            DotGrid()
                            SchematicView(
                                layout: layout,
                                style: SchematicStyle(focus: focus, loops: meshLoops(analysis), formatter: FormattingPreferences.formatter()),
                                camera: .fitting(layout.bounds, in: geo.size, padding: 18)
                            )
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.black.opacity(0.08)))
                    if let caption = keyframe?.caption, !caption.isEmpty {
                        Text(caption)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(PMTheme.ink)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 36)
                            .padding(.horizontal, 8)
                            .contentTransition(.opacity)
                            .animation(.easeInOut(duration: 0.25), value: caption)
                    }
                }
            }
        } else {
            DemoUnavailable()
        }
    }

    private func meshLoops(_ analysis: CircuitAnalysis) -> [LoopPath] {
        analysis.methods.first { $0.method == .mesh }?.loops ?? []
    }

    /// The keyframe active at `phase` and the focus it asks for.
    static func state(at phase: Double, spec: CircuitDemoSpec, analysis: CircuitAnalysis) -> (DemoKeyframe?, StepFocus) {
        guard !spec.keyframes.isEmpty else { return (nil, flowFocus(analysis, polarity: false)) }
        let share = spec.loopSeconds / Double(spec.keyframes.count)
        var start = 0.0
        var active = spec.keyframes[spec.keyframes.count - 1]
        for keyframe in spec.keyframes {
            let length = keyframe.seconds ?? share
            if phase < start + length { active = keyframe; break }
            start += length
        }
        return (active, focus(for: active.highlight, analysis: analysis))
    }

    static func flowFocus(_ analysis: CircuitAnalysis, polarity: Bool) -> StepFocus {
        var focus = StepFocus()
        guard let primary = analysis.methods.first else { return focus }
        focus.nodeVoltages = primary.nodeVoltages
        focus.elementCurrents = Dictionary(uniqueKeysWithValues: primary.elements.map { ($0.id, $0.current) })
        focus.animateCurrents = true
        focus.showPolarity = polarity
        return focus
    }

    static func focus(for highlight: DemoKeyframe.Highlight, analysis: CircuitAnalysis) -> StepFocus {
        let primary = analysis.methods.first
        let mesh = analysis.methods.first { $0.method == .mesh }
        switch highlight {
        case .all:
            return StepFocus()
        case .elements(let ids):
            return StepFocus(elements: ids)
        case .nodes(let nodes):
            var focus = StepFocus(nodes: nodes)
            if let primary { focus.nodeVoltages = primary.nodeVoltages.filter { nodes.contains($0.key) } }
            return focus
        case .flow:
            return flowFocus(analysis, polarity: false)
        case .flowWithPolarity:
            return flowFocus(analysis, polarity: true)
        case .mesh(let index):
            var focus = StepFocus(loops: [index], showMeshArrows: true)
            focus.meshCurrents = meshCurrents(mesh)
            return focus
        case .meshes:
            var focus = StepFocus(loops: Array((mesh?.loops ?? []).indices), showMeshArrows: true)
            focus.meshCurrents = meshCurrents(mesh)
            return focus
        case .supernode(let nodes, let elements):
            var focus = StepFocus(nodes: nodes, elements: elements)
            focus.supernodes = [Supernode(nodes: nodes, elements: elements)]
            return focus
        }
    }

    /// The mesh method's solved currents, from the last step that knows them all.
    private static func meshCurrents(_ mesh: MethodSolution?) -> [Int: Double] {
        guard let mesh else { return [:] }
        for step in mesh.steps.reversed() where step.focus.meshCurrents.count == mesh.loops.count && !step.focus.meshCurrents.isEmpty {
            return step.focus.meshCurrents
        }
        return [:]
    }
}

// MARK: - Auto-played solving steps

/// The engine's own walkthrough of a circuit, one step every few seconds, with the schematic
/// following each step the way the Solving Steps screen does.
struct StepsDemoView: View {
    let spec: CircuitDemoSpec
    let method: AnalysisMethod
    @State private var index = 0
    @State private var autoAdvance = true

    var body: some View {
        if let analysis = DemoAnalysisCache.analysis(for: spec),
           let solution = analysis.methods.first(where: { $0.method == method }) ?? analysis.methods.first,
           let layout = analysis.layout, !solution.steps.isEmpty {
            let step = solution.steps[min(index, solution.steps.count - 1)]
            VStack(spacing: 10) {
                SchematicWindow(layout: layout, loops: solution.loops, focus: step.focus)
                    .frame(height: 200)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Step \(index + 1) of \(solution.steps.count)")
                            .font(.system(size: 11, weight: .semibold))
                            .kerning(0.5)
                            .foregroundStyle(PMTheme.secondaryText)
                        Spacer()
                        Button {
                            autoAdvance.toggle()
                            Haptics.selection()
                        } label: {
                            Label(autoAdvance ? "Auto" : "Paused", systemImage: autoAdvance ? "play.fill" : "pause.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(PMTheme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    Text(step.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(PMTheme.ink)
                    ForEach(Array(step.equations.prefix(5).enumerated()), id: \.offset) { _, line in
                        ScrollView(.horizontal, showsIndicators: false) {
                            MathText(latex: EquationLaTeX.latex(for: line), fallback: line, fontSize: 13.5, color: PMTheme.ink)
                                .padding(.vertical, 1)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                    }
                    if step.equations.count > 5 {
                        Text("… \(step.equations.count - 5) more lines in the full walkthrough")
                            .font(.system(size: 11))
                            .foregroundStyle(PMTheme.tertiaryText)
                    }
                    Text(step.explanation)
                        .font(.system(size: 13))
                        .foregroundStyle(PMTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(step.result)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(PMTheme.accent)
                }
                .id(index)
                .transition(.opacity)
                HStack {
                    Button {
                        autoAdvance = false
                        Haptics.impact(.light)
                        withAnimation { index = (index - 1 + solution.steps.count) % solution.steps.count }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 40, height: 36)
                            .background(Capsule().fill(PMTheme.groupedBackground))
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(0..<solution.steps.count, id: \.self) { i in
                            Circle()
                                .fill(i == index ? PMTheme.accent : PMTheme.chipBorder)
                                .frame(width: 5, height: 5)
                        }
                    }
                    Spacer()
                    Button {
                        autoAdvance = false
                        Haptics.impact(.light)
                        withAnimation { index = (index + 1) % solution.steps.count }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 40, height: 36)
                            .background(Capsule().fill(PMTheme.groupedBackground))
                    }
                }
                .foregroundStyle(PMTheme.ink)
                .buttonStyle(.plain)
            }
            .task(id: index) {
                guard autoAdvance else { return }
                try? await Task.sleep(for: .seconds(7))
                if !Task.isCancelled, autoAdvance {
                    withAnimation { index = (index + 1) % solution.steps.count }
                }
            }
        } else {
            DemoUnavailable()
        }
    }
}

// MARK: - Transient playback

/// The circuit switched on and played in time, the way the lab's Simulate mode does it.
struct TransientDemoView: View {
    let spec: CircuitDemoSpec
    let traces: [TransientTrace]
    var switchAt: Double? = nil

    @State private var result: TransientSimulator.Result?
    @State private var layout: SchematicLayout?
    @State private var failed = false

    private var formatter: QuantityFormatter { FormattingPreferences.formatter() }

    var body: some View {
        Group {
            if let result, let layout {
                DemoPlayer(duration: 7, autoplay: true) { phase, _ in
                    let t = min(result.duration, result.duration * max(0, phase - 0.6) / 6.0)
                    let index = result.index(at: t)
                    VStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack {
                                Color.white
                                DotGrid()
                                SchematicView(layout: layoutAt(t, layout: layout), style: SchematicStyle(focus: focus(result, index: index), formatter: formatter), camera: .fitting(layout.bounds, in: geo.size, padding: 18))
                            }
                        }
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.black.opacity(0.08)))
                        MiniTraceChart(result: result, traces: traces, time: t, formatter: formatter)
                            .frame(height: 130)
                        Text("t = \(formatter.format(t, "s"))" + (result.timeConstants.isEmpty ? "" : "   τ = \(formatter.format(result.timeConstants.values.max() ?? 0, "s"))"))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(PMTheme.secondaryText)
                            .monospacedDigit()
                    }
                }
            } else if failed {
                DemoUnavailable()
            } else {
                ProgressView().tint(PMTheme.accent).frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard result == nil, let circuit = spec.circuit else { failed = true; return }
        var options = TransientSimulator.Options()
        options.samples = 300
        if let switchAt, let sw = circuit.components.first(where: { $0.kind.isSwitch }) {
            options.switchEvents = [TransientSimulator.SwitchEvent(elementId: sw.id, time: switchAt)]
        }
        let computed = try? TransientSimulator.simulate(circuit, options: options)
        if let computed {
            result = computed
            layout = SchematicLayoutEngine.layout(for: circuit)
        } else {
            failed = true
        }
    }

    private func layoutAt(_ t: Double, layout: SchematicLayout) -> SchematicLayout {
        guard let switchAt, t >= switchAt, let circuit = spec.circuit else { return layout }
        var flipped = circuit
        flipped.components = flipped.components.map { c in
            var copy = c
            if c.kind == .switchClosed { copy.kind = .switchOpen } else if c.kind == .switchOpen { copy.kind = .switchClosed }
            return copy
        }
        return SchematicLayoutEngine.layout(for: flipped)
    }

    private func focus(_ result: TransientSimulator.Result, index: Int) -> StepFocus {
        var focus = StepFocus()
        focus.nodeVoltages = result.nodeVoltages(at: index)
        focus.elementCurrents = result.elementCurrents(at: index)
        focus.animateCurrents = true
        focus.flowReference = result.elementCurrents.values.map { result.peak($0) }.max() ?? 1
        return focus
    }
}

/// A small plot of a few traces with a cursor.
struct MiniTraceChart: View {
    let result: TransientSimulator.Result
    let traces: [TransientTrace]
    let time: Double
    let formatter: QuantityFormatter

    private struct Point: Identifiable {
        let id: Int
        let t: Double
        let v: Double
    }

    private static let palette: [Color] = [PMTheme.accent, Color(red: 0.86, green: 0.36, blue: 0.14), Color(red: 0.16, green: 0.42, blue: 0.86)]

    private func values(_ trace: TransientTrace) -> [Double] {
        switch trace.kind {
        case .nodeVoltage: return result.nodeVoltages[trace.id] ?? []
        case .elementCurrent: return result.elementCurrents[trace.id] ?? []
        case .elementVoltage: return result.elementVoltages[trace.id] ?? []
        }
    }

    private func points(_ trace: TransientTrace) -> [Point] {
        let v = values(trace)
        let step = max(1, v.count / 120)
        return stride(from: 0, to: v.count, by: step).map { Point(id: $0, t: result.times[$0], v: v[$0]) }
    }

    var body: some View {
        let unit = traces.first.map { $0.kind == .elementCurrent ? "A" : "V" } ?? "V"
        Chart {
            ForEach(Array(traces.enumerated()), id: \.offset) { offset, trace in
                ForEach(points(trace)) { p in
                    LineMark(x: .value("Time", p.t), y: .value(trace.label, p.v))
                }
                .foregroundStyle(MiniTraceChart.palette[offset % MiniTraceChart.palette.count])
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            RuleMark(x: .value("Now", time))
                .foregroundStyle(PMTheme.ink.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .chartXScale(domain: 0...max(result.duration, 1e-9))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let t = value.as(Double.self) { Text(formatter.format(t, "s")).font(.system(size: 9)) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(formatter.format(v, unit)).font(.system(size: 9)) }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                ForEach(Array(traces.enumerated()), id: \.offset) { offset, trace in
                    HStack(spacing: 4) {
                        Circle().fill(MiniTraceChart.palette[offset % MiniTraceChart.palette.count]).frame(width: 7, height: 7)
                        Text(trace.label).font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(PMTheme.ink)
                    }
                }
            }
            .padding(6)
        }
    }
}

struct DemoUnavailable: View {
    var body: some View {
        ContentUnavailableView("Demo unavailable", systemImage: "bolt.slash", description: Text("This example could not be built."))
            .frame(maxWidth: .infinity, minHeight: 160)
    }
}
