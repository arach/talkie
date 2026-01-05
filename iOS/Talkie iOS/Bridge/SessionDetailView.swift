//
//  SessionDetailView.swift
//  Talkie iOS
//
//  View Claude Code session conversation history
//

import SwiftUI

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

            // Input bar
            if session.isLive {
                Divider()

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
                    transcriptionPreview: speechRecognizer.transcript,
                    delivery: lastDelivery,
                    error: sendError,
                    canRetryAudio: lastFailedAudioURL != nil,
                    isFocused: $isInputFocused,
                    onSend: sendMessage,
                    onMicTap: toggleRecording,
                    onRetry: retryAudio
                )
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
        guard !text.isEmpty else { return }

        isSending = true
        sendError = nil

        Task {
            do {
                try await bridgeManager.sendMessage(sessionId: session.id, text: text)
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
            // Stop recording and send
            recorder.stopRecording()
            recorder.finalizeRecording()
            speechRecognizer.stopListening()

            guard let audioURL = recorder.currentRecordingURL else {
                sendError = "No recording available"
                return
            }

            sendAudio(url: audioURL)
        } else {
            // Start recording - clear any previous failed audio
            sendError = nil
            lastFailedAudioURL = nil
            speechRecognizer.clear()
            recorder.startRecording()
            speechRecognizer.startListening()
        }
    }

    private func sendAudio(url: URL) {
        isTranscribing = true
        sendError = nil
        lastDelivery = nil

        Task {
            do {
                let response = try await bridgeManager.sendAudioWithResponse(
                    sessionId: session.id,
                    audioURL: url
                )
                sendError = nil
                lastFailedAudioURL = nil  // Clear on success

                // Show delivery confirmation
                if response.success, let deliveredAt = response.deliveredAt {
                    lastDelivery = DeliveryConfirmation(
                        text: response.insertedText ?? response.transcript ?? "",
                        deliveredAt: deliveredAt
                    )
                    // Auto-hide after 3 seconds
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    lastDelivery = nil
                }

                // Refresh to see result
                await fetchMessages()
            } catch {
                sendError = error.localizedDescription
                lastFailedAudioURL = url  // Store for retry
            }
            isTranscribing = false
        }
    }

    private func retryAudio() {
        guard let url = lastFailedAudioURL else { return }
        sendAudio(url: url)
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
    let transcriptionPreview: String
    let delivery: DeliveryConfirmation?
    let error: String?
    let canRetryAudio: Bool
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onMicTap: () -> Void
    let onRetry: () -> Void

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
                    transcriptionPreview: transcriptionPreview,
                    onStop: onMicTap
                )
            } else if isSending {
                // Sending state - show transcription being sent
                SendingOverlay(transcriptionPreview: transcriptionPreview)
            } else if let delivery = delivery {
                // Delivery confirmation
                DeliveredOverlay(delivery: delivery)
            } else {
                // Normal input bar
                HStack(spacing: Spacing.xs) {
                    // Mic button
                    Button(action: onMicTap) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 14))
                            .frame(width: 32, height: 32)
                            .background(Color.surfaceSecondary)
                            .foregroundColor(.textSecondary)
                            .clipShape(Circle())
                    }

                    // Text field
                    TextField("Send to Claude...", text: $text, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.bodySmall)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(Color.surfaceSecondary)
                        .cornerRadius(CornerRadius.lg)
                        .lineLimit(1...5)
                        .focused(isFocused)
                        .submitLabel(.send)
                        .onSubmit {
                            onSend()
                        }

                    // Send button (enter/return)
                    Button(action: onSend) {
                        Image(systemName: "return")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 32, height: 32)
                            .background(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.surfaceTertiary : Color.active)
                            .foregroundColor(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .textTertiary : .white)
                            .clipShape(Circle())
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
            }
        }
        .background(Color.surfacePrimary)
    }
}

// MARK: - Recording Overlay

struct RecordingOverlay: View {
    let duration: TimeInterval
    let audioLevels: [Float]
    let transcriptionPreview: String
    let onStop: () -> Void

    private var durationText: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            // Particles + Timer
            HStack(spacing: Spacing.md) {
                // Compact particles visualization
                ParticlesWaveformView(
                    levels: audioLevels,
                    height: 28,
                    color: .recording
                )
                .frame(maxWidth: .infinity)

                // Duration with recording dot
                HStack(spacing: Spacing.xs) {
                    RecordingPulse(color: .recording, size: 8)
                    Text(durationText)
                        .font(.monoMedium)
                        .foregroundColor(.recording)
                }
            }
            .padding(.horizontal, Spacing.md)

            // Transcription preview
            if !transcriptionPreview.isEmpty {
                Text(transcriptionPreview)
                    .font(.bodySmall)
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.sm)
                    .background(Color.surfaceSecondary)
                    .cornerRadius(CornerRadius.sm)
                    .padding(.horizontal, Spacing.sm)
            }

            // Stop button
            Button(action: onStop) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12))
                    Text("SEND")
                        .font(.techLabel)
                        .tracking(2)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .background(Color.recording)
                .cornerRadius(CornerRadius.sm)
            }
            .padding(.horizontal, Spacing.sm)
        }
        .padding(.vertical, Spacing.sm)
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
        VStack(spacing: Spacing.sm) {
            // Sending indicator with braille spinner
            HStack(spacing: Spacing.xs) {
                BrailleSpinner(color: .active)
                Text("SENDING")
                    .font(.techLabel)
                    .tracking(2)
                    .foregroundColor(.textSecondary)
            }
            .padding(.vertical, Spacing.sm)

            // Show what's being sent
            if !transcriptionPreview.isEmpty {
                Text(transcriptionPreview)
                    .font(.bodySmall)
                    .foregroundColor(.textSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.sm)
                    .background(Color.surfaceSecondary)
                    .cornerRadius(CornerRadius.sm)
                    .padding(.horizontal, Spacing.sm)
            }
        }
        .padding(.vertical, Spacing.sm)
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
        VStack(spacing: Spacing.sm) {
            // Success indicator
            HStack(spacing: Spacing.xs) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.success)
                Text("DELIVERED")
                    .font(.techLabel)
                    .tracking(2)
                    .foregroundColor(.success)
            }
            .padding(.vertical, Spacing.sm)

            // Show what was sent
            if !delivery.text.isEmpty {
                Text(delivery.text)
                    .font(.bodySmall)
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.sm)
                    .background(Color.success.opacity(0.1))
                    .cornerRadius(CornerRadius.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(Color.success.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal, Spacing.sm)
            }
        }
        .padding(.vertical, Spacing.sm)
        .background(Color.surfacePrimary)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: SessionMessage

    private var isUser: Bool {
        message.role == "user"
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                // Role label
                HStack(spacing: 4) {
                    if !isUser {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                    }
                    Text(isUser ? "You" : "Claude")
                        .font(.system(size: 11, weight: .medium))
                    Text(formatTime(message.timestamp))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .foregroundColor(isUser ? .blue : .purple)

                // Content
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.system(size: 14))
                        .padding(12)
                        .background(isUser ? Color.blue.opacity(0.1) : Color.purple.opacity(0.1))
                        .cornerRadius(16)
                        .textSelection(.enabled)
                }

                // Tool calls
                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(toolCalls, id: \.name) { tool in
                            ToolCallView(tool: tool)
                        }
                    }
                }
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }

    private func formatTime(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoString) else {
            return ""
        }
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        return timeFormatter.string(from: date)
    }
}

// MARK: - Tool Call View

struct ToolCallView: View {
    let tool: ToolCall

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { isExpanded.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: toolIcon)
                        .font(.system(size: 10))
                    Text(tool.name)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            if isExpanded {
                if let input = tool.input, !input.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Input:")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                        Text(input)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                }

                if let output = tool.output, !output.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Output:")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                        Text(output.prefix(500) + (output.count > 500 ? "..." : ""))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                }
            }
        }
    }

    private var toolIcon: String {
        switch tool.name.lowercased() {
        case let name where name.contains("read"):
            return "doc.text"
        case let name where name.contains("write"), let name where name.contains("edit"):
            return "pencil"
        case let name where name.contains("bash"):
            return "terminal"
        case let name where name.contains("glob"), let name where name.contains("grep"):
            return "magnifyingglass"
        case let name where name.contains("web"):
            return "globe"
        default:
            return "wrench"
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
