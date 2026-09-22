import Foundation
import Observation

/// State behind the circuit explorer's three modes: looking at the solved circuit, changing
/// values and switches to see the DC result follow, and playing the circuit in time.
@MainActor
@Observable
final class ExplorerModel {
    enum Mode: String, CaseIterable, Identifiable {
        case inspect, tweak, simulate
        var id: String { rawValue }
        var title: String {
            switch self {
            case .inspect: return "Inspect"
            case .tweak: return "Tweak"
            case .simulate: return "Simulate"
            }
        }
        var systemImage: String {
            switch self {
            case .inspect: return "hand.tap"
            case .tweak: return "slider.horizontal.3"
            case .simulate: return "play.circle"
            }
        }
    }

    /// One plotted quantity.
    enum TraceKey: Hashable, Identifiable {
        case nodeVoltage(String)
        case elementCurrent(String)
        case elementVoltage(String)

        var id: String {
            switch self {
            case .nodeVoltage(let n): return "V@\(n)"
            case .elementCurrent(let e): return "I(\(e))"
            case .elementVoltage(let e): return "V(\(e))"
            }
        }
        var isCurrent: Bool { if case .elementCurrent = self { return true } else { return false } }
        var label: String {
            switch self {
            case .nodeVoltage(let n): return "V" + n
            case .elementCurrent(let e): return "I(\(e))"
            case .elementVoltage(let e): return "V(\(e))"
            }
        }
    }

    let base: CircuitAnalysis
    let baseCircuit: Circuit
    var mode: Mode = .inspect

    // MARK: Tweaks

    /// Values that differ from the drawing.
    private(set) var overrides: [String: Double] = [:]
    /// Switches flipped relative to the drawing.
    private(set) var flippedSwitches: Set<String> = []
    /// The DC solution of the tweaked circuit (the original when nothing changed).
    private(set) var tweaked: CircuitAnalysis
    private(set) var tweakError: String?
    @ObservationIgnored private var resolveTask: Task<Void, Never>?

    var hasTweaks: Bool { !overrides.isEmpty || !flippedSwitches.isEmpty }

    // MARK: Simulation

    private(set) var simulation: TransientSimulator.Result?
    private(set) var simulationError: String?
    private(set) var simulating = false
    var time: Double = 0
    var playing = false
    /// Real seconds one full pass of the simulated window takes.
    var playbackSeconds: Double = 6
    private(set) var switchEvents: [TransientSimulator.SwitchEvent] = []
    var selectedTraces: Set<TraceKey> = []
    @ObservationIgnored private var playTask: Task<Void, Never>?
    @ObservationIgnored private var layoutCache: [Set<String>: SchematicLayout] = [:]

    init(analysis: CircuitAnalysis) {
        base = analysis
        baseCircuit = analysis.drawn ?? analysis.circuit ?? SampleCircuitSolver.sample
        tweaked = analysis
        selectedTraces = Set(ExplorerModel.defaultTraces(for: baseCircuit))
        // A circuit with no steady state (a series capacitor) opens straight on its time response.
        if analysis.methods.isEmpty { mode = .simulate }
    }

    /// The drawing for the current mode. Inspect and Tweak show the solved (DC) drawing; Simulate
    /// shows every node separately, with the switches as they stand at the playhead.
    var layout: SchematicLayout? {
        switch mode {
        case .inspect: return base.layout
        case .tweak: return tweaked.layout ?? base.layout
        case .simulate:
            let closed = Set(switches.map(\.id).filter { isClosedInSimulation($0) })
            if let cached = layoutCache[closed] { return cached }
            var circuit = tweakedCircuit
            circuit.components = circuit.components.map { component in
                var copy = component
                if component.kind.isSwitch { copy.kind = closed.contains(component.id) ? .switchClosed : .switchOpen }
                return copy
            }
            let built = SchematicLayoutEngine.layout(for: circuit)
            layoutCache[closed] = built
            return built
        }
    }

    /// Value changes redraw the labels, so the simulation drawings are rebuilt.
    private func invalidateLayouts() { layoutCache = [:] }

    // MARK: - Circuits

    /// The drawing with the current tweaks applied.
    var tweakedCircuit: Circuit {
        var circuit = baseCircuit
        circuit.components = circuit.components.map { component in
            var copy = component
            if let value = overrides[component.id] { copy.value = value }
            if flippedSwitches.contains(component.id) {
                copy.kind = component.kind == .switchClosed ? .switchOpen : (component.kind == .switchOpen ? .switchClosed : component.kind)
            }
            return copy
        }
        return circuit
    }

    var displayedAnalysis: CircuitAnalysis { mode == .inspect ? base : tweaked }

    func value(of id: String) -> Double {
        overrides[id] ?? baseCircuit.component(id)?.value ?? 0
    }

    func isClosed(_ id: String) -> Bool {
        guard let component = baseCircuit.component(id) else { return false }
        let drawnClosed = component.kind == .switchClosed
        return flippedSwitches.contains(id) ? !drawnClosed : drawnClosed
    }

    func setValue(_ value: Double, for id: String) {
        guard let component = baseCircuit.component(id) else { return }
        if abs(value - component.value) <= 1e-12 * max(1, abs(component.value)) {
            overrides[id] = nil
        } else {
            overrides[id] = value
        }
        invalidateLayouts()
        scheduleResolve()
    }

    func toggleSwitch(_ id: String) {
        if mode == .simulate {
            toggleSwitchInSimulation(id)
        } else {
            if flippedSwitches.contains(id) { flippedSwitches.remove(id) } else { flippedSwitches.insert(id) }
            invalidateLayouts()
            scheduleResolve()
        }
    }

    func resetTweaks() {
        overrides = [:]
        flippedSwitches = []
        tweaked = base
        tweakError = nil
        invalidateLayouts()
        if simulation != nil { simulate() }
    }

    /// Re-solves shortly after the last change, so a slider drag does not queue up solves.
    private func scheduleResolve() {
        resolveTask?.cancel()
        let circuit = tweakedCircuit
        resolveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled, let self else { return }
            do {
                let analysis = try CircuitAnalyzer.analyze(circuit, formatter: FormattingPreferences.formatter())
                self.tweaked = analysis
                self.tweakError = nil
            } catch {
                self.tweakError = error.localizedDescription
            }
            if self.mode == .simulate { self.simulate() }
        }
    }

    // MARK: - Simulation

    var hasEnergyStorage: Bool {
        baseCircuit.components.contains { ($0.kind == .capacitor || $0.kind == .inductor) }
    }

    var switches: [Component] { baseCircuit.components.filter { $0.kind.isSwitch } }

    /// Every quantity that can be plotted.
    var availableTraces: [TraceKey] {
        var keys: [TraceKey] = []
        for node in baseCircuit.nodes where node != baseCircuit.groundNode { keys.append(.nodeVoltage(node)) }
        for c in baseCircuit.components { keys.append(.elementCurrent(c.id)) }
        for c in baseCircuit.components where c.kind == .capacitor || c.kind == .inductor || c.kind == .currentSource { keys.append(.elementVoltage(c.id)) }
        return keys
    }

    static func defaultTraces(for circuit: Circuit) -> [TraceKey] {
        var keys: [TraceKey] = []
        for c in circuit.components {
            if c.kind == .capacitor { keys.append(.elementVoltage(c.id)) }
            if c.kind == .inductor { keys.append(.elementCurrent(c.id)) }
        }
        if keys.isEmpty {
            if let asked = circuit.unknowns.first?.element { keys.append(.elementCurrent(asked)) }
            if let node = circuit.nodes.first(where: { $0 != circuit.groundNode }) { keys.append(.nodeVoltage(node)) }
        }
        return Array(keys.prefix(3))
    }

    func trace(_ key: TraceKey) -> [Double] {
        guard let simulation else { return [] }
        switch key {
        case .nodeVoltage(let n): return simulation.nodeVoltages[n] ?? []
        case .elementCurrent(let e): return simulation.elementCurrents[e] ?? []
        case .elementVoltage(let e): return simulation.elementVoltages[e] ?? []
        }
    }

    func simulate() {
        simulating = true
        simulationError = nil
        let circuit = tweakedCircuit
        var options = TransientSimulator.Options()
        options.switchEvents = switchEvents
        let events = switchEvents
        Task.detached(priority: .userInitiated) { [weak self] in
            let outcome: Result<TransientSimulator.Result, Error>
            do { outcome = .success(try TransientSimulator.simulate(circuit, options: options)) } catch { outcome = .failure(error) }
            await MainActor.run { [weak self] in
                guard let self, self.switchEvents == events else { return }
                self.simulating = false
                switch outcome {
                case .success(let result):
                    self.simulation = result
                    if self.time > result.duration { self.time = 0 }
                case .failure(let error):
                    self.simulationError = error.localizedDescription
                }
            }
        }
    }

    /// Flips a switch at the current moment of the simulation; the run is redone with the event.
    private func toggleSwitchInSimulation(_ id: String) {
        if let index = switchEvents.lastIndex(where: { $0.elementId == id && abs($0.time - time) < 1e-9 }) {
            switchEvents.remove(at: index)
        } else {
            switchEvents.append(TransientSimulator.SwitchEvent(elementId: id, time: time))
        }
        simulate()
    }

    /// Whether a switch is closed at the current playhead, events included.
    func isClosedInSimulation(_ id: String) -> Bool {
        var closed = isClosed(id)
        for event in switchEvents where event.elementId == id && event.time <= time + 1e-12 { closed.toggle() }
        return closed
    }

    func clearEvents() {
        switchEvents = []
        simulate()
    }

    var sampleIndex: Int { simulation?.index(at: time) ?? 0 }

    /// Peak element current over the whole run, so the dots slow down as the currents die away.
    var peakCurrent: Double {
        guard let simulation else { return 1 }
        return simulation.elementCurrents.values.map { simulation.peak($0) }.max() ?? 1
    }

    // MARK: Playback

    func play() {
        guard let simulation, !playing else { return }
        if time >= simulation.duration * 0.999 { time = 0 }
        playing = true
        let duration = simulation.duration
        let startTime = time
        let startedAt = Date()
        playTask?.cancel()
        playTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard let self, self.playing else { return }
                let elapsed = Date().timeIntervalSince(startedAt)
                let next = startTime + elapsed * duration / max(self.playbackSeconds, 0.5)
                if next >= duration {
                    self.time = duration
                    self.playing = false
                    return
                }
                self.time = next
            }
        }
    }

    func pause() {
        playing = false
        playTask?.cancel()
        playTask = nil
    }

    func togglePlay() { playing ? pause() : play() }

    func restart() {
        pause()
        time = 0
    }

    // MARK: - What the schematic shows

    /// Focus for the schematic in the current mode.
    func schematicFocus(showsValues: Bool) -> StepFocus {
        var focus = StepFocus()
        switch mode {
        case .inspect:
            if showsValues, let primary = base.methods.first {
                focus.nodeVoltages = primary.nodeVoltages
                focus.elementCurrents = Dictionary(uniqueKeysWithValues: primary.elements.map { ($0.id, $0.current) })
            }
        case .tweak:
            if let primary = tweaked.methods.first {
                focus.nodeVoltages = primary.nodeVoltages
                focus.elementCurrents = Dictionary(uniqueKeysWithValues: primary.elements.map { ($0.id, $0.current) })
                focus.animateCurrents = true
            }
        case .simulate:
            if let simulation {
                let index = simulation.index(at: time)
                focus.nodeVoltages = simulation.nodeVoltages(at: index)
                focus.elementCurrents = simulation.elementCurrents(at: index)
                focus.animateCurrents = true
                focus.flowReference = peakCurrent
            }
        }
        return focus
    }

    /// The question's answer for the tweaked circuit, next to the original.
    var answerComparison: (label: String, original: String, tweaked: String)? {
        guard let originalAnswer = base.methods.first?.answers.first else { return nil }
        let newAnswer = tweaked.methods.first?.answers.first(where: { $0.label == originalAnswer.label }) ?? tweaked.methods.first?.answers.first
        return (originalAnswer.label, originalAnswer.value, newAnswer?.value ?? "—")
    }
}
