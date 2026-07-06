//
//  TranscriptionService.swift
//  talkie
//
//  Created by Claude Code on 2025-11-23.
//
//  Updated 2026-01: SpeechAnalyzer for Apple Speech (iOS 26+ only app)
//  Updated 2026-01: Added Parakeet (local AI) engine support
//

import Foundation
import Speech
import CoreData
import AVFoundation

// MARK: - Transcription Engine Protocol

protocol TranscriptionEngine {
    func transcribe(audioURL: URL) async throws -> String
    var engineName: String { get }
}

// MARK: - Transcription Settings

/// User preference for transcription engine
enum TranscriptionEnginePreference: String, CaseIterable {
    case auto = "auto"          // Use best available (Parakeet if downloaded, else Apple)
    case appleSpeech = "apple"  // Always use Apple Speech
    case parakeet = "parakeet"  // Always use Parakeet (downloads if needed)

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .appleSpeech: return "Apple Speech"
        case .parakeet: return "Parakeet (Local AI)"
        }
    }
}

/// Context for transcription - determines which engine preference to use
enum TranscriptionUseCase {
    case keyboard   // Live dictation via keyboard
    case memo       // Background memo transcription
}

// MARK: - TranscriptionService

class TranscriptionService {

    static let shared = TranscriptionService()

    /// The engine name used for the most recent transcription, for UI display
    @MainActor static var lastUsedEngineName: String = ""

    /// Engine preference for keyboard dictation (default: auto/Parakeet)
    var keyboardEnginePreference: TranscriptionEnginePreference {
        get {
            let raw = TalkieAppConfigurationStore.shared.configuration.transcription.keyboardEngine
            return TranscriptionEnginePreference(rawValue: raw) ?? .auto
        }
        set {
            TalkieAppConfigurationStore.shared.update { configuration in
                configuration.transcription.keyboardEngine = newValue.rawValue
            }
            Task { @MainActor in
                TalkieAppSettings.shared.transcriptionKeyboardEngine = newValue
            }
        }
    }

    /// Engine preference for memo transcription (default: Apple Speech)
    var memoEnginePreference: TranscriptionEnginePreference {
        get {
            let raw = TalkieAppConfigurationStore.shared.configuration.transcription.memoEngine
            return TranscriptionEnginePreference(rawValue: raw) ?? .appleSpeech
        }
        set {
            TalkieAppConfigurationStore.shared.update { configuration in
                configuration.transcription.memoEngine = newValue.rawValue
            }
            Task { @MainActor in
                TalkieAppSettings.shared.transcriptionMemoEngine = newValue
            }
        }
    }

    /// Legacy: global engine preference (for backwards compatibility)
    var enginePreference: TranscriptionEnginePreference {
        get { keyboardEnginePreference }
        set { keyboardEnginePreference = newValue }
    }

    /// The Apple Speech engine (SpeechAnalyzer).
    private let appleSpeechEngine: TranscriptionEngine

    private init() {
        self.appleSpeechEngine = SpeechAnalyzerEngine()
        AppLogger.transcription.info("Apple Speech engine: SpeechAnalyzer")
    }

    /// Get the engine to use based on use case preference
    /// - Parameter useCase: The context (keyboard vs memo) - if nil, uses keyboard preference
    private func getEngine(for useCase: TranscriptionUseCase?) async -> TranscriptionEngine {
        // Determine which preference to use
        let preference: TranscriptionEnginePreference
        let useCaseLabel: String

        switch useCase {
        case .keyboard, .none:
            preference = keyboardEnginePreference
            useCaseLabel = "Keyboard"
        case .memo:
            preference = memoEnginePreference
            useCaseLabel = "Memo"
        }

        // Resolve preference to engine
        // For keyboard dictation, NEVER block on model loading — fall back to Apple Speech
        let parakeetManager = await ParakeetModelManager.shared
        let parakeetState = await parakeetManager.state
        let parakeetWarmed = await parakeetManager.isWarmedUp
        let parakeetReady = parakeetState == .ready && parakeetWarmed

        switch preference {
        case .appleSpeech:
            AppLogger.transcription.debug("\(useCaseLabel) transcription: using Apple Speech (configured)")
            return appleSpeechEngine

        case .parakeet:
            if parakeetReady {
                AppLogger.transcription.debug("\(useCaseLabel) transcription: using Parakeet (configured, ready)")
                return ParakeetEngine()
            }

            // Parakeet preferred but not ready — fall back to Apple Speech for keyboard
            // (don't block live dictation waiting for model to load)
            // NOTE: Do NOT call preheatForKeyboard() here — it triggers ANE-heavy model
            // compilation that competes with SpeechAnalyzer. Preheat is already kicked off
            // from HeadlessDictationService (enterReadyMode, handleDictationRequest, etc.)
            if useCase == .keyboard || useCase == nil {
                AppLogger.transcription.info("\(useCaseLabel) transcription: Parakeet preferred but not ready (state=\(parakeetState), warmed=\(parakeetWarmed)), falling back to Apple Speech")
                return appleSpeechEngine
            }

            // Non-keyboard use case (memo) — allow blocking load
            AppLogger.transcription.debug("\(useCaseLabel) transcription: using Parakeet (configured, will load)")
            return ParakeetEngine()

        case .auto:
            if parakeetReady {
                AppLogger.transcription.debug("\(useCaseLabel) transcription: using Parakeet (auto, ready)")
                return ParakeetEngine()
            }

            // Parakeet not ready — use Apple Speech, no waiting
            // NOTE: Do NOT call preheatForKeyboard() here — it triggers ANE-heavy model
            // compilation that competes with SpeechAnalyzer. Preheat is already kicked off
            // from HeadlessDictationService (enterReadyMode, handleDictationRequest, etc.)
            AppLogger.transcription.info("\(useCaseLabel) transcription: Parakeet not ready (state=\(parakeetState), warmed=\(parakeetWarmed)), using Apple Speech")
            return appleSpeechEngine
        }
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }

    /// Transcribe audio file
    /// - Parameters:
    ///   - audioURL: URL to the audio file
    ///   - useCase: Context for transcription (keyboard vs memo) - determines engine selection
    ///   - completion: Result callback
    func transcribe(audioURL: URL, useCase: TranscriptionUseCase? = nil, completion: @escaping (Result<String, Error>) -> Void) {
        Task {
            do {
                let engine = await getEngine(for: useCase)
                await MainActor.run {
                    TranscriptionService.lastUsedEngineName = engine.engineName
                }
                let startTime = CFAbsoluteTimeGetCurrent()

                let result = try await engine.transcribe(audioURL: audioURL)

                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                AppLogger.transcription.info("[\(engine.engineName)] Transcription completed in \(String(format: "%.2f", elapsed))s")

                DispatchQueue.main.async {
                    completion(.success(result))
                }
            } catch {
                AppLogger.transcription.error("Transcription failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    func transcribeVoiceMemo(_ memo: VoiceMemo, context: NSManagedObjectContext) {
        let memoObjectID = memo.objectID

        guard let filename = memo.fileURL else {
            AppLogger.transcription.warning("No filename for transcription")
            clearTranscribingFlag(for: memoObjectID, context: context)
            return
        }

        let url = URL.documentsDirectory.appending(path: filename)

        guard FileManager.default.fileExists(atPath: url.path) else {
            AppLogger.transcription.warning("Audio file doesn't exist at \(url.path)")
            clearTranscribingFlag(for: memoObjectID, context: context)
            return
        }

        // Set transcribing flag on main context
        context.perform {
            guard let memo = try? context.existingObject(with: memoObjectID) as? VoiceMemo else { return }
            memo.isTranscribing = true
            try? context.save()
            VoiceMemoStore.publishChange(context: context)
            AppLogger.transcription.info("Starting transcription for: \(filename)")
        }

        // Do transcription work - memos use Apple Speech (no model loading overhead)
        transcribe(audioURL: url, useCase: .memo) { [weak context] result in
            guard let context = context else { return }

            // Save transcription on main context
            context.perform {
                // Fetch the memo in this context using objectID
                guard let memo = try? context.existingObject(with: memoObjectID) as? VoiceMemo else {
                    AppLogger.transcription.error("Failed to fetch memo in background context")
                    return
                }

                switch result {
                case .success(let transcription):
                    AppLogger.transcription.info("Transcription succeeded (\(transcription.count) chars)")
                    // Create versioned transcript (also sets legacy field for compatibility)
                    memo.addSystemTranscript(
                        content: transcription,
                        fromMacOS: false,
                        engine: TranscriptEngines.bestIOSEngine
                    )
                    memo.isTranscribing = false

                    // Auto-title with Apple Intelligence in background
                    Task { @MainActor in
                        await OnDeviceAIService.shared.autoTitleMemoIfNeeded(memo, context: context)
                    }

                    if let memoId = memo.id?.uuidString {
                        let memoTitle = memo.title ?? "Recording"
                        let memoDuration = memo.duration

                        Task { @MainActor in
                            await RecordingSidecarProcessor.shared.processQueuedRequests(
                                memoId: memoId,
                                memoTitle: memoTitle,
                                transcript: transcription,
                                duration: memoDuration
                            )
                        }
                    }

                case .failure(let error):
                    AppLogger.transcription.error("Transcription failed: \(error.localizedDescription)")
                    memo.isTranscribing = false
                }

                do {
                    try context.save()
                    VoiceMemoStore.publishChange(context: context)
                    AppLogger.persistence.info("Transcription saved successfully to Core Data")
                } catch {
                    AppLogger.persistence.error("Failed to save transcription: \(error.localizedDescription)")
                }
            }
        }
    }

    private func clearTranscribingFlag(for memoObjectID: NSManagedObjectID, context: NSManagedObjectContext) {
        context.perform {
            guard let memo = try? context.existingObject(with: memoObjectID) as? VoiceMemo else { return }
            memo.isTranscribing = false

            do {
                try context.save()
                VoiceMemoStore.publishChange(context: context)
            } catch {
                AppLogger.persistence.error("Failed to clear transcription state: \(error.localizedDescription)")
            }
        }
    }
}

enum TranscriptionError: Error {
    case recognizerNotAvailable
    case noResult
    case modelNotAvailable
    case transcriptionFailed(String)

    var localizedDescription: String {
        switch self {
        case .recognizerNotAvailable:
            return "Speech recognizer is not available"
        case .noResult:
            return "No transcription result"
        case .modelNotAvailable:
            return "Speech model is not available"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        }
    }
}

// MARK: - SpeechAnalyzer Engine

private class SpeechAnalyzerEngine: TranscriptionEngine {
    var engineName: String { "SpeechAnalyzer" }

    /// Find a supported locale from SpeechTranscriber.supportedLocales
    /// Must use actual locale objects from the list, not manually constructed ones
    private func findSupportedLocale(preferring languageCode: String) async throws -> Locale {
        let supportedLocales = await SpeechTranscriber.supportedLocales

        // First, try to find exact match for preferred language
        if let match = supportedLocales.first(where: {
            $0.language.languageCode?.identifier == languageCode
        }) {
            return match
        }

        // Fall back to English
        if let english = supportedLocales.first(where: {
            $0.language.languageCode?.identifier == "en"
        }) {
            AppLogger.transcription.info("SpeechAnalyzer: Locale \(languageCode) not supported, using English")
            return english
        }

        // Last resort: first available locale
        guard let fallback = supportedLocales.first else {
            throw TranscriptionError.recognizerNotAvailable
        }

        AppLogger.transcription.info("SpeechAnalyzer: Using fallback locale \(fallback.identifier)")
        return fallback
    }

    func transcribe(audioURL: URL) async throws -> String {
        // Find a supported locale - must use one from supportedLocales, not create manually
        let transcriptionLocale = try await findSupportedLocale(preferring: Locale.current.language.languageCode?.identifier ?? "en")
        AppLogger.transcription.debug("SpeechAnalyzer: Using locale \(transcriptionLocale.identifier)")

        // Create transcriber with transcription preset
        let transcriber = SpeechTranscriber(locale: transcriptionLocale, preset: .transcription)

        // Ensure the model is installed
        let installedLocales = await SpeechTranscriber.installedLocales
        let isInstalled = installedLocales.contains {
            $0.language.languageCode == transcriptionLocale.language.languageCode
        }

        if !isInstalled {
            AppLogger.transcription.info("SpeechAnalyzer: Model not installed for \(transcriptionLocale.identifier), downloading...")
            if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await downloader.downloadAndInstall()
                AppLogger.transcription.info("SpeechAnalyzer: Model downloaded successfully")
            }
        }

        // Create the analyzer with the transcriber module
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        // Start collecting results before analysis begins
        async let transcriptionFuture: String = {
            var text = ""
            for try await result in transcriber.results {
                if result.isFinal {
                    // result.text is AttributedString, convert to String
                    text += String(result.text.characters)
                }
            }
            return text
        }()

        // Open audio file and analyze
        let audioFile = try AVAudioFile(forReading: audioURL)
        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        }

        // Wait for all results
        let transcriptionText = try await transcriptionFuture

        if transcriptionText.isEmpty {
            throw TranscriptionError.noResult
        }

        return transcriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
