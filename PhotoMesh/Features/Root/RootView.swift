import SwiftUI

/// Hosts the camera home screen, the left drawer, and every modal sheet.
struct RootView: View {
    @Environment(AppRouter.self) private var router
    @State private var menuDrag: CGFloat = 0   // live drag translation while the drawer is open
    @State private var edgeDrag: CGFloat = 0   // live drag translation while opening from the edge

    var body: some View {
        @Bindable var router = router

        GeometryReader { geo in
            let menuWidth = geo.size.width * PMTheme.menuWidthFraction
            let baseOffset: CGFloat = router.isMenuOpen ? 0 : -menuWidth
            let liveOffset = min(0, max(-menuWidth, baseOffset + menuDrag + edgeDrag))
            let progress = 1 + liveOffset / menuWidth   // 0 closed … 1 open

            ZStack(alignment: .leading) {
                CameraScreen()
                    .zIndex(0)

                // Dim layer over the camera while the drawer is out.
                Color.black
                    .opacity(0.45 * progress)
                    .ignoresSafeArea()
                    .allowsHitTesting(router.isMenuOpen)
                    .onTapGesture { router.closeMenu() }
                    .zIndex(1)

                // Invisible strip along the left edge that opens the drawer with a swipe.
                if !router.isMenuOpen {
                    Color.clear
                        .frame(width: 18)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .gesture(edgeOpenGesture(menuWidth: menuWidth))
                        .zIndex(2)
                }

                SideMenuView()
                    .frame(width: menuWidth)
                    .offset(x: liveOffset)
                    .shadow(color: .black.opacity(0.25 * progress), radius: 18, x: 6)
                    .gesture(menuCloseGesture(menuWidth: menuWidth))
                    .zIndex(3)
            }
        }
        .sheet(item: $router.activeSheet) { route in
            sheetContent(for: route)
        }
    }

    // MARK: Gestures

    private func edgeOpenGesture(menuWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                edgeDrag = max(0, value.translation.width)
            }
            .onEnded { value in
                let shouldOpen = value.translation.width > menuWidth * 0.25 || value.predictedEndTranslation.width > menuWidth * 0.6
                withAnimation(PMTheme.menuAnimation) {
                    edgeDrag = 0
                    router.isMenuOpen = shouldOpen
                }
            }
    }

    private func menuCloseGesture(menuWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                menuDrag = min(0, value.translation.width)
            }
            .onEnded { value in
                let shouldClose = -value.translation.width > menuWidth * 0.3 || value.predictedEndTranslation.width < -menuWidth * 0.6
                withAnimation(PMTheme.menuAnimation) {
                    menuDrag = 0
                    if shouldClose { router.isMenuOpen = false }
                }
            }
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(for route: SheetRoute) -> some View {
        switch route {
        case .calculator:
            CalculatorSheet()
        case .help:
            HelpCenterSheet()
                .presentationBackground(PMTheme.darkSheet)
        case .settings:
            SettingsSheet()
        case .language:
            LanguageSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
        case .about:
            AboutSheet()
        case .plus:
            PlusSheet()
        case .solutions(let request):
            SolutionsSheet(request: request)
                .presentationBackground(PMTheme.darkSheet)
        }
    }
}

#Preview {
    RootView()
        .environment(AppRouter())
}
