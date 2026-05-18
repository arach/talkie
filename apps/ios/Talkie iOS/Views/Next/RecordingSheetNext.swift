//
//  RecordingSheetNext.swift
//  Talkie iOS
//
//  Phase 3 paint — minimal Next-style recording modal. Two detents
//  (compact 280pt for the active record; expanded 560pt for save
//  metadata). Existing RecordingView.swift carries the full feature
//  set; this is the rebuilt visual entry point chrome's mic-FAB
//  routes into. Codex bridges the real recorder/save flow.
//

import SwiftUI

/// Tracks the active state of the next-style recording sheet — the
/// chrome's mic-FAB sets this true; the sheet observes and presents.
@MainActor
final class RecordingSheetController: ObservableObject {
    static let shared = RecordingSheetController()
    @Published var isPresented: Bool = false
    private init() {}
}

struct RecordingSheetNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var controller = RecordingSheetController.shared

    @State private var detent: PresentationDetent = .height(280)
    @State private var phase: Phase = .recording
    @State private var elapsed: TimeInterval = 0
    @State private var title: String = ""
    @State private var startedAt: Date = Date()

    private enum Phase { case starting, recording, stopped }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(theme.colors.textTertiary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 12)

            switch phase {
            case .starting:  startingBody
            case .recording: recordingBody
            case .stopped:   stoppedBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 20)
        .presentationDetents([.height(280), .height(560)], selection: $detent)
        .presentationDragIndicator(.hidden)
        .presentationBackground(.regularMaterial)
        .onAppear { startTimer() }
    }

    // MARK: - Starting

    private var startingBody: some View {
        VStack(spacing: 14) {
            Image(systemName: "mic.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(theme.currentTheme.chrome.accent)
            Text("· LISTENING")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .padding(.top, 30)
    }

    // MARK: - Recording

    private var recordingBody: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                LiveWaveform(color: theme.currentTheme.chrome.accent)
                    .frame(width: 60, height: 28)
                Text(timeString(elapsed))
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(theme.colors.textPrimary)
                    .tracking(-1)
            }

            Text("· REC · \(qualityLabel) · \(memoTargetLabel)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(theme.colors.textTertiary)

            Spacer()

            HStack(spacing: 18) {
                circleButton(
                    systemImage: "xmark",
                    label: "Cancel",
                    isPrimary: false,
                    action: { controller.isPresented = false }
                )
                circleButton(
                    systemImage: "stop.fill",
                    label: "Stop",
                    isPrimary: true,
                    action: { phase = .stopped }
                )
                circleButton(
                    systemImage: "checkmark",
                    label: "Save & continue",
                    isPrimary: false,
                    action: { phase = .stopped }
                )
            }
            .padding(.bottom, 22)
        }
        .padding(.top, 8)
    }

    // MARK: - Stopped (save metadata)

    private var stoppedBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("· READY TO SAVE")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                Spacer()
                Text(timeString(elapsed))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(theme.colors.textTertiary)
            }

            TextField("Title (optional)", text: $title)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(theme.colors.textPrimary)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.colors.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                              lineWidth: theme.currentTheme.chrome.hairlineWidth)
                        )
                )

            metadataRow(label: "Started", value: startedAt.formatted(date: .omitted, time: .shortened))
            metadataRow(label: "Length",  value: timeString(elapsed))
            metadataRow(label: "Quality", value: qualityLabel)

            Spacer()

            HStack(spacing: 10) {
                Button(action: { controller.isPresented = false }) {
                    Text("Discard")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                                   lineWidth: theme.currentTheme.chrome.hairlineWidth)
                        )
                }
                .buttonStyle(.plain)

                Button(action: {
                    // TODO M3+: persist via existing save flow; for
                    // now just dismiss.
                    controller.isPresented = false
                }) {
                    Text("Save memo")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.colors.cardBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(theme.currentTheme.chrome.accent))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 22)
        }
        .padding(.top, 4)
        .onAppear { detent = .height(560) }
    }

    // MARK: - Helpers

    private func startTimer() {
        startedAt = Date()
        elapsed = 0
        Task { @MainActor in
            while phase == .recording || phase == .starting {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if phase == .recording { elapsed += 0.1 }
            }
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        let total = Int(t)
        let m = total / 60
        let s = total % 60
        let ms = Int((t - TimeInterval(total)) * 10)
        return String(format: "%01d:%02d.%d", m, s, ms)
    }

    private var qualityLabel: String { "HQ · 44.1k" }
    private var memoTargetLabel: String { "MEMO" }

    @ViewBuilder
    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(theme.colors.textTertiary)
                .textCase(.uppercase)
            Spacer()
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(theme.colors.textSecondary)
        }
    }

    @ViewBuilder
    private func circleButton(systemImage: String, label: String, isPrimary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(isPrimary ? theme.currentTheme.chrome.accent : theme.colors.cardBackground)
                        .overlay(Circle().strokeBorder(
                            isPrimary ? Color.clear : theme.currentTheme.chrome.edgeFaint,
                            lineWidth: theme.currentTheme.chrome.hairlineWidth
                        ))
                    Image(systemName: systemImage)
                        .font(.system(size: isPrimary ? 20 : 15, weight: .medium))
                        .foregroundStyle(isPrimary ? theme.colors.cardBackground : theme.colors.textSecondary)
                }
                .frame(width: isPrimary ? 60 : 44, height: isPrimary ? 60 : 44)
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)

                Text(label)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(theme.colors.textTertiary)
                    .textCase(.uppercase)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct LiveWaveform: View {
    let color: Color
    private let bars = 9

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<bars, id: \.self) { i in
                    let phase = sin(t * 2 * .pi / 0.8 + Double(i) * 0.55)
                    let h = 6 + (phase + 1) / 2 * 22
                    Capsule()
                        .fill(color)
                        .frame(width: 3, height: h)
                }
            }
        }
    }
}
