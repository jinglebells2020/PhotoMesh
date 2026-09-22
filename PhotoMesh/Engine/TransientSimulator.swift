import Foundation

/// Time-domain simulation of the drawn circuit, the way SPICE does it: for one small time step
/// every capacitor and inductor is replaced by a resistor plus a source that remembers the
/// previous step (its "companion model"), the resulting DC circuit is solved by nodal analysis,
/// and the step is repeated. Capacitors start empty and inductors start without current, the
/// moment the circuit is switched on; switches can be flipped at chosen times. The result is the
/// full history of every node voltage and every element current, for plots and for the moving
/// picture in Explore.
///
/// Integration is backward Euler: unconditionally stable, so a step can never blow up, and the
/// steps are fine enough (thousands per window) that the curves match the closed-form responses
/// to well under a percent.
enum TransientSimulator {
    struct SwitchEvent: Hashable, Codable {
        var elementId: String
        var time: Double
    }

    struct Options {
        /// Simulated seconds; nil picks five time constants of the slowest energy-storing element.
        var duration: Double? = nil
        /// Recorded samples; internal steps are `substeps` times finer.
        var samples = 400
        var substeps = 4
        /// Switches flipped while the simulation runs (closed ↔ open).
        var switchEvents: [SwitchEvent] = []
        /// Start from the settled DC state instead of from rest.
        var startAtSteadyState = false
        /// Component values to use instead of the drawn ones (what-if tweaks).
        var valueOverrides: [String: Double] = [:]
    }

    struct Result {
        var times: [Double]
        var nodeVoltages: [String: [Double]]
        /// Current through each element from its first terminal to its second.
        var elementCurrents: [String: [Double]]
        /// Voltage across each element, first terminal minus second.
        var elementVoltages: [String: [Double]]
        var duration: Double
        /// Time constant seen by each capacitor and inductor (seconds).
        var timeConstants: [String: Double]
        /// Elements drawn without a value; they were treated as open (capacitor) or as a wire (inductor).
        var missingValues: [String]

        var sampleCount: Int { times.count }

        /// Index of the sample at or just before `time`.
        func index(at time: Double) -> Int {
            guard !times.isEmpty else { return 0 }
            var low = 0, high = times.count - 1
            while low < high {
                let mid = (low + high + 1) / 2
                if times[mid] <= time { low = mid } else { high = mid - 1 }
            }
            return low
        }

        func nodeVoltages(at index: Int) -> [String: Double] {
            nodeVoltages.compactMapValues { index < $0.count ? $0[index] : nil }
        }

        func elementCurrents(at index: Int) -> [String: Double] {
            elementCurrents.compactMapValues { index < $0.count ? $0[index] : nil }
        }

        func elementVoltages(at index: Int) -> [String: Double] {
            elementVoltages.compactMapValues { index < $0.count ? $0[index] : nil }
        }

        /// Largest magnitude ever reached by a trace, for plot scales.
        func peak(_ trace: [Double]) -> Double { trace.map(abs).max() ?? 0 }
    }

    enum Failure: LocalizedError {
        case noElements
        case singular

        var errorDescription: String? {
            switch self {
            case .noElements: return "There is nothing to simulate."
            case .singular: return "The circuit cannot be simulated as drawn: two sources conflict, or a part is left floating."
            }
        }
    }

    /// Resistance of a closed switch and of an open one. The open value doubles as the leak that
    /// keeps a node connected only through opens from floating.
    static let closedSwitchResistance = 1e-3
    static let openSwitchResistance = 1e9
    /// Tiny conductance to ground on every node, the usual guard against a singular matrix.
    static let gmin = 1e-12

    // MARK: - Time constants and window

    /// Time constant of each capacitor (R·C) and inductor (L/R), with R the resistance the rest of
    /// the circuit presents at its terminals (sources switched off, other capacitors open, other
    /// inductors shorted). Elements without a value are left out.
    static func timeConstants(_ circuit: Circuit, switchStates: [String: Bool]? = nil, valueOverrides: [String: Double] = [:]) -> [String: Double] {
        var result: [String: Double] = [:]
        let states = switchStates ?? initialSwitchStates(circuit)
        for element in circuit.components where element.kind == .capacitor || element.kind == .inductor {
            let value = valueOverrides[element.id] ?? element.value
            guard value > 0, element.nodeA != element.nodeB else { continue }
            guard let r = theveninResistance(circuit, at: element, switchStates: states, valueOverrides: valueOverrides) else { continue }
            if element.kind == .capacitor {
                result[element.id] = max(r, 1e-6) * value
            } else {
                result[element.id] = value / max(r, 1e-6)
            }
        }
        return result
    }

    /// The window the plots should show: five time constants of the slowest element, stretched
    /// to cover every switch event, or one second for a circuit that does not change in time.
    static func suggestedDuration(_ circuit: Circuit, options: Options = Options()) -> Double {
        let constants = timeConstants(circuit, valueOverrides: options.valueOverrides)
        var duration = (constants.values.max() ?? 0) * 5
        if duration <= 0 { duration = 1 }
        if let latest = options.switchEvents.map(\.time).max() {
            duration = max(duration, latest + max(duration, constants.values.max().map { $0 * 5 } ?? 0.2 * latest))
        }
        return min(max(duration, 1e-6), 3600)
    }

    private static func initialSwitchStates(_ circuit: Circuit) -> [String: Bool] {
        var states: [String: Bool] = [:]
        for component in circuit.components where component.kind.isSwitch {
            states[component.id] = component.kind == .switchClosed
        }
        return states
    }

    /// Resistance between the terminals of `element` with every source switched off.
    private static func theveninResistance(_ circuit: Circuit, at element: Component, switchStates: [String: Bool], valueOverrides: [String: Double]) -> Double? {
        let nodes = circuit.nodes
        let ground = circuit.groundNode
        let unknownNodes = nodes.filter { $0 != ground }
        let index = Dictionary(uniqueKeysWithValues: unknownNodes.enumerated().map { ($1, $0) })
        // Voltage sources become shorts: keep them as 0 V branches.
        let branches = circuit.components.filter { $0.kind.dcRole == .voltageSource && $0.id != element.id }
        var system = LinearSystem(size: unknownNodes.count + branches.count)
        func stamp(_ a: String, _ b: String, conductance g: Double) {
            let ia = index[a], ib = index[b]
            if let ia { system.a[ia][ia] += g }
            if let ib { system.a[ib][ib] += g }
            if let ia, let ib { system.a[ia][ib] -= g; system.a[ib][ia] -= g }
        }
        for (i, _) in unknownNodes.enumerated() { system.a[i][i] += gmin }
        for c in circuit.components where c.id != element.id {
            let value = valueOverrides[c.id] ?? c.value
            switch c.kind {
            case .resistor, .lamp:
                if value > 0 { stamp(c.nodeA, c.nodeB, conductance: 1 / value) }
            case .capacitor:
                continue   // open
            case .inductor:
                stamp(c.nodeA, c.nodeB, conductance: 1 / closedSwitchResistance)
            case .switchOpen, .switchClosed:
                let closed = switchStates[c.id] ?? (c.kind == .switchClosed)
                stamp(c.nodeA, c.nodeB, conductance: 1 / (closed ? closedSwitchResistance : openSwitchResistance))
            case .currentSource:
                continue   // open
            case .voltageSource, .battery:
                continue   // stamped below as a 0 V branch
            }
        }
        for (k, s) in branches.enumerated() {
            let row = unknownNodes.count + k
            if let ip = index[s.nodeA] { system.a[ip][row] += 1; system.a[row][ip] += 1 }
            if let ineg = index[s.nodeB] { system.a[ineg][row] -= 1; system.a[row][ineg] -= 1 }
        }
        // Inject 1 A into nodeA and take it out of nodeB; the voltage that appears is the resistance.
        if let ia = index[element.nodeA] { system.b[ia] += 1 }
        if let ib = index[element.nodeB] { system.b[ib] -= 1 }
        guard let x = try? system.solve() else { return nil }
        let va = index[element.nodeA].map { x[$0] } ?? 0
        let vb = index[element.nodeB].map { x[$0] } ?? 0
        return max(va - vb, 0)
    }

    // MARK: - Simulation

    static func simulate(_ circuit: Circuit, options: Options = Options()) throws -> Result {
        guard !circuit.components.isEmpty else { throw Failure.noElements }
        let ground = circuit.groundNode
        let nodes = circuit.nodes
        let unknownNodes = nodes.filter { $0 != ground }
        let index = Dictionary(uniqueKeysWithValues: unknownNodes.enumerated().map { ($1, $0) })
        let sources = circuit.components.filter { $0.kind.dcRole == .voltageSource }
        let sourceRow = Dictionary(uniqueKeysWithValues: sources.enumerated().map { ($1.id, unknownNodes.count + $0) })
        let n = unknownNodes.count + sources.count

        func value(_ c: Component) -> Double { options.valueOverrides[c.id] ?? c.value }
        var missing: [String] = []
        for c in circuit.components where (c.kind == .capacitor || c.kind == .inductor) && !(value(c) > 0) { missing.append(c.id) }

        let duration = options.duration ?? suggestedDuration(circuit, options: options)
        let samples = max(options.samples, 2)
        let substeps = max(options.substeps, 1)
        let h = duration / Double(samples * substeps)
        let events = options.switchEvents.sorted { $0.time < $1.time }
        var switchStates = initialSwitchStates(circuit)
        let constants = timeConstants(circuit, switchStates: switchStates, valueOverrides: options.valueOverrides)

        // State carried from step to step.
        var capacitorVoltage: [String: Double] = [:]
        var inductorCurrent: [String: Double] = [:]
        for c in circuit.components {
            if c.kind == .capacitor { capacitorVoltage[c.id] = 0 }
            if c.kind == .inductor { inductorCurrent[c.id] = 0 }
        }

        /// One backward-Euler step of length `step`; returns node voltages and element currents.
        func advance(step: Double) throws -> (voltages: [String: Double], currents: [String: Double]) {
            var system = LinearSystem(size: n)
            func stamp(_ a: String, _ b: String, conductance g: Double) {
                let ia = index[a], ib = index[b]
                if let ia { system.a[ia][ia] += g }
                if let ib { system.a[ib][ib] += g }
                if let ia, let ib { system.a[ia][ib] -= g; system.a[ib][ia] -= g }
            }
            /// A current `i` flowing inside an element from `a` to `b`.
            func inject(_ a: String, _ b: String, current i: Double) {
                if let ia = index[a] { system.b[ia] -= i }
                if let ib = index[b] { system.b[ib] += i }
            }
            for i in 0..<unknownNodes.count { system.a[i][i] += gmin }
            for c in circuit.components {
                let v = value(c)
                switch c.kind {
                case .resistor, .lamp:
                    stamp(c.nodeA, c.nodeB, conductance: 1 / max(v, 1e-9))
                case .capacitor:
                    guard v > 0 else { continue }
                    let g = v / step
                    stamp(c.nodeA, c.nodeB, conductance: g)
                    inject(c.nodeA, c.nodeB, current: -g * (capacitorVoltage[c.id] ?? 0))
                case .inductor:
                    if v > 0 {
                        stamp(c.nodeA, c.nodeB, conductance: step / v)
                        inject(c.nodeA, c.nodeB, current: inductorCurrent[c.id] ?? 0)
                    } else {
                        stamp(c.nodeA, c.nodeB, conductance: 1 / closedSwitchResistance)
                    }
                case .switchOpen, .switchClosed:
                    let closed = switchStates[c.id] ?? (c.kind == .switchClosed)
                    stamp(c.nodeA, c.nodeB, conductance: 1 / (closed ? closedSwitchResistance : openSwitchResistance))
                case .currentSource:
                    inject(c.nodeA, c.nodeB, current: v)
                case .voltageSource, .battery:
                    guard let row = sourceRow[c.id] else { continue }
                    if let ip = index[c.nodeA] { system.a[ip][row] += 1; system.a[row][ip] += 1 }
                    if let ineg = index[c.nodeB] { system.a[ineg][row] -= 1; system.a[row][ineg] -= 1 }
                    system.b[row] = v
                }
            }
            let x: [Double]
            do { x = try system.solve() } catch { throw Failure.singular }
            var voltages: [String: Double] = [ground: 0]
            for (node, i) in index { voltages[node] = x[i] }
            var currents: [String: Double] = [:]
            for c in circuit.components {
                let va = voltages[c.nodeA] ?? 0, vb = voltages[c.nodeB] ?? 0
                let drop = va - vb
                let v = value(c)
                switch c.kind {
                case .resistor, .lamp:
                    currents[c.id] = drop / max(v, 1e-9)
                case .capacitor:
                    if v > 0 {
                        let g = v / step
                        currents[c.id] = g * (drop - (capacitorVoltage[c.id] ?? 0))
                        capacitorVoltage[c.id] = drop
                    } else {
                        currents[c.id] = 0
                    }
                case .inductor:
                    if v > 0 {
                        let i = (inductorCurrent[c.id] ?? 0) + (step / v) * drop
                        currents[c.id] = i
                        inductorCurrent[c.id] = i
                    } else {
                        currents[c.id] = drop / closedSwitchResistance
                    }
                case .switchOpen, .switchClosed:
                    let closed = switchStates[c.id] ?? (c.kind == .switchClosed)
                    currents[c.id] = drop / (closed ? closedSwitchResistance : openSwitchResistance)
                case .currentSource:
                    currents[c.id] = v
                case .voltageSource, .battery:
                    currents[c.id] = sourceRow[c.id].map { x[$0] } ?? 0
                }
            }
            return (voltages, currents)
        }

        // Settle first when asked: backward Euler with huge steps converges straight to the DC state.
        if options.startAtSteadyState {
            for _ in 0..<60 { _ = try advance(step: max(duration, 1) * 1e3) }
        }

        var times: [Double] = []
        var nodeTraces: [String: [Double]] = Dictionary(uniqueKeysWithValues: nodes.map { ($0, []) })
        var currentTraces: [String: [Double]] = Dictionary(uniqueKeysWithValues: circuit.components.map { ($0.id, []) })
        var voltageTraces: [String: [Double]] = currentTraces
        func record(time: Double, voltages: [String: Double], currents: [String: Double]) {
            times.append(time)
            for node in nodes { nodeTraces[node, default: []].append(voltages[node] ?? 0) }
            for c in circuit.components {
                currentTraces[c.id, default: []].append(currents[c.id] ?? 0)
                voltageTraces[c.id, default: []].append((voltages[c.nodeA] ?? 0) - (voltages[c.nodeB] ?? 0))
            }
        }

        // t = 0: the state before the first step (capacitors empty, inductors without current),
        // solved with a vanishing step so the record starts at the true initial values.
        var nextEvent = 0
        let initial = try advance(step: h * 1e-6)
        record(time: 0, voltages: initial.voltages, currents: initial.currents)

        var time = 0.0
        for _ in 0..<samples {
            var last: (voltages: [String: Double], currents: [String: Double]) = initial
            for _ in 0..<substeps {
                while nextEvent < events.count, events[nextEvent].time <= time {
                    let id = events[nextEvent].elementId
                    if let state = switchStates[id] { switchStates[id] = !state }
                    nextEvent += 1
                }
                last = try advance(step: h)
                time += h
            }
            record(time: time, voltages: last.voltages, currents: last.currents)
        }

        return Result(
            times: times,
            nodeVoltages: nodeTraces,
            elementCurrents: currentTraces,
            elementVoltages: voltageTraces,
            duration: duration,
            timeConstants: constants,
            missingValues: missing
        )
    }
}
