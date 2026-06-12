//
//  AgentCameraCaptureService.swift
//  TalkieAgent
//
//  Lightweight AVCaptureSession owner for Agent's screen-recording camera bubble.
//

@preconcurrency import AVFoundation
import AppKit
import TalkieKit

private let agentCameraLog = Log(.system)

@MainActor
@Observable
final class AgentCameraCaptureService: NSObject {
    static let shared = AgentCameraCaptureService()

    enum State: Equatable {
        case idle
        case previewing
    }

    private(set) var state: State = .idle
    private(set) var isAuthorized = false
    private(set) var isSessionRunning = false
    private(set) var captureSession: AVCaptureSession?

    var bubbleSize: CGFloat {
        switch TalkieSharedSettings.string(forKey: "cameraBubbleSize") {
        case "small": return 80
        case "large": return 130
        default: return 100
        }
    }

    @ObservationIgnored
    private var previewReadyContinuation: CheckedContinuation<Void, Never>?
    @ObservationIgnored
    private let captureQueue = DispatchQueue(label: "to.talkie.agent.cameraCapture")

    private override init() {
        super.init()
        isAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            isAuthorized = granted
            return granted
        default:
            isAuthorized = false
            return false
        }
    }

    func startPreviewAsync() async -> Bool {
        if state == .previewing, isSessionRunning {
            return true
        }
        guard startPreview() else { return false }
        if isSessionRunning {
            return true
        }
        await withCheckedContinuation { continuation in
            self.previewReadyContinuation = continuation
        }
        return true
    }

    @discardableResult
    func startPreview() -> Bool {
        guard state == .idle else { return true }
        guard isAuthorized else {
            agentCameraLog.warning("Camera not authorized, cannot show Agent camera bubble")
            return false
        }

        let session = AVCaptureSession()
        session.sessionPreset = .hd1280x720

        let device: AVCaptureDevice?
        if let selectedDeviceID = TalkieSharedSettings.string(forKey: "cameraDeviceID"),
           !selectedDeviceID.isEmpty,
           let selected = AVCaptureDevice(uniqueID: selectedDeviceID) {
            device = selected
        } else {
            device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }

        guard let device else {
            agentCameraLog.error("No camera available for Agent camera bubble")
            return false
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                agentCameraLog.error("Cannot add camera input to Agent preview session")
                return false
            }
            session.addInput(input)

            captureSession = session
            isSessionRunning = false
            state = .previewing

            captureQueue.async { [weak self] in
                session.startRunning()

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isSessionRunning = true
                    self.previewReadyContinuation?.resume()
                    self.previewReadyContinuation = nil
                    agentCameraLog.info("Agent camera bubble preview started")
                }
            }
            return true
        } catch {
            agentCameraLog.error("Failed to set up Agent camera bubble: \(error)")
            return false
        }
    }

    func stopPreview() {
        guard state == .previewing else { return }

        let session = captureSession
        captureSession = nil
        isSessionRunning = false
        state = .idle

        captureQueue.async { session?.stopRunning() }
        agentCameraLog.info("Agent camera bubble preview stopped")
    }

    func teardown() {
        previewReadyContinuation?.resume()
        previewReadyContinuation = nil
        stopPreview()
    }
}
