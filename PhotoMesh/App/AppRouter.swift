import SwiftUI
import UIKit
import Observation

/// Central navigation state: which sheet is up and whether the side menu is open.
@Observable
final class AppRouter {
    var activeSheet: SheetRoute?
    var isMenuOpen = false

    func present(_ route: SheetRoute) {
        activeSheet = route
    }

    func dismissSheet() {
        activeSheet = nil
    }

    func openMenu() {
        withAnimation(PMTheme.menuAnimation) { isMenuOpen = true }
    }

    func closeMenu() {
        withAnimation(PMTheme.menuAnimation) { isMenuOpen = false }
    }

    /// Closes the menu first, then presents the sheet once the drawer has slid away.
    func closeMenuThenPresent(_ route: SheetRoute) {
        closeMenu()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            present(route)
        }
    }
}

enum SheetRoute: Identifiable, Hashable {
    case calculator
    case help
    case settings
    case language
    case about
    case plus
    case history
    case solutions(SolutionRequest)

    var id: String {
        switch self {
        case .calculator: return "calculator"
        case .help: return "help"
        case .settings: return "settings"
        case .language: return "language"
        case .about: return "about"
        case .plus: return "plus"
        case .history: return "history"
        case .solutions(let request): return "solutions-\(request.id.uuidString)"
        }
    }
}

/// What the solver should work on. Identity-based so it can live inside `Hashable` routes.
struct SolutionRequest: Identifiable, Hashable {
    enum Source {
        case image(UIImage)
        case expression(String)
        case circuit(Circuit)
    }

    let id = UUID()
    let source: Source

    static func == (lhs: SolutionRequest, rhs: SolutionRequest) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
