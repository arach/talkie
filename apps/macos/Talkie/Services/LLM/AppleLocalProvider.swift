//
//  AppleLocalProvider.swift
//  Talkie
//
//  On-device LLM provider using Apple FoundationModels (macOS 26+)
//  Zero cost, zero latency, zero network. Runs entirely on Apple Silicon.
//

import Foundation
import TalkieKit

#if canImport(FoundationModels)
import FoundationModels
#endif

private let log = Log(.system)

class AppleLocalProvider: LLMProvider {
    let id = "apple-local"
    let name = "Apple Intelligence"
    #if canImport(FoundationModels)
    private let warmupController = AppleLocalWarmupController()
    #endif

    init() {
        #if canImport(FoundationModels)
        Task { [warmupController] in
            await warmupController.prewarmIfNeeded()
        }
        #endif
    }

    var models: [LLMModel] {
        get async throws {
            guard await isAvailable else { return [] }
            return [
                LLMModel(
                    id: "apple-on-device",
                    name: "apple-on-device",
                    displayName: "Apple Intelligence (On-Device)",
                    size: "On-Device",
                    type: .local,
                    provider: id,
                    downloadURL: nil,
                    isInstalled: true
                )
            ]
        }
    }

    var isAvailable: Bool {
        get async {
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                let availability = SystemLanguageModel.default.availability
                switch availability {
                case .available:
                    return true
                case .unavailable(let reason):
                    log.debug("Apple Intelligence unavailable: \(reason)")
                    return false
                @unknown default:
                    return false
                }
            }
            #endif
            return false
        }
    }

    func generate(
        prompt: String,
        model: String,
        options: GenerationOptions  // Talkie's GenerationOptions
    ) async throws -> String {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else {
            throw LLMError.providerNotAvailable("Requires macOS 26+")
        }

        guard await isAvailable else {
            throw LLMError.providerNotAvailable("Apple Intelligence is not enabled")
        }

        await warmupController.prewarmIfNeeded()

        let session = makeSession(systemPrompt: options.systemPrompt)
        let trimmedPrompt = String(prompt.prefix(3000))

        let response = try await session.respond(
            to: trimmedPrompt,
            options: makeNativeOptions(from: options)
        )
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        throw LLMError.providerNotAvailable("FoundationModels not available")
        #endif
    }

    func streamGenerate(
        prompt: String,
        model: String,
        options: GenerationOptions  // Talkie's GenerationOptions
    ) async throws -> AsyncThrowingStream<String, Error> {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else {
            throw LLMError.providerNotAvailable("Requires macOS 26+")
        }

        guard await isAvailable else {
            throw LLMError.providerNotAvailable("Apple Intelligence is not enabled")
        }

        await warmupController.prewarmIfNeeded()

        let session = makeSession(systemPrompt: options.systemPrompt)
        let trimmedPrompt = String(prompt.prefix(3000))
        let nativeOpts = makeNativeOptions(from: options)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let stream = session.streamResponse(to: trimmedPrompt, options: nativeOpts)
                    var prev = ""

                    for try await snapshot in stream {
                        let content = snapshot.content
                        if content.count > prev.count {
                            let idx = content.index(content.startIndex, offsetBy: prev.count)
                            let delta = String(content[idx...])
                            continuation.yield(delta)
                        }
                        prev = content
                    }

                    continuation.finish()
                } catch {
                    log.error("Apple Intelligence streaming failed: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
        #else
        throw LLMError.providerNotAvailable("FoundationModels not available")
        #endif
    }

    // MARK: - Private

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func makeSession(systemPrompt: String?) -> LanguageModelSession {
        guard let systemPrompt, !systemPrompt.isEmpty else {
            return LanguageModelSession()
        }
        let instructions = "You are a helpful assistant. " + systemPrompt
        return LanguageModelSession(instructions: instructions)
    }

    @available(macOS 26.0, *)
    private func makeNativeOptions(from options: GenerationOptions) -> FoundationModels.GenerationOptions {
        FoundationModels.GenerationOptions(temperature: options.temperature)
    }

    private func schedulePrewarmIfNeeded() {
        Task { [warmupController] in
            await warmupController.prewarmIfNeeded()
        }
    }
    #endif
}

#if canImport(FoundationModels)
private actor AppleLocalWarmupController {
    private let refreshInterval: TimeInterval = 300
    private var warmSession: Any?
    private var lastPrewarmAt: Date?

    func prewarmIfNeeded() {
        guard #available(macOS 26.0, *) else { return }
        guard modelIsAvailable else { return }

        let now = Date()
        if let lastPrewarmAt,
           now.timeIntervalSince(lastPrewarmAt) < refreshInterval {
            return
        }

        let session = (warmSession as? LanguageModelSession) ?? LanguageModelSession()
        session.prewarm()
        warmSession = session
        lastPrewarmAt = now
        log.debug("Apple Intelligence prewarmed")
    }

    @available(macOS 26.0, *)
    private var modelIsAvailable: Bool {
        switch SystemLanguageModel.default.availability {
        case .available:
            return true
        default:
            return false
        }
    }
}
#endif
