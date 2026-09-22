import SwiftUI

struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DeveloperOptions.unlockedKey) private var developerUnlocked = false
    @State private var versionTaps = 0
    @State private var unlockMessage: String?

    /// Seven taps on the version reveal the developer rows in Settings (API key, models, allowance reset).
    private func versionTapped() {
        versionTaps += 1
        guard versionTaps >= 7 else { return }
        versionTaps = 0
        developerUnlocked.toggle()
        Haptics.notify(.success)
        unlockMessage = developerUnlocked ? "Developer options unlocked in Settings → Recognition." : "Developer options hidden again."
    }

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        PMLogoMark(size: 76)
                        PMWordmark(size: 28)
                        Text(version)
                            .font(.system(size: 13))
                            .foregroundStyle(PMTheme.secondaryText)
                            .contentShape(Rectangle())
                            .onTapGesture { versionTapped() }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                }

                Section {
                    Text("Photocircuits turns a photo of a circuit into a clear, step-by-step analysis. Point the camera at a schematic or a hand-drawn loop, and follow each step the way you would in class.")
                        .font(.system(size: 15))
                        .foregroundStyle(PMTheme.ink)
                }

                Section {
                    // Placeholder destinations until the marketing site exists.
                    Link("Terms of Service", destination: URL(string: "https://photomesh.app/terms")!)
                    Link("Privacy Policy", destination: URL(string: "https://photomesh.app/privacy")!)
                    Link("Contact us", destination: URL(string: "mailto:hello@photomesh.app")!)
                }
                .foregroundStyle(PMTheme.ink)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("About us")
            .navigationBarTitleDisplayMode(.inline)
            .alert(unlockMessage ?? "", isPresented: Binding(get: { unlockMessage != nil }, set: { if !$0 { unlockMessage = nil } })) {
                Button("OK", role: .cancel) {}
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(PMTheme.accent)
                }
            }
        }
    }
}

#Preview {
    AboutSheet()
}
