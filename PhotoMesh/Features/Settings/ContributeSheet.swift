import SwiftUI

/// "Help & bonus scans": the one place that explains the program, shows the balance and the ways
/// to earn, hosts the questionnaire, and lets people see or delete what they have shared. Reached
/// from the side menu, from Settings → Privacy & data, and from the "limit reached" card.
struct ContributeSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContributeView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
        }
        .tint(PMTheme.accent)
    }
}

struct ContributeView: View {
    @AppStorage("analytics.usage") private var shareUsage = false
    @AppStorage("analytics.scans") private var shareScans = false
    @State private var balance = ScanCredits.balance
    @State private var summary = Analytics.shared.summary()
    @State private var feedbackCount = FeedbackStore.all().count
    @State private var confirmForget = false
    @State private var forgetting = false
    @State private var forgetNote: String?
    @State private var toast: String?

    var body: some View {
        List {
            Section {
                balanceCard
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Section {
                sharingRow
                NavigationLink {
                    SurveyView { granted in note(granted) }
                } label: {
                    EarnRow(reason: .survey, status: status(.survey))
                }
                EarnRow(reason: .feedback, status: status(.feedback))
                EarnRow(reason: .correction, status: status(.correction))
            } header: {
                Text("WAYS TO EARN")
            } footer: {
                Text("Bonus scans are spent only once the month's \(UsageAllowance.monthlyLimit) free scans are used up, and up to \(ScanCredits.bankLimit) can be banked. The daily caps keep it fair for everyone.")
            }

            Section {
                row("Scans shared", sharedText)
                row("Circuits corrected", "\(ScanCredits.awardsTotal(.correction))")
                row("Walkthroughs rated", "\(feedbackCount)")
                row("Bonus scans earned", "\(ScanCredits.earnedTotal)")
                row("Bonus scans used", "\(ScanCredits.spentTotal)")
            } header: {
                Text("YOUR CONTRIBUTIONS")
            }

            Section {
                NavigationLink {
                    DataView()
                } label: {
                    Text("Collected data").foregroundStyle(PMTheme.ink)
                }
                Link(destination: URL(string: "https://photomesh.app/privacy")!) {
                    Text("Privacy policy")
                }
                Button(role: .destructive) {
                    confirmForget = true
                } label: {
                    HStack {
                        Text("Delete my shared data")
                        if forgetting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(forgetting)
                if let forgetNote {
                    Text(forgetNote)
                        .font(.system(size: 12))
                        .foregroundStyle(PMTheme.secondaryText)
                }
            } header: {
                Text("YOUR DATA")
            } footer: {
                Text("No account, no names: a random install id groups what you share. Deleting removes everything on this device, asks our server to erase what it holds for that id, and starts a new id.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Help & bonus scans")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: ScanCredits.didChange)) { _ in refresh() }
        .confirmationDialog("Delete everything you shared?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Delete on this device and on the server", role: .destructive) { forget() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Bonus scans you already earned stay with you.")
        }
        .overlay(alignment: .bottom) {
            if let toast {
                ToastPill(text: toast)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toast)
    }

    // MARK: Pieces

    private var balanceCard: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(balance)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(PMTheme.accent)
                Text(balance == 1 ? "bonus scan" : "bonus scans")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PMTheme.secondaryText)
            }
            .frame(minWidth: 96, alignment: .leading)
            Text(PlusAccess.hasPlus
                 ? "Plus has a far higher monthly cap, so these are pure thank-yous. Your feedback still shapes the app."
                 : "Spent by themselves once the month's free scans are used up, so a busy homework night never stops at the cap.")
                .font(.system(size: 13))
                .foregroundStyle(PMTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: PMTheme.cardRadius, style: .continuous).fill(Color.white))
    }

    private var sharingRow: some View {
        Toggle(isOn: $shareScans) {
            EarnRow(reason: .sharing, status: status(.sharing))
        }
        .tint(PMTheme.accent)
        .onChange(of: shareScans) { _, on in
            if on {
                shareUsage = true
                AnalyticsConsent.asked = true
                Analytics.shared.track("consent_granted", ["from": .string("contribute")])
                note(ScanCredits.award(.sharing))
            } else {
                Analytics.shared.track("consent_revoked", ["what": .string("scans")])
            }
            refresh()
        }
    }

    private func status(_ reason: ScanCredits.Reason) -> String {
        if let cap = reason.dailyCap {
            let today = ScanCredits.awardsToday(reason)
            return today >= cap ? "Daily cap reached, more tomorrow" : "\(today) of \(cap) rewarded today"
        }
        return ScanCredits.canAward(reason) ? "Available" : "Done. Thank you!"
    }

    private var sharedText: String {
        let sent = summary.uploadedSamples
        let waiting = summary.samples
        if waiting == 0 { return "\(sent)" }
        return "\(sent) sent · \(waiting) waiting"
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(PMTheme.ink)
            Spacer()
            Text(value).foregroundStyle(PMTheme.secondaryText).font(.system(size: 15, design: .rounded))
        }
    }

    // MARK: Actions

    private func refresh() {
        balance = ScanCredits.balance
        summary = Analytics.shared.summary()
        feedbackCount = FeedbackStore.all().count
    }

    private func note(_ granted: Int) {
        guard granted > 0 else { return }
        Haptics.notify(.success)
        toast = "+\(granted) bonus scans. Thank you!"
        refresh()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.6))
            toast = nil
        }
    }

    private func forget() {
        forgetting = true
        forgetNote = nil
        Analytics.shared.forget { serverDone in
            forgetting = false
            forgetNote = serverDone
                ? "Deleted here and on the server. A new install id is in use."
                : "Deleted on this device. The server could not be reached; the request will be honoured when you email us your old install id."
            Analytics.shared.track("data_forgotten", ["server": .bool(serverDone)])
            refresh()
        }
    }
}

/// One way to earn: what to do, what it pays, and where the person stands.
private struct EarnRow: View {
    let reason: ScanCredits.Reason
    let status: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: reason.systemImage)
                .font(.system(size: 18))
                .foregroundStyle(PMTheme.accent)
                .frame(width: 26)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(reason.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(PMTheme.ink)
                    Text("+\(reason.reward)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(PMTheme.plusOrange))
                }
                Text(reason.detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(PMTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(status)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PMTheme.accent)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ToastPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(PMTheme.accent))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
    }
}

// MARK: - Survey

/// Five questions, answered once; stored on the device and sent with the feedback stream.
enum Survey {
    private static let completedKey = "survey.completedAt"
    private static let answersKey = "survey.answers"

    static let roles = ["Student", "Teacher or tutor", "Engineer or technician", "Hobbyist or maker", "Other"]
    static let stages = ["First circuits course", "Later years or graduate", "Exam preparation", "Self-taught", "Not studying"]
    static let uses = ["Checking homework answers", "Learning the method step by step", "Teaching or grading", "Quick calculations at work", "Curiosity"]

    static var isCompleted: Bool { UserDefaults.standard.double(forKey: completedKey) > 0 }

    static func complete(role: String, stage: String, uses: [String], wish: String, nps: Int) {
        let answers: [String: JSONValue] = [
            "role": .string(role), "stage": .string(stage), "uses": .string(uses.joined(separator: "|")),
            "wish": .string(String(wish.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))), "nps": .init(nps),
        ]
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: completedKey)
        if let data = try? JSONEncoder().encode(answers) { UserDefaults.standard.set(data, forKey: answersKey) }
        Analytics.shared.submit("survey", answers)
    }
}

struct SurveyView: View {
    var onSubmitted: (Int) -> Void = { _ in }

    @State private var role: String?
    @State private var stage: String?
    @State private var uses: Set<String> = []
    @State private var wish = ""
    @State private var nps: Int?
    @State private var done = Survey.isCompleted
    @State private var granted = 0
    @FocusState private var wishFocused: Bool

    private var canSubmit: Bool { role != nil && stage != nil && !uses.isEmpty && nps != nil }

    var body: some View {
        List {
            if done {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Thank you!")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(PMTheme.ink)
                        Text(granted > 0 ? "+\(granted) bonus scans added. Your answers decide what gets built next." : "Your answers are in. They decide what gets built next.")
                            .font(.system(size: 14))
                            .foregroundStyle(PMTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 6)
                }
            } else {
                single("1. Which describes you best?", Survey.roles, selection: $role)
                single("2. Where are you with circuits?", Survey.stages, selection: $stage)
                multiple("3. What do you mostly use Photocircuits for?", Survey.uses, selection: $uses)
                Section {
                    TextField("Optional: a feature, a circuit type, anything", text: $wish, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($wishFocused)
                } header: {
                    Text("4. What would make you use it more?")
                }
                Section {
                    npsRow
                } header: {
                    Text("5. How likely are you to recommend it to a classmate or colleague?")
                }
                Section {
                    Button("Send answers") { submit() }
                        .buttonStyle(PMPrimaryButtonStyle())
                        .disabled(!canSubmit)
                        .opacity(canSubmit ? 1 : 0.5)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Five questions")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
    }

    private func single(_ title: String, _ options: [String], selection: Binding<String?>) -> some View {
        Section {
            ForEach(options, id: \.self) { option in
                Button {
                    Haptics.selection()
                    selection.wrappedValue = option
                } label: {
                    HStack {
                        Text(option).foregroundStyle(PMTheme.ink)
                        Spacer()
                        if selection.wrappedValue == option {
                            Image(systemName: "checkmark").foregroundStyle(PMTheme.accent).fontWeight(.semibold)
                        }
                    }
                }
            }
        } header: {
            Text(title)
        }
    }

    private func multiple(_ title: String, _ options: [String], selection: Binding<Set<String>>) -> some View {
        Section {
            ForEach(options, id: \.self) { option in
                Button {
                    Haptics.selection()
                    if selection.wrappedValue.contains(option) {
                        selection.wrappedValue.remove(option)
                    } else {
                        selection.wrappedValue.insert(option)
                    }
                } label: {
                    HStack {
                        Text(option).foregroundStyle(PMTheme.ink)
                        Spacer()
                        Image(systemName: selection.wrappedValue.contains(option) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(selection.wrappedValue.contains(option) ? PMTheme.accent : PMTheme.tertiaryText)
                    }
                }
            }
        } header: {
            Text(title)
        } footer: {
            Text("Pick all that apply.")
        }
    }

    private var npsRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0...10, id: \.self) { n in
                    Button {
                        Haptics.selection()
                        nps = n
                    } label: {
                        Text("\(n)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(nps == n ? .white : PMTheme.ink)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(nps == n ? PMTheme.accent : PMTheme.groupedBackground))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Text("Not likely")
                Spacer()
                Text("Very likely")
            }
            .font(.system(size: 11))
            .foregroundStyle(PMTheme.secondaryText)
        }
        .padding(.vertical, 4)
    }

    private func submit() {
        guard let role, let stage, let nps else { return }
        wishFocused = false
        Survey.complete(role: role, stage: stage, uses: Survey.uses.filter { uses.contains($0) }, wish: wish, nps: nps)
        granted = ScanCredits.award(.survey)
        Haptics.notify(.success)
        withAnimation { done = true }
        onSubmitted(granted)
    }
}
