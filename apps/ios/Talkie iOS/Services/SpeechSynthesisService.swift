//
//  SpeechSynthesisService.swift
//  Talkie iOS
//
//  On-device text-to-speech using Apple's AVSpeechSynthesizer.
//  Mirrors the macOS SpeechSynthesisService API.
//

import AVFoundation
import Observation

@MainActor
@Observable
class SpeechSynthesisService: NSObject {
    static let shared = SpeechSynthesisService()

    private let synthesizer = AVSpeechSynthesizer()
    private let minimumPlaybackRate: Float = 0.75
    private let maximumPlaybackRate: Float = 2.0

    var isSpeaking = false

    // Settings
    var selectedVoiceIdentifier: String?
    var speechRate: Float = AVSpeechUtteranceDefaultSpeechRate
    var speechPitch: Float = 1.0
    var speechVolume: Float = 1.0
    var playbackRate: Float = 1.0 {
        didSet {
            speechRate = mappedSpeechRate(for: playbackRate)
        }
    }

    private var completionHandler: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
        selectDefaultVoice()
    }

    // MARK: - Voice Selection

    private func selectDefaultVoice() {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.starts(with: "en") }

        // Prefer enhanced Samantha > any enhanced > default
        if let samantha = voices.first(where: {
            $0.name.contains("Samantha") && $0.quality == .enhanced
        }) {
            selectedVoiceIdentifier = samantha.identifier
        } else if let enhanced = voices.first(where: { $0.quality == .enhanced }) {
            selectedVoiceIdentifier = enhanced.identifier
        } else if let first = voices.first {
            selectedVoiceIdentifier = first.identifier
        }
    }

    private var selectedVoice: AVSpeechSynthesisVoice? {
        guard let id = selectedVoiceIdentifier else { return nil }
        return AVSpeechSynthesisVoice(identifier: id)
    }

    // MARK: - Speech

    func speak(_ text: String, completion: (() -> Void)? = nil) {
        guard !text.isEmpty else {
            completion?()
            return
        }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        // Configure audio session for playback
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        if let voice = selectedVoice {
            utterance.voice = voice
        }
        utterance.rate = speechRate
        utterance.pitchMultiplier = speechPitch
        utterance.volume = speechVolume
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.2

        completionHandler = completion
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func speakAsync(_ text: String) async {
        await withCheckedContinuation { continuation in
            speak(text) {
                continuation.resume()
            }
        }
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        completionHandler = nil
    }

    func toggleReadout(_ text: String) {
        if isSpeaking {
            stop()
        } else {
            speak(text)
        }
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = min(max(rate, minimumPlaybackRate), maximumPlaybackRate)
    }

    private func mappedSpeechRate(for playbackRate: Float) -> Float {
        let clampedRate = min(max(playbackRate, minimumPlaybackRate), maximumPlaybackRate)

        if clampedRate <= 1 {
            let progress = (clampedRate - minimumPlaybackRate) / (1 - minimumPlaybackRate)
            return AVSpeechUtteranceMinimumSpeechRate + progress * (AVSpeechUtteranceDefaultSpeechRate - AVSpeechUtteranceMinimumSpeechRate)
        }

        let progress = (clampedRate - 1) / (maximumPlaybackRate - 1)
        return AVSpeechUtteranceDefaultSpeechRate + progress * (AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceDefaultSpeechRate)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechSynthesisService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            completionHandler?()
            completionHandler = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            completionHandler = nil
        }
    }
}
