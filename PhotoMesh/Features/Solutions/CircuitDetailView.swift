import SwiftUI

/// Everything the engine knows about the recognized circuit: netlist, node voltages, element results.
struct CircuitDetailView: View {
    let analysis: CircuitAnalysis

    private var formatter: QuantityFormatter { FormattingPreferences.formatter() }
    private var primary: MethodSolution? { analysis.methods.first }

    var body: some View {
        List {
            Section {
                Text(analysis.question)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(PMTheme.ink)
            } header: {
                Text("QUESTION")
            }

            if let circuit = analysis.circuit {
                Section {
                    ForEach(circuit.components) { component in
                        HStack(spacing: 12) {
                            Text(component.id)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .frame(width: 40, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(component.kind.displayName)
                                    .font(.system(size: 13))
                                    .foregroundStyle(PMTheme.secondaryText)
                                Text(terminals(component))
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundStyle(PMTheme.secondaryText)
                            }
                            Spacer()
                            Text(formatter.format(component.value, component.kind.unitSymbol))
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(PMTheme.ink)
                    }
                } header: {
                    Text("COMPONENTS")
                } footer: {
                    Text("Reference node: \(circuit.groundNode). Nodes: \(circuit.nodes.joined(separator: ", ")).")
                }
            }

            if let primary, !primary.nodeVoltages.isEmpty, let circuit = analysis.circuit {
                Section {
                    ForEach(circuit.nodes, id: \.self) { node in
                        HStack {
                            Text(node == circuit.groundNode ? "\(node) (reference)" : node)
                                .font(.system(size: 16, design: .rounded))
                            Spacer()
                            Text(formatter.format(primary.nodeVoltages[node] ?? 0, "V"))
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(PMTheme.ink)
                    }
                } header: {
                    Text("NODE VOLTAGES")
                }
            }

            if let primary, !primary.elements.isEmpty {
                Section {
                    ForEach(primary.elements) { element in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(element.id)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                            HStack(spacing: 16) {
                                metric("I", formatter.format(element.current, "A"))
                                metric("V", formatter.format(element.voltage, "V"))
                                metric("P", formatter.format(abs(element.power), "W") + (element.kind == .resistor ? "" : (element.power < 0 ? " out" : " in")))
                            }
                        }
                        .foregroundStyle(PMTheme.ink)
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("ELEMENT RESULTS")
                } footer: {
                    Text("Current is positive from the first listed terminal to the second. For sources, \"out\" means the source delivers power.")
                }
            }

            Section {
                HStack(spacing: 8) {
                    Image(systemName: analysis.methodsAgree ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(analysis.methodsAgree ? PMTheme.accent : PMTheme.whyOrange)
                    Text(analysis.methodsAgree
                         ? "Solved with \(analysis.methods.map { $0.method.title.lowercased() }.joined(separator: " and ")); results match."
                         : "The methods returned different results. The recognized circuit is probably inconsistent.")
                        .font(.system(size: 14))
                        .foregroundStyle(PMTheme.ink)
                }
                if let notes = analysis.recognitionNotes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 14))
                        .foregroundStyle(PMTheme.secondaryText)
                }
            } header: {
                Text("CHECKS")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Circuit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func terminals(_ component: Component) -> String {
        switch component.kind {
        case .resistor: return "\(component.nodeA) — \(component.nodeB)"
        case .voltageSource: return "+ \(component.nodeA), − \(component.nodeB)"
        case .currentSource: return "\(component.nodeA) → \(component.nodeB)"
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(PMTheme.secondaryText)
            Text(value)
                .font(.system(size: 14, design: .rounded))
        }
    }
}

#Preview {
    NavigationStack {
        if let analysis = try? CircuitAnalyzer.analyze(SampleCircuitSolver.sample) {
            CircuitDetailView(analysis: analysis)
        }
    }
}
