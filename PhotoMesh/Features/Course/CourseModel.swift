import Foundation
import Observation

// MARK: - Course structure

/// A chapter of the course, in the order a first circuits course teaches it.
struct CourseModule: Identifiable, Hashable {
    let id: String
    let number: Int
    let title: String
    let subtitle: String
    /// Free for everyone; the other modules need Plus (their first lesson stays open as a preview).
    let isFree: Bool
    let lessons: [Lesson]

    static func == (lhs: CourseModule, rhs: CourseModule) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct Lesson: Identifiable, Hashable {
    let id: String
    let title: String
    /// Rough reading time.
    let minutes: Int
    let scenes: [LessonScene]
    let quiz: [QuizQuestion]

    static func == (lhs: Lesson, rhs: Lesson) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// One page of a lesson: an illustration that moves, a short explanation, and optionally the
/// formula it comes down to.
struct LessonScene: Identifiable {
    let id = UUID()
    var title: String
    var body: String
    var illustration: Illustration = .none
    /// LaTeX shown under the text.
    var formula: String? = nil
    /// Plain-text reading of the formula for accessibility and fallback.
    var formulaText: String? = nil
    /// Water-to-electricity pairs shown as a small two-column map under the text.
    var analogy: [AnalogyPair] = []
    /// One sentence to take away, shown in its own box at the end of the scene.
    var remember: String? = nil
}

/// One row of the water-in-pipes map: the water picture on the left, the electrical word on the right.
struct AnalogyPair: Hashable {
    var water: String
    var electric: String
}

/// What moves on a scene.
enum Illustration {
    case none
    /// A small circuit solved by the app's own engine, lit up keyframe by keyframe.
    case circuit(CircuitDemoSpec)
    /// The engine's solving steps for a circuit, played one after the other.
    case steps(CircuitDemoSpec, method: AnalysisMethod)
    /// The circuit played in time by the transient simulator, with a plot.
    case transient(CircuitDemoSpec, traces: [TransientTrace], switchAt: Double? = nil)
    /// A drawn explanation that is not a circuit solve.
    case concept(ConceptAnimation)
}

struct TransientTrace: Hashable {
    enum Kind: Hashable { case nodeVoltage, elementCurrent, elementVoltage }
    var kind: Kind
    var id: String
    var label: String
}

/// A circuit for the course: the payload the recognizer would produce, plus what to light up.
struct CircuitDemoSpec: Identifiable {
    let id: String
    let json: String
    var keyframes: [DemoKeyframe] = []
    /// Seconds one loop of the keyframes lasts (each keyframe gets an equal share unless set).
    var loopSeconds: Double = 8

    var circuit: Circuit? {
        do {
            var payload = try CircuitPayload.parse(json)
            payload.aspectRatio = 1.5
            return try payload.toCircuit()
        } catch {
            return nil
        }
    }
}

/// One moment of a circuit demonstration.
struct DemoKeyframe {
    enum Highlight {
        /// Nothing special: the whole circuit.
        case all
        /// These elements (and their nodes).
        case elements([String])
        /// These nodes with their voltages shown.
        case nodes([String])
        /// Every current moving, voltages shown.
        case flow
        /// Every current moving with the passive-sign polarities marked.
        case flowWithPolarity
        /// One mesh with its circulating arrow (index into the mesh method's loops).
        case mesh(Int)
        /// All meshes with arrows.
        case meshes
        /// Dashed boundary around these nodes (a supernode) tied by these elements.
        case supernode(nodes: [String], elements: [String])
    }

    var caption: String
    var highlight: Highlight
    var seconds: Double? = nil
}

/// A drawn, non-circuit animation (see ConceptAnimations.swift).
enum ConceptAnimation: String {
    // Water in pipes (see WaterAnimations.swift)
    case waterLoop
    case waterPressure
    case waterFlowRate
    case waterNarrowPipe
    case waterPump
    case waterValve
    case waterOhm
    case waterJunction
    case waterSeries
    case waterParallel
    case waterTank
    case waterWheel
    // Drawn electrical concepts (see ConceptAnimations.swift)
    case chargeFlow
    case potentialHill
    case powerBalance
    case ohmLine
    case kclJunction
    case kvlStaircase
    case seriesBulbs
    case parallelBulbs
    case voltageDivider
    case capacitorCharging
    case capacitorDischarging
    case inductorRise
    case rlcRinging
    case timeConstant
    case superposition
    case theveninBox
    case maxPower
    case sineWave
    case phasor
    case impedanceTriangle
    case wyeDelta
}

struct QuizQuestion: Identifiable, Hashable {
    let id = UUID()
    var prompt: String
    var options: [String]
    /// Index into `options`.
    var answer: Int
    var explanation: String
}

// MARK: - Progress

/// Which lessons are done and how the quizzes went; kept on the device.
@MainActor
@Observable
final class CourseProgress {
    static let shared = CourseProgress()

    private struct Stored: Codable {
        var completed: Set<String> = []
        var bestScores: [String: Int] = [:]
        var quizTotals: [String: Int] = [:]
        var lastLessonId: String?
    }

    private var stored: Stored
    private let key = "course.progress"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key), let decoded = try? JSONDecoder().decode(Stored.self, from: data) {
            stored = decoded
        } else {
            stored = Stored()
        }
    }

    var completedCount: Int { stored.completed.count }
    var lastLessonId: String? { stored.lastLessonId }

    func isCompleted(_ lesson: Lesson) -> Bool { stored.completed.contains(lesson.id) }

    func bestScore(_ lesson: Lesson) -> (score: Int, total: Int)? {
        guard let score = stored.bestScores[lesson.id], let total = stored.quizTotals[lesson.id] else { return nil }
        return (score, total)
    }

    func completed(in module: CourseModule) -> Int {
        module.lessons.filter { stored.completed.contains($0.id) }.count
    }

    func markOpened(_ lesson: Lesson) {
        stored.lastLessonId = lesson.id
        save()
    }

    func recordQuiz(_ lesson: Lesson, score: Int, total: Int) {
        stored.completed.insert(lesson.id)
        stored.quizTotals[lesson.id] = total
        stored.bestScores[lesson.id] = max(stored.bestScores[lesson.id] ?? 0, score)
        save()
        Analytics.shared.track("lesson_completed", ["lesson": .string(lesson.id), "score": .init(score), "total": .init(total)])
    }

    func reset() {
        stored = Stored()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(stored) { UserDefaults.standard.set(data, forKey: key) }
    }
}

// MARK: - Access

extension Course {
    /// Whether this lesson can be opened right now: free module, first lesson of any module, or Plus.
    @MainActor
    static func isUnlocked(_ lesson: Lesson, in module: CourseModule) -> Bool {
        if module.isFree { return true }
        if module.lessons.first?.id == lesson.id { return true }
        return PlusAccess.allows(.course)
    }

    static func module(containing lesson: Lesson) -> CourseModule? {
        modules.first { $0.lessons.contains(where: { $0.id == lesson.id }) }
    }

    static func lesson(withId id: String) -> Lesson? {
        for module in modules { if let lesson = module.lessons.first(where: { $0.id == id }) { return lesson } }
        return nil
    }

    /// The lesson after this one, across modules.
    static func next(after lesson: Lesson) -> Lesson? {
        let all = modules.flatMap(\.lessons)
        guard let index = all.firstIndex(where: { $0.id == lesson.id }), index + 1 < all.count else { return nil }
        return all[index + 1]
    }
}
