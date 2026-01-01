//
//  DownloadProgressView.swift
//  Talkie
//
//  Consistent download progress UI for AI models.
//  Shows progress bar with percentage and cancel button.
//

import SwiftUI

// MARK: - Download Progress View

/// Progress indicator for model downloads with cancel action
struct DownloadProgressView: View {
    let progress: Double
    let accentColor: Color
    let onCancel: () -> Void

    private let settings = SettingsManager.shared

    init(
        progress: Double,
        accentColor: Color = .cyan,
        onCancel: @escaping () -> Void
    ) {
        self.progress = progress
        self.accentColor = accentColor
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 3) {
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(.linear)
                .tint(accentColor)

            HStack {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(settings.midnightTextTertiary)

                Spacer()

                Button("Cancel", action: onCancel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.red.opacity(0.8))
                    .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Compact Download Progress

/// Smaller progress indicator for inline use
struct CompactDownloadProgress: View {
    let progress: Double
    let accentColor: Color

    init(progress: Double, accentColor: Color = .cyan) {
        self.progress = progress
        self.accentColor = accentColor
    }

    var body: some View {
        HStack(spacing: 6) {
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(.linear)
                .tint(accentColor)
                .frame(width: 60)

            Text("\(Int(progress * 100))%")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.current.foregroundSecondary)
        }
    }
}

// MARK: - Loading Indicator

/// Indeterminate loading indicator with optional label
struct ModelLoadingIndicator: View {
    let label: String?

    init(label: String? = nil) {
        self.label = label
    }

    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 14, height: 14)

            if let label {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
        }
    }
}

// MARK: - Preview

#Preview("Download Progress") {
    VStack(spacing: 24) {
        VStack(alignment: .leading, spacing: 8) {
            Text("Full Progress").font(.headline)

            DownloadProgressView(progress: 0.45, accentColor: .orange) {
                print("Cancel tapped")
            }
            .frame(width: 200)
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("Compact Progress").font(.headline)

            HStack(spacing: 16) {
                CompactDownloadProgress(progress: 0.25, accentColor: .cyan)
                CompactDownloadProgress(progress: 0.75, accentColor: .purple)
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("Loading Indicators").font(.headline)

            HStack(spacing: 16) {
                ModelLoadingIndicator()
                ModelLoadingIndicator(label: "Loading...")
            }
        }
    }
    .padding(24)
    .background(Color(white: 0.1))
    .frame(width: 400)
}
