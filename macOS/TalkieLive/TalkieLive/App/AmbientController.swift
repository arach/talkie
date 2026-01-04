//
//  AmbientController.swift
//  TalkieLive
//
//  State machine for ambient mode - always-on audio with wake word detection.
//  Coordinates between AmbientAudioCapture, transcription providers, and command routing.
//

import Foundation
import Combine
import AppKit
import TalkieKit

private let log = Log(.system)

// MARK: - Transcript Chunk

/// A chunk of transcribed text with timestamp
struct TranscriptChunk: Identifiable {
    let id: UUID
    let text: String
    let timestamp: Date
    let audioChunkId: UUID?

    var age: TimeInterval {
        Date().timeIntervalSince(timestamp)
    }

    init(id: UUID = UUID(), text: String, timestamp: Date = Date(), audioChunkId: UUID? = nil) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.audioChunkId = audioChunkId
    }
}

// MARK: - Ambient Command

/// A captured command from ambient mode
struct AmbientCommand {
    let id: UUID
    let text: String              // The command text (between wake and end phrase)
    let wakeTimestamp: Date       // When wake word was detected
    let endTimestamp: Date        // When end phrase was detected
    let duration: TimeInterval    // How long the command took

    init(text: String, wakeTimestamp: Date) {
        self.id = UUID()
        self.text = text
        self.wakeTimestamp = wakeTimestamp
        self.endTimestamp = Date()
        self.duration = endTimestamp.timeIntervalSince(wakeTimestamp)
    }
}

// MARK: - Ambient Controller

@MainActor
final class AmbientController: ObservableObject {
    static let shared = AmbientController()

    // MARK: - Published State

    @Published private(set) var state: AmbientState = .disabled
    @Published private(set) var commandText: String = ""  // Live command text during .command state

    /// Rolling transcript buffer
    @Published private(set) var transcriptBuffer: [TranscriptChunk] = []

    /// Last captured command (for display)
    @Published private(set) var lastCommand: AmbientCommand?

    /// Whether streaming ASR is active (for UI display)
    @Published private(set) var isStreamingMode: Bool = false

    // MARK: - Dependencies

    private let settings = AmbientSettings.shared
    private let audioCapture = AmbientAudioCapture.shared

    // MARK: - Dual-Channel Providers

    /// Streaming provider for fast wake detection (hypothesis channel)
    private var streamingProvider: StreamingTranscriptionProvider?

    /// Batch provider for context buffer (5-min rolling transcript)
    private var batchProvider: BatchTranscriptionProvider?

    /// Tasks consuming provider events
    private var streamingEventTask: Task<Void, Never>?
    private var batchEventTask: Task<Void, Never>?

    // MARK: - Callbacks

    /// Called when a command is captured and ready for routing
    var onCommandCaptured: ((AmbientCommand) -> Void)?

    // MARK: - State

    private var wakeTimestamp: Date?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    private init() {
        setupBindings()
    }

    private func setupBindings() {
        // Listen to settings changes
        settings.$isEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                Task { @MainActor in
                    if enabled {
                        await self?.enable()
                    } else {
                        await self?.disable()
                    }
                }
            }
            .store(in: &cancellables)

        // Listen for streaming mode changes (restart streaming provider if needed)
        settings.$useStreamingASR
            .dropFirst()  // Skip initial value
            .receive(on: DispatchQueue.main)
            .sink { [weak self] useStreaming in
                Task { @MainActor in
                    guard let self = self, self.state != .disabled else { return }
                    if useStreaming {
                        log.info("Enabling streaming wake detection")
                        await self.startStreamingProvider()
                    } else {
                        log.info("Disabling streaming wake detection")
                        await self.stopStreamingProvider()
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Enable/Disable

    /// Enable ambient mode
    func enable() async {
        guard state == .disabled else { return }

        log.info("🎙️ Enabling ambient mode (dual-channel)")
        log.info("Settings: streaming=\(settings.useStreamingASR), wake='\(settings.wakePhrase)'")

        // Create config
        let config = AmbientTranscriptionConfig(
            wakePhrase: settings.wakePhrase,
            endPhrase: settings.endPhrase,
            cancelPhrase: settings.cancelPhrase
        )

        // Always start batch provider (context buffer)
        log.info("Starting batch provider (context buffer)...")
        let batch = BatchTranscriptionProvider()
        batchProvider = batch

        do {
            try await batch.start(config: config)
            log.info("✓ Batch provider ready")
        } catch {
            log.error("✗ Batch provider failed", error: error)
            batchProvider = nil
        }

        // Start streaming provider if enabled (fast wake detection)
        isStreamingMode = settings.useStreamingASR
        log.info("Streaming mode: \(isStreamingMode ? "ENABLED" : "disabled")")
        if isStreamingMode {
            log.info("Starting streaming provider (fast wake detection)...")
            await startStreamingProvider()
        } else {
            log.info("⚠️ Streaming disabled - using batch-only mode (slower wake detection)")
        }

        // Wire up audio callbacks (both channels from same mic tap)
        audioCapture.onChunkReady = { [weak self] chunk in
            Task { @MainActor in
                // Batch channel: context buffer (always active)
                await self?.batchProvider?.ingest(.chunk(chunk))
            }
        }

        audioCapture.onPCMDataReady = { [weak self] data in
            Task { @MainActor in
                // Streaming channel: fast wake detection (when enabled)
                await self?.streamingProvider?.ingest(.pcm16kFloat(data))
            }
        }

        // Start consuming events from both providers
        startEventConsumers()

        // Start audio capture
        audioCapture.start()

        // Transition to listening
        state = .listening
        playChime(.start)

        // Update HUD
        AmbientHUDController.shared.currentState = state
        AmbientHUDController.shared.show()

        log.info("Ambient mode enabled - listening for '\(settings.wakePhrase)'")
        if isStreamingMode {
            log.info("Streaming wake detection active (subsecond latency)")
        }
    }

    /// Disable ambient mode
    func disable() async {
        guard state != .disabled else { return }

        log.info("Disabling ambient mode")

        // Stop audio capture first
        audioCapture.stop()
        audioCapture.onChunkReady = nil
        audioCapture.onPCMDataReady = nil

        // Stop event consumers
        streamingEventTask?.cancel()
        streamingEventTask = nil
        batchEventTask?.cancel()
        batchEventTask = nil

        // Stop providers
        await stopStreamingProvider()

        if let batch = batchProvider {
            await batch.stop()
            batchProvider = nil
        }

        // Clear state
        state = .disabled
        commandText = ""
        wakeTimestamp = nil
        transcriptBuffer.removeAll()
        isStreamingMode = false

        // Update HUD
        AmbientHUDController.shared.currentState = state
        AmbientHUDController.shared.addActivity(.system("Ambient mode disabled"))
        AmbientHUDController.shared.hide()

        log.info("Ambient mode disabled")
    }

    // MARK: - Streaming Provider Management

    /// Start the streaming provider for fast wake detection
    private func startStreamingProvider() async {
        guard streamingProvider == nil else { return }

        let config = AmbientTranscriptionConfig(
            wakePhrase: settings.wakePhrase,
            endPhrase: settings.endPhrase,
            cancelPhrase: settings.cancelPhrase
        )

        let streaming = StreamingTranscriptionProvider()
        streamingProvider = streaming

        do {
            try await streaming.start(config: config)
            isStreamingMode = true
            log.info("Streaming provider ready (fast wake detection)")

            // Start consuming streaming events
            streamingEventTask = Task { [weak self] in
                for await event in streaming.events {
                    guard let self = self, !Task.isCancelled else { break }
                    await self.handleStreamingEvent(event)
                }
            }

        } catch {
            log.error("Failed to start streaming provider", error: error)
            streamingProvider = nil
            isStreamingMode = false
        }
    }

    /// Stop the streaming provider
    private func stopStreamingProvider() async {
        streamingEventTask?.cancel()
        streamingEventTask = nil

        if let streaming = streamingProvider {
            await streaming.stop()
            streamingProvider = nil
        }

        isStreamingMode = false
    }

    /// Toggle ambient mode
    func toggle() {
        if state == .disabled {
            settings.isEnabled = true
        } else {
            settings.isEnabled = false
        }
    }

    // MARK: - Event Consumption

    /// Start consuming events from both providers
    private func startEventConsumers() {
        // Batch events (context buffer - always active)
        if let batch = batchProvider {
            batchEventTask = Task { [weak self] in
                for await event in batch.events {
                    guard let self = self, !Task.isCancelled else { break }
                    await self.handleBatchEvent(event)
                }
            }
        }

        // Streaming events already started in startStreamingProvider()
    }

    /// Handle events from streaming provider (fast wake detection)
    private func handleStreamingEvent(_ event: AmbientTranscriptionEvent) async {
        switch event {
        case .ready(let memoryMB):
            log.info("Streaming provider ready", detail: memoryMB.map { "\($0)MB" } ?? "")

        case .speechStart, .speechEnd:
            // VAD events from streaming - could show speaking indicator
            break

        case .transcript(let text, _, let isFinal):
            // Show streaming transcripts in HUD (fast feedback)
            if state == .listening {
                AmbientHUDController.shared.addActivity(.heard(text))
            }

            // Update live command text during command mode
            if state == .command && isFinal {
                if !commandText.isEmpty {
                    commandText += " "
                }
                commandText += text
                AmbientHUDController.shared.updateLiveTranscript(commandText)
            }

        case .wakeDetected(let phrase, let afterText):
            // Fast wake detection from streaming!
            log.info("🎯 Wake phrase detected (streaming)!", detail: "'\(phrase)'")

            wakeTimestamp = Date()
            commandText = afterText
            state = .command
            playChime(.wake)

            // Update HUD
            AmbientHUDController.shared.currentState = state
            AmbientHUDController.shared.addActivity(.wake())
            AmbientHUDController.shared.updateLiveTranscript(commandText)

        case .endDetected(let command):
            log.info("End phrase detected (streaming)", detail: "command='\(command)'")
            processCommand(command)

        case .cancelDetected:
            log.info("Cancel phrase detected (streaming)")
            cancelCommand()

        case .error(let message, let isFatal):
            log.warning("Streaming provider error", detail: "\(message) (fatal=\(isFatal))")
            if isFatal {
                // Streaming failed - fall back to batch-only mode
                log.info("Falling back to batch-only mode")
                await stopStreamingProvider()
                AmbientHUDController.shared.addActivity(.system("Streaming disabled, using batch mode"))
            }
        }
    }

    /// Handle events from batch provider (context buffer)
    private func handleBatchEvent(_ event: AmbientTranscriptionEvent) async {
        switch event {
        case .ready:
            log.info("Batch provider ready (context buffer)")

        case .speechStart, .speechEnd:
            // Batch doesn't emit VAD events
            break

        case .transcript(let text, _, let isFinal):
            // Add to context buffer (5-min rolling transcript)
            if isFinal {
                let chunk = TranscriptChunk(text: text)
                transcriptBuffer.append(chunk)
                pruneTranscriptBuffer()
            }

            // If streaming is disabled, also use batch for wake detection
            if !isStreamingMode && state == .listening {
                AmbientHUDController.shared.addActivity(.heard(text))
            }

            // Update command text if streaming is disabled
            if !isStreamingMode && state == .command && isFinal {
                if !commandText.isEmpty {
                    commandText += " "
                }
                commandText += text
                AmbientHUDController.shared.updateLiveTranscript(commandText)
            }

        case .wakeDetected(let phrase, let afterText):
            // Batch wake detection (slower but fallback if streaming disabled)
            guard !isStreamingMode else {
                // Streaming already handles wake - ignore batch duplicate
                return
            }

            log.info("Wake phrase detected (batch)!", detail: "'\(phrase)'")

            wakeTimestamp = Date()
            commandText = afterText
            state = .command
            playChime(.wake)

            AmbientHUDController.shared.currentState = state
            AmbientHUDController.shared.addActivity(.wake())
            AmbientHUDController.shared.updateLiveTranscript(commandText)

        case .endDetected(let command):
            guard !isStreamingMode else { return }
            log.info("End phrase detected (batch)", detail: "command='\(command)'")
            processCommand(command)

        case .cancelDetected:
            guard !isStreamingMode else { return }
            log.info("Cancel phrase detected (batch)")
            cancelCommand()

        case .error(let message, let isFatal):
            log.warning("Batch provider error", detail: "\(message) (fatal=\(isFatal))")
            AmbientHUDController.shared.addActivity(.system("Batch error: \(message)"))

            if isFatal {
                // Batch failed - this is critical, disable ambient
                await disable()
            }
        }
    }

    // MARK: - Cancel Command

    /// Cancel current command (called by click on indicator or voice cancel)
    func cancelCommand() {
        guard state == .command else { return }

        log.info("Cancelling ambient command")

        playChime(.cancel)

        // Clear command state
        commandText = ""
        wakeTimestamp = nil

        // Return to listening
        state = .listening

        // Update HUD
        AmbientHUDController.shared.currentState = state
        AmbientHUDController.shared.updateLiveTranscript("")
        AmbientHUDController.shared.addActivity(.cancelled())

        log.info("Command cancelled, returning to listening")
    }

    // MARK: - Command Processing

    /// Process a captured command
    private func processCommand(_ text: String) {
        guard !text.isEmpty else {
            log.warning("Empty command captured, ignoring")
            state = .listening
            commandText = ""
            wakeTimestamp = nil
            return
        }

        state = .processing

        let command = AmbientCommand(
            text: text,
            wakeTimestamp: wakeTimestamp ?? Date()
        )

        log.info("Command captured", detail: "'\(text)' (\(String(format: "%.1f", command.duration))s)")

        lastCommand = command
        playChime(.end)

        // Notify listener (callback)
        onCommandCaptured?(command)

        // Send to Talkie via XPC
        let bufferContext = getRecentTranscript(seconds: 60)
        TalkieLiveXPCService.shared.notifyAmbientCommand(
            text,
            duration: command.duration,
            bufferContext: bufferContext.isEmpty ? nil : bufferContext
        )

        // Update HUD
        AmbientHUDController.shared.addActivity(.sent(text))
        AmbientHUDController.shared.updateLiveTranscript("")

        // Clear state and return to listening
        commandText = ""
        wakeTimestamp = nil
        state = .listening

        // Update HUD state
        AmbientHUDController.shared.currentState = state

        log.info("Returning to listening mode")
    }

    // MARK: - Buffer Management

    private func pruneTranscriptBuffer() {
        let maxAge = settings.bufferDuration

        transcriptBuffer.removeAll { chunk in
            chunk.age > maxAge
        }
    }

    /// Get recent transcript text (for context retrieval)
    func getRecentTranscript(seconds: TimeInterval = 60) -> String {
        let cutoff = Date().addingTimeInterval(-seconds)
        return transcriptBuffer
            .filter { $0.timestamp >= cutoff }
            .map { $0.text }
            .joined(separator: " ")
    }

    // MARK: - Audio Feedback

    private enum ChimeType {
        case start      // Ambient mode enabled
        case wake       // Wake word detected
        case end        // Command completed
        case cancel     // Command cancelled
    }

    private func playChime(_ type: ChimeType) {
        guard settings.enableChimes else { return }

        // Use system sounds for now
        // TODO: Add custom chime sounds
        switch type {
        case .start:
            NSSound(named: "Tink")?.play()
        case .wake:
            NSSound(named: "Pop")?.play()
        case .end:
            NSSound(named: "Purr")?.play()
        case .cancel:
            NSSound(named: "Basso")?.play()
        }
    }
}

// MARK: - Extension: TimeInterval Formatting

private extension TimeInterval {
    func formatted() -> String {
        if self < 60 {
            return String(format: "%.1fs", self)
        }
        let minutes = Int(self) / 60
        let seconds = Int(self) % 60
        return "\(minutes)m \(seconds)s"
    }
}
