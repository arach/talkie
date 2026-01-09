//
//  QRScannerView.swift
//  Talkie iOS
//
//  QR code scanner for pairing with Mac
//

import SwiftUI
import AVFoundation
import AudioToolbox

struct QRScannerView: View {
    @Environment(\.dismiss) private var dismiss
    private var bridgeManager = BridgeManager.shared
    @State private var isScanning = true
    @State private var scannedCode: String?
    @State private var errorMessage: String?
    @State private var currentStep = 0

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

                if isScanning {
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

                            Text("Open Talkie on your Mac, go to Settings > iOS Bridge, and click \"Pair\"")
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
                        if bridgeManager.status == .connecting {
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
                            .onAppear {
                                startStepProgression()
                            }

                        } else if bridgeManager.status == .connected {
                            // Success state with delightful animation
                            SuccessView(
                                macName: bridgeManager.pairedMacName,
                                onDone: { dismiss() }
                            )

                        } else if bridgeManager.status == .error {
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

    private func startStepProgression() {
        currentStep = 0
        Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { timer in
            if bridgeManager.status != .connecting {
                timer.invalidate()
                return
            }
            if currentStep < pairingSteps.count - 1 {
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentStep += 1
                }
            }
        }
    }

    private func handleScannedCode(_ code: String) {
        guard isScanning else { return }
        isScanning = false
        scannedCode = code

        // Parse QR code
        guard let data = code.data(using: .utf8),
              let qrData = try? JSONDecoder().decode(QRCodeData.self, from: data) else {
            errorMessage = "Invalid QR code format"
            bridgeManager.setError("Invalid QR code format")
            return
        }

        // Verify protocol
        guard qrData.protocol == "talkie-bridge-v1" else {
            errorMessage = "Incompatible bridge version"
            bridgeManager.setError("Incompatible bridge version")
            return
        }

        // Start pairing
        Task {
            await bridgeManager.processPairing(qrData: qrData)
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
    }

    private func startScanning() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }

    private func stopScanning() {
        captureSession?.stopRunning()
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
    @State private var checkmarkScale: CGFloat = 0.3
    @State private var ringScale: CGFloat = 0.8
    @State private var ringOpacity: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 20) {
            // Animated checkmark with ring burst
            ZStack {
                // Expanding ring effect
                Circle()
                    .stroke(Color.green.opacity(ringOpacity), lineWidth: 2)
                    .frame(width: 80, height: 80)
                    .scaleEffect(ringScale)

                // Checkmark circle
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

            // Text content
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

            // Done button
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
            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            // Sequence the animations
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                showCheckmark = true
                checkmarkScale = 1.0
            }

            // Ring burst
            withAnimation(.easeOut(duration: 0.6)) {
                ringScale = 1.8
                ringOpacity = 0
            }

            // Text fade in
            withAnimation(.easeOut(duration: 0.3).delay(0.2)) {
                showText = true
            }

            // Button pop in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.4)) {
                showButton = true
            }
        }
    }
}

#Preview {
    QRScannerView()
}
