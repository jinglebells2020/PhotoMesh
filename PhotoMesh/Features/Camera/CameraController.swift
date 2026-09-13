import AVFoundation
import UIKit
import Observation

/// Owns the AVCaptureSession. All session work happens on a private queue; published
/// state is always mutated on the main thread.
@Observable
final class CameraController {
    enum Authorization { case notDetermined, authorized, denied }

    private(set) var authorization: Authorization = .notDetermined
    private(set) var isRunning = false
    private(set) var isTorchOn = false
    private(set) var hasCamera = false
    private(set) var hasTorch = false

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "app.photomesh.camera.session", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    @ObservationIgnored private var videoDevice: AVCaptureDevice?
    @ObservationIgnored private var isConfigured = false
    @ObservationIgnored private var configurationFailed = false
    @ObservationIgnored private var inFlightCapture: PhotoCaptureDelegate?

    // MARK: Lifecycle

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorization = .authorized
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.authorization = granted ? .authorized : .denied
                    if granted { self.startSession() }
                }
            }
        default:
            authorization = .denied
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            guard session.isRunning else { return }
            session.stopRunning()
            DispatchQueue.main.async {
                self.isRunning = false
                self.isTorchOn = false
            }
        }
    }

    private func startSession() {
        sessionQueue.async { [self] in
            configureIfNeeded()
            guard isConfigured, !session.isRunning else { return }
            session.startRunning()
            let running = session.isRunning
            DispatchQueue.main.async { self.isRunning = running }
        }
    }

    private func configureIfNeeded() {
        guard !isConfigured, !configurationFailed else { return }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            configurationFailed = true
            DispatchQueue.main.async { self.hasCamera = false }
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .photo

        guard session.canAddInput(input), session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            configurationFailed = true
            DispatchQueue.main.async { self.hasCamera = false }
            return
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .balanced
        session.commitConfiguration()

        videoDevice = device
        isConfigured = true
        let torch = device.hasTorch
        DispatchQueue.main.async {
            self.hasCamera = true
            self.hasTorch = torch
        }
    }

    // MARK: Torch

    func toggleTorch() {
        guard let device = videoDevice, device.hasTorch else { return }
        let target = !isTorchOn
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                device.torchMode = target ? .on : .off
                device.unlockForConfiguration()
                DispatchQueue.main.async { self.isTorchOn = target }
            } catch {
                // Torch unavailable (overheating, etc.) – leave the state as is.
            }
        }
    }

    // MARK: Capture

    /// Captures a still. The completion is called on the main thread with `nil` on failure.
    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        guard hasCamera else {
            completion(nil)
            return
        }
        sessionQueue.async { [self] in
            let settings: AVCapturePhotoSettings
            if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else {
                settings = AVCapturePhotoSettings()
            }
            settings.flashMode = .off
            settings.photoQualityPrioritization = .balanced

            let delegate = PhotoCaptureDelegate { [weak self] image in
                DispatchQueue.main.async { completion(image) }
                self?.sessionQueue.async { self?.inFlightCapture = nil }
            }
            inFlightCapture = delegate
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }
}

/// Bridges the delegate callback into a closure and keeps itself alive for the duration.
final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (UIImage?) -> Void

    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            completion(nil)
            return
        }
        completion(image)
    }
}
