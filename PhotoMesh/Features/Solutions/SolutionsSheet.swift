import SwiftUI

enum SolutionDestination: Hashable {
    case steps(Solution)
    case circuit(Solution)
}

/// Dark results sheet with white solution cards, like Photomath's "Solutions".
struct SolutionsSheet: View {
    let request: SolutionRequest
    @Environment(\.dismiss) private var dismiss

    private enum LoadState {
        case loading
        case loaded(Solution)
        case failed
    }

    @State private var state: LoadState = .loading

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
                            LoadingCard()
                        case .failed:
                            FailedCard { Task { await load() } }
                        case .loaded(let solution):
                            SolutionCard(solution: solution, request: request)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            if let detail = solution.detail {
                                CircuitCard(solution: solution, detail: detail)
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
                case .steps(let solution):
                    SolvingStepsView(solution: solution)
                case .circuit(let solution):
                    CircuitDetailView(solution: solution)
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        state = .loading
        do {
            let solution = try await SolverProvider.current.solve(request)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                state = .loaded(solution)
            }
            Haptics.notify(.success)
        } catch {
            state = .failed
        }
    }
}

// MARK: - Cards

private struct SolutionCard: View {
    let solution: Solution
    let request: SolutionRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(solution.category)
                .font(.system(size: 12, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(PMTheme.secondaryText)
            Text(solution.title)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(PMTheme.ink)
                .padding(.top, 4)

            HStack(alignment: .top, spacing: 12) {
                if case .image(let image) = request.source {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 130)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.black.opacity(0.08)))
                } else {
                    Text(solution.problem)
                        .font(.system(size: 18))
                        .foregroundStyle(PMTheme.ink)
                }
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
                Text(solution.approach)
                    .font(.system(size: 14))
                    .foregroundStyle(PMTheme.secondaryText)
            }
            .padding(.top, 12)

            HStack(spacing: 0) {
                Rectangle()
                    .fill(PMTheme.accent)
                    .frame(width: 4)
                Text(solution.result)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(PMTheme.ink)
                    .padding(.leading, 12)
                    .padding(.vertical, 12)
            }
            .padding(.leading, -16)
            .padding(.top, 14)

            HStack {
                Spacer()
                NavigationLink(value: SolutionDestination.steps(solution)) {
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

private struct CircuitCard: View {
    let solution: Solution
    let detail: CircuitDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CIRCUIT")
                .font(.system(size: 12, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(PMTheme.secondaryText)
            Text(detail.title)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(PMTheme.ink)
                .padding(.top, 4)

            CircuitSketchView(kind: detail.sketch)
                .frame(height: 190)
                .padding(.top, 12)

            HStack {
                Spacer()
                NavigationLink(value: SolutionDestination.circuit(solution)) {
                    HStack(spacing: 10) {
                        Text("Explore Circuit")
                        Image(systemName: "arrow.right").font(.system(size: 16, weight: .semibold))
                    }
                }
                .buttonStyle(PMPrimaryButtonStyle())
                Spacer()
            }
            .padding(.top, 16)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: PMTheme.cardRadius, style: .continuous).fill(Color.white))
    }
}

private struct LoadingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ANALYZING")
                .font(.system(size: 12, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(PMTheme.secondaryText)
            HStack(spacing: 12) {
                ProgressView().tint(PMTheme.accent)
                Text("Reading the circuit…")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(PMTheme.ink)
            }
            SkeletonLine(width: 0.9)
            SkeletonLine(width: 0.6)
            SkeletonLine(width: 0.75)
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
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Something went wrong")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(PMTheme.ink)
            Text("We couldn't analyze this picture. Check your connection and try again.")
                .font(.system(size: 15))
                .foregroundStyle(PMTheme.secondaryText)
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
