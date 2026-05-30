//
//  TalkieQRCodeNavigator.swift
//  Talkie iOS
//
//  Routes scanned QR payloads to the right Talkie surface (bridge,
//  SSH, AI credentials, deep links). Shared by the dedicated scanner
//  and the live camera capture flow.
//

import Foundation
import TalkieMobileKit

@MainActor
enum TalkieQRCodeNavigator {
    struct Outcome {
        let userMessage: String?
        let leavesCaptureSurface: Bool
    }

    static func handle(scannedCode: String) async -> Outcome {
        do {
            let route = try await TalkieQRCodeRouter.route(scannedCode: scannedCode)

            switch route {
            case .bridge(let qrData):
                AppLogger.ui.info("Talkie QR routed to Mac Bridge pairing", detail: "host=\(qrData.hostname)")
                let bridgeManager = BridgeManager.shared
                let pairingResult = await bridgeManager.processPairing(qrData: qrData)

                switch pairingResult {
                case .approved:
                    let macName = bridgeManager.pairedMacDisplayName ?? qrData.hostname
                    AppShellRouter.shared.openConnectionCenter()
                    return Outcome(
                        userMessage: "Paired with \(macName)",
                        leavesCaptureSurface: true
                    )

                case .pendingApproval:
                    AppShellRouter.shared.openConnectionCenter()
                    return Outcome(
                        userMessage: "Waiting for Mac approval",
                        leavesCaptureSurface: true
                    )

                case nil:
                    let message = bridgeManager.errorMessage ?? "Could not pair with this Mac."
                    bridgeManager.setError(message)
                    return Outcome(userMessage: message, leavesCaptureSurface: false)
                }

            case .sshPayload(_, let payload):
                let host = payload.connection?.normalizedHost ?? "terminal"
                AppLogger.ui.info("Talkie QR routed to SSH terminal import", detail: "host=\(host)")
                let label = payload.label?.trimmingCharacters(in: .whitespacesAndNewlines)
                let sourceDescription = if let label, !label.isEmpty {
                    "Review \(label) from terminal setup before importing."
                } else {
                    "Review the SSH import from terminal setup before saving anything."
                }
                DeepLinkManager.shared.queueSSHImport(
                    payload: payload,
                    sourceDescription: sourceDescription
                )
                DeepLinkManager.shared.pendingAction = .openSSHTerminal
                AppShellRouter.shared.openTerminal()
                return Outcome(userMessage: "SSH key ready to import", leavesCaptureSurface: true)

            case .aiProviderCredential(let payload):
                _ = try await TalkieAIProviderCredentialIngestor.shared.ingest(.directCredential(payload))
                AppShellRouter.shared.openAICredentials()
                return Outcome(userMessage: "AI key saved", leavesCaptureSurface: true)

            case .aiProviderCredentialSetup(let invite):
                _ = try await TalkieAIProviderCredentialIngestor.shared.ingest(.setupInvite(invite))
                AppShellRouter.shared.openAICredentials()
                return Outcome(userMessage: "AI setup invite accepted", leavesCaptureSurface: true)

            case .talkieURL(let url):
                AppLogger.ui.info("Talkie QR routed via deep link", detail: url.absoluteString)
                DeepLinkManager.shared.handle(url: url)
                return Outcome(userMessage: nil, leavesCaptureSurface: true)
            }
        } catch TalkieQRCodeRouterError.unrecognizedCode {
            return Outcome(
                userMessage: TalkieQRCodeRouterError.unrecognizedCode.localizedDescription,
                leavesCaptureSurface: false
            )
        } catch {
            return Outcome(userMessage: error.localizedDescription, leavesCaptureSurface: false)
        }
    }
}
