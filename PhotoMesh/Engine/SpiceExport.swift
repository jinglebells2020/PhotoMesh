import Foundation

/// Writes the drawn circuit for LTspice: a plain SPICE netlist (`.cir`, readable by any SPICE)
/// and an LTspice schematic (`.asc`) laid out like the drawing, with every element wired up and
/// the nets named after the nodes. Element names are given the letter SPICE expects
/// (a battery B1 becomes VB1, a lamp LP1 becomes RLP1, a switch S1 a resistor RS1).
enum SpiceExport {
    struct Files {
        var netlist: String
        var schematic: String
        var baseName: String
    }

    static func files(for circuit: Circuit, layout: SchematicLayout, title: String? = nil) -> Files {
        let name = safeBaseName(title ?? circuit.question ?? "circuit")
        return Files(netlist: netlist(circuit, title: title), schematic: schematic(circuit, layout: layout, title: title), baseName: name)
    }

    // MARK: - Names and values

    /// The SPICE element letter for each kind.
    static func spiceLetter(_ kind: ComponentKind) -> String {
        switch kind {
        case .resistor, .lamp, .switchOpen, .switchClosed: return "R"
        case .capacitor: return "C"
        case .inductor: return "L"
        case .voltageSource, .battery: return "V"
        case .currentSource: return "I"
        }
    }

    /// "R1" stays "R1"; "B1" (battery) becomes "VB1"; "LP1" (lamp) becomes "RLP1".
    static func spiceName(_ component: Component) -> String {
        let letter = spiceLetter(component.kind)
        let id = component.id.replacingOccurrences(of: " ", with: "_")
        return id.uppercased().hasPrefix(letter) && !(component.kind == .lamp && id.uppercased().hasPrefix("L")) ? id : letter + id
    }

    /// SPICE node: the reference is always "0".
    static func spiceNode(_ node: String, circuit: Circuit) -> String {
        node == circuit.groundNode ? "0" : node.replacingOccurrences(of: " ", with: "_")
    }

    /// "4.7k", "100u", "1Meg", "12": SPICE's suffixes, no unit.
    static func spiceValue(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value == 0 { return "0" }
        let magnitude = abs(value)
        let suffixes: [(Double, String)] = [(1e9, "G"), (1e6, "Meg"), (1e3, "k"), (1, ""), (1e-3, "m"), (1e-6, "u"), (1e-9, "n"), (1e-12, "p")]
        var chosen: (Double, String) = (1, "")
        for (scale, suffix) in suffixes where magnitude >= scale * 0.99999 {
            chosen = (scale, suffix)
            break
        }
        if magnitude < 1e-12 { chosen = (1e-12, "p") }
        let mantissa = value / chosen.0
        var text = String(format: "%.6g", mantissa)
        if text.contains("e") { text = String(format: "%.6f", mantissa) }
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text + chosen.1
    }

    /// The value a SPICE element line carries for each kind.
    static func spiceElementValue(_ component: Component) -> String {
        switch component.kind {
        case .switchClosed: return spiceValue(TransientSimulator.closedSwitchResistance)
        case .switchOpen: return spiceValue(TransientSimulator.openSwitchResistance)
        case .voltageSource, .battery: return "DC " + spiceValue(component.value)
        case .currentSource: return "DC " + spiceValue(component.value)
        default: return spiceValue(component.value)
        }
    }

    static func safeBaseName(_ text: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var out = ""
        var lastWasDash = false
        for ch in text.prefix(40) {
            if allowed.contains(ch) { out.append(ch); lastWasDash = false } else if !lastWasDash { out.append("-"); lastWasDash = true }
        }
        while out.hasSuffix("-") { out.removeLast() }
        while out.hasPrefix("-") { out.removeFirst() }
        return out.isEmpty ? "circuit" : out
    }

    // MARK: - Netlist

    static func netlist(_ circuit: Circuit, title: String? = nil) -> String {
        var lines: [String] = []
        lines.append("* \(title ?? circuit.question ?? "Circuit") - exported from PhotoMesh")
        lines.append("* Nodes: " + circuit.nodes.map { "\($0)" + ($0 == circuit.groundNode ? " (ground = 0)" : "") }.joined(separator: ", "))
        var renamed: [String] = []
        for c in circuit.components {
            let name = spiceName(c)
            if name != c.id { renamed.append("\(c.id) -> \(name)") }
            var comment = ""
            switch c.kind {
            case .lamp: comment = "   ; lamp \(c.id), as a resistor"
            case .battery: comment = "   ; battery \(c.id)"
            case .switchClosed: comment = "   ; closed switch \(c.id)"
            case .switchOpen: comment = "   ; open switch \(c.id)"
            default: break
            }
            lines.append("\(name) \(spiceNode(c.nodeA, circuit: circuit)) \(spiceNode(c.nodeB, circuit: circuit)) \(spiceElementValue(c))\(comment)")
        }
        if !renamed.isEmpty { lines.insert("* Renamed for SPICE: " + renamed.joined(separator: ", "), at: 2) }
        lines.append(analysisDirective(circuit))
        lines.append(".end")
        return lines.joined(separator: "\n") + "\n"
    }

    /// `.op` for a resistive circuit; a transient run over five time constants when something stores energy.
    static func analysisDirective(_ circuit: Circuit) -> String {
        let hasStorage = circuit.components.contains { ($0.kind == .capacitor || $0.kind == .inductor) && $0.value > 0 }
        guard hasStorage else { return ".op" }
        let window = TransientSimulator.suggestedDuration(circuit)
        return ".tran 0 \(spiceValue(window)) 0 \(spiceValue(window / 1000)) uic"
    }

    // MARK: - LTspice schematic

    /// Pin offsets of the LTspice library symbols at rotation R0 (pin 1 first).
    private static func pins(for kind: ComponentKind) -> (symbol: String, p1: (Int, Int), p2: (Int, Int)) {
        switch kind {
        case .resistor, .lamp, .switchOpen, .switchClosed: return ("res", (16, 16), (16, 96))
        case .capacitor: return ("cap", (16, 0), (16, 64))
        case .inductor: return ("ind", (16, 16), (16, 96))
        case .voltageSource, .battery: return ("voltage", (0, 0), (0, 96))
        case .currentSource: return ("current", (0, 0), (0, 96))
        }
    }

    /// LTspice rotations: R90 turns the symbol a quarter turn clockwise on screen (y down).
    private static func rotate(_ p: (Int, Int), _ rotation: String) -> (Int, Int) {
        switch rotation {
        case "R90": return (-p.1, p.0)
        case "R180": return (-p.0, -p.1)
        case "R270": return (p.1, -p.0)
        default: return p
        }
    }

    static func schematic(_ circuit: Circuit, layout: SchematicLayout, title: String? = nil) -> String {
        // Layout units → LTspice pixels on a 16 px grid: the 1000-unit canvas becomes 40 cells.
        let scale = 640.0 / max(layout.bounds.height, 1)
        let originX = layout.bounds.minX, originY = layout.bounds.minY
        func grid(_ p: SPoint) -> (Int, Int) {
            let x = ((p.x - originX) * scale / 16).rounded() * 16 + 96
            let y = ((p.y - originY) * scale / 16).rounded() * 16 + 96
            return (Int(x), Int(y))
        }

        var out: [String] = ["Version 4", "SHEET 1 \(Int(layout.bounds.width * scale) + 400) \(Int(layout.bounds.height * scale) + 400)"]
        var wires: [(Int, Int, Int, Int)] = []
        func wire(_ a: (Int, Int), _ b: (Int, Int)) {
            guard a != b else { return }
            wires.append((a.0, a.1, b.0, b.1))
        }
        for w in layout.wires { wire(grid(w.from), grid(w.to)) }

        var symbols: [String] = []
        var flags: [String] = []
        var labelled: Set<String> = []
        var pinPoints: [(Int, Int)] = []
        for symbol in layout.symbols {
            guard let component = circuit.component(symbol.id) else { continue }
            let spec = pins(for: component.kind)
            var t1 = grid(symbol.a), t2 = grid(symbol.b)
            // Polarised parts keep their first terminal on pin 1; others put pin 1 at the top/left.
            var swapped = false
            if !component.kind.hasPolarity, component.kind != .currentSource {
                let vertical = abs(t2.1 - t1.1) >= abs(t2.0 - t1.0)
                if (vertical && t1.1 > t2.1) || (!vertical && t1.0 > t2.0) { swap(&t1, &t2); swapped = true }
            }
            let vertical = abs(t2.1 - t1.1) >= abs(t2.0 - t1.0)
            let rotation: String
            if vertical { rotation = t1.1 <= t2.1 ? "R0" : "R180" } else { rotation = t1.0 <= t2.0 ? "R270" : "R90" }
            let r1 = rotate(spec.p1, rotation), r2 = rotate(spec.p2, rotation)
            let mid = ((t1.0 + t2.0) / 2, (t1.1 + t2.1) / 2)
            let pinMid = ((r1.0 + r2.0) / 2, (r1.1 + r2.1) / 2)
            // The origin sits on LTspice's 16 px grid so the pins do too; the symbol may then be
            // off-centre by a few pixels, which the lead wires absorb.
            func snap(_ v: Int) -> Int { Int((Double(v) / 16).rounded()) * 16 }
            let origin = (snap(mid.0 - pinMid.0), snap(mid.1 - pinMid.1))
            let pin1 = (origin.0 + r1.0, origin.1 + r1.1), pin2 = (origin.0 + r2.0, origin.1 + r2.1)
            wire(t1, pin1)
            wire(pin2, t2)
            pinPoints.append(pin1)
            pinPoints.append(pin2)
            symbols.append("SYMBOL \(spec.symbol) \(origin.0) \(origin.1) \(rotation)")
            symbols.append("SYMATTR InstName \(spiceName(component))")
            let value: String
            switch component.kind {
            case .switchClosed, .switchOpen: value = spiceValue(component.kind == .switchClosed ? TransientSimulator.closedSwitchResistance : TransientSimulator.openSwitchResistance)
            default: value = spiceValue(component.value)
            }
            symbols.append("SYMATTR Value \(value)")
            if component.kind == .lamp || component.kind.isSwitch || component.kind == .battery {
                symbols.append("SYMATTR SpiceLine ; \(component.kind.displayName.lowercased()) \(component.id)")
            }
            // Net names once per node, on a terminal point.
            let nodeA = swapped ? component.nodeB : component.nodeA
            let nodeB = swapped ? component.nodeA : component.nodeB
            for (node, point) in [(nodeA, t1), (nodeB, t2)] where !labelled.contains(node) {
                labelled.insert(node)
                flags.append("FLAG \(point.0) \(point.1) \(spiceNode(node, circuit: circuit))")
            }
        }
        // A lead or a flag that lands on the middle of a rail must split the rail there, or the
        // two are not connected: LTspice joins wires only where an endpoint meets another.
        var touchPoints = Set<[Int]>()
        for (x1, y1, x2, y2) in wires { touchPoints.insert([x1, y1]); touchPoints.insert([x2, y2]) }
        for pin in pinPoints { touchPoints.insert([pin.0, pin.1]) }
        var split: [(Int, Int, Int, Int)] = []
        for (x1, y1, x2, y2) in wires {
            var cuts: [(Int, Int)] = []
            for point in touchPoints {
                let (px, py) = (point[0], point[1])
                if (px, py) == (x1, y1) || (px, py) == (x2, y2) { continue }
                if y1 == y2, py == y1, px > min(x1, x2), px < max(x1, x2) { cuts.append((px, py)) }
                if x1 == x2, px == x1, py > min(y1, y2), py < max(y1, y2) { cuts.append((px, py)) }
            }
            let ordered = ([(x1, y1)] + cuts.sorted { a, b in a.0 != b.0 ? (a.0 < b.0) == (x2 > x1) : (a.1 < b.1) == (y2 > y1) } + [(x2, y2)])
            for (a, b) in zip(ordered, ordered.dropFirst()) where a != b { split.append((a.0, a.1, b.0, b.1)) }
        }
        for (x1, y1, x2, y2) in split { out.append("WIRE \(x1) \(y1) \(x2) \(y2)") }
        out.append(contentsOf: flags)
        out.append(contentsOf: symbols)
        let textY = Int(layout.bounds.height * scale) + 176
        out.append("TEXT 96 \(textY) Left 2 !\(analysisDirective(circuit))")
        out.append("TEXT 96 \(textY + 32) Left 2 ;\(title ?? circuit.question ?? "Circuit") - exported from PhotoMesh")
        return out.joined(separator: "\n") + "\n"
    }
}
