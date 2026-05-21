//
//  CameraCaptureNext.swift
//  Talkie iOS
//
//  Next camera capture surface. Uses AVFoundation for a full-screen
//  photo preview, Vision-backed OCR via ScreenshotOCRService, then
//  writes scanned image captures to CaptureStore.
//

import AVFoundation
import PhotosUI
import SwiftUI
import TalkieMobileKit
import UIKit
import VisionKit

struct CameraCaptureNext: View {
    private let initialURL: URL?
    private let onCaptureSaved: ((String) -> Void)?

    @StateObject private var camera = CameraCaptureNextModel()
    @ObservedObject private var theme = ThemeManager.shared
    @State private var fallbackPhotoItem: PhotosPickerItem?
    @State private var isShowingDocumentScanner = false

    init(initialURL: URL? = nil, onCaptureSaved: ((String) -> Void)? = nil) {
        self.initialURL = initialURL
        self.onCaptureSaved = onCaptureSaved
    }

    var body: some View {
        if let initialURL {
            WebCaptureBrowserNext(initialURL: initialURL, onCaptureSaved: onCaptureSaved)
        } else {
            cameraBody
        }
    }

    private var cameraBody: some View {
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
                    systemImage: "camera.slash",
                    showsPhotoLibraryFallback: true
                )
            case .authorized:
                CameraPreviewView(session: camera.session)
                    .ignoresSafeArea()
                    .overlay(cameraGradient)
            }

            if let preview = camera.scanPreview {
                ScanPreviewOverlay(
                    preview: preview,
                    onReshoot: { camera.discardPreview() },
                    onSave:    { editedText in
                        camera.confirmAndSave(
                            editedText: editedText,
                            onCaptureSaved: onCaptureSaved
                        )
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .zIndex(1)
            } else {
                chrome
            }
        }
        .animation(.easeOut(duration: 0.22), value: camera.scanPreview != nil)
        .task {
            await camera.prepare()
        }
        .onDisappear {
            camera.stop()
        }
        .onChange(of: fallbackPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await camera.importFallbackPhoto(newItem)
                fallbackPhotoItem = nil
            }
        }
        .sheet(isPresented: $isShowingDocumentScanner) {
            CameraDocumentScannerNext(
                onScan: { pages in
                    Task {
                        await camera.importDocumentScan(pages)
                    }
                },
                onFailure: { message in
                    camera.finishWithError(message)
                }
            )
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

            Button(action: { isShowingDocumentScanner = true }) {
                Image(systemName: "doc.viewfinder")
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
            .disabled(!CameraDocumentScannerNext.isSupported || camera.isProcessing)
            .opacity(CameraDocumentScannerNext.isSupported && !camera.isProcessing ? 1 : 0.45)
            .accessibilityLabel("Scan multiple pages")
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
        primaryAction: (() -> Void)? = nil,
        showsPhotoLibraryFallback: Bool = false
    ) -> some View {
        let isImportingFallback = camera.isProcessing
        let fallbackForeground = theme.colors.cardBackground
        let fallbackAccent = theme.currentTheme.chrome.accent

        return VStack(spacing: 16) {
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

            if showsPhotoLibraryFallback {
                PhotosPicker(selection: $fallbackPhotoItem, matching: .images) {
                    HStack(spacing: 6) {
                        if isImportingFallback {
                            ProgressView()
                                .scaleEffect(0.72)
                        } else {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 12, weight: .semibold))
                        }

                        Text(isImportingFallback ? "Importing…" : "Choose Photo")
                    }
                    .talkieType(.preview)
                    .foregroundStyle(fallbackForeground)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(fallbackAccent))
                }
                .buttonStyle(.plain)
                .disabled(isImportingFallback)
                .accessibilityLabel("Choose a photo to scan")
            }
        }
        .padding(24)
    }
}

/// One OCR-recognized segment with its Vision confidence score.
/// Codex wires real per-observation confidence from
/// `VNRecognizedText.confidence`; paint side currently mocks a
/// deterministic gradient so the visual treatment is exercisable.
struct OCRChunk: Identifiable, Equatable {
    let id = UUID()
    let text: String
    /// 0.0 = no confidence, 1.0 = perfect. Vision returns the same
    /// 0..1 range, so this can be wired through verbatim.
    let confidence: Double

    enum Band { case high, medium, low }
    var band: Band {
        switch confidence {
        case 0.80...:  return .high
        case 0.55..<0.80: return .medium
        default:       return .low
        }
    }
}

/// Snapshot of an OCR pass awaiting user confirmation. Held by the
/// model after `processCapturedPhoto` finishes; cleared on either
/// confirmAndSave (proceeds to CaptureDetail) or discardPreview
/// (returns to the live camera).
struct ScanPreview: Equatable {
    let image: UIImage
    let chunks: [OCRChunk]
    let pageCount: Int
    let deferredPageCount: Int
    let deferredPageImages: [UIImage]
    /// Joined text fallback for downstream save / OCR consumers that
    /// don't need chunk granularity.
    var combinedText: String { chunks.map(\.text).joined(separator: "\n") }
    /// True when any chunk falls below the medium-confidence band —
    /// drives the "consider reshooting" coaching banner.
    var hasLowConfidence: Bool { chunks.contains { $0.band == .low } }
    var pageStatusText: String? {
        guard pageCount > 1 || deferredPageCount > 0 else { return nil }

        let scannedPageCount = max(1, pageCount - deferredPageCount)
        var status = "Page \(scannedPageCount) of \(max(pageCount, scannedPageCount)) scanned"
        if deferredPageCount > 0 {
            status += " · \(deferredPageCount) \(deferredPageCount == 1 ? "page" : "pages") waiting"
        }
        return status
    }

    static func == (lhs: ScanPreview, rhs: ScanPreview) -> Bool {
        lhs.image === rhs.image &&
            lhs.chunks == rhs.chunks &&
            lhs.pageCount == rhs.pageCount &&
            lhs.deferredPageCount == rhs.deferredPageCount &&
            lhs.deferredPageImages.count == rhs.deferredPageImages.count
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
    /// Set after a photo is captured and OCR'd. Non-nil = the
    /// ScanPreviewOverlay is showing; user must confirm or reshoot.
    @Published var scanPreview: ScanPreview?

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

    func importFallbackPhoto(_ item: PhotosPickerItem) async {
        guard !isProcessing else { return }
        isProcessing = true
        statusMessage = "Importing photo…"

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                finishWithError("Talkie could not read that photo.")
                return
            }

            await processCapturedPhoto(data)
        } catch {
            finishWithError("Photo import failed: \(error.localizedDescription)")
        }
    }

    func importDocumentScan(_ pages: [UIImage]) async {
        guard !isProcessing else { return }
        guard !pages.isEmpty else {
            finishWithError("No pages were captured.")
            return
        }

        isProcessing = true
        statusMessage = pages.count > 1 ? "Reading first page…" : "Reading text…"
        await processCapturedPages(pages)
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
        guard let image = UIImage(data: data) else {
            finishWithError("Talkie could not read that photo.")
            return
        }

        statusMessage = "Reading text…"
        await processCapturedPages([image])
    }

    private func processCapturedPages(_ pages: [UIImage]) async {
        guard let firstImage = pages.first else {
            finishWithError("Talkie could not read that scan.")
            return
        }

        let deferredPages = Array(pages.dropFirst())
        let preview: ScanPreview
        do {
            let result = try await ScreenshotOCRService.extractChunks(from: firstImage)
            preview = ScanPreview(
                image: result.image,
                chunks: result.chunks,
                pageCount: max(pages.count, result.pageCount),
                deferredPageCount: deferredPages.count,
                deferredPageImages: deferredPages
            )
        } catch {
            AppLogger.ai.warning("Camera capture OCR found no text: \(error.localizedDescription)")
            preview = ScanPreview(
                image: firstImage,
                chunks: [],
                pageCount: pages.count,
                deferredPageCount: deferredPages.count,
                deferredPageImages: deferredPages
            )
        }

        statusMessage = nil
        isProcessing = false
        scanPreview = preview
    }

    /// Persist the pending preview as a capture, sync, and route to
    /// CaptureDetail. Called from the ScanPreviewOverlay's Save chip.
    /// `editedText` overrides the OCR-derived combined text when the
    /// user has hand-corrected the scan before saving (M02 path).
    func confirmAndSave(
        editedText: String? = nil,
        onCaptureSaved: ((String) -> Void)? = nil
    ) {
        guard let preview = scanPreview else { return }
        scanPreview = nil

        let combined = editedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? editedText!
            : preview.combinedText
        let captureID = UUID()
        let storedData = normalizedJPEGData(from: preview.image)
            ?? preview.image.jpegData(compressionQuality: 0.92)
            ?? Data()
        let imageFilename = CaptureStore.shared.saveImage(storedData, id: captureID)
        let deferredFilenames = saveDeferredPages(preview.deferredPageImages, captureID: captureID)
        let title = Self.title(from: combined, timestamp: Date())

        let capture = Capture(
            id: captureID,
            sourceType: "scan",
            text: combined,
            title: title,
            imageFilename: imageFilename,
            deferredPageFilenames: deferredFilenames.isEmpty ? nil : deferredFilenames,
            totalPageCount: preview.pageCount > 1 ? preview.pageCount : nil
        )

        CaptureStore.shared.add(capture)
        CaptureSyncService.shared.syncIfConnected()

        statusMessage = "Saved scan"
        if let onCaptureSaved {
            onCaptureSaved(capture.id.uuidString)
        } else {
            AppShellRouter.shared.openCaptureDetail(captureID: capture.id.uuidString)
        }
    }

    /// Discard the pending preview and return to the live camera.
    /// Called from the ScanPreviewOverlay's Reshoot chip.
    func discardPreview() {
        scanPreview = nil
        statusMessage = nil
    }

    func finishWithError(_ message: String) {
        isProcessing = false
        statusMessage = nil
        alertMessage = message
        showingAlert = true
    }

    private func saveDeferredPages(_ images: [UIImage], captureID: UUID) -> [String] {
        images.enumerated().compactMap { offset, image in
            guard let data = image.pngData() else { return nil }
            return CaptureStore.shared.saveDeferredPage(
                data,
                captureId: captureID,
                pageIndex: offset + 2
            )
        }
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

private struct CameraDocumentScannerNext: UIViewControllerRepresentable {
    static var isSupported: Bool {
        VNDocumentCameraViewController.isSupported
    }

    let onScan: ([UIImage]) -> Void
    let onFailure: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onScan: onScan,
            onFailure: onFailure,
            dismiss: dismiss.callAsFunction
        )
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onScan: ([UIImage]) -> Void
        private let onFailure: (String) -> Void
        private let dismiss: () -> Void

        init(
            onScan: @escaping ([UIImage]) -> Void,
            onFailure: @escaping (String) -> Void,
            dismiss: @escaping () -> Void
        ) {
            self.onScan = onScan
            self.onFailure = onFailure
            self.dismiss = dismiss
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            dismiss()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            onFailure(error.localizedDescription)
            dismiss()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            guard scan.pageCount > 0 else {
                onFailure("No pages were captured.")
                dismiss()
                return
            }

            var pages: [UIImage] = []
            pages.reserveCapacity(scan.pageCount)
            for index in 0..<scan.pageCount {
                autoreleasepool {
                    pages.append(scan.imageOfPage(at: index))
                }
            }

            onScan(pages)
            dismiss()
        }
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

// MARK: - Scan preview overlay (chunks + confidence + reshoot / save)

/// Full-bleed overlay shown between OCR completion and the save
/// step. Lets the user review each recognized chunk against its
/// confidence band, then either commit to a capture or discard and
/// re-frame the shot.
private struct ScanPreviewOverlay: View {
    let preview: ScanPreview
    let onReshoot: () -> Void
    /// Save callback receives the edited transcript when the user has
    /// switched into edit mode and modified the text. `nil` means save
    /// the OCR-derived combinedText as-is (M02 edit path is opt-in).
    let onSave: (String?) -> Void

    @ObservedObject private var theme = ThemeManager.shared
    @State private var isEditing: Bool = false
    @State private var editedText: String = ""
    @FocusState private var editorFocused: Bool

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(uiImage: preview.image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                                  lineWidth: theme.currentTheme.chrome.hairlineWidth)
                            )
                            .padding(.horizontal, 12)
                            .padding(.top, 12)

                        if let pageStatusText = preview.pageStatusText {
                            pageStatusRow(pageStatusText)
                                .padding(.horizontal, 12)
                        }

                        if preview.hasLowConfidence && !isEditing {
                            lowConfidenceBanner
                                .padding(.horizontal, 12)
                        }

                        HStack(spacing: 6) {
                            Text(isEditing
                                 ? "· EDITING · \(wordCount(editedText)) WORDS"
                                 : "· RECOGNIZED · \(preview.chunks.count) CHUNKS")
                                .talkieType(.channelLabelTiny)
                                .foregroundStyle(theme.colors.textTertiary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)

                        if isEditing {
                            editorPanel
                                .padding(.horizontal, 12)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(preview.chunks.enumerated()), id: \.element.id) { idx, chunk in
                                    ChunkRow(chunk: chunk, showDivider: idx > 0)
                                }
                            }
                            .background(theme.colors.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                                  lineWidth: theme.currentTheme.chrome.hairlineWidth)
                            )
                            .padding(.horizontal, 12)
                        }

                        actionRow
                            .padding(.horizontal, 12)
                            .padding(.top, 6)

                        Spacer(minLength: 100)
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .onAppear {
            if editedText.isEmpty {
                editedText = preview.combinedText
            }
        }
    }

    private var header: some View {
        HStack {
            Text(isEditing ? "EDIT SCAN" : "REVIEW SCAN")
                .talkieType(.channelLabel)
                .foregroundStyle(theme.colors.textTertiary)
            Spacer()
            Button {
                if isEditing {
                    editorFocused = false
                }
                withAnimation(.easeInOut(duration: 0.18)) {
                    isEditing.toggle()
                }
                if isEditing {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        editorFocused = true
                    }
                }
            } label: {
                Text(isEditing ? "DONE" : "EDIT")
                    .talkieType(.channelLabelSmall)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .overlay(
                        Capsule()
                            .strokeBorder(theme.currentTheme.chrome.accent.opacity(0.5),
                                          lineWidth: theme.currentTheme.chrome.hairlineWidth)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: theme.currentTheme.chrome.hairlineWidth)
        }
    }

    private var editorPanel: some View {
        ZStack(alignment: .topLeading) {
            if editedText.isEmpty {
                Text("Correct any wobbly chunks before saving.")
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textTertiary.opacity(0.6))
                    .padding(.top, 14)
                    .padding(.horizontal, 18)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $editedText)
                .focused($editorFocused)
                .scrollContentBackground(.hidden)
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textPrimary)
                .tint(theme.currentTheme.chrome.accent)
                .frame(minHeight: 240)
                .padding(10)
        }
        .background(theme.colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(theme.currentTheme.chrome.accent.opacity(0.45),
                              lineWidth: theme.currentTheme.chrome.hairlineWidth)
        )
    }

    private func wordCount(_ s: String) -> Int {
        s.split { $0.isWhitespace || $0.isNewline }.count
    }

    private func pageStatusRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.currentTheme.chrome.accent)
            Text(text)
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                      lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
        )
    }

    private var lowConfidenceBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(red: 0.85, green: 0.46, blue: 0.34))
            Text("Some chunks scored low. Reshoot for a cleaner scan.")
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(red: 0.85, green: 0.46, blue: 0.34).opacity(0.45),
                                      lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
        )
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button(action: onReshoot) {
                HStack(spacing: 5) {
                    Image(systemName: "camera.rotate")
                        .font(.system(size: 12, weight: .medium))
                    Text("Reshoot")
                        .talkieType(.fieldLabel)
                }
                .foregroundStyle(theme.colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    Capsule().strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                           lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
            }
            .buttonStyle(.plain)

            Button {
                let override: String?
                if isEditing {
                    let trimmed = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let original = preview.combinedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    override = (trimmed != original) ? editedText : nil
                } else {
                    override = nil
                }
                onSave(override)
            } label: {
                Text(isEditing ? "Save edited ›" : "Save scan ›")
                    .talkieType(.fieldLabel)
                    .foregroundStyle(theme.colors.cardBackground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(theme.currentTheme.chrome.accent))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ChunkRow: View {
    let chunk: OCRChunk
    let showDivider: Bool

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            if showDivider {
                Rectangle()
                    .fill(theme.currentTheme.chrome.edgeSubtle)
                    .frame(height: theme.currentTheme.chrome.hairlineWidth)
                    .padding(.leading, 14)
            }
            HStack(alignment: .top, spacing: 8) {
                Text(chunk.text)
                    .talkieType(.preview)
                    .foregroundStyle(textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)

                confidencePill
                    .padding(.top, 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(rowTint)
        }
    }

    private var textColor: Color {
        switch chunk.band {
        case .high, .medium: return theme.colors.textPrimary
        case .low:           return theme.colors.textSecondary
        }
    }

    private var rowTint: Color {
        switch chunk.band {
        case .low: return Color(red: 0.85, green: 0.46, blue: 0.34).opacity(0.07)
        default:   return Color.clear
        }
    }

    private var confidencePill: some View {
        let pct = Int((chunk.confidence * 100).rounded())
        return Text("\(pct)%")
            .talkieType(.channelLabelTiny)
            .foregroundStyle(pillColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .strokeBorder(pillColor.opacity(0.55),
                                  lineWidth: theme.currentTheme.chrome.hairlineWidth)
            )
    }

    private var pillColor: Color {
        switch chunk.band {
        case .high:   return Color(red: 0.36, green: 0.74, blue: 0.50)
        case .medium: return theme.currentTheme.chrome.accent
        case .low:    return Color(red: 0.85, green: 0.46, blue: 0.34)
        }
    }
}
