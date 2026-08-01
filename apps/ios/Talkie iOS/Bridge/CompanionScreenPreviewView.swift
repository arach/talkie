//
//  CompanionScreenPreviewView.swift
//  Talkie iOS
//


import SwiftUI

/// Presents the paired Mac's current main display without opening capture UI on the Mac.
struct CompanionScreenPreviewView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @State private var screenStream = CompanionScreenStream.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                theme.colors.background.ignoresSafeArea()

                VStack(spacing: 12) {
                    statusStrip
                    previewSurface
                    frameReadout
                }
                .padding(16)
            }
            .navigationTitle("Screen Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.colors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tint(theme.chrome.accent)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { startStream() }
        .onDisappear { screenStream.stop() }
    }

    private var statusStrip: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .shadow(color: statusColor.opacity(0.55), radius: 5)

            Text(statusLabel)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1)

            Spacer(minLength: 8)

            if screenStream.isStreaming {
                Text("\(screenStream.appliedFPS) FPS")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }
        }
        .foregroundStyle(theme.colors.textSecondary)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var previewSurface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black)

            if let image = screenStream.latestFrame {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 14))
                    .padding(4)
            } else if let errorMessage = screenStream.errorMessage {
                ContentUnavailableView {
                    Label("Preview unavailable", systemImage: "display.trianglebadge.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry", systemImage: "arrow.clockwise") { restartStream() }
                }
                .foregroundStyle(theme.colors.textSecondary)
            } else {
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(theme.chrome.accent)

                    Text("CONNECTING TO MAC")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(theme.colors.textSecondary)

                    Text("The current main display will appear automatically.")
                        .font(.footnote)
                        .foregroundStyle(theme.colors.textTertiary)
                }
                .multilineTextAlignment(.center)
                .padding(24)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(theme.chrome.accent.opacity(screenStream.isStreaming ? 0.42 : 0.16), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Live preview of the paired Mac screen")
    }

    private var frameReadout: some View {
        HStack {
            Text("MAIN DISPLAY")
            Spacer()
            if let latestFrameAt = screenStream.latestFrameAt {
                Text(latestFrameAt, format: .dateTime.hour().minute().second())
            } else {
                Text("WAITING")
            }
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .tracking(0.8)
        .foregroundStyle(theme.colors.textTertiary)
    }

    private var statusLabel: String {
        if screenStream.errorMessage != nil { return "OFFLINE" }
        if screenStream.isStreaming { return "LIVE" }
        return "CONNECTING"
    }

    private var statusColor: Color {
        if screenStream.errorMessage != nil {
            return Color(red: 0.85, green: 0.35, blue: 0.33)
        }
        return screenStream.isStreaming ? theme.chrome.accent : theme.colors.textTertiary
    }

    private func startStream() {
        screenStream.start(fps: 2, maxDimension: 1600, quality: 0.65)
    }

    private func restartStream() {
        screenStream.stop()
        startStream()
    }
}
