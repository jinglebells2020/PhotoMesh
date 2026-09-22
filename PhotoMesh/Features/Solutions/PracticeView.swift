import SwiftUI

/// A similar problem with fresh values, answered exam-style before the steps are shown.
/// Reached from the end of a walkthrough; a Plus feature.
struct PracticeView: View {
    let source: CircuitAnalysis

    @State private var practice: CircuitAnalysis?
    @State private var target: Practice.Target?
    @State private var failed = false
    @State private var typed = ""
    @State private var verdict: Verdict?
    @State private var attempts = 0
    @State private var revealed = false
    @State private var count = 0
    @FocusState private var typing: Bool

    private enum Verdict { case correct, wrong, unreadable }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                if let practice {
                    header
                    if let layout = practice.layout {
                        SchematicWindow(layout: layout, embedded: true)
                            .frame(height: 240)
                    }
                    valuesCard(practice)
                    answerCard(practice)
                } else if failed {
                    ContentUnavailableView("No variant for this one", systemImage: "repeat",
                                           description: Text("This circuit's values cannot be changed and still solve cleanly. Try another circuit."))
                        .padding(.top, 40)
                } else {
                    ProgressView("Making a similar problem…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                }
            }
            .padding(16)
        }
        .background(PMTheme.groupedBackground.ignoresSafeArea())
        .navigationTitle("Practice")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .task { if practice == nil { generate() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Same shape, new values")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(PMTheme.ink)
            Text("Work it out on paper, type your answer, then compare. The steps stay hidden until you have tried.")
                .font(.system(size: 14))
                .foregroundStyle(PMTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func valuesCard(_ practice: CircuitAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(practice.question)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(PMTheme.ink)
            if let circuit = practice.drawn ?? practice.circuit {
                let formatter = FormattingPreferences.formatter()
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(circuit.components) { component in
                        HStack(spacing: 8) {
                            Text(component.id)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .frame(width: 34, alignment: .leading)
                            Text(component.kind.hasValue ? formatter.format(component.value, component.kind.unitSymbol) : (component.kind == .switchOpen ? "open" : "closed"))
                                .font(.system(size: 14, design: .rounded))
                            Spacer(minLength: 0)
                            Text("\(component.nodeA) → \(component.nodeB)")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(PMTheme.secondaryText)
                        }
                    }
                }
                .foregroundStyle(PMTheme.ink)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: PMTheme.cardRadius, style: .continuous).fill(Color.white))
    }

    private func answerCard(_ practice: CircuitAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text((target?.label ?? "Your answer").uppercased())
                .font(.system(size: 12, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(PMTheme.secondaryText)
            HStack(spacing: 10) {
                TextField(target.map { "e.g. 1.5 m\($0.unit) or 0.0015" } ?? "Your answer", text: $typed)
                    .font(.system(size: 18, design: .rounded))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($typing)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(PMTheme.groupedBackground))
                    .onSubmit(check)
                Button("Check", action: check)
                    .buttonStyle(PMPrimaryButtonStyle())
                    .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty || revealed)
                    .opacity(typed.trimmingCharacters(in: .whitespaces).isEmpty || revealed ? 0.5 : 1)
            }
            if let verdict {
                verdictView(verdict, practice)
            }
            if revealed {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "eye").foregroundStyle(PMTheme.secondaryText)
                    Text(answerText(practice))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(PMTheme.ink)
                }
            }
            HStack {
                if !revealed && verdict != .correct {
                    Button("Show the answer") { reveal() }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(PMTheme.secondaryText)
                }
                Spacer()
                Button {
                    Haptics.impact(.light)
                    generate()
                } label: {
                    Label("Another one", systemImage: "repeat")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PMTheme.accent)
                }
            }
            if revealed || verdict == .correct, !practice.methods.isEmpty {
                NavigationLink(value: SolutionDestination.steps(practice, methodIndex: 0)) {
                    HStack(spacing: 10) {
                        Text("Read the fresh steps")
                        Image(systemName: "arrow.right").font(.system(size: 16, weight: .semibold))
                    }
                }
                .buttonStyle(PMBlackButtonStyle())
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: PMTheme.cardRadius, style: .continuous).fill(Color.white))
    }

    private func verdictView(_ verdict: Verdict, _ practice: CircuitAnalysis) -> some View {
        HStack(alignment: .top, spacing: 8) {
            switch verdict {
            case .correct:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(PMTheme.accent)
                Text("Correct: \(answerText(practice))")
                    .foregroundStyle(PMTheme.ink)
            case .wrong:
                Image(systemName: "xmark.circle.fill").foregroundStyle(PMTheme.whyOrange)
                Text(attempts >= 2
                     ? "Not quite. Check the units: the answer is in \(target?.unit ?? "base units"); prefixes like m and k are fine. Try once more or show the answer."
                     : "Not quite. Try again, or show the answer.")
                    .foregroundStyle(PMTheme.ink)
            case .unreadable:
                Image(systemName: "questionmark.circle.fill").foregroundStyle(PMTheme.secondaryText)
                Text("Type a number, with a prefix if you like: 1.5m, 0.0015 or 1.5 mA.")
                    .foregroundStyle(PMTheme.ink)
            }
        }
        .font(.system(size: 14, weight: .medium))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func answerText(_ practice: CircuitAnalysis) -> String {
        if let answer = practice.methods.first?.answers.first { return answer.value }
        if let target { return FormattingPreferences.formatter().format(abs(target.value), target.unit) }
        return practice.methods.first?.headline ?? ""
    }

    // MARK: Actions

    private func generate() {
        guard let circuit = source.drawn ?? source.circuit else {
            failed = true
            return
        }
        practice = nil
        target = nil
        failed = false
        typed = ""
        verdict = nil
        attempts = 0
        revealed = false
        let formatter = FormattingPreferences.formatter()
        Task.detached(priority: .userInitiated) {
            let variant = Practice.similar(to: circuit)
            let analysis = variant.flatMap { try? CircuitAnalyzer.analyze($0, formatter: formatter) }
            await MainActor.run {
                if let analysis {
                    practice = analysis
                    target = Practice.target(for: analysis)
                    count += 1
                    Analytics.shared.track("practice_started", ["components": .init(circuit.components.count), "nth": .init(count)])
                } else {
                    failed = true
                }
            }
        }
    }

    private func check() {
        guard let target, !revealed else { return }
        typing = false
        attempts += 1
        switch Practice.check(typed, against: target) {
        case .some(true):
            verdict = .correct
            Haptics.notify(.success)
        case .some(false):
            verdict = .wrong
            Haptics.notify(.error)
        case .none:
            verdict = .unreadable
        }
        Analytics.shared.track("practice_checked", ["correct": .bool(verdict == .correct), "attempts": .init(attempts)])
    }

    private func reveal() {
        typing = false
        withAnimation { revealed = true }
        Analytics.shared.track("practice_revealed", ["attempts": .init(attempts)])
    }
}
