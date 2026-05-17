//
//  TalkieAIProviderCredentialIngestor.swift
//  Talkie iOS
//
//  Single entry point for accepting iPhone AI credentials from any source
//  (deep link, QR scanner, SSH importer). Consolidates the
//  validate -> save -> set defaults -> reportCompletion pipeline so callers
//  only need to surface the result.
//

import Foundation

@MainActor
struct TalkieAIProviderCredentialIngestor {
    static let shared = TalkieAIProviderCredentialIngestor()

    private init() { }

    struct ImportResult {
        let providerName: String
        let providerId: String
        let modelId: String
        let viaSetupHandshake: Bool
    }

    enum InputRoute {
        case directCredential(TalkieAIProviderCredentialPayload)
        case setupInvite(TalkieAIProviderCredentialSetupInvite)
    }

    func ingest(_ input: InputRoute) async throws -> ImportResult {
        switch input {
        case .directCredential(let payload):
            try await TalkieAIProviderCredentialValidator.shared.validate(payload)
            try Self.persist(payload)
            AppLogger.ui.info(
                "Talkie QR imported iPhone AI credentials",
                detail: "provider=\(payload.providerId) model=\(payload.modelId)"
            )
            return ImportResult(
                providerName: payload.providerName,
                providerId: payload.providerId,
                modelId: payload.modelId,
                viaSetupHandshake: false
            )

        case .setupInvite(let invite):
            do {
                let payload = try await TalkieAIProviderCredentialImportService.shared.importCredentials(from: invite)
                try Self.persist(payload)
                await TalkieAIProviderCredentialImportService.shared.reportCompletion(
                    invite: invite,
                    success: true
                )
                AppLogger.ui.info(
                    "Talkie QR completed secure iPhone AI setup",
                    detail: "provider=\(payload.providerId) model=\(payload.modelId)"
                )
                return ImportResult(
                    providerName: payload.providerName,
                    providerId: payload.providerId,
                    modelId: payload.modelId,
                    viaSetupHandshake: true
                )
            } catch {
                await TalkieAIProviderCredentialImportService.shared.reportCompletion(
                    invite: invite,
                    success: false,
                    message: error.localizedDescription
                )
                throw error
            }
        }
    }

    private static func persist(_ payload: TalkieAIProviderCredentialPayload) throws {
        guard ComposeProviderCredentialStore.shared.save(payload) else {
            throw TalkieAIProviderCredentialImportError.saveFailed
        }
        TalkieAppSettings.shared.composeDirectProviderId = payload.providerId
        TalkieAppSettings.shared.composeDirectModelId = payload.modelId

        if payload.providerId == "openai" {
            TalkieAppSettings.shared.ttsProvider = "openai"
            TalkieAppSettings.shared.ttsMode = "direct"
            if TalkieAppSettings.shared.ttsVoice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                TalkieAppSettings.shared.ttsVoice = "echo"
            }
        }
    }
}
