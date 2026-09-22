import SwiftUI

enum SolutionDestination: Hashable {
    case steps(CircuitAnalysis, methodIndex: Int)
    case circuit(CircuitAnalysis)
    case practice(CircuitAnalysis)
}

/// Dark results sheet. One white card per solving method so the user picks which to follow,
/// plus a card describing what the reader recognized.
struct SolutionsSheet: View {
    let request: SolutionRequest
    @Environment(\.dismiss) private var dismiss

    private enum LoadState {
        case loading
        case review(Circuit, notes: String?)
        case loaded(CircuitAnalysis)
        case failed(String)
    }

    @State private var state: LoadState = .loading
    @State private var phase = "Reading the circuit…"
    @State private var editing: Circuit?
    @State private var showEditor = false
    /// What the reader produced and which model did it, for samples.
    @State private var reviewed: Circuit?
    @State private var reviewedModel = "none"
    @State private var startedAt = Date()
    @State private var showConsent = false
    /// A circuit whose DC steady state could not be solved but which can still be simulated.
    @State private var labOnly: CircuitAnalysis?
    /// The last failure was the beta allowance, so the card can point at ways to earn bonus scans.
    @State private var limited = false
    @State private var showContribute = false
    /// A thank-you line after a reward, shown above the cards.
    @State private var rewardNote: String?
    /// Bumped whenever the sheet comes back into view, so method locks follow a trial or a purchase.
    @State private var entitlementsTick = 0

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                PMTheme.darkSheet.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Solutions")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.top, 48)

                        if let rewardNote {
                            RewardNote(text: rewardNote)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        switch state {
                        case .loading:
                            LoadingCard(phase: phase, image: sourceImage)
                        case .failed(let message):
                            FailedCard(message: message, lab: labOnly, earn: limited ? { showContribute = true } : nil) { Task { await load() } }
                        case .review(let circuit, let notes):
                            ReviewCard(circuit: circuit, notes: notes, image: sourceImage) {
                                Analytics.shared.recordSample(image: sourceImage, model: reviewedModel, recognized: circuit, corrected: nil, accepted: true)
                                solve(.circuit(circuit, notes: notes, needsReview: false, model: reviewedModel))
                            } onEdit: {
                                editing = circuit
                                showEditor = true
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            if showConsent { ConsentCard { granted in showConsent = false; noteReward(granted, "for sharing") } }
                        case .loaded(let analysis):
                            // The circuit first: what was solved, then how.
                            if analysis.circuit != nil {
                                RecognizedCircuitCard(analysis: analysis, image: sourceImage, isDrawn: isDrawn, onFix: sourceImage == nil ? nil : {
                                    editing = analysis.drawn ?? analysis.circuit
                                    showEditor = true
                                })
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                            ForEach(Array(analysis.methods.enumerated()), id: \.element.id) { index, method in
                                // The first method is the free walkthrough; switching methods is Plus (or the trial's).
                                MethodCard(method: method, methodIndex: index, analysis: analysis, request: request,
                                           locked: entitlementsTick >= 0 && index > 0 && !PlusAccess.allows(.methods, for: analysis))
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                            if showConsent { ConsentCard { granted in showConsent = false; noteReward(granted, "for sharing") } }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 36)
                }
                .onAppear { entitlementsTick += 1 }

                PMCloseButton { dismiss() }
                    .padding(.top, 14)
                    .padding(.trailing, 16)
            }
            .navigationTitle("Solutions")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showEditor) {
                if let editing {
                    CircuitEditorView(circuit: editing) { corrected in
                        if let original = reviewed {
                            Analytics.shared.recordSample(image: sourceImage, model: reviewedModel, recognized: original, corrected: corrected, accepted: false)
                            if AnalyticsConsent.scans, sourceImage != nil { noteReward(ScanCredits.award(.correction), "for the fix") }
                        }
                        solve(.circuit(corrected, notes: "Corrected by you.", needsReview: false, model: reviewedModel))
                    }
                }
            }
            .navigationDestination(for: SolutionDestination.self) { destination in
                switch destination {
                case .steps(let analysis, let index):
                    SolvingStepsView(analysis: analysis, solution: analysis.methods[min(index, analysis.methods.count - 1)])
                case .circuit(let analysis):
                    CircuitExplorerView(analysis: analysis)
                case .practice(let analysis):
                    PracticeView(source: analysis)
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showContribute) { ContributeSheet() }
    }

    private func noteReward(_ granted: Int, _ what: String) {
        guard granted > 0 else { return }
        Haptics.notify(.success)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { rewardNote = "+\(granted) bonus scans \(what). Thank you!" }
    }

    private var sourceImage: UIImage? {
        if case .image(let image) = request.source { return image }
        return nil
    }

    private var isDrawn: Bool {
        if case .circuit = request.source { return true }
        return false
    }

    private var sourceName: String {
        switch request.source {
        case .image: return "scan"
        case .expression: return "expression"
        case .circuit: return "drawn"
        }
    }

    private func load() async {
        state = .loading
        limited = false
        phase = "Reading the circuit…"
        startedAt = Date()
        let solver = SolverProvider.make()
        do {
            let input = try await solver.prepare(request) { text in
                Task { @MainActor in phase = text }
            }
            if case .circuit(let circuit, let notes, let needsReview, let model) = input {
                reviewed = circuit
                reviewedModel = model
                if needsReview {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        state = .review(circuit, notes: notes)
                    }
                    Haptics.impact(.light)
                    offerConsentIfNeeded()
                    return
                }
            }
            solve(input)
        } catch {
            Haptics.notify(.error)
            Analytics.shared.track("solve_failed", ["source": .string(sourceName), "reason": .string(String(error.localizedDescription.prefix(120)))])
            limited = error is UsageAllowance.LimitError
            state = .failed(error.localizedDescription)
        }
    }

    private func solve(_ input: SolveInput) {
        phase = "Solving…"
        labOnly = nil
        do {
            let analysis = try SolveRunner.analyze(input)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                state = .loaded(analysis)
            }
            Haptics.notify(.success)
            if let circuit = analysis.circuit {
                HistoryStore.shared.remember(circuit: circuit, analysis: analysis, origin: isDrawn ? .drawn : .scan)
            }
            Analytics.shared.track("solve", [
                "source": .string(sourceName), "model": .string(reviewedModel),
                "components": .init(analysis.circuit?.components.count ?? 0), "methods": .init(analysis.methods.count),
                "agree": .init(analysis.methodsAgree), "ms": .init(Int(Date().timeIntervalSince(startedAt) * 1000)),
            ])
            offerConsentIfNeeded()
            Analytics.shared.flush()
        } catch {
            Haptics.notify(.error)
            Analytics.shared.track("solve_failed", ["source": .string(sourceName), "reason": .string(String(error.localizedDescription.prefix(120)))])
            if case .circuit(let circuit, _, _, _) = input, CircuitAnalyzer.isTransientOnlyFailure(error) {
                labOnly = CircuitAnalyzer.labOnly(circuit)
            }
            state = .failed(error.localizedDescription)
        }
    }

    private func offerConsentIfNeeded() {
        guard !AnalyticsConsent.asked, sourceName != "expression" else { return }
        withAnimation { showConsent = true }
    }
}

// MARK: - Cards

private struct MethodCard: View {
    let method: MethodSolution
    let methodIndex: Int
    let analysis: CircuitAnalysis
    let request: SolutionRequest
    /// Another method's walkthrough, behind Plus. The answer on the card stays visible.
    var locked = false
    @State private var presentingPaywall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(method.method.eyebrow)
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(PMTheme.secondaryText)
                if locked { PlusTag() }
            }
            Text(method.method.title)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(PMTheme.ink)
                .padding(.top, 4)

            HStack(alignment: .top, spacing: 12) {
                Text(analysis.question)
                    .font(.system(size: 17))
                    .foregroundStyle(PMTheme.ink)
                Spacer(minLength: 0)
                Image(systemName: "pencil")
                    .font(.system(size: 17))
                    .foregroundStyle(PMTheme.secondaryText)
            }
            .padding(.top, 16)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(PMTheme.tertiaryText)
                    .frame(width: 16)
                Text(method.method.summary)
                    .font(.system(size: 14))
                    .foregroundStyle(PMTheme.secondaryText)
            }
            .padding(.top, 12)

            HStack(spacing: 0) {
                Rectangle()
                    .fill(PMTheme.accent)
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(method.answers.prefix(4)) { answer in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(answer.label)
                                .font(.system(size: 13))
                                .foregroundStyle(PMTheme.secondaryText)
                            Text(answer.value)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(PMTheme.ink)
                                .minimumScaleFactor(0.7)
                                .lineLimit(2)
                        }
                    }
                    if method.answers.count > 4 {
                        Text("+ \(method.answers.count - 4) more in the steps")
                            .font(.system(size: 13))
                            .foregroundStyle(PMTheme.secondaryText)
                    }
                }
                .padding(.leading, 12)
                .padding(.vertical, 12)
            }
            .padding(.leading, -16)
            .padding(.top, 14)

            HStack {
                Spacer()
                if locked {
                    Button {
                        PlusAccess.notedLockedTap(.methods)
                        presentingPaywall = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.fill").font(.system(size: 14, weight: .semibold))
                            Text("Solve by this method")
                        }
                    }
                    .buttonStyle(PMPrimaryButtonStyle())
                    .sheet(isPresented: $presentingPaywall) { PlusSheet() }
                } else {
                    NavigationLink(value: SolutionDestination.steps(analysis, methodIndex: methodIndex)) {
                        HStack(spacing: 10) {
                            Text("Show Solving Steps")
                            Image(systemName: "arrow.right").font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .buttonStyle(PMPrimaryButtonStyle())
                }
                Spacer()
            }
            .padding(.top, 20)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: PMTheme.cardRadius, style: .continuous).fill(Color.white))
    }
}

private struct RecognizedCircuitCard: View {
    let analysis: CircuitAnalysis
    let image: UIImage?
    var isDrawn = false
    /// Opens the editor on the solved circuit: a misread part can be fixed after the fact, and the
    /// fix is recorded like one made before solving. Never behind the paywall.
    var onFix: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isDrawn ? "YOUR CIRCUIT" : "RECOGNIZED CIRCUIT")
                .font(.system(size: 12, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(PMTheme.secondaryText)
            if let circuit = analysis.circuit {
                Text(summary(for: circuit))
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(PMTheme.ink)
                    .padding(.top, 4)

                if let layout = analysis.layout {
                    InteractiveSchematic(layout: layout)
                        .frame(height: 220)
                        .padding(.top, 14)
                }

                if let image {
                    HStack(spacing: 10) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.black.opacity(0.08)))
                        Text("Redrawn from your photo. Compare the two before trusting the numbers.")
                            .font(.system(size: 12))
                            .foregroundStyle(PMTheme.secondaryText)
                    }
                    .padding(.top, 10)
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(circuit.components) { component in
                        HStack(spacing: 8) {
                            Text(component.id)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .frame(width: 34, alignment: .leading)
                            Text(valueText(component))
                                .font(.system(size: 14, design: .rounded))
                            Spacer(minLength: 0)
                            Text("\(component.nodeA) → \(component.nodeB)")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(PMTheme.secondaryText)
                        }
                    }
                }
                .foregroundStyle(PMTheme.ink)
                .padding(.top, 14)

                HStack(spacing: 6) {
                    Image(systemName: analysis.methodsAgree ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(analysis.methodsAgree ? PMTheme.accent : PMTheme.whyOrange)
                    Text(analysis.methodsAgree ? (analysis.methods.count > 1 ? "All \(analysis.methods.count) methods agree" : "Solved") : "The methods disagree – check the recognized values")
                        .font(.system(size: 13))
                        .foregroundStyle(PMTheme.secondaryText)
                }
                .padding(.top, 12)

                if let notes = analysis.recognitionNotes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 13))
                        .foregroundStyle(PMTheme.secondaryText)
                        .padding(.top, 6)
                }
            }

            HStack {
                if let onFix {
                    Button(action: onFix) {
                        Label("Fix a misread part", systemImage: "wrench.and.screwdriver")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(PMTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                NavigationLink(value: SolutionDestination.circuit(analysis)) {
                    HStack(spacing: 10) {
                        Text("Explore & Simulate")
                        Image(systemName: "arrow.right").font(.system(size: 16, weight: .semibold))
                    }
                }
                .buttonStyle(PMPrimaryButtonStyle())
                Spacer()
            }
            .padding(.top, 18)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: PMTheme.cardRadius, style: .continuous).fill(Color.white))
    }

    private func summary(for circuit: Circuit) -> String {
        let r = circuit.resistors.count
        let s = circuit.voltageSources.count + circuit.currentSources.count
        return "\(r) resistor\(r == 1 ? "" : "s"), \(s) source\(s == 1 ? "" : "s"), \(circuit.nodes.count) nodes"
    }

    private func valueText(_ component: Component) -> String {
        component.kind.valueText(component.value, formatter: FormattingPreferences.formatter())
    }
}

private struct LoadingCard: View {
    let phase: String
    let image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ANALYZING")
                .font(.system(size: 12, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(PMTheme.secondaryText)
            HStack(spacing: 12) {
                ProgressView().tint(PMTheme.accent)
                Text(phase)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(PMTheme.ink)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: phase)
            }
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 150)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .opacity(0.85)
            }
            SkeletonLine(width: 0.9)
            SkeletonLine(width: 0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: PMTheme.cardRadius, style: .continuous).fill(Color.white))
    }
}

private struct SkeletonLine: View {
    let width: CGFloat
    @State private var shimmer = false

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(white: shimmer ? 0.90 : 0.94))
                .frame(width: geo.size.width * width, height: 12)
        }
        .frame(height: 12)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { shimmer = true }
        }
    }
}

private struct FailedCard: View {
    let message: String
    var lab: CircuitAnalysis? = nil
    /// Set when the beta allowance stopped the scan: opens the ways to earn bonus scans.
    var earn: (() -> Void)? = nil
    let retry: () -> Void
    @State private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Couldn't solve this one")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(PMTheme.ink)
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(PMTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button(showLog ? "Hide diagnostics" : "Show diagnostics") { withAnimation { showLog.toggle() } }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PMTheme.accent)
            if showLog {
                Text(RecognitionLog.shared.text.split(separator: "\n").suffix(10).joined(separator: "\n"))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(PMTheme.ink)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(PMTheme.groupedBackground))
            }
            if let lab {
                Text("There is no steady state to solve, but the circuit has a time response: watch the capacitor charge or the coil's current build up in the lab.")
                    .font(.system(size: 14))
                    .foregroundStyle(PMTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                NavigationLink(value: SolutionDestination.circuit(lab)) {
                    HStack(spacing: 10) {
                        Text("Simulate in the lab")
                        Image(systemName: "arrow.right").font(.system(size: 16, weight: .semibold))
                    }
                }
                .buttonStyle(PMPrimaryButtonStyle())
                .padding(.top, 6)
            }
            if let earn {
                Text("Bonus scans get you past this month's cap right away. Earn them by rating a walkthrough, fixing a misread circuit or answering five questions.")
                    .font(.system(size: 14))
                    .foregroundStyle(PMTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                Button(action: earn) {
                    HStack(spacing: 10) {
                        Text("Earn bonus scans")
                        Image(systemName: "arrow.right").font(.system(size: 16, weight: .semibold))
                    }
                }
                .buttonStyle(PMPrimaryButtonStyle())
                .padding(.top, 6)
            }
            if lab == nil {
                Button("Try again", action: retry)
                    .buttonStyle(PMPrimaryButtonStyle())
                    .padding(.top, 6)
            } else {
                Button("Try again", action: retry)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(PMTheme.accent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: PMTheme.cardRadius, style: .continuous).fill(Color.white))
    }
}

#Preview {
    SolutionsSheet(request: SolutionRequest(source: .expression("12/320")))
}

/// Schematic on a card that can be looked at closely: pinch to zoom, drag to pan once zoomed,
/// double-tap to fit. The page keeps scrolling normally until the user zooms in.
struct InteractiveSchematic: View {
    let layout: SchematicLayout
    var focus = StepFocus()

    var body: some View {
        SchematicWindow(layout: layout, focus: focus, embedded: true)
    }
}

/// Non-interactive schematic that fits its frame; used on small cards and history rows.
struct StaticSchematic: View {
    let layout: SchematicLayout
    var focus = StepFocus()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.white
                DotGrid()
                SchematicView(layout: layout, style: SchematicStyle(focus: focus, formatter: FormattingPreferences.formatter()), camera: .fitting(layout.bounds, in: geo.size, padding: 12))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.black.opacity(0.08)))
    }
}

/// "Is this what is on the page?" – shown before solving a scanned circuit.
private struct ReviewCard: View {
    let circuit: Circuit
    let notes: String?
    let image: UIImage?
    let onConfirm: () -> Void
    let onEdit: () -> Void

    private var layout: SchematicLayout { SchematicLayoutEngine.layout(for: circuit) }
    private var formatter: QuantityFormatter { FormattingPreferences.formatter() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CHECK THE CIRCUIT")
                .font(.system(size: 12, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(PMTheme.secondaryText)
            Text("Is this what's on the page?")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(PMTheme.ink)
                .padding(.top, 4)

            InteractiveSchematic(layout: layout)
                .frame(height: 240)
                .padding(.top, 14)

            if let image {
                HStack(spacing: 10) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.black.opacity(0.08)))
                    Text("Your photo, for comparison.")
                        .font(.system(size: 12))
                        .foregroundStyle(PMTheme.secondaryText)
                }
                .padding(.top, 10)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(circuit.components) { component in
                    HStack(spacing: 8) {
                        Text(component.id)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .frame(width: 34, alignment: .leading)
                        Text(component.kind.valueText(component.value, formatter: formatter))
                            .font(.system(size: 14, design: .rounded))
                        Spacer(minLength: 0)
                        Text(terminals(component))
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(PMTheme.secondaryText)
                    }
                }
                HStack(spacing: 8) {
                    Text("Ground")
                        .font(.system(size: 13))
                        .foregroundStyle(PMTheme.secondaryText)
                    Text(circuit.groundNode)
                        .font(.system(size: 14, design: .rounded))
                    Spacer()
                }
            }
            .foregroundStyle(PMTheme.ink)
            .padding(.top, 14)

            if let question = circuit.question {
                Text(question)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(PMTheme.ink)
                    .padding(.top, 12)
            }
            if let notes, !notes.isEmpty {
                Text(notes)
                    .font(.system(size: 12))
                    .foregroundStyle(PMTheme.secondaryText)
                    .padding(.top, 6)
            }

            HStack(spacing: 12) {
                Button(action: onEdit) {
                    Text("Fix something")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(PMTheme.accent)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(Capsule().stroke(PMTheme.accent, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: onConfirm) {
                    HStack(spacing: 8) {
                        Text("Looks right")
                        Image(systemName: "arrow.right").font(.system(size: 15, weight: .semibold))
                    }
                }
                .buttonStyle(PMPrimaryButtonStyle())
            }
            .padding(.top, 18)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: PMTheme.cardRadius, style: .continuous).fill(Color.white))
    }

    private func terminals(_ component: Component) -> String {
        switch component.kind.dcRole {
        case .voltageSource: return "+\(component.nodeA)  −\(component.nodeB)"
        case .currentSource: return "\(component.nodeA) → \(component.nodeB)"
        case .resistor, .open, .short: return "\(component.nodeA) — \(component.nodeB)"
        }
    }
}

/// One-time ask to share scans and usage; both stay off unless the user says yes. Saying yes
/// pays the sharing reward, and the callback receives how many bonus scans that was.
private struct ConsentCard: View {
    let onDone: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text("Help the reader learn, get \(ScanCredits.Reason.sharing.reward) bonus scans")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(PMTheme.ink)
                Spacer(minLength: 0)
                Text("+\(ScanCredits.Reason.sharing.reward)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(PMTheme.plusOrange))
            }
            Text("Share your scans and the corrections you make, plus anonymous usage statistics. No account, no names; the pictures are used only to improve recognition. You get \(ScanCredits.Reason.sharing.reward) bonus scans now and more each time you fix a misread circuit or rate a walkthrough. Change it any time in Settings → Privacy & data.")
                .font(.system(size: 13))
                .foregroundStyle(PMTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Not now") {
                    AnalyticsConsent.asked = true
                    onDone(0)
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(PMTheme.secondaryText)
                Spacer()
                Button("Share and earn") {
                    AnalyticsConsent.usage = true
                    AnalyticsConsent.scans = true
                    AnalyticsConsent.asked = true
                    Analytics.shared.track("consent_granted", ["from": .string("solve")])
                    onDone(ScanCredits.award(.sharing))
                }
                .buttonStyle(PMPrimaryButtonStyle())
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: PMTheme.cardRadius, style: .continuous).fill(Color.white))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// "+2 bonus scans for the fix. Thank you!" above the cards.
private struct RewardNote: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(PMTheme.plusOrange)
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PMTheme.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
    }
}
