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
                InputBar(
                    text: $inputText,
                    isSending: isSending,
                    error: sendError,
                    isFocused: $isInputFocused,
                    onSend: sendMessage
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
                try await bridgeManager.injectText(sessionId: session.id, text: text)
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
}

// MARK: - Input Bar

struct InputBar: View {
    @Binding var text: String
    let isSending: Bool
    let error: String?
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            // Error message
            if let error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }

            HStack(spacing: 8) {
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
                    .disabled(isSending)
                    .submitLabel(.send)
                    .onSubmit {
                        onSend()
                    }

                // Send button
                Button(action: onSend) {
                    Group {
                        if isSending {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .frame(width: 32, height: 32)
                    .background(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Circle())
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
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
            id: "test",
            project: "talkie",
            projectPath: "/Users/arach/dev/talkie",
            isLive: true,
            lastSeen: ISO8601DateFormatter().string(from: Date()),
            messageCount: 42
        ))
    }
}
