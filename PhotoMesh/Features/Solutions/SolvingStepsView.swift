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
    @State private var showExport = false
    @State private var showPaywall = false
    /// Steps past the first are open: Plus, or a free complete solution spent on this circuit.
    @State private var unlocked = false
    /// The wall after step one, once a student without Plus and without trial left taps on.
    @State private var showLock = false
    /// "Free complete solution 1 of 3", shown when the trial pays for this circuit.
    @State private var trialNote: String?

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
        .onAppear {
            unlocked = PlusAccess.allows(.fullSteps, for: analysis)
            Analytics.shared.track("steps_opened", ["method": .string(solution.method.rawValue), "steps": .init(solution.steps.count), "unlocked": .bool(unlocked)])
        }
        .onChange(of: showPaywall) { _, presenting in
            if !presenting { refreshEntitlement() }
        }
        .onChange(of: isComplete) { _, done in
            if done { Analytics.shared.track("steps_completed", ["method": .string(solution.method.rawValue), "steps": .init(solution.steps.count)]) }
        }
        .navigationTitle("Solving Steps")
        .navigationBarTitleDisplayMode(analysis.layout == nil ? .large : .inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(PMTheme.groupedBackground, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if PlusAccess.allows(.exports) {
                        showExport = true
                    } else {
                        PlusAccess.notedLockedTap(.exports)
                        showPaywall = true
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .foregroundStyle(PMTheme.accent)
                .accessibilityLabel("Export the steps as PDF")
            }
        }
        .navigationDestination(isPresented: $showExplorer) {
            CircuitExplorerView(analysis: analysis, initialFocus: currentFocus)
        }
        .sheet(isPresented: $showExport) {
            ExportSheet(kind: .stepsPDF(analysis: analysis, solution: solution))
        }
        .sheet(isPresented: $showPaywall) {
            PlusSheet()
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

                    if let trialNote {
                        HStack(spacing: 10) {
                            Image(systemName: "gift.fill")
                                .foregroundStyle(PMTheme.plusOrange)
                            Text(trialNote)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(PMTheme.ink)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(PMTheme.plusOrange.opacity(0.12)))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

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
                                    guard PlusAccess.allows(.explain, for: analysis) else {
                                        PlusAccess.notedLockedTap(.explain)
                                        showPaywall = true
                                        return
                                    }
                                    let opening = whyIndex != index
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        whyIndex = opening ? index : nil
                                    }
                                    if opening { Analytics.shared.track("why_opened", ["step": .init(index + 1), "method": .string(solution.method.rawValue)]) }
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

                    if showLock, !unlocked {
                        StepsLockCard(remaining: Array(solution.steps.dropFirst())) {
                            PlusAccess.notedLockedTap(.fullSteps)
                            showPaywall = true
                        }
                        .id("lock")
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear { scroll(proxy, to: "lock") }
                        // The final answer is free, wall or no wall.
                        SolutionRow(answers: solution.answers, headline: solution.headline)
                            .padding(.top, 12)
                    }

                    if isComplete {
                        SolutionRow(answers: solution.answers, headline: solution.headline)
                            .id("solution")
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .onAppear { scroll(proxy, to: "solution") }
                        PracticeCard(analysis: analysis)
                        FeedbackFlow(question: analysis.question, method: solution.method.title, circuit: analysis.circuit)
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
        // Paywall the second time, not the first: step one and the answer are free, step two is
        // where the trial fires and, once it is spent, where the wall stands.
        if revealedCount == 1, solution.steps.count > 1, !unlocked {
            switch SolveTrial.unlock(analysis) {
            case .unlocked(let ordinal):
                unlocked = true
                let last = SolveTrial.remaining == 0 ? " That was the last free one." : ""
                withAnimation { trialNote = "Free complete solution \(ordinal) of \(SolveTrial.total): every step, method and explanation on this circuit.\(last)" }
            case .alreadyUnlocked:
                unlocked = true
            case .exhausted:
                PlusAccess.notedLockedTap(.fullSteps)
                Analytics.shared.track("steps_locked", ["method": .string(solution.method.rawValue), "steps": .init(solution.steps.count)])
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    showLock = true
                    whyIndex = nil
                }
                return
            }
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            revealedCount += 1
            expandedIndex = isComplete ? nil : revealedCount - 1
            whyIndex = nil
        }
    }

    /// After the paywall closes: a purchase opens the wall and carries on where the student stopped.
    private func refreshEntitlement() {
        unlocked = PlusAccess.allows(.fullSteps, for: analysis)
        if unlocked, showLock {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showLock = false }
            revealNext()
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
                    if showLock, !unlocked {
                        PlusAccess.notedLockedTap(.fullSteps)
                        showPaywall = true
                    } else {
                        revealNext()
                    }
                } label: {
                    Text(showLock && !unlocked ? "Unlock every step" : (revealedCount == solution.steps.count ? "Show Answer" : "Next Step"))
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

/// The equations of a step, typeset. Long lines scroll sideways rather than wrap mid-fraction.
private struct EquationLines: View {
    let lines: [String]
    var emphasizeLast = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                let isLast = emphasizeLast && index == lines.count - 1
                ScrollView(.horizontal, showsIndicators: false) {
                    MathText(latex: EquationLaTeX.latex(for: line), fallback: line, fontSize: isLast ? 17 : 15.5, color: isLast ? PMTheme.accent : PMTheme.ink)
                        .padding(.vertical, 2)
                        .padding(.trailing, 12)
                }
                .scrollBounceBehavior(.basedOnSize)
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
        case let t where t.hasPrefix("Identify the meshes") || t.hasPrefix("Choose independent loops"):
            return "Each loop current is an independent unknown; there are exactly (elements − nodes + 1) of them for a connected circuit."
        case let t where t.hasPrefix("Choose the reference"):
            return "Only voltage differences matter physically, so one node can be set to 0 V without loss of generality."
        default:
            return step.summary
        }
    }
}

/// The wall after step one: the remaining step titles, blurred, and the way through.
private struct StepsLockCard: View {
    let remaining: [AnalysisStep]
    let onUnlock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(remaining.prefix(4).enumerated()), id: \.offset) { offset, step in
                    HStack(spacing: 10) {
                        Text("\(offset + 2).")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(PMTheme.tertiaryText)
                        Text(step.title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(PMTheme.ink)
                            .blur(radius: 4)
                            .accessibilityHidden(true)
                        Spacer(minLength: 0)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(PMTheme.plusOrange)
                    }
                }
                if remaining.count > 4 {
                    Text("+ \(remaining.count - 4) more steps")
                        .font(.system(size: 13))
                        .foregroundStyle(PMTheme.secondaryText)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: PMTheme.cardRadius, style: .continuous).fill(Color.white))

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(PMTheme.plusOrange)
                    Text("Photocircuits Plus")
                        .font(.system(size: 12, weight: .semibold))
                        .kerning(0.6)
                        .foregroundStyle(PMTheme.plusOrange)
                }
                Text("\(remaining.count) more steps to the answer")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(PMTheme.ink)
                Text("Your three free complete solutions are used up. Plus opens every step on every circuit, the other methods, and the explanation behind each step. The answer below stays free.")
                    .font(.system(size: 14))
                    .foregroundStyle(PMTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onUnlock) {
                    HStack(spacing: 8) {
                        Text(PlusFeature.fullSteps.unlockPrompt)
                        Image(systemName: "arrow.right").font(.system(size: 14, weight: .semibold))
                    }
                }
                .buttonStyle(PMBlackButtonStyle())
                .padding(.top, 4)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: PMTheme.cardRadius, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
            )
        }
    }
}

/// "Practice a similar problem" at the end of a walkthrough; Plus, with the lock card otherwise.
private struct PracticeCard: View {
    let analysis: CircuitAnalysis

    var body: some View {
        Group {
            if analysis.circuit != nil {
                if PlusAccess.allows(.practice) {
                    NavigationLink(value: SolutionDestination.practice(analysis)) {
                        HStack(spacing: 12) {
                            Image(systemName: "repeat")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(PMTheme.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Practice a similar problem")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(PMTheme.ink)
                                Text("Same circuit, new values. Answer first, then read fresh steps.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(PMTheme.secondaryText)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(PMTheme.tertiaryText)
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: PMTheme.cardRadius, style: .continuous).fill(Color.white))
                    }
                    .buttonStyle(.plain)
                } else {
                    PlusLockCard(feature: .practice, compact: true)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
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
    /// The solved circuit, sent with the feedback so a report can be reproduced.
    var circuit: Circuit? = nil

    private enum Stage: Equatable { case ask, thanksPositive, rate, form, thanksNegative }

    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL
    @State private var stage: Stage = .ask
    @State private var reasons: Set<String> = []
    @State private var comment = ""
    @State private var lastEntry: FeedbackEntry?
    /// Bonus scans paid for this rating, if any.
    @State private var granted = 0
    @FocusState private var commentFocused: Bool

    private var netlist: String? { circuit.map { SpiceExport.netlist($0) } }

    @ViewBuilder
    private var rewardLine: some View {
        if granted > 0 {
            Text("+\(granted) bonus scans added. Thank you!")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PMTheme.accent)
        }
    }

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
                rewardLine
            case .rate:
                card {
                    Text("Glad it helped!")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(PMTheme.ink)
                    rewardLine
                    Text("A quick rating on the App Store helps other students find Photocircuits.")
                        .font(.system(size: 14))
                        .foregroundStyle(PMTheme.secondaryText)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 6) {
                        ForEach(0..<5, id: \.self) { _ in
                            Image(systemName: "star.fill").foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.0))
                        }
                    }
                    .font(.system(size: 20))
                    Button("Rate Photocircuits") {
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
                    rewardLine
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
                FeedbackStore.save(FeedbackEntry(id: UUID(), date: Date(), helpful: true, reasons: [], comment: "", question: question, method: method, netlist: netlist))
                granted = ScanCredits.award(.feedback)
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
        let entry = FeedbackEntry(id: UUID(), date: Date(), helpful: false, reasons: Array(reasons), comment: comment.trimmingCharacters(in: .whitespacesAndNewlines), question: question, method: method, netlist: netlist)
        FeedbackStore.save(entry)
        granted = ScanCredits.award(.feedback)
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
