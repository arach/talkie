//
//  SessionDetailView.swift
//  Talkie iOS
//
//  View Claude Code session conversation history
//

import SwiftUI
import PhotosUI

struct SessionDetailView: View {
    let session: ClaudeSession

    @State private var bridgeManager = BridgeManager.shared
    @State private var messages: [SessionMessage] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    // Input state
    @State private var inputText = ""
    @State private var isSending = false
    @State private var sendError: String?
    @FocusState private var isInputFocused: Bool

    // Audio recording state
    @StateObject private var recorder = AudioRecorderManager()
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var isTranscribing = false
    @State private var lastFailedAudioURL: URL?  // For retry capability
    @State private var capturedTranscription: String = ""  // Captured when recording stops

    // Image picker state
    @State private var selectedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var imagePickerItem: PhotosPickerItem?

    // Delivery confirmation state
    @State private var lastDelivery: DeliveryConfirmation?

    // Quick reply options parsed from last assistant message
    private var quickReplyOptions: [QuickReplyOption] {
        parseQuickReplyOptions(from: messages.last(where: { $0.role == "assistant" }))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages area
            Group {
                if isLoading {
                    Spacer()
                    ProgressView("Loading messages...")
                    Spacer()
                } else if let error = errorMessage {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(error)
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            loadMessages()
                        }
                        .buttonStyle(.bordered)
                    }
                    Spacer()
                } else if messages.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No messages yet")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(messages) { message in
                                    MessageBubble(message: message)
                                        .id(message.id)
                                }
                            }
                            .padding()
                        }
                        .onAppear {
                            // Scroll to bottom
                            if let lastMessage = messages.last {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            // Input bar - always show, even for non-live sessions
            Divider()

            // Warning for non-live sessions
            if !session.isLive {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 10))
                        .foregroundColor(.warning)
                    Text("Session inactive — message will be queued")
                        .font(.techLabelSmall)
                        .foregroundColor(.textTertiary)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xxs)
            }

            // Quick reply buttons (when numbered options detected)
            if !quickReplyOptions.isEmpty {
                QuickReplyBar(options: quickReplyOptions) { number in
                    sendQuickReply(number)
                }
            }

            InputBar(
                text: $inputText,
                isSending: isSending || isTranscribing,
                isRecording: recorder.isRecording,
                recordingDuration: recorder.recordingDuration,
                audioLevels: recorder.audioLevels,
                liveTranscription: speechRecognizer.transcript,
                capturedTranscription: capturedTranscription,
                selectedImage: selectedImage,
                delivery: lastDelivery,
                error: sendError,
                canRetryAudio: lastFailedAudioURL != nil,
                isFocused: $isInputFocused,
                onSend: sendMessage,
                onMicTap: toggleRecording,
                onRetry: retryAudio,
                onImagePick: { showingImagePicker = true },
                onImageClear: { selectedImage = nil }
            )
        }
        .photosPicker(isPresented: $showingImagePicker, selection: $imagePickerItem, matching: .images)
        .onChange(of: imagePickerItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedImage = image
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: Spacing.xs) {
                    if session.isLive {
                        Circle()
                            .fill(Color.success)
                            .frame(width: 6, height: 6)
                    }
                    Text(session.project)
                        .font(.headlineMedium)
                        .foregroundColor(.textPrimary)
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: loadMessages) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
            }
        }
        .onAppear {
            loadMessages()
        }
        .refreshable {
            await fetchMessages()
        }
    }

    private func loadMessages() {
        isLoading = true
        errorMessage = nil
        Task {
            await fetchMessages()
        }
    }

    private func fetchMessages() async {
        do {
            messages = try await bridgeManager.getMessages(sessionId: session.id)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Allow empty text - sends Enter key only (submits last message)

        isSending = true
        sendError = nil

        Task {
            do {
                // If image is attached, send with image
                if let image = selectedImage {
                    try await bridgeManager.sendMessageWithImage(
                        sessionId: session.id,
                        text: text,
                        image: image
                    )
                    selectedImage = nil
                    imagePickerItem = nil
                } else {
                    try await bridgeManager.sendMessage(sessionId: session.id, text: text)
                }
                // Clear input on success
                inputText = ""
                sendError = nil
                // Refresh messages after a brief delay to see the result
                try? await Task.sleep(nanoseconds: 500_000_000)
                await fetchMessages()
            } catch {
                sendError = error.localizedDescription
            }
            isSending = false
        }
    }

    private func toggleRecording() {
        if recorder.isRecording {
            let stopTime = Date()

            // Stop audio recording immediately (so we can send the file)
            recorder.stopRecording()
            recorder.finalizeRecording()

            guard let audioURL = recorder.currentRecordingURL else {
                sendError = "No recording available"
                return
            }

            // Clear any previous transcription
            capturedTranscription = ""

            // Start BOTH in parallel:
            // 1. Send audio to server (for Whisper transcription + Claude)
            // 2. Transcribe audio file locally (for UI preview)
            sendAudioWithFileTranscription(url: audioURL, stopTime: stopTime)
        } else {
            // Start recording - clear any previous state
            sendError = nil
            lastFailedAudioURL = nil
            capturedTranscription = ""
            speechRecognizer.clear()
            recorder.startRecording()
            // NOTE: We don't start speech recognition here anymore
            // Instead, we transcribe the file AFTER recording stops
        }
    }

    /// Send audio while transcribing the file locally in parallel
    /// This shows progressive transcription during the send phase
    private func sendAudioWithFileTranscription(url: URL, stopTime: Date) {
        isTranscribing = true
        sendError = nil
        lastDelivery = nil

        // Start local file transcription (runs in background, updates speechRecognizer.transcript)
        speechRecognizer.transcribeFile(url)

        // Poll for transcription updates and update UI
        let transcriptionTask = Task { @MainActor in
            var lastUpdate = ""

            // Poll for updates while sending (max 5 seconds)
            for i in 0..<50 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

                if Task.isCancelled { break }

                let current = speechRecognizer.transcript
                if current != lastUpdate && !current.isEmpty {
                    capturedTranscription = current
                    lastUpdate = current
                }
            }
        }

        // Send audio to server in parallel
        Task {
            do {
                let response = try await bridgeManager.sendAudioWithResponse(
                    sessionId: session.id,
                    audioURL: url
                )

                // Cancel local transcription - we have server's result now
                transcriptionTask.cancel()
                speechRecognizer.stopFileTranscription()

                isTranscribing = false
                sendError = nil
                lastFailedAudioURL = nil

                // Show delivery confirmation with server's transcript
                if response.success, let deliveredAt = response.deliveredAt {
                    let serverText = response.insertedText ?? response.transcript ?? ""

                    // Update with server's version (Whisper is more accurate)
                    if !serverText.isEmpty {
                        capturedTranscription = serverText
                    }

                    lastDelivery = DeliveryConfirmation(
                        text: serverText,
                        deliveredAt: deliveredAt
                    )
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    lastDelivery = nil
                }

                await fetchMessages()
            } catch {
                transcriptionTask.cancel()
                speechRecognizer.stopFileTranscription()
                sendError = error.localizedDescription
                lastFailedAudioURL = url
                isTranscribing = false
            }
        }
    }

    private func retryAudio() {
        guard let url = lastFailedAudioURL else { return }
        // Retry uses file transcription for consistent UX
        sendAudioWithFileTranscription(url: url, stopTime: Date())
    }

    private func sendQuickReply(_ number: String) {
        isSending = true
        sendError = nil

        Task {
            do {
                try await bridgeManager.sendMessage(sessionId: session.id, text: number)
                // Refresh messages after a brief delay
                try? await Task.sleep(nanoseconds: 500_000_000)
                await fetchMessages()
            } catch {
                sendError = error.localizedDescription
            }
            isSending = false
        }
    }
}

// MARK: - Quick Reply Option

struct QuickReplyOption: Identifiable {
    let id: String
    let number: String
    let label: String
}

/// Parse numbered options from the last assistant message
/// Looks for patterns like "1. Allow", "[1] Proceed", "1) Skip"
func parseQuickReplyOptions(from message: SessionMessage?) -> [QuickReplyOption] {
    guard let message = message, message.role == "assistant" else { return [] }

    var options: [QuickReplyOption] = []
    let content = message.content

    // Pattern: "1. Label", "2. Label", etc.
    let dotPattern = /(\d)\.\s+([^\n\d][^\n]{0,30})/
    for match in content.matches(of: dotPattern) {
        let number = String(match.1)
        let label = String(match.2).trimmingCharacters(in: .whitespaces)
        if !label.isEmpty && options.count < 5 {
            options.append(QuickReplyOption(id: "\(number)-\(label)", number: number, label: label))
        }
    }

    // Pattern: "[1] Label", "[2] Label", etc.
    let bracketPattern = /\[(\d)\]\s+([^\n\[]{1,30})/
    if options.isEmpty {
        for match in content.matches(of: bracketPattern) {
            let number = String(match.1)
            let label = String(match.2).trimmingCharacters(in: .whitespaces)
            if !label.isEmpty && options.count < 5 {
                options.append(QuickReplyOption(id: "\(number)-\(label)", number: number, label: label))
            }
        }
    }

    // Pattern: "1) Label", "2) Label", etc.
    let parenPattern = /(\d)\)\s+([^\n\d][^\n]{0,30})/
    if options.isEmpty {
        for match in content.matches(of: parenPattern) {
            let number = String(match.1)
            let label = String(match.2).trimmingCharacters(in: .whitespaces)
            if !label.isEmpty && options.count < 5 {
                options.append(QuickReplyOption(id: "\(number)-\(label)", number: number, label: label))
            }
        }
    }

    return options
}

// MARK: - Quick Reply Bar

struct QuickReplyBar: View {
    let options: [QuickReplyOption]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options) { option in
                    Button(action: { onSelect(option.number) }) {
                        HStack(spacing: 4) {
                            Text(option.number)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .frame(width: 18, height: 18)
                                .background(Color.blue)
                                .clipShape(Circle())
                            Text(option.label)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color(.systemGray6))
    }
}

// MARK: - Input Bar

struct InputBar: View {
    @Binding var text: String
    let isSending: Bool
    let isRecording: Bool
    let recordingDuration: TimeInterval
    let audioLevels: [Float]
    let liveTranscription: String      // Real-time during recording
    let capturedTranscription: String  // Captured when recording stopped
    let selectedImage: UIImage?        // Attached image
    let delivery: DeliveryConfirmation?
    let error: String?
    let canRetryAudio: Bool
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onMicTap: () -> Void
    let onRetry: () -> Void
    let onImagePick: () -> Void
    let onImageClear: () -> Void

    private var durationText: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Error message with optional retry
            if let error {
                HStack(spacing: 8) {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.red)

                    if canRetryAudio {
                        Button(action: onRetry) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10))
                                Text("Retry")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            // Recording UI with waveform and transcription preview
            if isRecording {
                RecordingOverlay(
                    duration: recordingDuration,
                    audioLevels: audioLevels,
                    transcriptionPreview: liveTranscription,
                    onStop: onMicTap
                )
            } else if isSending {
                // Sending state - show captured transcription (what user said)
                SendingOverlay(transcriptionPreview: capturedTranscription)
            } else if let delivery = delivery {
                // Delivery confirmation
                DeliveredOverlay(delivery: delivery)
            } else {
                // Normal input bar
                VStack(spacing: Spacing.xs) {
                    // Image preview (if attached)
                    if let image = selectedImage {
                        HStack {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 60)
                                .cornerRadius(CornerRadius.sm)

                            Spacer()

                            Button(action: onImageClear) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.textTertiary)
                            }
                        }
                        .padding(.horizontal, Spacing.sm)
                    }

                    HStack(spacing: Spacing.xs) {
                        // Image picker button
                        Button(action: onImagePick) {
                            Image(systemName: "photo")
                                .font(.system(size: 16))
                                .frame(width: 36, height: 36)
                                .background(selectedImage != nil ? Color.brandAccent.opacity(0.15) : Color.surfaceSecondary)
                                .foregroundColor(selectedImage != nil ? .brandAccent : .textSecondary)
                                .clipShape(Circle())
                        }

                        // Mic button
                        Button(action: onMicTap) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 16))
                                .frame(width: 36, height: 36)
                                .background(Color.surfaceSecondary)
                                .foregroundColor(.textSecondary)
                                .clipShape(Circle())
                        }

                        // Text field
                        TextField("Send to Claude...", text: $text, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.bodySmall)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.sm)
                            .frame(minHeight: 40)
                            .background(Color.surfaceSecondary)
                            .cornerRadius(CornerRadius.lg)
                            .lineLimit(1...5)
                            .focused(isFocused)
                            .submitLabel(.send)
                            .onSubmit {
                                onSend()
                            }

                        // Send button - always enabled, empty sends Enter only
                        Button(action: onSend) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 40, height: 40)
                                .background(Color.brandAccent)
                                .foregroundColor(.white)
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.surfacePrimary)
    }
}

// MARK: - Recording Overlay

struct RecordingOverlay: View {
    let duration: TimeInterval
    let audioLevels: [Float]
    let transcriptionPreview: String
    let onStop: () -> Void

    @State private var recPulse = false

    var body: some View {
        VStack(spacing: Spacing.xs) {
            // REC indicator - like main recording view
            HStack(spacing: Spacing.xs) {
                Circle()
                    .fill(Color.recording)
                    .frame(width: 6, height: 6)
                    .scaleEffect(recPulse ? 1.2 : 0.8)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true),
                        value: recPulse
                    )

                Text("REC")
                    .font(.techLabelSmall)
                    .fontWeight(.bold)
                    .foregroundColor(.recording)
                    .tracking(1)
            }
            .onAppear { recPulse = true }

            // Particles waveform
            ParticlesWaveformView(
                levels: audioLevels,
                height: 32,
                color: .recording
            )
            .padding(.horizontal, Spacing.sm)

            // Transcription preview - compact
            if !transcriptionPreview.isEmpty {
                Text(transcriptionPreview)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.sm)
            }

            // Send button - pill with play icon
            Button(action: onStop) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("SEND")
                        .font(.techLabelSmall)
                        .tracking(1.5)
                }
                .foregroundColor(.white)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(Color.recording)
                .cornerRadius(CornerRadius.full)
            }
            .padding(.top, Spacing.xs)
        }
        .padding(.vertical, Spacing.xs)
        .padding(.bottom, 2)
        .background(Color.surfacePrimary)
    }
}

// MARK: - Braille Spinner

struct BrailleSpinner: View {
    var speed: Double = 0.08
    var color: Color = .textSecondary

    @State private var frame = 0
    private let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    var body: some View {
        Text(frames[frame])
            .font(.monoMedium)
            .foregroundColor(color)
            .onAppear { startAnimation() }
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: speed, repeats: true) { _ in
            frame = (frame + 1) % frames.count
        }
    }
}

// MARK: - Sending Overlay

struct SendingOverlay: View {
    let transcriptionPreview: String

    var body: some View {
        VStack(spacing: Spacing.xs) {
            // Show transcription first (what user said) - primary content
            if !transcriptionPreview.isEmpty {
                Text(transcriptionPreview)
                    .font(.monoSmall)
                    .foregroundColor(.textPrimary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.sm)
                    .background(Color.brandAccent.opacity(0.08))
                    .cornerRadius(CornerRadius.sm)
            } else {
                // Show placeholder when no transcription captured
                Text("Processing audio...")
                    .font(.monoSmall)
                    .foregroundColor(.textSecondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.sm)
                    .background(Color.surfaceSecondary)
                    .cornerRadius(CornerRadius.sm)
            }

            // Sending indicator - subtle, secondary
            HStack(spacing: Spacing.xs) {
                BrailleSpinner(color: .brandAccent)
                Text("sending")
                    .font(.techLabelSmall)
                    .foregroundColor(.textTertiary)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(Color.surfacePrimary)
    }
}

// MARK: - Delivery Confirmation

struct DeliveryConfirmation {
    let text: String
    let deliveredAt: String
}

struct DeliveredOverlay: View {
    let delivery: DeliveryConfirmation

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.success)
            Text("Sent")
                .font(.bodySmall)
                .foregroundColor(.textSecondary)
            if !delivery.text.isEmpty {
                Text("·")
                    .foregroundColor(.textTertiary)
                Text(delivery.text)
                    .font(.bodySmall)
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .background(Color.surfacePrimary)
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: SessionMessage

    @State private var isExpanded = false

    private var isUser: Bool {
        message.role == "user"
    }

    private var isLongMessage: Bool {
        message.content.count > 300
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            // Header: role + timestamp
            HStack(spacing: Spacing.xs) {
                Text(isUser ? ">" : "◆")
                    .font(.monoSmall)
                    .foregroundColor(isUser ? .active : .transcribing)

                Text(isUser ? "you" : "claude")
                    .font(.techLabel)
                    .foregroundColor(isUser ? .active : .transcribing)

                Spacer()

                Text(compactTime)
                    .font(.techLabelSmall)
                    .foregroundColor(.textTertiary)
            }

            // Content (tap to expand long messages)
            if !message.content.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(isExpanded || !isLongMessage ? message.content : String(message.content.prefix(300)) + "…")
                        .font(.monoSmall)
                        .foregroundColor(.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)

                    if isLongMessage {
                        Button(action: { isExpanded.toggle() }) {
                            Text(isExpanded ? "Show less" : "Show more…")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.brandAccent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Spacing.sm)
                .background(isUser ? Color.active.opacity(0.05) : Color.surfaceSecondary)
                .cornerRadius(CornerRadius.sm)
            }

            // Tool calls
            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    ForEach(toolCalls, id: \.name) { tool in
                        ToolCallView(tool: tool)
                    }
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private var compactTime: String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: message.timestamp) else { return "" }
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        return timeFormatter.string(from: date)
    }
}

// MARK: - Tool Call View

struct ToolCallView: View {
    let tool: ToolCall

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Button(action: { isExpanded.toggle() }) {
                HStack(spacing: Spacing.xs) {
                    Text("⚡")
                        .font(.system(size: 8))
                    Text(tool.name)
                        .font(.techLabel)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .medium))
                }
                .foregroundColor(.warning)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xxs)
                .background(Color.warning.opacity(0.08))
                .cornerRadius(CornerRadius.sm)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if let input = tool.input, !input.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("IN")
                                .font(.techLabelSmall)
                                .foregroundColor(.textTertiary)
                            Text(input)
                                .font(.monoSmall)
                                .foregroundColor(.textSecondary)
                                .lineLimit(5)
                        }
                        .padding(Spacing.xs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.surfaceTertiary)
                        .cornerRadius(CornerRadius.sm)
                    }

                    if let output = tool.output, !output.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("OUT")
                                .font(.techLabelSmall)
                                .foregroundColor(.textTertiary)
                            Text(output.prefix(300) + (output.count > 300 ? "…" : ""))
                                .font(.monoSmall)
                                .foregroundColor(.textSecondary)
                                .lineLimit(8)
                        }
                        .padding(Spacing.xs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.surfaceTertiary)
                        .cornerRadius(CornerRadius.sm)
                    }
                }
                .padding(.leading, Spacing.sm)
            }
        }
    }
}

#Preview {
    NavigationView {
        SessionDetailView(session: ClaudeSession(
            id: "fcf1ca5a-b801-4aa6-9329-d0b8fe7691a4",
            folderName: "-Users-arach-dev-talkie",
            project: "talkie",
            projectPath: "/Users/arach/dev/talkie",
            isLive: true,
            lastSeen: ISO8601DateFormatter().string(from: Date()),
            messageCount: 42
        ))
    }
}
