import SwiftUI

/// The course home: modules in order, progress, and the way into each lesson.
struct CourseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var progress = CourseProgress.shared
    @State private var path: [Lesson] = []

    private var totalLessons: Int { Course.modules.reduce(0) { $0 + $1.lessons.count } }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .topTrailing) {
                PMTheme.darkSheet.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Learn circuits")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.top, 58)
                        Text("Starts from water in pipes, with no formulas, and builds up to the full first-year circuits course. Every example is solved and animated by Photocircuits' own engine.")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.white.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)

                        summary

                        ForEach(Course.modules) { module in
                            ModuleCard(module: module, completed: progress.completed(in: module)) { lesson in
                                path.append(lesson)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
                PMCloseButton { dismiss() }
                    .padding(.top, 14)
                    .padding(.trailing, 16)
            }
            .navigationTitle("Learn")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Lesson.self) { lesson in
                LessonView(lesson: lesson) { next in
                    path.append(next)
                }
            }
        }
        .onAppear { Analytics.shared.track("course_opened") }
    }

    private var summary: some View {
        HStack(spacing: 14) {
            ProgressRing(fraction: totalLessons == 0 ? 0 : Double(progress.completedCount) / Double(totalLessons))
                .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(progress.completedCount) of \(totalLessons) lessons done")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                if let lastId = progress.lastLessonId, let lesson = Course.lesson(withId: lastId) {
                    Button {
                        path.append(lesson)
                    } label: {
                        Text("Continue: \(lesson.title) →")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(PMTheme.plusOrange)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Start with Water and wires; every lesson ends with a short quiz.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: PMTheme.cardRadius, style: .continuous).fill(Color.white.opacity(0.08)))
    }
}

struct ProgressRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.18), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0.001, min(fraction, 1)))
                .stroke(PMTheme.plusOrange, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((fraction * 100).rounded()))%")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

/// One chapter with its lessons listed; locked lessons show the lock and open the paywall.
private struct ModuleCard: View {
    let module: CourseModule
    let completed: Int
    let open: (Lesson) -> Void
    @State private var expanded = false
    @State private var presentingPaywall = false
    @State private var progress = CourseProgress.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { expanded.toggle() }
                Haptics.selection()
            } label: {
                HStack(alignment: .top, spacing: 14) {
                    Text("\(module.number)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(PMTheme.accent))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(module.title)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(PMTheme.ink)
                            if !module.isFree && !PlusAccess.hasPlus { PlusTag() }
                        }
                        Text(module.subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(PMTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(completed) of \(module.lessons.count) lessons · \(module.lessons.reduce(0) { $0 + $1.minutes }) min")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(completed == module.lessons.count ? PMTheme.accent : PMTheme.tertiaryText)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PMTheme.tertiaryText)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Divider().padding(.horizontal, 16)
                ForEach(Array(module.lessons.enumerated()), id: \.element.id) { index, lesson in
                    let unlocked = Course.isUnlocked(lesson, in: module)
                    Button {
                        if unlocked {
                            open(lesson)
                        } else {
                            PlusAccess.notedLockedTap(.course)
                            presentingPaywall = true
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: progress.isCompleted(lesson) ? "checkmark.circle.fill" : (unlocked ? "play.circle" : "lock.fill"))
                                .font(.system(size: 17))
                                .foregroundStyle(progress.isCompleted(lesson) ? PMTheme.accent : (unlocked ? PMTheme.ink : PMTheme.plusOrange))
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(module.number).\(index + 1)  \(lesson.title)")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(unlocked ? PMTheme.ink : PMTheme.secondaryText)
                                HStack(spacing: 6) {
                                    Text("\(lesson.minutes) min · \(lesson.quiz.count) questions")
                                    if let best = progress.bestScore(lesson) { Text("· best \(best.score)/\(best.total)") }
                                }
                                .font(.system(size: 12))
                                .foregroundStyle(PMTheme.tertiaryText)
                            }
                            Spacer()
                            if !unlocked && index == 0 { Text("preview").font(.system(size: 11)).foregroundStyle(PMTheme.tertiaryText) }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(PMTheme.tertiaryText)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 8)
            }
        }
        .background(RoundedRectangle(cornerRadius: PMTheme.cardRadius, style: .continuous).fill(Color.white))
        .sheet(isPresented: $presentingPaywall) { PlusSheet() }
    }
}

// MARK: - Lesson

/// Scenes as horizontal pages, the quiz on the last one.
struct LessonView: View {
    let lesson: Lesson
    let openNext: (Lesson) -> Void
    @State private var page = 0
    @State private var progress = CourseProgress.shared

    private var pageCount: Int { lesson.scenes.count + 1 }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(lesson.scenes.enumerated()), id: \.offset) { index, scene in
                    ScrollView(showsIndicators: false) {
                        SceneCard(scene: scene, index: index, count: lesson.scenes.count)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 24)
                    }
                    .tag(index)
                }
                ScrollView(showsIndicators: false) {
                    QuizView(lesson: lesson, next: Course.next(after: lesson).flatMap { next in
                        Course.module(containing: next).flatMap { Course.isUnlocked(next, in: $0) ? next : nil }
                    }, openNext: openNext)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                }
                .tag(lesson.scenes.count)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.25), value: page)

            pager
        }
        .background(PMTheme.groupedBackground.ignoresSafeArea())
        .navigationTitle(lesson.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(PMTheme.groupedBackground, for: .navigationBar)
        .onAppear {
            progress.markOpened(lesson)
            Analytics.shared.track("lesson_opened", ["lesson": .string(lesson.id)])
        }
    }

    private var pager: some View {
        HStack {
            Button {
                Haptics.impact(.light)
                page = max(0, page - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 48, height: 44)
                    .background(Capsule().fill(Color.white))
            }
            .disabled(page == 0)
            .opacity(page == 0 ? 0.4 : 1)
            Spacer()
            HStack(spacing: 5) {
                ForEach(0..<pageCount, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? PMTheme.accent : PMTheme.chipBorder)
                        .frame(width: i == page ? 18 : 6, height: 6)
                }
            }
            Spacer()
            Button {
                Haptics.impact(.light)
                page = min(pageCount - 1, page + 1)
            } label: {
                HStack(spacing: 6) {
                    Text(page == pageCount - 2 ? "Quiz" : (page == pageCount - 1 ? "Done" : "Next"))
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 18)
                .frame(height: 44)
                .background(Capsule().fill(page == pageCount - 1 ? Color.white : PMTheme.accent))
                .foregroundStyle(page == pageCount - 1 ? PMTheme.ink : .white)
            }
            .disabled(page == pageCount - 1)
        }
        .foregroundStyle(PMTheme.ink)
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// One scene: the moving picture, the words, the formula.
private struct SceneCard: View {
    let scene: LessonScene
    let index: Int
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(index + 1) / \(count)")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(PMTheme.tertiaryText)
            Text(scene.title)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(PMTheme.ink)
            illustration
            Text(scene.body)
                .font(.system(size: 15.5))
                .foregroundStyle(PMTheme.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if !scene.analogy.isEmpty {
                AnalogyMap(pairs: scene.analogy)
            }
            if let formula = scene.formula {
                ScrollView(.horizontal, showsIndicators: false) {
                    MathText(latex: formula, fallback: scene.formulaText ?? formula, fontSize: 18, color: PMTheme.accent)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(PMTheme.accentSoft))
            }
            if let remember = scene.remember {
                RememberBox(text: remember)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: PMTheme.cardRadius, style: .continuous).fill(Color.white))
    }

    @ViewBuilder
    private var illustration: some View {
        switch scene.illustration {
        case .none:
            EmptyView()
        case .circuit(let spec):
            CircuitDemoView(spec: spec)
                .frame(height: 250)
        case .steps(let spec, let method):
            StepsDemoView(spec: spec, method: method)
        case .transient(let spec, let traces, let switchAt):
            TransientDemoView(spec: spec, traces: traces, switchAt: switchAt)
        case .concept(let kind):
            ConceptAnimationView(kind: kind)
                .frame(height: 230)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.black.opacity(0.08)))
        }
    }
}

/// The water-to-electricity map: what the water picture is called in electrical words.
private struct AnalogyMap: View {
    let pairs: [AnalogyPair]
    private static let water = Color(red: 0.16, green: 0.47, blue: 0.86)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Label("WATER", systemImage: "drop.fill")
                    .foregroundStyle(AnalogyMap.water)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Label("ELECTRICITY", systemImage: "bolt.fill")
                    .foregroundStyle(PMTheme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 11, weight: .bold))
            .kerning(0.5)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            ForEach(Array(pairs.enumerated()), id: \.offset) { index, pair in
                Divider().opacity(0.6)
                HStack(alignment: .top, spacing: 10) {
                    Text(pair.water)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(pair.electric)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 14))
                .foregroundStyle(PMTheme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(index % 2 == 1 ? Color.black.opacity(0.025) : Color.clear)
            }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AnalogyMap.water.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AnalogyMap.water.opacity(0.18)))
    }
}

/// The one sentence to keep from a scene.
private struct RememberBox: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PMTheme.whyOrange)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text("REMEMBER")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(0.6)
                    .foregroundStyle(PMTheme.whyOrange)
                Text(text)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(PMTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(PMTheme.whyOrange.opacity(0.1)))
    }
}

// MARK: - Quiz

/// Multiple choice with an explanation after every answer; the score marks the lesson done.
private struct QuizView: View {
    let lesson: Lesson
    let next: Lesson?
    let openNext: (Lesson) -> Void
    @State private var current = 0
    @State private var chosen: Int?
    @State private var score = 0
    @State private var finished = false
    @State private var progress = CourseProgress.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("QUIZ")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(PMTheme.tertiaryText)
            if lesson.quiz.isEmpty {
                Text("No quiz for this lesson.")
                    .font(.system(size: 15))
                    .foregroundStyle(PMTheme.secondaryText)
                    .onAppear { progress.recordQuiz(lesson, score: 0, total: 0) }
            } else if finished {
                results
            } else {
                question(lesson.quiz[current])
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: PMTheme.cardRadius, style: .continuous).fill(Color.white))
    }

    private func question(_ q: QuizQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Question \(current + 1) of \(lesson.quiz.count)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PMTheme.secondaryText)
            Text(q.prompt)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(PMTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(q.options.enumerated()), id: \.offset) { index, option in
                Button {
                    guard chosen == nil else { return }
                    chosen = index
                    if index == q.answer {
                        score += 1
                        Haptics.notify(.success)
                    } else {
                        Haptics.notify(.error)
                    }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon(for: index, in: q))
                            .font(.system(size: 16))
                            .foregroundStyle(color(for: index, in: q))
                            .frame(width: 22)
                        Text(option)
                            .font(.system(size: 15))
                            .foregroundStyle(PMTheme.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(background(for: index, in: q)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if chosen != nil {
                Text(q.explanation)
                    .font(.system(size: 14))
                    .foregroundStyle(PMTheme.ink)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(PMTheme.whyOrange.opacity(0.12)))
                    .fixedSize(horizontal: false, vertical: true)
                Button(current == lesson.quiz.count - 1 ? "See the result" : "Next question") {
                    Haptics.impact(.light)
                    if current == lesson.quiz.count - 1 {
                        finished = true
                        progress.recordQuiz(lesson, score: score, total: lesson.quiz.count)
                    } else {
                        current += 1
                        chosen = nil
                    }
                }
                .buttonStyle(PMPrimaryButtonStyle(fillsWidth: true))
                .padding(.top, 4)
            }
        }
        .animation(.easeOut(duration: 0.2), value: chosen)
    }

    private func icon(for index: Int, in q: QuizQuestion) -> String {
        guard let chosen else { return "circle" }
        if index == q.answer { return "checkmark.circle.fill" }
        if index == chosen { return "xmark.circle.fill" }
        return "circle"
    }

    private func color(for index: Int, in q: QuizQuestion) -> Color {
        guard let chosen else { return PMTheme.tertiaryText }
        if index == q.answer { return PMTheme.accent }
        if index == chosen { return Color(red: 0.86, green: 0.22, blue: 0.2) }
        return PMTheme.tertiaryText
    }

    private func background(for index: Int, in q: QuizQuestion) -> Color {
        guard let chosen else { return PMTheme.groupedBackground }
        if index == q.answer { return PMTheme.accentSoft }
        if index == chosen { return Color(red: 0.86, green: 0.22, blue: 0.2).opacity(0.1) }
        return PMTheme.groupedBackground
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(score == lesson.quiz.count ? "Perfect!" : (score >= lesson.quiz.count / 2 ? "Well done" : "Worth another look"))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(PMTheme.ink)
            Text("\(score) of \(lesson.quiz.count) correct. The lesson is marked as done; you can come back to it any time.")
                .font(.system(size: 15))
                .foregroundStyle(PMTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let next {
                Button {
                    Haptics.impact(.light)
                    openNext(next)
                } label: {
                    HStack(spacing: 8) {
                        Text("Next lesson: \(next.title)")
                            .lineLimit(1)
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(PMPrimaryButtonStyle(fillsWidth: true))
            } else if Course.next(after: lesson) != nil {
                PlusLockCard(feature: .course, compact: true)
            } else {
                Text("That was the last lesson of the course. Scan or draw a circuit and try the methods for yourself.")
                    .font(.system(size: 14))
                    .foregroundStyle(PMTheme.ink)
            }
            Button("Try the quiz again") {
                current = 0
                chosen = nil
                score = 0
                finished = false
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(PMTheme.accent)
        }
    }
}
