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
    @State private var bridgeManager = BridgeManager.shared
    @State private var isScanning = true
    @State private var scannedCode: String?
    @State private var errorMessage: String?
    @State private var pairingStatus: String = ""
    @State private var statusIndex = 0

    // Techy status messages during pairing
    private let pairingStatuses = [
        "Decoding QR payload...",
        "Extracting public key...",
        "Generating keypair...",
        "Deriving shared secret...",
        "Establishing secure channel...",
        "Authenticating device...",
        "Syncing clocks...",
        "Verifying connection..."
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
                            // Techy pairing animation
                            VStack(spacing: 16) {
                                BrailleSpinner(speed: 0.06, color: .green)

                                Text("PAIRING")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .tracking(4)
                                    .foregroundColor(.green)

                                Text(pairingStatus)
                                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.8))
                                    .animation(.easeInOut(duration: 0.2), value: pairingStatus)
                            }
                            .onAppear {
                                startStatusAnimation()
                            }

                        } else if bridgeManager.status == .connected {
                            // Success state
                            VStack(spacing: 16) {
                                Text("✓")
                                    .font(.system(size: 48, weight: .light, design: .monospaced))
                                    .foregroundColor(.green)

                                Text("PAIRED")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .tracking(4)
                                    .foregroundColor(.green)

                                if let macName = bridgeManager.pairedMacName {
                                    Text(macName)
                                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.7))
                                }

                                Text("Secure connection established")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))
                            }

                            Button("Done") {
                                dismiss()
                            }
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                            .background(Color.green)
                            .cornerRadius(8)
                            .padding(.top, 20)

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
                                statusIndex = 0
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

    private func startStatusAnimation() {
        pairingStatus = pairingStatuses[0]
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { timer in
            if bridgeManager.status != .connecting {
                timer.invalidate()
                return
            }
            statusIndex = (statusIndex + 1) % pairingStatuses.count
            pairingStatus = pairingStatuses[statusIndex]
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

#Preview {
    QRScannerView()
}
