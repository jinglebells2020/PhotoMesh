import Foundation
import Observation
import SwiftUI

/// What Photocircuits Plus unlocks, in the order the paywall lists it, so the copy here is the
/// single source of truth for what a subscriber gets.
///
/// The rule behind the split: paywall the second time, not the first. Scanning, the recognized
/// schematic with tap to fix, the final answer and step one with its live highlight are always
/// free; a student who has never seen a node light up has nothing to buy. Everything from step
/// two on is Plus, after three complete free solutions (`SolveTrial`). The correction screen is
/// never behind the wall: every fix is training data.
enum PlusFeature: String, CaseIterable, Identifiable {
    case fullSteps
    case methods
    case explain
    case practice
    case history
    case lab
    case course
    case exports

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullSteps: return "Every step, not just the first"
        case .methods: return "Solve it their way: nodal, mesh or reduction"
        case .explain: return "Explain this step"
        case .practice: return "Practice: a similar problem, fresh steps"
        case .history: return "History beyond your last three"
        case .lab: return "Circuit lab: tweak and simulate"
        case .course: return "The full circuits course"
        case .exports: return "Export to LTspice and PDF"
        }
    }

    var detail: String {
        switch self {
        case .fullSteps:
            return "Step one is always free, with the schematic lighting up as you go. Plus opens steps two onward on every circuit: the whole walkthrough, written the way it is marked."
        case .methods:
            return "Professors specify the method. Switch between node voltages, mesh currents and series-parallel reduction on the same circuit and see each one written out in full."
        case .explain:
            return "Why this reference node, why this sign, why that equation: a plain-language reason behind every step, one tap away."
        case .practice:
            return "The same circuit shape with new values. Answer it yourself in exam mode, get checked, then read fresh steps. As many as you like."
        case .history:
            return "Every circuit you ever solved, ready to reopen. Free keeps your last three."
        case .lab:
            return "Drag any value and watch every current and voltage follow. Flip switches, then play the circuit in time: capacitors charging, coils resisting, curves you can scrub."
        case .course:
            return "The whole first-year circuits course as animated lessons with quizzes: it starts from water in pipes and builds up through Ohm's law to nodal and mesh analysis, Thévenin, RC and RL transients and phasors. The first two modules are free."
        case .exports:
            return "Save any solved circuit as an LTspice schematic and netlist, or share the complete step-by-step solution as a PDF."
        }
    }

    var systemImage: String {
        switch self {
        case .fullSteps: return "list.number"
        case .methods: return "arrow.triangle.branch"
        case .explain: return "questionmark.circle"
        case .practice: return "repeat"
        case .history: return "clock.arrow.circlepath"
        case .lab: return "slider.horizontal.below.square.and.square.filled"
        case .course: return "graduationcap"
        case .exports: return "square.and.arrow.up"
        }
    }

    /// One line for a locked spot in the app ("Unlock the circuit lab").
    var unlockPrompt: String {
        switch self {
        case .fullSteps: return "Unlock every step"
        case .methods: return "Unlock method switching"
        case .explain: return "Unlock explanations"
        case .practice: return "Unlock practice problems"
        case .history: return "Unlock your full history"
        case .lab: return "Unlock the circuit lab"
        case .course: return "Unlock the full course"
        case .exports: return "Unlock exports"
        }
    }
}

/// Three complete solutions on install. The trial fires at real need, when a student first taps
/// past step one, instead of burning down over seven days. A trial unlocks that circuit fully
/// (every step, every method, every explanation) and it stays unlocked when reopened later.
enum SolveTrial {
    static let total = 3
    private static let unlockedKey = "trial.unlocked"

    enum Outcome {
        case alreadyUnlocked
        case unlocked(ordinal: Int)
        case exhausted
    }

    static var unlockedKeys: [String] { UserDefaults.standard.stringArray(forKey: unlockedKey) ?? [] }
    static var used: Int { min(total, unlockedKeys.count) }
    static var remaining: Int { max(0, total - unlockedKeys.count) }

    /// Stable identity of a solved circuit: its parts and question, not its object identity.
    static func key(for analysis: CircuitAnalysis) -> String {
        guard let circuit = analysis.circuit else { return "expression|" + analysis.question }
        let parts = circuit.components.map { "\($0.id):\($0.kind.rawValue):\($0.value):\($0.nodeA):\($0.nodeB)" }.sorted()
        return parts.joined(separator: ";") + "#" + circuit.groundNode + "|" + analysis.question
    }

    static func isUnlocked(_ analysis: CircuitAnalysis) -> Bool {
        unlockedKeys.contains(key(for: analysis))
    }

    /// Spends one free complete solution on this circuit, if any is left.
    static func unlock(_ analysis: CircuitAnalysis) -> Outcome {
        let key = key(for: analysis)
        if unlockedKeys.contains(key) { return .alreadyUnlocked }
        guard remaining > 0 else { return .exhausted }
        UserDefaults.standard.set(unlockedKeys + [key], forKey: unlockedKey)
        Analytics.shared.track("trial_used", ["ordinal": .init(used), "remaining": .init(remaining)])
        return .unlocked(ordinal: used)
    }

    /// Developer options: start over.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: unlockedKey)
    }
}

/// Answers "may this user use that feature right now": the subscription, the trial for the
/// circuit at hand, plus a developer override so testers can walk the paid paths without buying.
@MainActor
enum PlusAccess {
    static let pretendKey = "developer.pretendPlus"

    /// Developer options: behave as a subscriber on this device.
    static var pretendPlus: Bool {
        get { DeveloperOptions.enabled && UserDefaults.standard.bool(forKey: pretendKey) }
        set { UserDefaults.standard.set(newValue, forKey: pretendKey) }
    }

    static var hasPlus: Bool { Subscriptions.shared.isPro || pretendPlus }

    /// Features that are not about one particular circuit.
    static func allows(_ feature: PlusFeature) -> Bool { hasPlus }

    /// Steps, methods and explanations are also open on a circuit the trial unlocked, and on
    /// calculator results, which have nothing past step one to sell.
    static func allows(_ feature: PlusFeature, for analysis: CircuitAnalysis) -> Bool {
        if hasPlus { return true }
        switch feature {
        case .fullSteps, .methods, .explain:
            return analysis.circuit == nil || SolveTrial.isUnlocked(analysis)
        case .practice, .history, .lab, .course, .exports:
            return false
        }
    }

    /// Records that a locked feature was tapped, so the paywall's usefulness can be judged.
    static func notedLockedTap(_ feature: PlusFeature) {
        Analytics.shared.track("plus_gate", ["feature": .string(feature.rawValue), "trial_left": .init(SolveTrial.remaining)])
    }
}

/// Non-isolated mirror for code running off the main actor (the solver pipeline).
enum PlusAccessCached {
    nonisolated static var hasPlus: Bool {
        Subscriptions.isProCached || (DeveloperOptions.enabled && UserDefaults.standard.bool(forKey: PlusAccess.pretendKey))
    }
}

// MARK: - Locked-feature card

/// The card shown in place of a Plus feature: what it does, one tap to the paywall.
struct PlusLockCard: View {
    let feature: PlusFeature
    var compact = false
    @State private var presentingPaywall = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(PMTheme.plusOrange)
                Text("Photocircuits Plus")
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(PMTheme.plusOrange)
            }
            Text(feature.title)
                .font(.system(size: compact ? 16 : 19, weight: .bold))
                .foregroundStyle(PMTheme.ink)
            Text(feature.detail)
                .font(.system(size: compact ? 13 : 14))
                .foregroundStyle(PMTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                PlusAccess.notedLockedTap(feature)
                presentingPaywall = true
            } label: {
                HStack(spacing: 8) {
                    Text(feature.unlockPrompt)
                    Image(systemName: "arrow.right").font(.system(size: 14, weight: .semibold))
                }
            }
            .buttonStyle(PMBlackButtonStyle())
            .padding(.top, 4)
        }
        .padding(compact ? 14 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PMTheme.cardRadius, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
        )
        .sheet(isPresented: $presentingPaywall) {
            PlusSheet()
        }
    }
}

/// Small orange "PLUS" tag for menu rows and headers.
struct PlusTag: View {
    var body: some View {
        Text("PLUS")
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(PMTheme.plusOrange))
    }
}
