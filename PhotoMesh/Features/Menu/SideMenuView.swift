import SwiftUI

/// The left drawer: logo header plus the five navigation rows.
struct SideMenuView: View {
    @Environment(AppRouter.self) private var router
    @AppStorage(SettingsKeys.language) private var languageCode = "en"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                PMLogoMark(size: 38)
                PMWordmark(size: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 28)
            .padding(.bottom, 22)

            Divider()

            VStack(spacing: 0) {
                MenuRow(icon: "globe", title: "Language", subtitle: AppLanguage.named(languageCode).englishName) {
                    router.present(.language)
                }
                MenuRow(icon: "gearshape", title: "Settings") {
                    router.closeMenuThenPresent(.settings)
                }
                MenuRow(icon: "graduationcap", title: "Learn circuits", subtitle: "The course, from water in pipes to phasors") {
                    router.closeMenuThenPresent(.course)
                }
                MenuRow(icon: "questionmark.circle", title: "Help center") {
                    router.closeMenuThenPresent(.help)
                }
                MenuRow(icon: "info.circle", title: "About us") {
                    router.closeMenuThenPresent(.about)
                }
                MenuRow(icon: "plus", title: "Photocircuits Plus", iconTint: PMTheme.plusOrange, iconWeight: .bold) {
                    router.closeMenuThenPresent(.plus)
                }
            }
            .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.ignoresSafeArea())
    }
}

private struct MenuRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var iconTint: Color = PMTheme.ink
    var iconWeight: Font.Weight = .regular
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: iconWeight))
                    .foregroundStyle(iconTint)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17))
                        .foregroundStyle(PMTheme.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(PMTheme.secondaryText)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: subtitle == nil ? 56 : 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowButtonStyle())
    }
}

private struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.black.opacity(0.05) : Color.clear)
    }
}

#Preview {
    SideMenuView()
        .environment(AppRouter())
        .frame(width: 320)
}
