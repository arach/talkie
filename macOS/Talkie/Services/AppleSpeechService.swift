//
//  AppleSpeechService.swift
//  Talkie macOS
//
//  Apple Speech Framework transcription service.
//  Uses SFSpeechRecognizer for on-device transcription without requiring model downloads.
//  This is the same engine iOS uses, providing a guaranteed-available baseline transcription.
//

import Foundation
import Speech
import os
import Observation

private let logger = Logger(subsystem: "jdi.talkie.core", category: "AppleSpeechService")

// MARK: - Apple Speech Service

@MainActor
@Observable
class AppleSpeechService {
    static let shared = AppleSpeechService()

    var isTranscribing = false
    var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    var lastError: String?

    private let recognizer: SFSpeechRecognizer?

    private init() {
        self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        checkAuthorizationStatus()
    }

    // MARK: - Authorization

    /// Check current authorization status
    func checkAuthorizationStatus() {
        authorizationStatus = SFSpeechRecognizer.authorizationStatus()
    }

    /// Request speech recognition authorization
    func requestAuthorization() async -> Bool {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    self.authorizationStatus = status
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }

    /// Check if service is available and authorized
    var isAvailable: Bool {
        guard let recognizer = recognizer else { return false }
        return recognizer.isAvailable && authorizationStatus == .authorized
    }

    // MARK: - Transcription

    /// Transcribe audio data using Apple Speech
    /// - Parameter audioData: Raw audio data (m4a, wav, etc.)
    /// - Returns: Transcribed text
    func transcribe(audioData: Data) async throws -> String {
        guard let recognizer = recognizer else {
            throw AppleSpeechError.recognizerNotAvailable
        }

        guard recognizer.isAvailable else {
            throw AppleSpeechError.recognizerNotAvailable
        }

        // Check authorization
        if authorizationStatus != .authorized {
            let authorized = await requestAuthorization()
            if !authorized {
                throw AppleSpeechError.notAuthorized
            }
        }

        // Prevent concurrent transcriptions
        guard !isTranscribing else {
            throw AppleSpeechError.alreadyTranscribing
        }

        isTranscribing = true
        lastError = nil

        defer {
            Task { @MainActor in
                self.isTranscribing = false
            }
        }

        logger.info("Starting Apple Speech transcription (\(audioData.count) bytes)")
        await SystemEventManager.shared.log(.transcribe, "Apple Speech transcription started", detail: "\(audioData.count / 1024) KB")

        // Write audio data to temporary file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        do {
            try audioData.write(to: tempURL)

            defer {
                try? FileManager.default.removeItem(at: tempURL)
            }

            // Create recognition request
            let request = SFSpeechURLRecognitionRequest(url: tempURL)
            request.shouldReportPartialResults = false

            // Perform transcription
            let transcript = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                recognizer.recognitionTask(with: request) { result, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let result = result else {
                        continuation.resume(throwing: AppleSpeechError.noResult)
                        return
                    }

                    if result.isFinal {
                        continuation.resume(returning: result.bestTranscription.formattedString)
                    }
                }
            }

            logger.info("Apple Speech transcription complete: \(transcript.prefix(100))...")
            await SystemEventManager.shared.log(.transcribe, "Apple Speech complete", detail: "\(transcript.count) chars")

            return transcript

        } catch {
            lastError = error.localizedDescription
            logger.error("Apple Speech transcription failed: \(error.localizedDescription)")
            await SystemEventManager.shared.log(.error, "Apple Speech failed", detail: error.localizedDescription)
            throw AppleSpeechError.transcriptionFailed(error)
        }
    }
}

// MARK: - Errors

enum AppleSpeechError: LocalizedError {
    case recognizerNotAvailable
    case notAuthorized
    case alreadyTranscribing
    case noResult
    case transcriptionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .recognizerNotAvailable:
            return "Speech recognizer is not available"
        case .notAuthorized:
            return "Speech recognition not authorized"
        case .alreadyTranscribing:
            return "Already transcribing"
        case .noResult:
            return "No transcription result"
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        }
    }
}
