import SwiftUI
import PhotosUI

/// The home screen: live camera, adjustable viewfinder, and the capture controls.
/// Layout mirrors Photomath's main page one-to-one.
struct CameraScreen: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.pmSafeAreaInsets) private var safeInsets

    @State private var camera = CameraController()
    @State private var region: ScanRegion?
    @State private var canvasSize: CGSize = .zero
    @State private var frozenImage: UIImage?
    @State private var isAnalyzing = false
    @State private var pickerItem: PhotosPickerItem?

    private let controlsHeight: CGFloat = 236
    private let topBarHeight: CGFloat = 56

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let insets = SafeArea.resolve(from: safeInsets)
            let bounds = CGRect(
                x: 14,
                y: insets.top + topBarHeight,
                width: size.width - 28,
                height: max(120, size.height - insets.top - topBarHeight - insets.bottom - controlsHeight)
            )
            let regionBinding = Binding<ScanRegion>(
                get: { region ?? ScanRegion.standard(in: size) },
                set: { region = $0 }
            )

            ZStack {
                backdrop(size: size)

                if let frozenImage {
                    Image(uiImage: frozenImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .transition(.opacity)
                }

                legibilityGradients(size: size)

                ViewfinderOverlay(region: regionBinding, bounds: bounds, isDimmed: isAnalyzing)

                if isAnalyzing {
                    ScanLine(rect: regionBinding.wrappedValue.rect)
                        .transition(.opacity)
                }

                chrome(insets: insets)

                if camera.authorization == .denied {
                    PermissionOverlay()
                }
            }
            .frame(width: size.width, height: size.height)
            .onAppear {
                canvasSize = size
                if region == nil { region = ScanRegion.standard(in: size) }
            }
            .onChange(of: size) { _, newSize in
                canvasSize = newSize
            }
        }
        .ignoresSafeArea()
        .background(Color.black)
        .task { camera.start() }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active, oldPhase != .active {
                camera.start()
            } else if newPhase == .background {
                camera.stop()
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await loadPickedPhoto(item) }
        }
        .onChange(of: router.activeSheet) { _, sheet in
            if sheet == nil, frozenImage != nil || isAnalyzing {
                resetCapture()
            }
        }
    }

    // MARK: Layers

    @ViewBuilder
    private func backdrop(size: CGSize) -> some View {
        if camera.hasCamera {
            CameraPreviewView(session: camera.session)
                .frame(width: size.width, height: size.height)
        } else {
            NoCameraBackdrop()
                .frame(width: size.width, height: size.height)
        }
    }

    private func legibilityGradients(size: CGSize) -> some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 150)
            Spacer(minLength: 0)
            LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                .frame(height: 280)
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    private func chrome(insets: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            HStack {
                TopIconButton(systemName: "line.3.horizontal", label: "Menu") {
                    router.openMenu()
                }
                Spacer()
                TopIconButton(systemName: "questionmark.circle", label: "Help") {
                    router.present(.help)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, insets.top + 4)

            Spacer(minLength: 0)

            bottomControls
                .padding(.bottom, insets.bottom + 22)
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 20) {
            Text(isAnalyzing ? "Analyzing circuit…" : "Take a picture of a circuit")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(PMTheme.hintPill))
                .animation(.easeInOut(duration: 0.2), value: isAnalyzing)

            ZStack {
                ShutterButton(isBusy: isAnalyzing, action: capture)

                HStack {
                    CalculatorButton { router.present(.calculator) }
                        .frame(width: 84)
                        .padding(.leading, 38)
                    Spacer()
                    HistoryButton { router.present(.history) }
                        .frame(width: 84)
                        .padding(.trailing, 38)
                }
            }

            HStack(spacing: 30) {
                PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                    Image(systemName: "photo")
                        .font(.system(size: 21, weight: .regular))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose from album")

                Button {
                    Haptics.selection()
                    camera.toggleTorch()
                } label: {
                    Image(systemName: camera.isTorchOn ? "bolt.fill" : "bolt")
                        .font(.system(size: 21, weight: .regular))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(camera.hasTorch ? 1 : 0.45)
                .accessibilityLabel(camera.isTorchOn ? "Turn flashlight off" : "Turn flashlight on")
            }
        }
    }

    // MARK: Capture flow

    private func capture() {
        guard !isAnalyzing else { return }
        Haptics.impact(.medium)
        let currentRegion = region ?? ScanRegion.standard(in: canvasSize)
        withAnimation(.easeOut(duration: 0.15)) { isAnalyzing = true }

        if camera.hasCamera {
            camera.capturePhoto { image in
                guard let image else {
                    Haptics.notify(.error)
                    resetCapture()
                    return
                }
                beginAnalysis(fullImage: image, cropTo: currentRegion.rect)
            }
        } else {
            // Simulator / no camera: keep the flow testable.
            beginAnalysis(fullImage: ImageCropper.placeholderImage(), cropTo: nil)
        }
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        withAnimation(.easeOut(duration: 0.15)) { isAnalyzing = true }
        beginAnalysis(fullImage: image, cropTo: nil)
    }

    private func beginAnalysis(fullImage: UIImage, cropTo rect: CGRect?) {
        withAnimation(.easeOut(duration: 0.15)) { frozenImage = fullImage }
        let subject: UIImage
        if let rect, canvasSize != .zero {
            subject = ImageCropper.crop(fullImage, toViewRect: rect, in: canvasSize)
        } else {
            subject = fullImage.orientedUp()
        }
        Task { @MainActor in
            // Brief scan animation before the results slide up.
            try? await Task.sleep(for: .milliseconds(900))
            guard isAnalyzing else { return }
            router.present(.solutions(SolutionRequest(source: .image(subject))))
        }
    }

    private func resetCapture() {
        withAnimation(.easeOut(duration: 0.2)) {
            frozenImage = nil
            isAnalyzing = false
        }
    }
}

// MARK: - Controls

private struct TopIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 2)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct ShutterButton: View {
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.92), lineWidth: 2.5)
                    .frame(width: PMTheme.shutterRingDiameter, height: PMTheme.shutterRingDiameter)
                Circle()
                    .fill(PMTheme.accent)
                    .frame(width: PMTheme.shutterDiameter, height: PMTheme.shutterDiameter)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                if isBusy {
                    ProgressView()
                        .tint(.white)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(ShutterButtonStyle())
        .disabled(isBusy)
        .accessibilityLabel("Take picture")
    }
}

private struct ShutterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct CalculatorButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                CalculatorGlyph()
                Text("Calculator")
                    .font(.system(size: 11, weight: .regular))
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Calculator")
    }
}

struct HistoryButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 21, weight: .regular))
                    .frame(height: 25)
                Text("History")
                    .font(.system(size: 11, weight: .regular))
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("History")
    }
}

/// Small calculator outline, drawn with shapes so it matches the white line icons around it.
struct CalculatorGlyph: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .stroke(lineWidth: 1.6)
            VStack(spacing: 3.2) {
                RoundedRectangle(cornerRadius: 1)
                    .frame(width: 11, height: 4.2)
                HStack(spacing: 2.6) { dot; dot; dot }
                HStack(spacing: 2.6) { dot; dot; dot }
            }
        }
        .frame(width: 19, height: 25)
    }

    private var dot: some View {
        Circle().frame(width: 2.2, height: 2.2)
    }
}

/// Green line sweeping the scan area while a capture is being analysed.
struct ScanLine: View {
    let rect: CGRect
    @State private var progress: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(LinearGradient(colors: [PMTheme.accent.opacity(0), .white, PMTheme.accent.opacity(0)], startPoint: .leading, endPoint: .trailing))
            .frame(width: max(rect.width - 10, 10), height: 2)
            .shadow(color: PMTheme.accent.opacity(0.9), radius: 6)
            .position(x: rect.midX, y: rect.minY + 8 + (rect.height - 16) * progress)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    progress = 1
                }
            }
    }
}

/// Neutral background shown when no camera is available (Simulator).
private struct NoCameraBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.30), Color(white: 0.16)], startPoint: .top, endPoint: .bottom)
            Canvas { context, size in
                let step: CGFloat = 36
                var path = Path()
                var x: CGFloat = 0
                while x <= size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
                var y: CGFloat = 0
                while y <= size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
                context.stroke(path, with: .color(.white.opacity(0.06)), lineWidth: 1)
            }
        }
    }
}

private struct PermissionOverlay: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 34))
                .foregroundStyle(.white)
            Text("Allow camera access")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
            Text("PhotoMesh needs the camera to scan circuit diagrams. You can enable it in Settings.")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
            }
            .buttonStyle(PMPrimaryButtonStyle())
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.72))
    }
}

#Preview {
    CameraScreen()
        .environment(AppRouter())
}
