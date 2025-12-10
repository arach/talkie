//
//  SpeechSynthesisService.swift
//  Talkie macOS
//
//  Text-to-Speech service for voice replies - turning Talkie into Walkie-Talkie!
//  Uses Apple's AVSpeechSynthesizer for on-device, private speech generation.
//

import AVFoundation
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "SpeechSynthesis")

// MARK: - Speech Synthesis Service

@MainActor
class SpeechSynthesisService: NSObject, ObservableObject {
    static let shared = SpeechSynthesisService()

    private let synthesizer = AVSpeechSynthesizer()

    @Published var isSpeaking = false
    @Published var availableVoices: [AVSpeechSynthesisVoice] = []

    // Settings
    @Published var selectedVoiceIdentifier: String?
    @Published var speechRate: Float = AVSpeechUtteranceDefaultSpeechRate
    @Published var speechPitch: Float = 1.0
    @Published var speechVolume: Float = 1.0

    private var completionHandler: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
        loadAvailableVoices()
        selectDefaultVoice()
    }

    // MARK: - Voice Management

    private func loadAvailableVoices() {
        // Get all available voices, prioritize enhanced/premium voices
        let allVoices = AVSpeechSynthesisVoice.speechVoices()

        // Filter for English voices and sort by quality
        availableVoices = allVoices
            .filter { $0.language.starts(with: "en") }
            .sorted { v1, v2 in
                // Prefer enhanced voices
                if v1.quality != v2.quality {
                    return v1.quality.rawValue > v2.quality.rawValue
                }
                return v1.name < v2.name
            }

        logger.info("Found \(self.availableVoices.count) English voices")
    }

    private func selectDefaultVoice() {
        // Try to find a good default voice
        // Prefer: Samantha (enhanced) > Any enhanced > Default
        if let samantha = availableVoices.first(where: {
            $0.name.contains("Samantha") && $0.quality == .enhanced
        }) {
            selectedVoiceIdentifier = samantha.identifier
            logger.info("Selected voice: Samantha (enhanced)")
        } else if let enhanced = availableVoices.first(where: { $0.quality == .enhanced }) {
            selectedVoiceIdentifier = enhanced.identifier
            logger.info("Selected voice: \(enhanced.name) (enhanced)")
        } else if let first = availableVoices.first {
            selectedVoiceIdentifier = first.identifier
            logger.info("Selected voice: \(first.name)")
        }
    }

    var selectedVoice: AVSpeechSynthesisVoice? {
        guard let id = selectedVoiceIdentifier else { return nil }
        return AVSpeechSynthesisVoice(identifier: id)
    }

    // MARK: - Speech Generation

    /// Speak text immediately
    func speak(_ text: String, completion: (() -> Void)? = nil) {
        guard !text.isEmpty else {
            completion?()
            return
        }

        // Stop any current speech
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)

        // Apply voice settings
        if let voice = selectedVoice {
            utterance.voice = voice
        }
        utterance.rate = speechRate
        utterance.pitchMultiplier = speechPitch
        utterance.volume = speechVolume

        // Pre/post delays for natural feel
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.2

        completionHandler = completion
        isSpeaking = true

        logger.info("Speaking: \(text.prefix(50))...")
        synthesizer.speak(utterance)
    }

    /// Speak text and wait for completion
    func speakAsync(_ text: String) async {
        await withCheckedContinuation { continuation in
            speak(text) {
                continuation.resume()
            }
        }
    }

    /// Stop current speech
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        completionHandler = nil
    }

    /// Pause current speech
    func pause() {
        synthesizer.pauseSpeaking(at: .word)
    }

    /// Resume paused speech
    func resume() {
        synthesizer.continueSpeaking()
    }

    // MARK: - Audio File Generation

    /// Generate audio file from text (for push notifications or saving)
    func generateAudioFile(from text: String, to url: URL) async throws {
        logger.info("📁 Starting audio file generation")
        return try await withCheckedThrowingContinuation { continuation in
            let utterance = AVSpeechUtterance(string: text)

            if let voice = selectedVoice {
                utterance.voice = voice
            }
            utterance.rate = speechRate
            utterance.pitchMultiplier = speechPitch

            var audioBuffers: [AVAudioPCMBuffer] = []
            var hasResumed = false

            synthesizer.write(utterance) { buffer in
                guard !hasResumed else { return }

                // Cast to PCM buffer
                guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
                    // Non-PCM buffer means synthesis complete
                    hasResumed = true
                    logger.info("📁 Synthesis complete (non-PCM buffer), saving \(audioBuffers.count) buffers")
                    if audioBuffers.isEmpty {
                        logger.error("📁 Audio generation failed - no buffers collected")
                        continuation.resume(throwing: SpeechError.generationFailed)
                    } else {
                        do {
                            try self.combineAndSaveBuffers(audioBuffers, to: url)
                            logger.info("📁 Audio file saved successfully")
                            continuation.resume()
                        } catch {
                            logger.error("📁 Failed to save audio: \(error.localizedDescription)")
                            continuation.resume(throwing: error)
                        }
                    }
                    return
                }

                // Empty PCM buffer also signals completion
                if pcmBuffer.frameLength == 0 {
                    hasResumed = true
                    logger.info("📁 Synthesis complete (empty buffer), saving \(audioBuffers.count) buffers")
                    if audioBuffers.isEmpty {
                        logger.error("📁 Audio generation failed - no buffers collected")
                        continuation.resume(throwing: SpeechError.generationFailed)
                    } else {
                        do {
                            try self.combineAndSaveBuffers(audioBuffers, to: url)
                            logger.info("📁 Audio file saved successfully")
                            continuation.resume()
                        } catch {
                            logger.error("📁 Failed to save audio: \(error.localizedDescription)")
                            continuation.resume(throwing: error)
                        }
                    }
                    return
                }

                // Valid audio data - collect it
                audioBuffers.append(pcmBuffer)
            }
        }
    }

    private func combineAndSaveBuffers(_ buffers: [AVAudioPCMBuffer], to url: URL) throws {
        guard let firstBuffer = buffers.first else {
            throw SpeechError.noAudioData
        }

        let format = firstBuffer.format
        let totalFrames = buffers.reduce(0) { $0 + AVAudioFrameCount($1.frameLength) }

        guard let combinedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            throw SpeechError.bufferCreationFailed
        }

        var offset: AVAudioFrameCount = 0
        for buffer in buffers {
            let frameCount = buffer.frameLength
            for channel in 0..<Int(format.channelCount) {
                let src = buffer.floatChannelData![channel]
                let dst = combinedBuffer.floatChannelData![channel]
                memcpy(dst.advanced(by: Int(offset)), src, Int(frameCount) * MemoryLayout<Float>.size)
            }
            offset += frameCount
        }
        combinedBuffer.frameLength = totalFrames

        // Write to file
        let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        try audioFile.write(from: combinedBuffer)

        logger.info("Saved audio file: \(url.lastPathComponent) (\(totalFrames) frames)")
    }

    // MARK: - Utility

    /// Get estimated duration for text
    func estimatedDuration(for text: String) -> TimeInterval {
        // Rough estimate: ~150 words per minute at default rate
        let wordCount = text.split(separator: " ").count
        let wordsPerMinute = 150.0 * Double(speechRate / AVSpeechUtteranceDefaultSpeechRate)
        return Double(wordCount) / wordsPerMinute * 60.0
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechSynthesisService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            completionHandler?()
            completionHandler = nil
            logger.info("Speech finished")
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            completionHandler = nil
            logger.info("Speech cancelled")
        }
    }
}

// MARK: - Errors

enum SpeechError: LocalizedError {
    case generationFailed
    case noAudioData
    case bufferCreationFailed

    var errorDescription: String? {
        switch self {
        case .generationFailed: return "Failed to generate speech audio"
        case .noAudioData: return "No audio data was generated"
        case .bufferCreationFailed: return "Failed to create audio buffer"
        }
    }
}

// MARK: - Voice Quality Extension

extension AVSpeechSynthesisVoiceQuality: Comparable {
    public static func < (lhs: AVSpeechSynthesisVoiceQuality, rhs: AVSpeechSynthesisVoiceQuality) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}
