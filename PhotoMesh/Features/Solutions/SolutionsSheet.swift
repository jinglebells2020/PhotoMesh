import SwiftUI

enum SolutionDestination: Hashable {
    case steps(MethodSolution, question: String)
    case circuit(CircuitAnalysis)
}

/// Dark results sheet. One white card per solving method so the user picks which to follow,
/// plus a card describing what the reader recognized.
struct SolutionsSheet: View {
    let request: SolutionRequest
    @Environment(\.dismiss) private var dismiss

    private enum LoadState {
        case loading
        case loaded(CircuitAnalysis)
        case failed(String)
    }

    @State private var state: LoadState = .loading
    @State private var phase = "Reading the circuit…"

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

                        switch state {
                        case .loading:
                            LoadingCard(phase: phase, image: sourceImage)
                        case .failed(let message):
                            FailedCard(message: message) { Task { await load() } }
                        case .loaded(let analysis):
                            ForEach(analysis.methods) { method in
                                MethodCard(method: method, analysis: analysis, request: request)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                            if analysis.circuit != nil {
                                RecognizedCircuitCard(analysis: analysis, image: sourceImage)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 36)
                }

                PMCloseButton { dismiss() }
                    .padding(.top, 14)
                    .padding(.trailing, 16)
            }
            .navigationTitle("Solutions")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SolutionDestination.self) { destination in
                switch destination {
                case .steps(let method, let question):
                    SolvingStepsView(solution: method, question: question)
                case .circuit(let analysis):
                    CircuitDetailView(analysis: analysis)
                }
            }
        }
        .task { await load() }
    }

    private var sourceImage: UIImage? {
        if case .image(let image) = request.source { return image }
        return nil
    }

    private func load() async {
        state = .loading
        phase = "Reading the circuit…"
        let solver = SolverProvider.make()
        do {
            let analysis = try await solver.solve(request) { text in
                Task { @MainActor in phase = text }
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                state = .loaded(analysis)
            }
            Haptics.notify(.success)
        } catch {
            Haptics.notify(.error)
            state = .failed(error.localizedDescription)
        }
    }
}

// MARK: - Cards

private struct MethodCard: View {
    let method: MethodSolution
    let analysis: CircuitAnalysis
    let request: SolutionRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(method.method.eyebrow)
                .font(.system(size: 12, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(PMTheme.secondaryText)
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
                NavigationLink(value: SolutionDestination.steps(method, question: analysis.question)) {
                    HStack(spacing: 10) {
                        Text("Show Solving Steps")
                        Image(systemName: "arrow.right").font(.system(size: 16, weight: .semibold))
                    }
                }
                .buttonStyle(PMPrimaryButtonStyle())
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RECOGNIZED CIRCUIT")
                .font(.system(size: 12, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(PMTheme.secondaryText)
            if let circuit = analysis.circuit {
                Text(summary(for: circuit))
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(PMTheme.ink)
                    .padding(.top, 4)

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 150)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.black.opacity(0.08)))
                        .padding(.top, 14)
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
                    Text(analysis.methodsAgree ? "Nodal and mesh analysis agree" : "The methods disagree – check the recognized values")
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
                Spacer()
                NavigationLink(value: SolutionDestination.circuit(analysis)) {
                    HStack(spacing: 10) {
                        Text("Explore Circuit")
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
        FormattingPreferences.formatter().format(component.value, component.kind.unitSymbol)
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
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Couldn't solve this one")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(PMTheme.ink)
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(PMTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again", action: retry)
                .buttonStyle(PMPrimaryButtonStyle())
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: PMTheme.cardRadius, style: .continuous).fill(Color.white))
    }
}

#Preview {
    SolutionsSheet(request: SolutionRequest(source: .expression("12/320")))
}
