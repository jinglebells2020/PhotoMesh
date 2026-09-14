import SwiftUI

/// Lets the user correct what the reader got wrong: parts, values, nodes, ground and the question.
struct CircuitEditorView: View {
    @State private var draft: Circuit
    let onSave: (Circuit) -> Void
    @Environment(\.dismiss) private var dismiss

    init(circuit: Circuit, onSave: @escaping (Circuit) -> Void) {
        _draft = State(initialValue: circuit)
        self.onSave = onSave
    }

    private var formatter: QuantityFormatter { FormattingPreferences.formatter() }
    private var nodeNames: [String] { draft.nodes }

    var body: some View {
        List {
            Section {
                ForEach($draft.components) { $component in
                    NavigationLink {
                        ComponentEditorView(component: $component, nodeNames: nodeNames) {
                            draft.components.removeAll { $0.id == component.id }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Text(component.id)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .frame(width: 44, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(component.kind.displayName)
                                    .font(.system(size: 13))
                                    .foregroundStyle(PMTheme.secondaryText)
                                Text(terminals(component))
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundStyle(PMTheme.secondaryText)
                            }
                            Spacer()
                            Text(component.kind.valueText(component.value, formatter: formatter))
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(PMTheme.ink)
                    }
                }
                .onDelete { offsets in draft.components.remove(atOffsets: offsets) }

                Button {
                    addComponent()
                } label: {
                    Label("Add a component", systemImage: "plus.circle.fill")
                        .foregroundStyle(PMTheme.accent)
                }
            } header: {
                Text("COMPONENTS")
            } footer: {
                Text("Nodes are the wires that join parts. Two parts that share a wire must use the same node name.")
            }

            Section {
                Picker("Reference (ground)", selection: $draft.groundNode) {
                    ForEach(nodeNames, id: \.self) { node in
                        Text(node).tag(node)
                    }
                }
                .foregroundStyle(PMTheme.ink)
            } header: {
                Text("REFERENCE NODE")
            }

            Section {
                TextField("What is asked?", text: Binding(get: { draft.question ?? "" }, set: { draft.question = $0.isEmpty ? nil : $0 }))
                    .foregroundStyle(PMTheme.ink)
                ForEach(draft.components) { component in
                    Toggle(isOn: askBinding(for: component.id)) {
                        Text("Find the current through \(component.id)")
                            .foregroundStyle(PMTheme.ink)
                    }
                    .tint(PMTheme.accent)
                }
            } header: {
                Text("QUESTION")
            } footer: {
                Text("With nothing selected, every resistor current is reported.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Edit circuit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Solve") {
                    onSave(draft)
                    dismiss()
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(PMTheme.accent)
                .disabled(draft.components.isEmpty)
            }
        }
    }

    private func terminals(_ component: Component) -> String {
        switch component.kind.dcRole {
        case .voltageSource: return "+ \(component.nodeA), − \(component.nodeB)"
        case .currentSource: return "\(component.nodeA) → \(component.nodeB)"
        case .resistor, .open, .short: return "\(component.nodeA) — \(component.nodeB)"
        }
    }

    private func askBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { draft.unknowns.contains { $0.kind == .current && $0.element == id } },
            set: { asked in
                draft.unknowns.removeAll { $0.kind == .current && $0.element == id }
                if asked { draft.unknowns.append(Unknown(kind: .current, element: id)) }
            }
        )
    }

    private func addComponent() {
        var index = draft.resistors.count + 1
        while draft.component("R\(index)") != nil { index += 1 }
        let nodes = nodeNames
        let a = nodes.first { $0 != draft.groundNode } ?? "n1"
        let b = draft.groundNode.isEmpty ? "0" : draft.groundNode
        draft.components.append(Component(id: "R\(index)", kind: .resistor, value: 1000, nodeA: a, nodeB: b))
    }
}

/// One component's kind, value and terminals.
struct ComponentEditorView: View {
    @Binding var component: Component
    let nodeNames: [String]
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var valueText = ""
    @State private var multiplier: Double = 1
    @State private var idText = ""

    private struct Prefix: Identifiable {
        let symbol: String
        let multiplier: Double
        var id: String { symbol }
    }

    private var prefixes: [Prefix] {
        switch component.kind {
        case .resistor, .lamp: return [Prefix(symbol: "Ω", multiplier: 1), Prefix(symbol: "kΩ", multiplier: 1e3), Prefix(symbol: "MΩ", multiplier: 1e6)]
        case .voltageSource, .battery: return [Prefix(symbol: "mV", multiplier: 1e-3), Prefix(symbol: "V", multiplier: 1), Prefix(symbol: "kV", multiplier: 1e3)]
        case .currentSource: return [Prefix(symbol: "µA", multiplier: 1e-6), Prefix(symbol: "mA", multiplier: 1e-3), Prefix(symbol: "A", multiplier: 1)]
        case .capacitor: return [Prefix(symbol: "pF", multiplier: 1e-12), Prefix(symbol: "nF", multiplier: 1e-9), Prefix(symbol: "µF", multiplier: 1e-6)]
        case .inductor: return [Prefix(symbol: "µH", multiplier: 1e-6), Prefix(symbol: "mH", multiplier: 1e-3), Prefix(symbol: "H", multiplier: 1)]
        case .switchOpen, .switchClosed: return [Prefix(symbol: "", multiplier: 1)]
        }
    }

    var body: some View {
        List {
            Section("PART") {
                HStack {
                    Text("Name").foregroundStyle(PMTheme.ink)
                    Spacer()
                    TextField("R1", text: $idText)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .onChange(of: idText) { _, new in
                            let trimmed = new.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty { component.id = trimmed }
                        }
                }
                Picker("Type", selection: $component.kind) {
                    ForEach(ComponentKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .foregroundStyle(PMTheme.ink)
                .onChange(of: component.kind) { _, _ in
                    multiplier = prefixes.first { $0.multiplier == 1 }?.multiplier ?? 1
                    applyValue()
                }
            }

            if component.kind.hasValue {
              Section("VALUE") {
                HStack(spacing: 12) {
                    TextField("Value", text: $valueText)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .onChange(of: valueText) { _, _ in applyValue() }
                    Picker("Unit", selection: $multiplier) {
                        ForEach(prefixes) { prefix in
                            Text(prefix.symbol).tag(prefix.multiplier)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                    .onChange(of: multiplier) { _, _ in applyValue() }
                }
              }
            }

            Section {
                NodeField(title: firstTerminalTitle, value: $component.nodeA, nodeNames: nodeNames)
                NodeField(title: secondTerminalTitle, value: $component.nodeB, nodeNames: nodeNames)
            } header: {
                Text("TERMINALS")
            } footer: {
                Text(terminalFooter)
            }

            Section {
                Button("Delete \(component.id)", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(component.id)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            idText = component.id
            let value = component.value
            let best = prefixes.min { abs(log10(max(value, 1e-12) / $0.multiplier)) < abs(log10(max(value, 1e-12) / $1.multiplier)) } ?? prefixes[0]
            multiplier = best.multiplier
            valueText = QuantityFormatter().number(value / best.multiplier)
        }
    }

    private var firstTerminalTitle: String {
        switch component.kind.dcRole {
        case .voltageSource: return "+ terminal node"
        case .currentSource: return "From node"
        case .resistor, .open, .short: return "Node A"
        }
    }

    private var secondTerminalTitle: String {
        switch component.kind.dcRole {
        case .voltageSource: return "− terminal node"
        case .currentSource: return "To node"
        case .resistor, .open, .short: return "Node B"
        }
    }

    private var terminalFooter: String {
        switch component.kind {
        case .currentSource: return "The arrow inside the source points toward the second terminal."
        case .voltageSource: return "The first terminal is the + side."
        case .battery: return "The first terminal is the + side (the long plate)."
        case .capacitor: return "At DC a capacitor is an open circuit: it carries no current and takes the voltage between its nodes."
        case .inductor: return "At DC an inductor is a short circuit: its two nodes are the same node."
        case .switchOpen: return "Open: no current flows. Change the type to close it."
        case .switchClosed: return "Closed: acts as a wire. Change the type to open it."
        case .resistor, .lamp: return "Order does not matter."
        }
    }

    private func applyValue() {
        let cleaned = valueText.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "−", with: "-")
        if let number = Double(cleaned), number > 0 { component.value = number * multiplier }
    }
}

/// Node name with quick picks for the nodes that already exist.
private struct NodeField: View {
    let title: String
    @Binding var value: String
    let nodeNames: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).foregroundStyle(PMTheme.ink)
                Spacer()
                TextField("node", text: $value)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(nodeNames, id: \.self) { node in
                        Button {
                            value = node
                        } label: {
                            Text(node)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(value == node ? PMTheme.accent : PMTheme.groupedBackground))
                                .foregroundStyle(value == node ? .white : PMTheme.ink)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        var index = nodeNames.count
                        while nodeNames.contains("n\(index)") { index += 1 }
                        value = "n\(index)"
                    } label: {
                        Text("+ new")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().stroke(PMTheme.chipBorder))
                            .foregroundStyle(PMTheme.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        CircuitEditorView(circuit: SampleCircuitSolver.sample) { _ in }
    }
}
