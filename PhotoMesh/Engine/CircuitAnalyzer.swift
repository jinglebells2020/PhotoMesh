import Foundation

enum CircuitAnalyzerError: LocalizedError {
    case allMethodsFailed(String)

    var errorDescription: String? {
        switch self {
        case .allMethodsFailed(let reason): return reason
        }
    }
}

/// Runs every applicable method on a recognized circuit and cross-checks the results.
enum CircuitAnalyzer {
    static func analyze(_ raw: Circuit, formatter: QuantityFormatter = QuantityFormatter(), recognitionNotes: String? = nil) throws -> CircuitAnalysis {
        let original = try raw.validated()
        let (solvedRaw, presented, alias, replacements) = original.dcEquivalent()
        let solved: Circuit
        do {
            solved = try solvedRaw.validated()
        } catch {
            guard !replacements.isEmpty else { throw error }
            let opens = replacements.filter { $0.change == .open }.map(\.id)
            if !opens.isEmpty, let validation = error as? CircuitValidationError,
               validation == .disconnected || { if case .danglingElement = validation { return true }; return false }() {
                throw CircuitAnalyzerError.allMethodsFailed("At DC steady state \(opens.joined(separator: ", ")) \(opens.count == 1 ? "is an open circuit" : "are open circuits"), which leaves part of the circuit without a closed path: no steady current flows there. Move or remove \(opens.count == 1 ? "it" : "them") to analyze the rest.")
            }
            throw CircuitAnalyzerError.allMethodsFailed("After replacing \(replacements.map(\.id).joined(separator: ", ")) by their DC behaviour: \(error.localizedDescription)")
        }
        var methods: [MethodSolution] = []
        var failures: [String] = []
        // The drawing comes first so the mesh method can run its currents clockwise on it.
        let layout = SchematicLayoutEngine.layout(for: presented)
        let displayed = replacements.isEmpty ? nil : original   // the drawing as the user sees it

        // The simplest method first, when the network allows it.
        if let reduced = try? ReductionAnalysis.solve(solved, formatter: formatter, presented: displayed) {
            methods.append(reduced)
        }
        do {
            methods.append(try NodalAnalysis.solve(solved, formatter: formatter, presented: displayed))
        } catch {
            failures.append("Nodal analysis: \(error.localizedDescription)")
        }
        do {
            methods.append(try MeshAnalysis.solve(solved, formatter: formatter, layout: replacements.isEmpty ? layout : SchematicLayoutEngine.layout(for: solved), presented: displayed))
        } catch {
            failures.append("Mesh analysis: \(error.localizedDescription)")
        }

        guard !methods.isEmpty else {
            throw CircuitAnalyzerError.allMethodsFailed(failures.joined(separator: "\n"))
        }

        if !replacements.isEmpty {
            let context = AnalysisContext(circuit: solved, formatter: formatter, presented: original)
            let dcStep = SharedSteps.dcEquivalentStep(context: context, replacements: replacements)
            methods = methods.map { method in
                var expanded = SharedSteps.expand(method, original: original, presented: presented, alias: alias, formatter: formatter)
                expanded.steps.insert(dcStep, at: min(1, expanded.steps.count))
                return expanded
            }
        }

        return CircuitAnalysis(
            circuit: presented,
            drawn: original,
            question: presented.question ?? defaultQuestion(for: presented),
            methods: methods,
            methodsAgree: agree(methods),
            recognitionNotes: recognitionNotes,
            layout: layout
        )
    }

    /// True when the failure is the DC redraw leaving no closed path (a series capacitor, an
    /// open switch): the circuit still has a perfectly good time response to look at.
    static func isTransientOnlyFailure(_ error: Error) -> Bool {
        (error.localizedDescription).contains("At DC steady state")
    }

    /// An analysis with no method results, enough for the lab to draw and simulate a circuit
    /// whose steady state cannot be solved.
    static func labOnly(_ raw: Circuit) -> CircuitAnalysis? {
        guard let circuit = try? raw.validated() else { return nil }
        return CircuitAnalysis(
            circuit: circuit,
            drawn: circuit,
            question: circuit.question ?? "Watch the circuit in time",
            methods: [],
            methodsAgree: true,
            recognitionNotes: nil,
            layout: SchematicLayoutEngine.layout(for: circuit)
        )
    }

    static func agree(_ methods: [MethodSolution]) -> Bool {
        guard let first = methods.first else { return false }
        for other in methods.dropFirst() {
            for (a, b) in zip(first.elements, other.elements) {
                let scale = max(abs(a.current), abs(b.current), 1e-9)
                if abs(a.current - b.current) / scale > 1e-6 { return false }
            }
        }
        return true
    }

    private static func defaultQuestion(for circuit: Circuit) -> String {
        "Find the current through every element"
    }
}
