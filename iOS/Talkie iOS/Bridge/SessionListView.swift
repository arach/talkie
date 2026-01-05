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
    @State private var isCapturing = false
    @State private var captureError: String?
    @State private var selectedWindow: WindowCapture?

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

            // Terminal Windows (Screenshots)
            Section("Terminal Windows") {
                if let error = captureError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if bridgeManager.windowCaptures.isEmpty {
                    HStack {
                        Image(systemName: "macwindow")
                            .foregroundColor(.secondary)
                        Text("No windows captured")
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)

                    Button(action: captureWindows) {
                        if isCapturing {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Capturing...")
                            }
                        } else {
                            Label("Capture Windows", systemImage: "camera")
                        }
                    }
                    .disabled(isCapturing)
                } else {
                    // Grid of window thumbnails
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(bridgeManager.windowCaptures) { capture in
                            WindowThumbnailCell(capture: capture)
                                .onTapGesture {
                                    selectedWindow = capture
                                }
                        }
                    }
                    .padding(.vertical, 8)

                    Button(action: captureWindows) {
                        if isCapturing {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Refreshing...")
                            }
                        } else {
                            Label("Refresh Screenshots", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isCapturing)
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
            await bridgeManager.refreshAll()
            await bridgeManager.refreshWindowCaptures()
        }
        .sheet(item: $selectedWindow) { window in
            WindowDetailSheet(capture: window)
        }
    }

    // MARK: - Actions

    private func captureWindows() {
        isCapturing = true
        captureError = nil
        Task {
            do {
                try await bridgeManager.refreshWindowCapturesWithError()
            } catch {
                captureError = error.localizedDescription
            }
            isCapturing = false
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

// MARK: - Window Thumbnail Cell

struct WindowThumbnailCell: View {
    let capture: WindowCapture

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Screenshot
            Group {
                if let imageData = capture.imageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 90)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 90)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                        }
                }
            }
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )

            // Window title
            Text(capture.title)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Window Detail Sheet

struct WindowDetailSheet: View {
    let capture: WindowCapture
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Full-size screenshot
                    if let imageData = capture.imageData,
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(12)
                            .shadow(radius: 4)
                    }

                    // Metadata
                    VStack(alignment: .leading, spacing: 12) {
                        MetadataRow(label: "Window ID", value: "\(capture.windowID)")
                        MetadataRow(label: "Bundle ID", value: capture.bundleId)
                        MetadataRow(label: "Title", value: capture.title)
                        if let imageData = capture.imageData {
                            MetadataRow(label: "Image Size", value: "\(imageData.count / 1024) KB")
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle(capture.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(1)
        }
    }
}

#Preview {
    NavigationView {
        SessionListView()
            .navigationTitle("Mac Bridge")
    }
}
