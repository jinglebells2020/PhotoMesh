import SwiftUI

/// Step-by-step walkthrough revealed one step at a time with "Next Step".
struct SolvingStepsView: View {
    let solution: Solution

    @State private var revealedCount = 1
    @State private var expandedIndex: Int? = 0
    @State private var whyIndex: Int?
    @State private var feedback: Bool?

    private var isComplete: Bool { revealedCount > solution.steps.count }

    var body: some View {
        ZStack(alignment: .bottom) {
            PMTheme.groupedBackground.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(solution.steps.enumerated()), id: \.offset) { index, step in
                            if index < revealedCount {
                                StepRow(
                                    step: step,
                                    isExpanded: expandedIndex == index,
                                    showsWhy: whyIndex == index,
                                    onToggle: {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                            expandedIndex = (expandedIndex == index) ? nil : index
                                            whyIndex = nil
                                        }
                                    },
                                    onWhy: {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            whyIndex = (whyIndex == index) ? nil : index
                                        }
                                    }
                                )
                                .id("step-\(index)")
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }

                        if isComplete {
                            SolutionRow(result: solution.result)
                                .id("solution")
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            FeedbackRow(feedback: $feedback)
                                .padding(.top, 26)
                        }
                    }
                    .padding(.bottom, 130)
                }
                .onChange(of: revealedCount) { _, count in
                    withAnimation {
                        proxy.scrollTo(isComplete ? "solution" : "step-\(count - 1)", anchor: .bottom)
                    }
                }
            }

            bottomBar
        }
        .navigationTitle("Solving Steps")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(PMTheme.groupedBackground, for: .navigationBar)
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
                        feedback = nil
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
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        revealedCount += 1
                        expandedIndex = isComplete ? nil : revealedCount - 1
                        whyIndex = nil
                    }
                } label: {
                    Text("Next Step")
                }
                .buttonStyle(PMPrimaryButtonStyle())
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.bottom, 16)
        .padding(.top, 10)
        .background(alignment: .top) {
            LinearGradient(colors: [PMTheme.groupedBackground.opacity(0), PMTheme.groupedBackground], startPoint: .top, endPoint: .bottom)
                .frame(height: 110)
                .offset(y: -20)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Rows

private struct StepRow: View {
    let step: SolutionStep
    let isExpanded: Bool
    let showsWhy: Bool
    let onToggle: () -> Void
    let onWhy: () -> Void

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
                        Text(step.expression)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(PMTheme.ink)
                        Text(step.description)
                            .font(.system(size: 14))
                            .foregroundStyle(PMTheme.secondaryText)
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
                Text(step.expression)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(PMTheme.ink)
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
            .padding(.top, 8)
            .padding(.leading, 12)

            if showsWhy {
                Text(step.description)
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
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(PMTheme.ink)
                Spacer()
                Image(systemName: "arrow.down")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(PMTheme.ink)
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(Color.white)
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}

private struct SolutionRow: View {
    let result: String

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(PMTheme.accent)
                .frame(width: 5)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Solution")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(PMTheme.accent)
                    Spacer()
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(PMTheme.ink)
                }
                Text(result)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(PMTheme.ink)
            }
            .padding(.leading, 15)
            .padding(.trailing, 20)
            .padding(.vertical, 18)
        }
        .background(Color.white)
    }
}

private struct FeedbackRow: View {
    @Binding var feedback: Bool?

    var body: some View {
        VStack(spacing: 14) {
            Text("Did this explanation help you?")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PMTheme.ink)
            HStack(spacing: 44) {
                feedbackButton(isPositive: true)
                feedbackButton(isPositive: false)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func feedbackButton(isPositive: Bool) -> some View {
        Button {
            Haptics.impact(.light)
            feedback = isPositive
        } label: {
            Image(systemName: isPositive ? "hand.thumbsup" : "hand.thumbsdown")
                .symbolVariant(feedback == isPositive ? .fill : .none)
                .font(.system(size: 22))
                .foregroundStyle(feedback == isPositive ? PMTheme.accent : PMTheme.ink)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        SolvingStepsView(solution: MockCircuitSolver.seriesLoop)
    }
}
