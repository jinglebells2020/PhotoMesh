import UIKit

/// What a request turns into before solving: a circuit to (optionally) confirm, or a typed expression.
/// `model` names what produced the circuit ("sample", "user", or a model id) for samples and events.
enum SolveInput {
    case circuit(Circuit, notes: String?, needsReview: Bool, model: String)
    case expression(String)
}

/// Anything that can turn a capture, a drawing or a typed problem into a `SolveInput`.
protocol CircuitSolverService {
    func prepare(_ request: SolutionRequest, progress: @escaping (String) -> Void) async throws -> SolveInput
}

enum SolveRunner {
    /// Deterministic part of the pipeline, shared by every solver.
    static func analyze(_ input: SolveInput) throws -> CircuitAnalysis {
        switch input {
        case .circuit(let circuit, let notes, _, _):
            return try CircuitAnalyzer.analyze(circuit, formatter: FormattingPreferences.formatter(), recognitionNotes: notes)
        case .expression(let text):
            return try ExpressionSolver.solve(text)
        }
    }
}

enum SolverProvider {
    /// Picks the solver for the current settings: sample mode, or the VLM when a key is configured.
    static func make() -> any CircuitSolverService {
        if APIConfiguration.useSampleCircuit { return SampleCircuitSolver() }
        if let key = APIConfiguration.apiKey, !key.isEmpty {
            let primary = OpenRouterClient.Configuration(apiKey: key, model: APIConfiguration.model, fastReasoning: APIConfiguration.fastRecognition)
            let fallback = APIConfiguration.fallbackModel.map { OpenRouterClient.Configuration(apiKey: key, model: $0, fastReasoning: false) }
            return VLMCircuitSolver(primary: primary, fallback: fallback, metered: APIConfiguration.usesBuiltInKey)
        }
        let reason = DeveloperOptions.enabled
            ? "No API key is set, so this is the built-in sample circuit. Add your OpenRouter key in Settings → Recognition to analyze your own photos."
            : "This build has no recognition key, so this is the built-in sample circuit. Drawn circuits still solve normally."
        return SampleCircuitSolver(reason: reason)
    }
}

// MARK: - Live solver with escalation

/// Cheap model first; a stronger one only when the first answer does not hold up.
struct VLMCircuitSolver: CircuitSolverService {
    let primary: OpenRouterClient.Configuration
    let fallback: OpenRouterClient.Configuration?
    /// Shared tester key: every scan counts against the monthly cap in `UsageAllowance`
    /// (a second-pass read is part of the same scan and is not counted again).
    var metered = false

    func prepare(_ request: SolutionRequest, progress: @escaping (String) -> Void) async throws -> SolveInput {
        switch request.source {
        case .image(let image):
            return try await recognizeWithEscalation(image, progress: progress)
        case .expression(let text):
            return .expression(text)
        case .circuit(let circuit):
            return .circuit(circuit, notes: circuit.notes, needsReview: false, model: "user")
        }
    }

    private func recognizeWithEscalation(_ image: UIImage, progress: @escaping (String) -> Void) async throws -> SolveInput {
        if metered {
            // The monthly soft cap is checked before anything is spent; the error says when it resets.
            do {
                try UsageAllowance.shared.consume(plus: PlusAccessCached.hasPlus)
            } catch {
                Analytics.shared.track("recognition_limited", ["reason": .string(error.localizedDescription), "plus": .bool(PlusAccessCached.hasPlus)])
                throw error
            }
        }
        progress("Reading the circuit…")
        let started = Date()
        var firstResult: CircuitRecognizer.Result?
        var firstProblem: String?
        var firstError: Error?

        do {
            let result = try await CircuitRecognizer(client: OpenRouterClient(configuration: primary)).recognize(image)
            firstResult = result
            firstProblem = VLMCircuitSolver.problem(with: result)
            track(result, tier: "primary", problem: firstProblem)
        } catch {
            firstError = error
            firstProblem = error.localizedDescription
            trackFailure(model: primary.model, tier: "primary", error: error, since: started)
        }

        if firstProblem == nil, let result = firstResult {
            return input(from: result)
        }

        guard let fallback else {
            if let result = firstResult { return input(from: result) }
            throw firstError ?? CircuitPayload.PayloadError.noCircuit
        }
        progress("Taking a closer look…")
        RecognitionLog.shared.record("escalating to \(fallback.model): \(firstProblem ?? "?")")
        do {
            let result = try await CircuitRecognizer(client: OpenRouterClient(configuration: fallback)).recognize(image)
            track(result, tier: "fallback", problem: VLMCircuitSolver.problem(with: result))
            return input(from: result)
        } catch {
            trackFailure(model: fallback.model, tier: "fallback", error: error, since: started)
            if let result = firstResult { return input(from: result) }
            throw error
        }
    }

    /// Nil when the circuit validates and both methods agree; otherwise why the read is doubtful.
    static func problem(with result: CircuitRecognizer.Result) -> String? {
        if let confidence = result.confidence, confidence < 0.6 { return "low confidence \(confidence)" }
        do {
            let analysis = try CircuitAnalyzer.analyze(result.circuit, formatter: FormattingPreferences.formatter())
            return analysis.methodsAgree ? nil : "methods disagree"
        } catch {
            return error.localizedDescription
        }
    }

    private func input(from result: CircuitRecognizer.Result) -> SolveInput {
        var notes = result.notes
        if let confidence = result.confidence, confidence < 0.7 {
            notes = ["The reader was not fully confident (\(Int(confidence * 100))%). Double-check the values below.", notes].compactMap { $0 }.joined(separator: " ")
        }
        return .circuit(result.circuit, notes: notes, needsReview: APIConfiguration.confirmRecognizedCircuits, model: result.completion.model)
    }

    private func track(_ result: CircuitRecognizer.Result, tier: String, problem: String?) {
        let c = result.completion
        Analytics.shared.track("recognition", [
            "model": .string(c.model), "tier": .string(tier),
            "ms": .init(Int(c.latency * 1000)),
            "prompt_tokens": .init(c.promptTokens ?? -1), "completion_tokens": .init(c.completionTokens ?? -1), "reasoning_tokens": .init(c.reasoningTokens ?? -1),
            "outcome": .string(problem == nil ? "ok" : "doubtful"), "problem": .string(problem ?? ""),
            "components": .init(result.circuit.components.count), "confidence": .init(result.confidence ?? -1),
        ])
    }

    private func trackFailure(model: String, tier: String, error: Error, since started: Date) {
        Analytics.shared.track("recognition", [
            "model": .string(model), "tier": .string(tier),
            "ms": .init(Int(Date().timeIntervalSince(started) * 1000)),
            "outcome": .string("failed"), "problem": .string(String(describing: type(of: error)) + ": " + error.localizedDescription.prefix(120)),
        ])
    }
}

// MARK: - Offline sample

/// Runs the real engine on a built-in circuit so the whole flow works without a key or a camera.
struct SampleCircuitSolver: CircuitSolverService {
    var reason: String? = nil

    static let sample = Circuit(
        components: [
            Component(id: "V1", kind: .voltageSource, value: 10, nodeA: "a", nodeB: "0"),
            Component(id: "R1", kind: .resistor, value: 2, nodeA: "a", nodeB: "b"),
            Component(id: "R2", kind: .resistor, value: 4, nodeA: "b", nodeB: "0"),
            Component(id: "R3", kind: .resistor, value: 3, nodeA: "b", nodeB: "c"),
            Component(id: "V2", kind: .voltageSource, value: 5, nodeA: "c", nodeB: "0"),
        ],
        groundNode: "0",
        meshes: [["V1", "R1", "R2"], ["R2", "R3", "V2"]],
        unknowns: [Unknown(kind: .current, element: "R2")],
        question: "Find the current through R2.",
        geometry: CircuitGeometry(
            placements: [
                "V1": .init(box: SRect(minX: 0.135, minY: 0.43, maxX: 0.20, maxY: 0.535), isHorizontal: false),
                "R1": .init(box: SRect(minX: 0.26, minY: 0.21, maxX: 0.43, maxY: 0.27), isHorizontal: true),
                "R2": .init(box: SRect(minX: 0.47, minY: 0.34, maxX: 0.53, maxY: 0.62), isHorizontal: false),
                "R3": .init(box: SRect(minX: 0.57, minY: 0.21, maxX: 0.74, maxY: 0.27), isHorizontal: true),
                "V2": .init(box: SRect(minX: 0.80, minY: 0.43, maxX: 0.865, maxY: 0.535), isHorizontal: false),
            ],
            nodePoints: ["0": SPoint(x: 0.5, y: 0.725), "a": SPoint(x: 0.17, y: 0.24), "b": SPoint(x: 0.5, y: 0.24), "c": SPoint(x: 0.83, y: 0.24)],
            aspectRatio: 900.0 / 620.0
        )
    )

    func prepare(_ request: SolutionRequest, progress: @escaping (String) -> Void) async throws -> SolveInput {
        switch request.source {
        case .image:
            progress("Reading the circuit…")
            try await Task.sleep(for: .milliseconds(900))
            return .circuit(Self.sample, notes: reason ?? "Sample circuit (offline mode).", needsReview: APIConfiguration.confirmRecognizedCircuits, model: "sample")
        case .expression(let text):
            return .expression(text)
        case .circuit(let circuit):
            return .circuit(circuit, notes: circuit.notes, needsReview: false, model: "user")
        }
    }
}

// MARK: - Calculator path

enum ExpressionSolver {
    enum Failure: LocalizedError {
        case notEvaluable
        var errorDescription: String? { "This input can't be evaluated yet. Symbolic and circuit expressions are coming with the manual-entry update." }
    }

    static func solve(_ text: String) throws -> CircuitAnalysis {
        let sign = FormattingPreferences.decimalSign
        let evaluator = ExpressionEvaluator(decimalSign: sign)
        guard let value = try? evaluator.evaluate(text) else { throw Failure.notEvaluable }
        let formatted = ExpressionEvaluator.format(value, decimalSign: sign)
        let step = AnalysisStep(
            title: "Apply the order of operations",
            summary: text,
            equations: ["\(text) = \(formatted)"],
            explanation: "Parentheses first, then powers and roots, then multiplication and division, and finally addition and subtraction.",
            result: "= \(formatted)"
        )
        let method = MethodSolution(
            method: .arithmetic,
            headline: "= \(formatted)",
            steps: [step],
            nodeVoltages: [:],
            elements: [],
            answers: [Answer(label: "Result", value: formatted)]
        )
        return CircuitAnalysis(circuit: nil, question: "Evaluate \(text)", methods: [method], methodsAgree: true, recognitionNotes: nil)
    }
}
