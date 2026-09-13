import SwiftUI
import StoreKit

/// Step-by-step walkthrough revealed one step at a time with "Next Step".
struct SolvingStepsView: View {
    let analysis: CircuitAnalysis
    let solution: MethodSolution

    @State private var revealedCount = 1
    @State private var expandedIndex: Int? = 0
    @State private var whyIndex: Int?
    @State private var showExplorer = false

    private var isComplete: Bool { revealedCount > solution.steps.count }

    /// The step the schematic should illustrate: the open one, else the latest revealed.
    private var currentFocus: StepFocus {
        guard !solution.steps.isEmpty else { return StepFocus() }
        if let expandedIndex, expandedIndex < solution.steps.count { return solution.steps[expandedIndex].focus }
        let index = min(revealedCount, solution.steps.count) - 1
        return solution.steps[max(index, 0)].focus
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                if let layout = analysis.layout {
                    SchematicWindow(layout: layout, loops: solution.loops, focus: currentFocus) {
                        showExplorer = true
                    }
                    .frame(height: max(190, geo.size.height * 0.31))
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                }
                stepsList
            }
        }
        .background(PMTheme.groupedBackground.ignoresSafeArea())
        .navigationTitle("Solving Steps")
        .navigationBarTitleDisplayMode(analysis.layout == nil ? .large : .inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(PMTheme.groupedBackground, for: .navigationBar)
        .navigationDestination(isPresented: $showExplorer) {
            CircuitExplorerView(analysis: analysis, initialFocus: currentFocus)
        }
    }

    private var stepsList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(solution.method.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PMTheme.secondaryText)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)

                    ForEach(Array(solution.steps.enumerated()), id: \.offset) { index, step in
                        if index < revealedCount {
                            StepRow(
                                number: index + 1,
                                step: step,
                                isExpanded: expandedIndex == index,
                                showsWhy: whyIndex == index,
                                nextTitle: index == solution.steps.count - 1 ? "Show the answer" : "Next step",
                                onToggle: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        expandedIndex = (expandedIndex == index) ? nil : index
                                        whyIndex = nil
                                    }
                                    if expandedIndex == index { scroll(proxy, to: "step-\(index)") }
                                },
                                onWhy: {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        whyIndex = (whyIndex == index) ? nil : index
                                    }
                                },
                                onNext: { advance(from: index, proxy: proxy) }
                            )
                            .id("step-\(index)")
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .onAppear {
                                // A freshly revealed step scrolls itself into view.
                                if index == revealedCount - 1, index > 0 { scroll(proxy, to: "step-\(index)") }
                            }
                        }
                    }

                    if isComplete {
                        SolutionRow(answers: solution.answers, headline: solution.headline)
                            .id("solution")
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .onAppear { scroll(proxy, to: "solution") }
                        FeedbackFlow(question: analysis.question, method: solution.method.title)
                            .padding(.top, 26)
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
        }
    }

    /// Reveals the next step (or the answer) when called from the latest step; otherwise opens the following one.
    private func advance(from index: Int, proxy: ScrollViewProxy) {
        Haptics.impact(.light)
        if index == revealedCount - 1 {
            revealNext()
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                expandedIndex = index + 1
                whyIndex = nil
            }
            scroll(proxy, to: "step-\(index + 1)")
        }
    }

    private func revealNext() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            revealedCount += 1
            expandedIndex = isComplete ? nil : revealedCount - 1
            whyIndex = nil
        }
    }

    /// Scrolls after the layout has settled so the target exists; top-aligned so the whole card is readable.
    private func scroll(_ proxy: ScrollViewProxy, to id: String) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo(id, anchor: UnitPoint(x: 0, y: 0.04))
            }
        }
    }

    private var bottomBar: some View {
        ZStack {
            HStack {
                Button {
                    Haptics.impact(.light)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        revealedCount = 1
                        expandedIndex = 0
                        whyIndex = nil
                    }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(PMTheme.ink)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(Color.white).shadow(color: .black.opacity(0.15), radius: 8, y: 3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start over")
                Spacer()
            }
            .padding(.leading, 18)

            if !isComplete {
                Button {
                    Haptics.impact(.light)
                    revealNext()
                } label: {
                    Text(revealedCount == solution.steps.count ? "Show Answer" : "Next Step")
                }
                .buttonStyle(PMPrimaryButtonStyle())
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.bottom, 8)
        .padding(.top, 10)
        .background {
            LinearGradient(colors: [PMTheme.groupedBackground.opacity(0), PMTheme.groupedBackground], startPoint: .top, endPoint: .bottom)
                .padding(.top, -30)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Rows

private struct EquationLines: View {
    let lines: [String]
    var emphasizeLast = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .font(.system(size: 15, weight: emphasizeLast && index == lines.count - 1 ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(PMTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct StepRow: View {
    let number: Int
    let step: AnalysisStep
    let isExpanded: Bool
    let showsWhy: Bool
    let nextTitle: String
    let onToggle: () -> Void
    let onWhy: () -> Void
    let onNext: () -> Void

    var body: some View {
        Group {
            if isExpanded {
                expanded
            } else {
                collapsed
            }
        }
    }

    private var collapsed: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(number). \(step.title)")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(PMTheme.ink)
                        Text(step.result)
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(PMTheme.secondaryText)
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PMTheme.tertiaryText)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                Divider().padding(.leading, 20)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(number). \(step.title)")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(PMTheme.ink)
                    Text(step.summary)
                        .font(.system(size: 14))
                        .foregroundStyle(PMTheme.secondaryText)
                }
                Spacer()
                Button(action: onToggle) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(PMTheme.ink)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Collapse step")
            }

            if !step.equations.isEmpty {
                EquationLines(lines: step.equations, emphasizeLast: step.equations.count > 1)
                    .padding(.top, 14)
                    .padding(.leading, 12)
            }

            HStack(alignment: .top, spacing: 12) {
                Text(step.explanation)
                    .font(.system(size: 14))
                    .foregroundStyle(PMTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(action: onWhy) {
                    VStack(spacing: 2) {
                        Text("?")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(PMTheme.whyOrange))
                        Text("Why")
                            .font(.system(size: 9))
                            .foregroundStyle(PMTheme.whyOrange)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 14)
            .padding(.leading, 12)

            if showsWhy {
                Text(whyText)
                    .font(.system(size: 13))
                    .foregroundStyle(PMTheme.ink)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(PMTheme.whyOrange.opacity(0.12)))
                    .padding(.top, 10)
                    .padding(.leading, 12)
            }

            HStack(alignment: .bottom) {
                Text(step.result)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(PMTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(action: onNext) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(PMTheme.accent)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(PMTheme.accentSoft))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(nextTitle)
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(Color.white)
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    private var whyText: String {
        switch step.title {
        case let t where t.hasPrefix("Apply KCL"):
            return "Kirchhoff's current law: charge cannot pile up at a node, so the currents flowing out must add up to the currents flowing in."
        case let t where t.hasPrefix("Apply KVL"):
            return "Kirchhoff's voltage law: going once around any closed loop brings you back to the same potential, so the voltage rises and drops sum to zero."
        case let t where t.hasPrefix("Identify the meshes"):
            return "Each mesh current is an independent unknown; there are exactly (elements − nodes + 1) of them for a connected circuit."
        case let t where t.hasPrefix("Choose the reference"):
            return "Only voltage differences matter physically, so one node can be set to 0 V without loss of generality."
        default:
            return step.summary
        }
    }
}

private struct SolutionRow: View {
    let answers: [Answer]
    let headline: String

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(PMTheme.accent)
                .frame(width: 5)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Solution")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(PMTheme.accent)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(PMTheme.accent)
                }
                if answers.isEmpty {
                    Text(headline)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(PMTheme.ink)
                } else {
                    ForEach(answers) { answer in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(answer.label)
                                .font(.system(size: 13))
                                .foregroundStyle(PMTheme.secondaryText)
                            Text(answer.value)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(PMTheme.ink)
                        }
                    }
                }
            }
            .padding(.leading, 15)
            .padding(.trailing, 20)
            .padding(.vertical, 18)
        }
        .background(Color.white)
    }
}

/// "Did this explanation help you?" → rating request, or a short feedback form.
private struct FeedbackFlow: View {
    let question: String
    let method: String

    private enum Stage: Equatable { case ask, thanksPositive, rate, form, thanksNegative }

    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL
    @State private var stage: Stage = .ask
    @State private var reasons: Set<String> = []
    @State private var comment = ""
    @State private var lastEntry: FeedbackEntry?
    @FocusState private var commentFocused: Bool

    var body: some View {
        VStack(spacing: 14) {
            switch stage {
            case .ask:
                Text("Did this explanation help you?")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PMTheme.ink)
                HStack(spacing: 44) {
                    thumb(up: true)
                    thumb(up: false)
                }
            case .thanksPositive:
                Text("Glad it helped!")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(PMTheme.ink)
            case .rate:
                card {
                    Text("Glad it helped!")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(PMTheme.ink)
                    Text("A quick rating on the App Store helps other students find PhotoMesh.")
                        .font(.system(size: 14))
                        .foregroundStyle(PMTheme.secondaryText)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 6) {
                        ForEach(0..<5, id: \.self) { _ in
                            Image(systemName: "star.fill").foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.0))
                        }
                    }
                    .font(.system(size: 20))
                    Button("Rate PhotoMesh") {
                        FeedbackStore.markRated()
                        if let url = FeedbackStore.writeReviewURL {
                            openURL(url)
                        } else {
                            requestReview()
                        }
                        withAnimation { stage = .thanksPositive }
                    }
                    .buttonStyle(PMPrimaryButtonStyle())
                    Button("Not now") {
                        FeedbackStore.markDeclined()
                        withAnimation { stage = .thanksPositive }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(PMTheme.secondaryText)
                }
            case .form:
                card {
                    Text("Sorry about that. What went wrong?")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(PMTheme.ink)
                    FlowChips(options: FeedbackStore.reasons, selected: $reasons)
                    TextField("Anything else? (optional)", text: $comment, axis: .vertical)
                        .lineLimit(2...4)
                        .font(.system(size: 14))
                        .focused($commentFocused)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(PMTheme.groupedBackground))
                    Button("Send feedback") { submitNegative() }
                        .buttonStyle(PMPrimaryButtonStyle())
                        .disabled(reasons.isEmpty && comment.trimmingCharacters(in: .whitespaces).isEmpty)
                        .opacity(reasons.isEmpty && comment.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                }
            case .thanksNegative:
                card {
                    Text("Thank you. We'll look into it.")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(PMTheme.ink)
                    if let entry = lastEntry, let url = FeedbackStore.mailURL(for: entry) {
                        Button("Also send it by email") { openURL(url) }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(PMTheme.accent)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: stage)
    }

    private func thumb(up: Bool) -> some View {
        Button {
            Haptics.impact(.light)
            if up {
                FeedbackStore.save(FeedbackEntry(id: UUID(), date: Date(), helpful: true, reasons: [], comment: "", question: question, method: method))
                withAnimation { stage = FeedbackStore.shouldAskForRating ? .rate : .thanksPositive }
            } else {
                withAnimation { stage = .form }
            }
        } label: {
            Image(systemName: up ? "hand.thumbsup" : "hand.thumbsdown")
                .font(.system(size: 22))
                .foregroundStyle(PMTheme.ink)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(up ? "Yes, it helped" : "No, it did not help")
    }

    private func submitNegative() {
        let entry = FeedbackEntry(id: UUID(), date: Date(), helpful: false, reasons: Array(reasons), comment: comment.trimmingCharacters(in: .whitespacesAndNewlines), question: question, method: method)
        FeedbackStore.save(entry)
        lastEntry = entry
        commentFocused = false
        Haptics.notify(.success)
        withAnimation { stage = .thanksNegative }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 12) { content() }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
    }
}

/// Wrapping row of toggle chips.
private struct FlowChips: View {
    let options: [String]
    @Binding var selected: Set<String>

    var body: some View {
        let rows = stride(from: 0, to: options.count, by: 2).map { Array(options[$0..<min($0 + 2, options.count)]) }
        VStack(spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { option in
                        let isOn = selected.contains(option)
                        Button {
                            if isOn { selected.remove(option) } else { selected.insert(option) }
                        } label: {
                            Text(option)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(isOn ? .white : PMTheme.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(Capsule().fill(isOn ? PMTheme.accent : PMTheme.groupedBackground))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        if let analysis = try? CircuitAnalyzer.analyze(SampleCircuitSolver.sample) {
            SolvingStepsView(analysis: analysis, solution: analysis.methods[0])
        }
    }
}
