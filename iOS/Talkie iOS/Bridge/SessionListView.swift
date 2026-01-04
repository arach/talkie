//
//  SessionListView.swift
//  Talkie iOS
//
//  List of active Claude Code sessions from Mac
//

import SwiftUI

struct SessionListView: View {
    @State private var bridgeManager = BridgeManager.shared
    @State private var isRefreshing = false

    var body: some View {
        Group {
            if bridgeManager.status == .connected {
                connectedView
            } else {
                disconnectedView
            }
        }
        .onAppear {
            if bridgeManager.isPaired && bridgeManager.status == .disconnected {
                Task {
                    await bridgeManager.connect()
                }
            }
        }
    }

    private var connectedView: some View {
        List {
            // Connection status
            Section {
                HStack {
                    Image(systemName: "desktopcomputer")
                        .font(.title2)
                        .foregroundColor(.green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(bridgeManager.pairedMacName ?? "Mac")
                            .font(.headline)
                        Text("Connected")
                            .font(.caption)
                            .foregroundColor(.green)
                    }

                    Spacer()

                    Button(action: {
                        Task {
                            isRefreshing = true
                            await bridgeManager.refreshSessions()
                            isRefreshing = false
                        }
                    }) {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }

            // Sessions
            Section("Claude Sessions") {
                if bridgeManager.sessions.isEmpty {
                    HStack {
                        Image(systemName: "tray")
                            .foregroundColor(.secondary)
                        Text("No active sessions")
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(bridgeManager.sessions) { session in
                        NavigationLink(destination: SessionDetailView(session: session)) {
                            SessionRow(session: session)
                        }
                    }
                }
            }

            // Disconnect
            Section {
                Button(action: {
                    bridgeManager.disconnect()
                }) {
                    HStack {
                        Spacer()
                        Text("Disconnect")
                            .foregroundColor(.red)
                        Spacer()
                    }
                }
            }
        }
        .refreshable {
            await bridgeManager.refreshSessions()
        }
    }

    private var disconnectedView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "desktopcomputer")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            if bridgeManager.isPaired {
                // Has pairing but disconnected
                VStack(spacing: 8) {
                    Text("Mac Disconnected")
                        .font(.headline)

                    if let error = bridgeManager.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                Button("Reconnect") {
                    Task {
                        await bridgeManager.connect()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Unpair Mac") {
                    bridgeManager.unpair()
                }
                .font(.caption)
                .foregroundColor(.red)
            } else {
                // No pairing
                VStack(spacing: 8) {
                    Text("Connect to Mac")
                        .font(.headline)

                    Text("View Claude Code sessions from your Mac remotely")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                NavigationLink(destination: QRScannerView()) {
                    Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - Session Row

struct SessionRow: View {
    let session: ClaudeSession

    var body: some View {
        HStack(spacing: 12) {
            // Live indicator
            Circle()
                .fill(session.isLive ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.project)
                    .font(.headline)

                HStack(spacing: 8) {
                    Label("\(session.messageCount)", systemImage: "bubble.left.and.bubble.right")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(formatRelativeTime(session.lastSeen))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if session.isLive {
                Text("LIVE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green)
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatRelativeTime(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoString) else {
            return isoString
        }
        let relativeFormatter = RelativeDateTimeFormatter()
        relativeFormatter.unitsStyle = .abbreviated
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    NavigationView {
        SessionListView()
            .navigationTitle("Mac Bridge")
    }
}
