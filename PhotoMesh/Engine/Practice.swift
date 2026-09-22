import Foundation

/// "Practice a similar problem": the same circuit shape with fresh, realistic values, so a student
/// can try the method again without the answer in front of them, and an exam-style check of what
/// they typed.
enum Practice {
    static let e12: [Double] = [1.0, 1.2, 1.5, 1.8, 2.2, 2.7, 3.3, 3.9, 4.7, 5.6, 6.8, 8.2]
    static let e6: [Double] = [1.0, 1.5, 2.2, 3.3, 4.7, 6.8]
    static let voltages: [Double] = [1.5, 3, 4.5, 5, 6, 9, 10, 12, 15, 18, 20, 24, 30, 36, 48]
    static let currents: [Double] = [0.5, 1, 1.5, 2, 2.5, 3, 4, 5]

    /// A variant of `circuit` with different values that still solves with every method agreeing,
    /// or nil when eight tries do not produce one.
    static func similar(to circuit: Circuit, using rng: inout some RandomNumberGenerator) -> Circuit? {
        for _ in 0..<8 {
            let candidate = vary(circuit, using: &rng)
            guard candidate != circuit,
                  let analysis = try? CircuitAnalyzer.analyze(candidate),
                  analysis.methodsAgree, !analysis.methods.isEmpty else { continue }
            return candidate
        }
        return nil
    }

    static func similar(to circuit: Circuit) -> Circuit? {
        var rng = SystemRandomNumberGenerator()
        return similar(to: circuit, using: &rng)
    }

    /// Every valued part gets a new value from the right series; ids, wiring, question and
    /// geometry stay, so the drawing looks the same and the method applies unchanged.
    static func vary(_ circuit: Circuit, using rng: inout some RandomNumberGenerator) -> Circuit {
        var copy = circuit
        copy.notes = nil
        copy.components = circuit.components.map { component in
            var changed = component
            changed.value = newValue(for: component, using: &rng)
            return changed
        }
        return copy
    }

    static func newValue(for component: Component, using rng: inout some RandomNumberGenerator) -> Double {
        let value = component.value
        guard component.kind.hasValue, value != 0, value.isFinite else { return value }
        let sign: Double = value < 0 ? -1 : 1
        let magnitude = abs(value)
        let decade = pow(10, floor(log10(magnitude)))
        switch component.kind.dcRole {
        case .voltageSource:
            return sign * pick(from: voltages, near: magnitude, spread: 4, avoiding: magnitude, using: &rng)
        case .currentSource:
            let candidates = currents.map { $0 * decade } + currents.map { $0 * decade / 10 }
            return sign * pick(from: candidates, near: magnitude, spread: 5, avoiding: magnitude, using: &rng)
        case .resistor, .open, .short:
            let series = (component.kind == .capacitor || component.kind == .inductor) ? e6 : e12
            let candidates = [decade / 10, decade, decade * 10].flatMap { d in series.map { $0 * d } }
            return sign * pick(from: candidates, near: magnitude, spread: 4, avoiding: magnitude, using: &rng)
        }
    }

    /// A random candidate within `spread`× of `near`, never `avoiding`.
    private static func pick(from candidates: [Double], near: Double, spread: Double, avoiding: Double, using rng: inout some RandomNumberGenerator) -> Double {
        let different: (Double) -> Bool = { abs($0 - avoiding) > 1e-9 * max(1, avoiding) }
        let window = candidates.filter { $0 >= near / spread && $0 <= near * spread && different($0) }
        let pool = window.isEmpty ? candidates.filter(different) : window
        guard !pool.isEmpty else { return near }
        return pool[Int.random(in: 0..<pool.count, using: &rng)]
    }

    // MARK: Exam-style check

    struct Target {
        var label: String
        /// Base units; the sign follows the method's convention.
        var value: Double
        var unit: String
    }

    /// What the student must produce: the first asked unknown of the primary method.
    static func target(for analysis: CircuitAnalysis) -> Target? {
        guard let circuit = analysis.circuit, let method = analysis.methods.first else { return nil }
        let byId = Dictionary(method.elements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for unknown in circuit.unknowns {
            switch unknown.kind {
            case .current:
                if let id = unknown.element, let e = byId[id] { return Target(label: "Current through \(id)", value: e.current, unit: "A") }
            case .voltage:
                if let id = unknown.element, let e = byId[id] { return Target(label: "Voltage across \(id)", value: e.voltage, unit: "V") }
                if let node = unknown.node, let v = method.nodeVoltages[node] { return Target(label: "Voltage at node \(node)", value: v, unit: "V") }
                if let pair = unknown.between, pair.count == 2, let a = method.nodeVoltages[pair[0]], let b = method.nodeVoltages[pair[1]] {
                    return Target(label: "Voltage from \(pair[0]) to \(pair[1])", value: a - b, unit: "V")
                }
            case .power:
                if let id = unknown.element, let e = byId[id] { return Target(label: "Power in \(id)", value: e.power, unit: "W") }
            case .resistance:
                continue
            }
        }
        if let e = method.elements.first(where: { $0.kind == .resistor }) {
            return Target(label: "Current through \(e.id)", value: e.current, unit: "A")
        }
        return nil
    }

    /// Whether a typed answer ("1.5 mA", "0.0015", "1.5m") matches the target within 2 %. Signs
    /// are ignored, because direction conventions differ between books. Nil when unreadable.
    static func check(_ typed: String, against target: Target) -> Bool? {
        guard let value = QuantityFormatter.parseValue(typed) else { return nil }
        let expected = abs(target.value)
        let tolerance = max(0.02 * expected, 1e-12)
        return abs(abs(value) - expected) <= tolerance
    }
}
