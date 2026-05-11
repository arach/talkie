//
//  SSHPrivateKeyQRCodeImportView.swift
//  Talkie iOS
//
//  Camera-based QR importer for SSH private keys.
//

import SwiftUI
import TalkieMobileKit

struct SSHPrivateKeyQRCodeImportView: View {
    private struct BridgePairingResult: Equatable {
        let macName: String
        let hostname: String
        let awaitingApproval: Bool
    }

    @Environment(\.dismiss) private var dismiss

    let onImport: (SSHPrivateKeyQRCodePayload) -> Void

    @State private var scannerResetID = UUID()
    @State private var errorMessage: String?
    @State private var isImporting = false
    @State private var bridgePairingResult: BridgePairingResult?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                QRCodeScannerRepresentable { code in
                    handleScannedCode(code)
                }
                .id(scannerResetID)
                .ignoresSafeArea()

                overlayContent
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }

    private var overlayContent: some View {
        VStack(spacing: 0) {
            Spacer()

            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 3)
                .frame(width: 240, height: 240)

            Spacer()

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Scan SSH Access QR")
                    .font(.headlineMedium)
                    .foregroundStyle(.white)

                Text("Scan the SSH access QR from Talkie for Mac to add a terminal here. Bridge pairing QRs are recognized too, but they only pair the Mac and won’t create a configured terminal.")
                    .font(.bodySmall)
                    .foregroundStyle(Color.white.opacity(0.8))

                if let bridgePairingResult {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(
                            bridgePairingResult.awaitingApproval
                                ? "Sent a pairing request to \(bridgePairingResult.macName)."
                                : "Paired \(bridgePairingResult.macName) for Mac Bridge."
                        )
                            .font(.bodySmall)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)

                        Text(
                            bridgePairingResult.awaitingApproval
                                ? "Approve this iPhone on \(bridgePairingResult.hostname) to finish Mac Bridge pairing. To add it under Configured terminals, scan the SSH access QR from Talkie for Mac."
                                : "This QR only set up direct pairing for \(bridgePairingResult.hostname). To add it under Configured terminals, scan the SSH access QR from Talkie for Mac."
                        )
                            .font(.bodySmall)
                            .foregroundStyle(Color.white.opacity(0.8))

                        HStack(spacing: Spacing.sm) {
                            Button("Scan SSH QR") {
                                resetScanner()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.white)
                            .foregroundStyle(.black)

                            Button("Done") {
                                dismiss()
                            }
                            .buttonStyle(.bordered)
                            .tint(.white)
                            .foregroundStyle(.white)
                        }
                    }
                    .padding(Spacing.sm)
                    .background(Color.white.opacity(0.12))
                    .clipShape(.rect(cornerRadius: CornerRadius.md))
                } else if let errorMessage {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(errorMessage)
                            .font(.bodySmall)
                            .foregroundStyle(Color.recording)

                        Button("Scan Again") {
                            resetScanner()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                        .foregroundStyle(.black)
                    }
                    .padding(Spacing.sm)
                    .background(Color.white.opacity(0.12))
                    .clipShape(.rect(cornerRadius: CornerRadius.md))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
            .background(.black.opacity(0.72))
        }
    }

    private func handleScannedCode(_ code: String) {
        guard !isImporting, errorMessage == nil, bridgePairingResult == nil else { return }
        isImporting = true

        Task {
            do {
                let route = try await TalkieQRCodeRouter.route(scannedCode: code)

                switch route {
                case .sshPayload(_, let payload):
                    let privateKey = payload.normalizedPrivateKey
                    _ = try SSHPrivateKeyParser.parse(privateKey)
                    let host = payload.connection?.normalizedHost ?? "none"
                    let username = payload.connection?.normalizedUsername ?? "none"

                    await MainActor.run {
                        AppLogger.ui.info(
                            "SSH QR recognized",
                            detail: "label=\(payload.label ?? "none") host=\(host) username=\(username) autoConnect=\(payload.connection?.shouldAutoConnect == true)"
                        )
                        onImport(payload)
                        dismiss()
                    }

                case .bridge(let qrData):
                    await MainActor.run {
                        AppLogger.ui.info("Talkie QR routed to Mac Bridge pairing", detail: "host=\(qrData.hostname)")
                    }
                    let pairingResult = await BridgeManager.shared.processPairing(qrData: qrData)
                    await MainActor.run {
                        guard let pairingResult else {
                            errorMessage = BridgeManager.shared.errorMessage ?? "Could not pair with this Mac."
                            isImporting = false
                            return
                        }

                        let macName = BridgeManager.shared.pairedMacName?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        let resolvedMacName = if let macName, !macName.isEmpty {
                            macName
                        } else {
                            qrData.hostname
                        }
                        bridgePairingResult = BridgePairingResult(
                            macName: resolvedMacName,
                            hostname: qrData.hostname,
                            awaitingApproval: pairingResult == .pendingApproval
                        )
                        isImporting = false
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
                    AppLogger.ui.error("SSH QR import failed: \(error.localizedDescription)")
                    errorMessage = error.localizedDescription
                    isImporting = false
                }
            }
        }
    }

    private func resetScanner() {
        errorMessage = nil
        isImporting = false
        bridgePairingResult = nil
        scannerResetID = UUID()
    }
}
