//
//  CameraCaptureNext.swift
//  Talkie iOS
//
//  Next camera capture surface. Uses AVFoundation for a full-screen
//  photo preview, Vision-backed OCR via ScreenshotOCRService, then
//  writes scanned image captures to CaptureStore.
//

import AVFoundation
import SwiftUI
import TalkieMobileKit
import UIKit

struct CameraCaptureNext: View {
    @StateObject private var camera = CameraCaptureNextModel()
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            switch camera.permissionState {
            case .unknown:
                cameraUnavailableOverlay(
                    title: "Preparing Camera",
                    message: "Checking camera access…",
                    systemImage: "camera"
                )
            case .denied:
                cameraUnavailableOverlay(
                    title: "Camera Access Needed",
                    message: "Allow Talkie to use the camera so scans can be captured and OCR’d.",
                    systemImage: "camera.fill",
                    primaryActionTitle: "Open Settings",
                    primaryAction: camera.openSystemSettings
                )
            case .unavailable:
                cameraUnavailableOverlay(
                    title: "Camera Unavailable",
                    message: camera.statusMessage ?? "This device does not have an available camera.",
                    systemImage: "camera.slash"
                )
            case .authorized:
                CameraPreviewView(session: camera.session)
                    .ignoresSafeArea()
                    .overlay(cameraGradient)
            }

            chrome
        }
        .task {
            await camera.prepare()
        }
        .onDisappear {
            camera.stop()
        }
        .alert("Camera Capture", isPresented: $camera.showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(camera.alertMessage)
        }
    }

    private var chrome: some View {
        ZStack {
            CameraCornerButton(
                alignment: .topLeading,
                systemImage: "chevron.left",
                label: "Done",
                action: { AppShellRouter.shared.openHome() }
            )

            CameraCornerButton(
                alignment: .topTrailing,
                systemImage: "gearshape",
                label: "Settings",
                action: { AppShellRouter.shared.openSettings() }
            )

            VStack(spacing: 14) {
                Spacer()

                if let message = camera.statusMessage {
                    Text(message)
                        .talkieType(.preview)
                        .foregroundStyle(theme.colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(theme.colors.cardBackground.opacity(0.78))
                                .background(.ultraThinMaterial, in: Capsule())
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    theme.currentTheme.chrome.edgeFaint,
                                    lineWidth: theme.currentTheme.chrome.hairlineWidth
                                )
                        )
                        .padding(.horizontal, 24)
                }

                bottomControls
            }
            .padding(.bottom, 18)
        }
    }

    private var bottomControls: some View {
        HStack(spacing: 24) {
            Button(action: { camera.toggleCamera() }) {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(theme.colors.cardBackground.opacity(0.76))
                            .background(.ultraThinMaterial, in: Circle())
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(
                                theme.currentTheme.chrome.edgeFaint,
                                lineWidth: theme.currentTheme.chrome.hairlineWidth
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(!camera.canCapture)
            .opacity(camera.canCapture ? 1 : 0.45)
            .accessibilityLabel("Switch camera")

            Button(action: { camera.capturePhoto() }) {
                ZStack {
                    Circle().fill(theme.currentTheme.chrome.accent)
                    if camera.isProcessing {
                        ProgressView()
                            .tint(theme.colors.cardBackground)
                    } else {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(theme.colors.cardBackground)
                    }
                }
                .frame(width: 72, height: 72)
                .shadow(color: theme.currentTheme.chrome.accentGlow, radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .disabled(!camera.canCapture)
            .opacity(camera.canCapture ? 1 : 0.55)
            .accessibilityLabel("Capture scan")

            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
    }

    private var cameraGradient: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.50), location: 0.00),
                .init(color: .clear, location: 0.25),
                .init(color: .clear, location: 0.68),
                .init(color: .black.opacity(0.58), location: 1.00)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private func cameraUnavailableOverlay(
        title: String,
        message: String,
        systemImage: String,
        primaryActionTitle: String? = nil,
        primaryAction: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(theme.currentTheme.chrome.accent)

            Text(title)
                .talkieType(.channelLabel)
                .foregroundStyle(theme.colors.textPrimary)

            Text(message)
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            if let primaryActionTitle, let primaryAction {
                Button(primaryActionTitle, action: primaryAction)
                    .buttonStyle(.plain)
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.cardBackground)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(theme.currentTheme.chrome.accent))
            }
        }
        .padding(24)
    }
}

@MainActor
private final class CameraCaptureNextModel: NSObject, ObservableObject {
    enum PermissionState {
        case unknown
        case authorized
        case denied
        case unavailable
    }

    @Published var permissionState: PermissionState = .unknown
    @Published var statusMessage: String?
    @Published var isProcessing = false
    @Published var showingAlert = false
    @Published var alertMessage = ""

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "to.talkie.camera-capture.session")
    private var currentInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    private var photoDelegate: CameraPhotoCaptureDelegate?
    private var isConfigured = false
    private var currentPosition: AVCaptureDevice.Position = .back

    var canCapture: Bool {
        permissionState == .authorized && isConfigured && !isProcessing
    }

    func prepare() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionState = .authorized
            configureIfNeeded()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            permissionState = granted ? .authorized : .denied
            if granted {
                configureIfNeeded()
            }
        case .denied, .restricted:
            permissionState = .denied
        @unknown default:
            permissionState = .denied
        }
    }

    func stop() {
        guard session.isRunning else { return }
        sessionQueue.async { [session] in
            session.stopRunning()
        }
    }

    func toggleCamera() {
        guard canCapture else { return }
        let nextPosition: AVCaptureDevice.Position = currentPosition == .back ? .front : .back
        configureSession(position: nextPosition, startAfterConfig: true)
    }

    func capturePhoto() {
        guard canCapture else { return }
        isProcessing = true
        statusMessage = "Capturing scan…"

        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off

        let delegate = CameraPhotoCaptureDelegate { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.photoDelegate = nil

                switch result {
                case .success(let data):
                    await self.processCapturedPhoto(data)
                case .failure(let error):
                    self.finishWithError("Capture failed: \(error.localizedDescription)")
                }
            }
        }

        photoDelegate = delegate
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func configureIfNeeded() {
        guard !isConfigured else {
            startSession()
            return
        }
        configureSession(position: currentPosition, startAfterConfig: true)
    }

    private func configureSession(position: AVCaptureDevice.Position, startAfterConfig: Bool) {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            guard let device = Self.cameraDevice(position: position),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                Task { @MainActor in
                    self.permissionState = .unavailable
                    self.statusMessage = "No \(position == .back ? "back" : "front") camera is available."
                }
                return
            }

            session.beginConfiguration()
            session.sessionPreset = .photo

            if let currentInput {
                session.removeInput(currentInput)
            }

            guard session.canAddInput(input) else {
                session.commitConfiguration()
                Task { @MainActor in
                    self.permissionState = .unavailable
                    self.statusMessage = "Talkie could not attach the camera input."
                }
                return
            }
            session.addInput(input)

            if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            }

            if let connection = photoOutput.connection(with: .video), connection.isVideoMirroringSupported {
                connection.isVideoMirrored = position == .front
            }

            session.commitConfiguration()

            Task { @MainActor in
                self.currentInput = input
                self.currentPosition = position
                self.isConfigured = true
                self.statusMessage = nil
            }

            if startAfterConfig, !session.isRunning {
                session.startRunning()
            }
        }
    }

    private func startSession() {
        sessionQueue.async { [session] in
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    private func processCapturedPhoto(_ data: Data) async {
        statusMessage = "Reading text…"

        guard let image = UIImage(data: data) else {
            finishWithError("Talkie could not read that photo.")
            return
        }

        let ocrText: String
        do {
            let result = try await ScreenshotOCRService.extractText(from: image)
            ocrText = result.text
        } catch {
            AppLogger.ai.warning("Camera capture OCR found no text: \(error.localizedDescription)")
            ocrText = ""
        }

        let captureID = UUID()
        let storedData = normalizedJPEGData(from: image) ?? data
        let imageFilename = CaptureStore.shared.saveImage(storedData, id: captureID)
        let title = Self.title(from: ocrText, timestamp: Date())

        let capture = Capture(
            id: captureID,
            sourceType: "scan",
            text: ocrText,
            title: title,
            imageFilename: imageFilename
        )

        CaptureStore.shared.add(capture)
        CaptureSyncService.shared.syncIfConnected()

        statusMessage = "Saved scan"
        isProcessing = false
        AppShellRouter.shared.openCaptureDetail(captureID: capture.id.uuidString)
    }

    private func finishWithError(_ message: String) {
        isProcessing = false
        statusMessage = nil
        alertMessage = message
        showingAlert = true
    }

    private func normalizedJPEGData(from image: UIImage) -> Data? {
        image.normalizedForCameraCapture().jpegData(compressionQuality: 0.92)
    }

    private static func title(from text: String, timestamp: Date) -> String {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        if let firstLine {
            return String(firstLine.prefix(80))
        }

        return "Scan · \(timestamp.formatted(.dateTime.month().day().hour().minute()))"
    }

    private static func cameraDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(for: .video)
    }
}

private final class CameraPhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<Data, Error>) -> Void

    init(completion: @escaping (Result<Data, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            completion(.failure(error))
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            completion(.failure(CameraCaptureError.missingPhotoData))
            return
        }

        completion(.success(data))
    }
}

private enum CameraCaptureError: LocalizedError {
    case missingPhotoData

    var errorDescription: String? {
        switch self {
        case .missingPhotoData:
            return "No photo data was returned by the camera."
        }
    }
}

private struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

private struct CameraCornerButton: View {
    let alignment: Alignment
    let systemImage: String
    let label: String
    let action: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(theme.colors.cardBackground.opacity(0.76))
                    .background(.ultraThinMaterial, in: Circle())
                Circle()
                    .strokeBorder(
                        theme.currentTheme.chrome.edgeFaint,
                        lineWidth: theme.currentTheme.chrome.hairlineWidth
                    )
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .frame(width: 40, height: 40)
            .shadow(color: .black.opacity(0.10), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }
}

private extension UIImage {
    func normalizedForCameraCapture() -> UIImage {
        guard imageOrientation != .up else { return self }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
