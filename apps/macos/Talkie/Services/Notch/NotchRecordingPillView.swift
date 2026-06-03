//
//  NotchRecordingPillView.swift
//  Talkie
//
//  Screen recording timer pill shown in the notch area during screen recordings.
//

import SwiftUI

struct ScreenRecordingNotchPillView: View {
    let startTime: Date
    let onStop: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var elapsedSeconds: Int = 0
    @State private var timer: Timer?
    @State private var isPulsing = false

    private var isLightMode: Bool {
        colorScheme == .light
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(red: 1.0, green: 0.23, blue: 0.23))
                .frame(width: 8, height: 8)
                .opacity(isPulsing ? 0.4 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)

            Text(formatTime(elapsedSeconds))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(timerColor)
                .frame(minWidth: 30, alignment: .leading)

            Button(action: onStop) {
                ZStack {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.20, blue: 0.20))
                        .frame(width: 28, height: 28)

                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 40, height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Stop screen recording")
            .accessibilityLabel("Stop screen recording")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(pillFill)
                .shadow(color: pillShadowColor, radius: 9, y: 2)
        )
        .overlay(
            Capsule()
                .stroke(pillStrokeColor, lineWidth: 1)
        )
        .onAppear {
            isPulsing = true
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                Task { @MainActor in
                    elapsedSeconds = Int(Date().timeIntervalSince(startTime))
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func formatTime(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let secondsText = seconds < 10 ? "0\(seconds)" : "\(seconds)"
        return "\(minutes):\(secondsText)"
    }

    private var pillFill: AnyShapeStyle {
        if isLightMode {
            return AnyShapeStyle(Color.white.opacity(0.96))
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }

    private var timerColor: Color {
        isLightMode ? Color.black.opacity(0.68) : Color.white.opacity(0.92)
    }

    private var pillStrokeColor: Color {
        isLightMode ? Color.red.opacity(0.22) : Color.red.opacity(0.34)
    }

    private var pillShadowColor: Color {
        isLightMode ? Color.black.opacity(0.16) : Color.black.opacity(0.28)
    }
}
