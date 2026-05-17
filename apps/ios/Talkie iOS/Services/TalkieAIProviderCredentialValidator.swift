//
//  TalkieAIProviderCredentialValidator.swift
//  Talkie iOS
//
//  Performs a quick provider-side key check before saving imported AI credentials.
//

import Foundation

struct TalkieAIProviderCredentialValidator {
    static let shared = TalkieAIProviderCredentialValidator()

    private init() { }

    func validate(_ payload: TalkieAIProviderCredentialPayload) async throws {
        guard TalkieAIProviderCredentialValidationPolicy.allowsProviderValidation else {
            AppLogger.ai.warning(
                "Provider credential validation blocked",
                detail: "provider=\(payload.providerId) reason=debug_override"
            )
            throw TalkieAIProviderCredentialValidationError.providerValidationDisabled
        }

        let url = try validationURL(for: payload.providerId)
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(payload.apiKey)", forHTTPHeaderField: "Authorization")

        AppLogger.ai.info(
            "Validating imported AI credentials",
            detail: "provider=\(payload.providerId) model=\(payload.modelId)"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TalkieAIProviderCredentialValidationError.invalidResponse(payload.providerName)
        }

        switch httpResponse.statusCode {
        case 200..<300:
            AppLogger.ai.info(
                "Imported AI credentials validated",
                detail: "provider=\(payload.providerId) model=\(payload.modelId)"
            )

        case 401, 403:
            AppLogger.ai.warning(
                "Imported AI credentials rejected",
                detail: "provider=\(payload.providerId) status=\(httpResponse.statusCode)"
            )
            throw TalkieAIProviderCredentialValidationError.rejected(payload.providerName)

        default:
            let message = parseAPIErrorMessage(from: data)
            AppLogger.ai.warning(
                "Imported AI credential validation failed",
                detail: "provider=\(payload.providerId) status=\(httpResponse.statusCode) message=\(message)"
            )
            throw TalkieAIProviderCredentialValidationError.apiError(
                providerName: payload.providerName,
                statusCode: httpResponse.statusCode,
                message: message
            )
        }
    }

    private func validationURL(for providerId: String) throws -> URL {
        switch providerId {
        case "openai":
            guard let url = URL(string: "https://api.openai.com/v1/models") else {
                throw TalkieAIProviderCredentialValidationError.invalidResponse("OpenAI")
            }
            return url
        case "groq":
            guard let url = URL(string: "https://api.groq.com/openai/v1/models") else {
                throw TalkieAIProviderCredentialValidationError.invalidResponse("Groq")
            }
            return url
        default:
            throw TalkieAIProviderCredentialValidationError.unsupportedProvider(
                TalkieAIProviderCredentialPayload.displayName(for: providerId)
            )
        }
    }

    private func parseAPIErrorMessage(from data: Data) -> String {
        if let errorEnvelope = try? JSONDecoder().decode(AIProviderValidationErrorEnvelope.self, from: data),
           let message = errorEnvelope.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return message
        }

        if let string = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !string.isEmpty {
            return string
        }

        return "Unknown API error"
    }
}

enum TalkieAIProviderCredentialValidationPolicy {
    private static let persistedDebugDisableKey = "TalkieDisableAIProviderCredentialValidation"

    static var allowsProviderValidation: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["TALKIE_DISABLE_AI_PROVIDER_CREDENTIAL_VALIDATION"] == "1" {
            return false
        }

        if UserDefaults.standard.object(forKey: persistedDebugDisableKey) != nil {
            UserDefaults.standard.removeObject(forKey: persistedDebugDisableKey)
        }
        #endif

        return true
    }
}

private struct AIProviderValidationErrorEnvelope: Decodable {
    let error: AIProviderValidationErrorBody?
}

private struct AIProviderValidationErrorBody: Decodable {
    let message: String?
}

enum TalkieAIProviderCredentialValidationError: LocalizedError {
    case providerValidationDisabled
    case unsupportedProvider(String)
    case invalidResponse(String)
    case rejected(String)
    case apiError(providerName: String, statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .providerValidationDisabled:
            return "Provider validation is disabled for this debug credential capture run."
        case .unsupportedProvider(let providerName):
            return "\(providerName) is not supported for iPhone AI credentials."
        case .invalidResponse(let providerName):
            return "\(providerName) returned an invalid validation response."
        case .rejected(let providerName):
            return "\(providerName) rejected this API key. Create a fresh key and scan again."
        case .apiError(let providerName, let statusCode, let message):
            return "\(providerName) could not validate this API key. HTTP \(statusCode): \(message)"
        }
    }
}
