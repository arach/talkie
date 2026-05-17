//
//  CompanionScreenPreviewView.swift
//  Talkie iOS
//
//  Live low-bandwidth peek into the paired Mac display.
//

import SwiftUI

struct CompanionScreenPreviewView: View {
    let macName: String

    @Environment(\.dismiss) private var dismiss
    @State private var stream = CompanionScreenStream.shared

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color.black,
                        Color.black.opacity(0.92),
                        Color.green.opacity(0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 16) {
                    previewPanel
                    statusPanel
                }
                .padding(16)
            }
            .navigationTitle("Desktop Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            let isPhone = UIDevice.current.userInterfaceIdiom == .phone
            stream.start(fps: 2, maxDimension: isPhone ? 900 : 1400, quality: isPhone ? 0.5 : 0.6)
        }
        .onDisappear {
            stream.stop()
        }
    }

    private var previewPanel: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )

            Group {
                if let image = stream.latestFrame {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    placeholderState
                }
            }
            .clipShape(.rect(cornerRadius: 18))
            .padding(10)

            HStack(spacing: 8) {
                Circle()
                    .fill(stream.isStreaming ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)

                    Text(stream.isStreaming ? "LIVE DESKTOP" : "CONNECTING")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.42))
            .clipShape(Capsule())
            .padding(18)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
    }

    private var placeholderState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.green)
                .scaleEffect(1.2)

            Text("Waiting for your Mac")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)

            Text("Talkie is opening a low-bandwidth desktop peek from \(macName).")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            TalkieEyebrow(text: macName, tint: .panelInk, showLeader: false)

            Text(statusCopy)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))

            HStack(spacing: 14) {
                statusMetric(label: "FPS", value: "\(stream.appliedFPS)")
                statusMetric(label: "Frames", value: "\(stream.frameCount)")
                statusMetric(label: "Updated", value: updatedLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.06))
        .clipShape(.rect(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func statusMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
        }
    }

    private var statusCopy: String {
        if let error = stream.errorMessage, !error.isEmpty {
            return error
        }
        if stream.isStreaming {
            return "Live desktop peek is running. This is tuned for quick visual context, not full remote control."
        }
        return "Establishing the preview stream."
    }

    private var updatedLabel: String {
        guard let lastUpdate = stream.latestFrameAt else {
            return "--"
        }

        let seconds = max(0, Int(Date().timeIntervalSince(lastUpdate)))
        if seconds == 0 {
            return "now"
        }
        return "\(seconds)s"
    }
}
