//
//  MessageQueueView.swift
//  Talkie
//
//  UI for viewing and managing the Bridge message queue.
//  Allows sending messages to sessions and retrying failed ones.
//

import SwiftUI
import TalkieKit

private let log = Log(.ui)

/// Session info from Bridge API
private struct BridgeSession: Codable, Identifiable {
    let id: String
    let project: String
    let projectPath: String
    let isLive: Bool
}

private struct BridgeSessionsResponse: Codable {
    let sessions: [BridgeSession]
}

struct MessageQueueView: View {
    @State private var queue = MessageQueue.shared

    // Sessions from Bridge API
    @State private var sessions: [BridgeSession] = []
    @State private var isLoadingSessions: Bool = false

    // New message input
    @State private var selectedSessionId: String = ""
    @State private var selectedProjectPath: String = ""
    @State private var messageText: String = ""
    @State private var isSending: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Session Manager")
                    .font(.headline)
                Spacer()
                if !queue.messages.isEmpty {
                    Button("Clear Sent") {
                        queue.clearSent()
                    }
                    .buttonStyle(.borderless)
                    .disabled(queue.messages.filter { $0.status == .sent }.isEmpty)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // New message composer
            VStack(spacing: 12) {
                // Session picker
                HStack {
                    Text("Session:")
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .trailing)

                    Picker("", selection: $selectedSessionId) {
                        Text("Select session...").tag("")
                        ForEach(sessions) { session in
                            HStack {
                                if session.isLive {
                                    Circle()
                                        .fill(.green)
                                        .frame(width: 6, height: 6)
                                }
                                Text(session.project)
                            }
                            .tag(session.id)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: selectedSessionId) { _, newValue in
                        if let session = sessions.first(where: { $0.id == newValue }) {
                            selectedProjectPath = session.projectPath
                        }
                    }

                    if isLoadingSessions {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button(action: fetchSessions) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                // Project path (read-only, for reference)
                if !selectedProjectPath.isEmpty {
                    HStack {
                        Text("Path:")
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .trailing)
                        Text(selectedProjectPath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                }

                // Message input
                HStack(alignment: .top) {
                    Text("Message:")
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .trailing)

                    TextField("Enter message...", text: $messageText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)
                        .lineLimit(1...4)

                    Button(action: sendMessage) {
                        if isSending {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedSessionId.isEmpty || messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Message list
            if queue.messages.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No messages in queue")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(queue.messages) { message in
                        MessageRow(message: message, onRetry: { retryMessage(message) }, onDelete: { queue.remove(message.id) })
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .onAppear {
            fetchSessions()
        }
    }

    private func fetchSessions() {
        isLoadingSessions = true
        Task {
            do {
                let url = URL(string: "http://localhost:8765/sessions")!
                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode(BridgeSessionsResponse.self, from: data)
                sessions = response.sessions
            } catch {
                log.error("Failed to fetch sessions: \(error)")
            }
            isLoadingSessions = false
        }
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !selectedSessionId.isEmpty else { return }

        // Add to queue with localUI source
        queue.enqueue(
            sessionId: selectedSessionId,
            projectPath: selectedProjectPath,
            text: text,
            source: .localUI,
            metadata: ["view": "MessageQueueView"]
        )

        // Get the message we just added
        guard let message = queue.messages.first else { return }

        // Send it
        sendToTalkieLive(message)

        // Clear input
        messageText = ""
    }

    private func retryMessage(_ message: QueuedMessage) {
        sendToTalkieLive(message)
    }

    private func sendToTalkieLive(_ message: QueuedMessage) {
        queue.updateStatus(message.id, status: .sending)
        isSending = true
        let xpcStartTime = Date()

        Task {
            do {
                // Get XPC proxy
                guard let xpcManager = ServiceManager.shared.live.xpcManager else {
                    throw NSError(domain: "MessageQueue", code: 1, userInfo: [NSLocalizedDescriptionKey: "TalkieLive not connected"])
                }

                guard let proxy = xpcManager.remoteObjectProxy(errorHandler: { error in
                    log.error("XPC error: \(error)")
                }) else {
                    throw NSError(domain: "MessageQueue", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not get XPC proxy"])
                }

                // Call appendMessage (submit: true to press Enter for Bridge messages)
                let result = await withCheckedContinuation { (continuation: CheckedContinuation<(Bool, String?), Never>) in
                    proxy.appendMessage(message.text, sessionId: message.sessionId, projectPath: message.projectPath, submit: true) { success, error in
                        continuation.resume(returning: (success, error))
                    }
                }

                let durationMs = Int(Date().timeIntervalSince(xpcStartTime) * 1000)
                if result.0 {
                    queue.updateStatus(message.id, status: .sent, xpcDurationMs: durationMs)
                    log.info("Message sent successfully in \(durationMs)ms")
                } else {
                    queue.updateStatus(message.id, status: .failed, error: result.1 ?? "Unknown error", xpcDurationMs: durationMs)
                    log.error("Message failed: \(result.1 ?? "unknown")")
                }
            } catch {
                let durationMs = Int(Date().timeIntervalSince(xpcStartTime) * 1000)
                queue.updateStatus(message.id, status: .failed, error: error.localizedDescription, xpcDurationMs: durationMs)
                log.error("Send error: \(error)")
            }

            isSending = false
        }
    }
}

// MARK: - Message Row

private struct MessageRow: View {
    let message: QueuedMessage
    let onRetry: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Status indicator
            statusIcon
                .frame(width: 20)

            // Message content
            VStack(alignment: .leading, spacing: 4) {
                // Session + time
                HStack {
                    Text(message.sessionId.prefix(8) + "...")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(message.createdAt, style: .time)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                // Message text
                Text(message.text)
                    .font(.system(size: 12))
                    .lineLimit(2)

                // Error message
                if let error = message.lastError {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }

                // Attempts
                if message.attempts > 1 {
                    Text("Attempts: \(message.attempts)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Actions
            if message.status == .failed || message.status == .pending {
                Button(action: onRetry) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Retry")
            }

            Button(action: onDelete) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
            .help("Remove")
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch message.status {
        case .pending:
            Image(systemName: "clock")
                .foregroundColor(.orange)
        case .sending:
            ProgressView()
                .controlSize(.small)
        case .sent:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)
        }
    }
}

#Preview {
    MessageQueueView()
        .frame(width: 500, height: 400)
}
