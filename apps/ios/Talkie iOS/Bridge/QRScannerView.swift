//
//  QRScannerView.swift
//  Talkie iOS
//
//  QR code scanner for pairing with Mac
//

import SwiftUI
import AVFoundation
import AudioToolbox
import TalkieMobileKit

struct QRScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var bridgeManager = BridgeManager.shared
    @State private var isScanning = true
    @State private var scannedCode: String?
    @State private var errorMessage: String?
    @State private var currentStep = 0
    @State private var pairingPhase: PairingPhase = .scanning

    private enum PairingPhase {
        case scanning
        case pairing
        case success
        case pendingApproval
        case failure
    }

    private let pairingSteps = [
        "Generating keypair",
        "Deriving shared secret",
        "Authenticating device",
        "Syncing clocks"
    ]

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if pairingPhase == .scanning {
                    QRCodeScannerRepresentable { code in
                        handleScannedCode(code)
                    }
                    .ignoresSafeArea()

                    // Scanning overlay
                    VStack {
                        Spacer()

                        // Viewfinder
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(Color.white, lineWidth: 3)
                            .frame(width: 250, height: 250)
                            .background(Color.clear)

                        Spacer()

                        // Instructions
                        VStack(spacing: 12) {
                            Text("Scan QR Code")
                                .font(.headline)
                                .foregroundColor(.white)

                            Text("Scan any Talkie pairing QR. Mac Bridge codes pair here, and SSH terminal codes are routed automatically.")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .padding(.bottom, 60)
                    }
                } else {
                    // Pairing in progress
                    VStack(spacing: 24) {
                        if pairingPhase == .pairing {
                            // Organized step list with progression
                            VStack(spacing: 24) {
                                Text("PAIRING")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .tracking(4)
                                    .foregroundColor(.green)

                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(Array(pairingSteps.enumerated()), id: \.offset) { index, step in
                                        HStack(alignment: .center, spacing: 12) {
                                            // Status indicator - fixed width column
                                            ZStack {
                                                if index < currentStep {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 10, weight: .bold))
                                                        .foregroundColor(.green)
                                                } else if index == currentStep {
                                                    BrailleSpinner(size: 14, speed: 0.08, color: .green)
                                                } else {
                                                    Circle()
                                                        .fill(Color.white.opacity(0.2))
                                                        .frame(width: 6, height: 6)
                                                }
                                            }
                                            .frame(width: 20, height: 20, alignment: .center)

                                            Text(step)
                                                .font(.system(size: 13, design: .monospaced))
                                                .foregroundColor(index <= currentStep ? .white : .white.opacity(0.4))
                                        }
                                        .frame(height: 32)

                                        // Connector line
                                        if index < pairingSteps.count - 1 {
                                            HStack(spacing: 0) {
                                                Rectangle()
                                                    .fill(index < currentStep ? Color.green.opacity(0.5) : Color.white.opacity(0.1))
                                                    .frame(width: 1, height: 12)
                                                    .frame(width: 20, alignment: .center)
                                                Spacer()
                                            }
                                        }
                                    }
                                }
                                .frame(width: 240)
                            }

                        } else if pairingPhase == .success {
                            // Success state with delightful animation
                            SuccessView(
                                macName: bridgeManager.pairedMacName,
                                onDone: { dismiss() }
                            )

                        } else if pairingPhase == .pendingApproval {
                            PendingApprovalView(
                                macName: bridgeManager.pairedMacDisplayName,
                                onDone: { dismiss() }
                            )

                        } else if pairingPhase == .failure {
                            // Error state
                            VStack(spacing: 16) {
                                Text("✗")
                                    .font(.system(size: 48, weight: .light, design: .monospaced))
                                    .foregroundColor(.red)

                                Text("FAILED")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .tracking(4)
                                    .foregroundColor(.red)

                                if let error = bridgeManager.errorMessage ?? errorMessage {
                                    Text(error)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.7))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                }
                            }

                            Button("Retry") {
                                pairingPhase = .scanning
                                isScanning = true
                                errorMessage = nil
                                currentStep = 0
                            }
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(8)
                            .padding(.top, 20)
                        }
                    }
                }
            }
            .task(id: pairingPhase) {
                guard pairingPhase == .pairing else { return }
                currentStep = 0

                while pairingPhase == .pairing {
                    try? await Task.sleep(for: .milliseconds(800))
                    guard pairingPhase == .pairing else { break }

                    await MainActor.run {
                        if currentStep < pairingSteps.count - 1 {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentStep += 1
                            }
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }

    private func handleScannedCode(_ code: String) {
        guard pairingPhase == .scanning else { return }
        isScanning = false
        pairingPhase = .pairing
        scannedCode = code

        Task {
            do {
                let route = try await TalkieQRCodeRouter.route(scannedCode: code)

                switch route {
                case .bridge(let qrData):
                    await MainActor.run {
                        AppLogger.ui.info("Talkie QR routed to Mac Bridge pairing", detail: "host=\(qrData.hostname)")
                    }
                    let pairingResult = await bridgeManager.processPairing(qrData: qrData)
                    await MainActor.run {
                        switch pairingResult {
                        case .approved:
                            pairingPhase = .success

                        case .pendingApproval:
                            pairingPhase = .pendingApproval

                        case nil:
                            errorMessage = bridgeManager.errorMessage ?? "Could not pair with this Mac."
                            pairingPhase = .failure
                        }
                    }

                case .sshPayload(let rawCode, let payload):
                    let host = payload.connection?.normalizedHost ?? "none"
                    await MainActor.run {
                        AppLogger.ui.info("Talkie QR routed to SSH terminal import", detail: "host=\(host)")
                        if let importURL = TalkieQRCodeRouter.makeSSHImportURL(from: rawCode) {
                            DeepLinkManager.shared.handle(url: importURL)
                        }
                        dismiss()
                    }

                case .talkieURL(let url):
                    await MainActor.run {
                        AppLogger.ui.info("Talkie QR routed via deep link", detail: url.absoluteString)
                        DeepLinkManager.shared.handle(url: url)
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    let message = error.localizedDescription
                    errorMessage = message
                    bridgeManager.setError(message)
                    pairingPhase = .failure
                }
            }
        }
    }
}

// MARK: - QR Code Scanner

struct QRCodeScannerRepresentable: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onCodeScanned = onCodeScanned
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCodeScanned: ((String) -> Void)?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startScanning()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopScanning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        updatePreviewOrientation()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.previewLayer?.frame = self.view.bounds
            self.updatePreviewOrientation()
        })
    }

    private func setupCamera() {
        let session = AVCaptureSession()

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)

        self.captureSession = session
        self.previewLayer = preview
        updatePreviewOrientation()
    }

    private func startScanning() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }

    private func stopScanning() {
        captureSession?.stopRunning()
    }

    private func updatePreviewOrientation() {
        guard let connection = previewLayer?.connection,
              connection.isVideoOrientationSupported,
              let interfaceOrientation = view.window?.windowScene?.interfaceOrientation else {
            return
        }

        switch interfaceOrientation {
        case .portrait:
            connection.videoOrientation = .portrait
        case .portraitUpsideDown:
            connection.videoOrientation = .portraitUpsideDown
        case .landscapeLeft:
            connection.videoOrientation = .landscapeLeft
        case .landscapeRight:
            connection.videoOrientation = .landscapeRight
        default:
            break
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = metadataObject.stringValue else {
            return
        }

        // Vibrate
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))

        // Stop scanning and report
        stopScanning()
        onCodeScanned?(code)
    }
}

// MARK: - Success View with Delightful Animation

private struct SuccessView: View {
    let macName: String?
    let onDone: () -> Void

    @State private var showCheckmark = false
    @State private var showText = false
    @State private var showButton = false
    @State private var ringScale: CGFloat = 0.8
    @State private var ringOpacity: CGFloat = 1.0

    private var completedLines: [String] {
        [
            "Generated a fresh device keypair on this iPhone",
            "Derived a shared secret from the Mac's QR bootstrap key",
            "Authenticated this iPhone with the Talkie Bridge gateway",
            "Saved the Mac hostname and server key for future signed requests",
            "Established an encrypted direct bridge for Mac actions",
        ]
    }

    private var readyLines: [String] {
        [
            "Bridge requests from this iPhone are now signed and encrypted",
            "SSH sessions stay separately encrypted whenever you use Terminal",
            "This pairing is ready to use as soon as you dismiss this receipt",
        ]
    }

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.green.opacity(ringOpacity), lineWidth: 2)
                    .frame(width: 80, height: 80)
                    .scaleEffect(ringScale)

                Circle()
                    .fill(Color.green)
                    .frame(width: 64, height: 64)
                    .scaleEffect(showCheckmark ? 1 : 0)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.black)
                            .scaleEffect(showCheckmark ? 1 : 0)
                    )
            }

            VStack(spacing: 8) {
                Text("PAIRED")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .tracking(4)
                    .foregroundColor(.green)

                if let macName = macName {
                    Text(macName)
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                }

                Text("Secure connection established")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
            .opacity(showText ? 1 : 0)
            .offset(y: showText ? 0 : 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PairingReceiptSection(title: "WHAT JUST HAPPENED", lines: completedLines)
                    PairingReceiptSection(title: "READY NOW", lines: readyLines)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 240)
            .opacity(showText ? 1 : 0)

            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)
            .opacity(showButton ? 1 : 0)
            .scaleEffect(showButton ? 1 : 0.8)
        }
        .onAppear {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                showCheckmark = true
            }

            withAnimation(.easeOut(duration: 0.6)) {
                ringScale = 1.8
                ringOpacity = 0
            }

            withAnimation(.easeOut(duration: 0.3).delay(0.2)) {
                showText = true
            }

            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.4)) {
                showButton = true
            }
        }
    }
}

private struct PairingReceiptSection: View {
    let title: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.green.opacity(0.85))

            VStack(alignment: .leading, spacing: 8) {
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.top, 2)

                        Text(line)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.white.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }
}

private struct PendingApprovalView: View {
    let macName: String?
    let onDone: () -> Void

    private var resolvedMacName: String {
        macName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? macName! : "your Mac"
    }

    private let waitingLines = [
        "This iPhone generated and saved its bridge keypair locally",
        "The Mac received the pairing request and is holding it for approval",
        "Approve the request on the Mac to enable signed bridge connections",
    ]

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.orange.opacity(0.35), lineWidth: 2)
                    .frame(width: 80, height: 80)

                Image(systemName: "desktopcomputer.badge.clock")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.orange)
            }

            VStack(spacing: 8) {
                Text("AWAITING APPROVAL")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(.orange)

                Text(resolvedMacName)
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)

                Text("Approve this iPhone on the Mac to finish pairing")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(waitingLines, id: \.self) { line in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "clock")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.top, 2)

                        Text(line)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 28)

            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.orange)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
        }
    }
}

#Preview {
    QRScannerView()
}
