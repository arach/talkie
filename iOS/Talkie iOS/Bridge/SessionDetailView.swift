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

    // Force Enter state
    @State private var isForcingEnter = false

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
        .navigationTitle(session.project)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 8) {
                    if session.isLive {
                        Text("LIVE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .cornerRadius(4)

                        // Force Enter button
                        Button(action: forceEnter) {
                            if isForcingEnter {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "return")
                            }
                        }
                        .disabled(isForcingEnter)
                    }

                    Button(action: loadMessages) {
                        Image(systemName: "arrow.clockwise")
                    }
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

    private func forceEnter() {
        isForcingEnter = true
        sendError = nil

        Task {
            do {
                try await bridgeManager.forceEnter(sessionId: session.id)
                // Refresh messages after a brief delay
                try? await Task.sleep(nanoseconds: 500_000_000)
                await fetchMessages()
            } catch {
                sendError = "Enter failed: \(error.localizedDescription)"
            }
            isForcingEnter = false
        }
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
                HStack(spacing: 8) {
                    // Mic button
                    Button(action: onMicTap) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 16))
                            .frame(width: 36, height: 36)
                            .background(Color(.systemGray5))
                            .foregroundColor(.primary)
                            .clipShape(Circle())
                    }

                    // Text field
                    TextField("Send to Claude...", text: $text, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .cornerRadius(20)
                        .lineLimit(1...5)
                        .focused(isFocused)
                        .submitLabel(.send)
                        .onSubmit {
                            onSend()
                        }

                    // Send button
                    Button(action: onSend) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .background(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .background(Color(.systemBackground))
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
        VStack(spacing: 12) {
            // Waveform visualization
            HStack(spacing: 12) {
                // Recording indicator
                RecordingPulse(color: .red)

                // Waveform
                WaveformView(
                    levels: audioLevels,
                    height: 32,
                    color: .red
                )

                // Duration
                Text(durationText)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.red)
            }
            .padding(.horizontal, 16)

            // Transcription preview
            if !transcriptionPreview.isEmpty {
                Text(transcriptionPreview)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal, 12)
            } else {
                Text("Listening...")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .italic()
            }

            // Stop button
            Button(action: onStop) {
                HStack(spacing: 8) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14))
                    Text("Tap to Send")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.red)
                .cornerRadius(24)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .padding(.top, 12)
        .background(Color(.systemBackground))
    }
}

// MARK: - Sending Overlay

struct SendingOverlay: View {
    let transcriptionPreview: String

    var body: some View {
        VStack(spacing: 12) {
            // Show what's being sent
            if !transcriptionPreview.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    Text(transcriptionPreview)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal, 12)
            }

            // Sending indicator
            HStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.9)

                Text("Sending to Mac...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 12)
        }
        .padding(.top, 8)
        .background(Color(.systemBackground))
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
        VStack(spacing: 12) {
            // Success icon with animation
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.green)

                Text("Delivered to Claude")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.green)
            }

            // Show what was sent
            if !delivery.text.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    Text(delivery.text)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
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
