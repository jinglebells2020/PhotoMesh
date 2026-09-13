import SwiftUI

/// Bottom sheet: Cancel / Language / Done with a check-marked list.
struct LanguageSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.language) private var languageCode = "en"
    @State private var draft: String

    init() {
        _draft = State(initialValue: UserDefaults.standard.string(forKey: SettingsKeys.language) ?? "en")
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Language")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(PMTheme.ink)
                HStack {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 17))
                        .foregroundStyle(PMTheme.accent)
                    Spacer()
                    Button("Done") {
                        languageCode = draft
                        dismiss()
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(PMTheme.accent)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 54)

            Divider()

            List(AppLanguage.all) { language in
                Button {
                    Haptics.selection()
                    draft = language.code
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(language.nativeName)
                                .font(.system(size: 17))
                                .foregroundStyle(PMTheme.ink)
                            Text(language.englishName)
                                .font(.system(size: 12))
                                .foregroundStyle(PMTheme.secondaryText)
                        }
                        Spacer()
                        if language.code == draft {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(PMTheme.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            }
            .listStyle(.plain)
        }
        .background(Color.white)
    }
}

#Preview {
    LanguageSheet()
}
