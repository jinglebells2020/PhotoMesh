import SwiftUI

struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

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
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                }

                Section {
                    Text("PhotoMesh turns a photo of a circuit into a clear, step-by-step analysis. Point the camera at a schematic or a hand-drawn loop, and follow each step the way you would in class.")
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
