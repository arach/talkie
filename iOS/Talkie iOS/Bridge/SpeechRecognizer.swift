//
//  SpeechRecognizer.swift
//  Talkie iOS
//
//  On-device speech recognition for live transcription preview
//  Uses Apple's Speech framework for instant feedback while recording
//
//  NOTE: This recognizer can work in two modes:
//  1. Standalone mode (startListening) - uses its own audio engine
//  2. External buffer mode (startListeningWithExternalAudio) - receives buffers from another source
//

import Foundation
import Speech
import AVFoundation

/// On-device speech recognizer for live transcription preview
@MainActor
class SpeechRecognizer: ObservableObject {
    @Published var transcript: String = ""
    @Published var isListening: Bool = false
    @Published var error: String?

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var useExternalAudio = false
    private var recognitionStartTime: Date?

    init() {
        // Use on-device recognition if available (iOS 13+)
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current)

        // Check if on-device recognition is supported
        if #available(iOS 13, *) {
            speechRecognizer?.supportsOnDeviceRecognition = true
        }
    }

    /// Request speech recognition authorization
    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Start listening and transcribing
    /// Call this when audio recording starts
    func startListening() {
        // Reset state
        transcript = ""
        error = nil

        // Check authorization
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            error = "Speech recognition not authorized"
            return
        }

        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            error = "Speech recognition not available"
            return
        }

        // Cancel any existing task
        stopListening()

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let recognitionRequest = recognitionRequest else {
            error = "Could not create recognition request"
            return
        }

        // Configure for live results
        recognitionRequest.shouldReportPartialResults = true

        // Prefer on-device recognition for speed and privacy
        if #available(iOS 13, *) {
            recognitionRequest.requiresOnDeviceRecognition = speechRecognizer.supportsOnDeviceRecognition
        }

        // Don't add punctuation for preview (cleaner look)
        if #available(iOS 16, *) {
            recognitionRequest.addsPunctuation = false
        }

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }

                if let result = result {
                    // Update transcript with best transcription
                    self.transcript = result.bestTranscription.formattedString
                }

                if let error = error {
                    // Only log actual errors, not cancellations
                    let nsError = error as NSError
                    if nsError.domain != "kAFAssistantErrorDomain" || nsError.code != 216 {
                        AppLogger.recording.debug("Speech recognition: \(error.localizedDescription)")
                    }
                }
            }
        }

        // Get audio input node
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Install tap to capture audio for recognition
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        // Start audio engine
        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            AppLogger.recording.info("Speech recognition started (on-device: \(speechRecognizer.supportsOnDeviceRecognition))")
        } catch {
            self.error = "Could not start audio engine"
            AppLogger.recording.error("Speech recognition engine failed: \(error)")
        }
    }

    /// Stop listening
    /// Call this when audio recording stops
    func stopListening() {
        // Stop audio engine
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        // End recognition request
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        // Cancel recognition task
        recognitionTask?.cancel()
        recognitionTask = nil

        isListening = false
    }

    /// Clear the transcript
    func clear() {
        transcript = ""
        error = nil
    }

    /// Transcribe an audio file (post-recording)
    /// This runs Apple Speech on the captured audio file for preview
    func transcribeFile(_ url: URL) {
        transcript = ""
        error = nil

        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            error = "Speech recognition not authorized"
            return
        }

        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            error = "Speech recognition not available"
            return
        }

        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Create URL-based recognition request
        let request = SFSpeechURLRecognitionRequest(url: url)

        // Configure for partial results (progressive transcription)
        request.shouldReportPartialResults = true

        // Prefer on-device for speed
        if #available(iOS 13, *) {
            request.requiresOnDeviceRecognition = speechRecognizer.supportsOnDeviceRecognition
        }

        isListening = true

        // Start recognition
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }

                if let result = result {
                    let newText = result.bestTranscription.formattedString

                    if newText != self.transcript {
                        self.transcript = newText
                    }

                    if result.isFinal {
                        self.isListening = false
                    }
                }

                if let error = error {
                    let nsError = error as NSError
                    // Ignore cancellation errors
                    if nsError.domain != "kAFAssistantErrorDomain" || nsError.code != 216 {
                        self.error = error.localizedDescription
                    }
                    self.isListening = false
                }
            }
        }
    }

    /// Stop file transcription
    func stopFileTranscription() {
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
    }
}
