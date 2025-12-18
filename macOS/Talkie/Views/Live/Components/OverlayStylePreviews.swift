//
//  OverlayStylePreviews.swift
//  Talkie
//
//  Live overlay style preview components for settings
//  Ported from TalkieLive with instrumentation
//

import SwiftUI
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "LiveSettings")

// MARK: - Wavy Particles Preview
// Miniature version of WavyParticlesView from TalkieLive

struct WavyParticlesPreview: View {
    let calm: Bool
    @State private var animationPhase: CGFloat = 0
    @State private var particlePositions: [(x: CGFloat, y: CGFloat, opacity: CGFloat)] = []

    private let particleCount = 16
    private let previewSize = CGSize(width: 80, height: 40)

    var body: some View {
        ZStack {
            // Darker background with subtle border
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(Color.black.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )

            TimelineView(.animation(minimumInterval: 0.033)) { timeline in
                Canvas { context, size in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let centerY = size.height / 2

                    // More dramatic difference between calm and energetic
                    let baseSpeed: CGFloat = calm ? 0.05 : 0.2
                    let waveSpeed: CGFloat = calm ? 1.0 : 3.5
                    let amplitude: CGFloat = calm ? 5 : 15

                    for i in 0..<particleCount {
                        let seed = Double(i) * 1.618

                        // Horizontal flow
                        let speed = baseSpeed + CGFloat(seed.truncatingRemainder(dividingBy: 0.3))
                        let xProgress = (time * Double(speed) + seed).truncatingRemainder(dividingBy: 1.0)
                        let x = CGFloat(xProgress) * size.width

                        // Wavy vertical motion
                        let wave = sin(time * Double(waveSpeed) + seed * 4) * Double(amplitude)
                        let y = centerY + CGFloat(wave)

                        // Size and opacity - white particles
                        let particleSize: CGFloat = calm ? 3.0 : 2.5
                        let opacity = 0.5 + sin(seed * 3) * 0.3

                        let rect = CGRect(
                            x: x - particleSize / 2,
                            y: y - particleSize / 2,
                            width: particleSize,
                            height: particleSize
                        )

                        context.fill(
                            Circle().path(in: rect),
                            with: .color(Color.white.opacity(opacity))
                        )
                    }
                }
            }
        }
        .onAppear {
            logger.debug("WavyParticlesPreview appeared (calm: \(calm))")
        }
    }
}

// MARK: - Waveform Bars Preview
// Miniature version of WaveformBarsView from TalkieLive

struct WaveformBarsPreview: View {
    let sensitive: Bool
    @State private var phase: CGFloat = 0

    private let barCount = 12
    private let previewSize = CGSize(width: 80, height: 40)

    var body: some View {
        ZStack {
            // Darker background with subtle border
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(Color.black.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )

            TimelineView(.animation(minimumInterval: 0.033)) { timeline in
                Canvas { context, size in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let barWidth: CGFloat = (size.width - CGFloat(barCount - 1) * 2) / CGFloat(barCount)
                    let centerY = size.height / 2
                    let maxHeight = size.height * 0.7

                    // More dramatic difference between sensitive and normal
                    let amplitude: CGFloat = sensitive ? 1.0 : 0.4
                    let speed: CGFloat = sensitive ? 3.5 : 1.8

                    for i in 0..<barCount {
                        let x = CGFloat(i) * (barWidth + 2)

                        // Animated bar height
                        let wave = sin(time * Double(speed) + Double(i) * 0.6) * Double(amplitude)
                        let barHeight = max(4, (wave * 0.5 + 0.5) * Double(maxHeight))

                        let rect = CGRect(
                            x: x,
                            y: centerY - CGFloat(barHeight) / 2,
                            width: barWidth,
                            height: CGFloat(barHeight)
                        )

                        // Gray waveform bars
                        let opacity = 0.6 + wave * 0.3
                        context.fill(
                            RoundedRectangle(cornerRadius: 1).path(in: rect),
                            with: .color(Color.gray.opacity(opacity))
                        )
                    }
                }
            }
        }
        .onAppear {
            logger.debug("WaveformBarsPreview appeared (sensitive: \(sensitive))")
        }
    }
}

// MARK: - Pill Only Preview

struct PillOnlyPreview: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(Color.black.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )

            VStack(spacing: 2) {
                Image(systemName: "minus")
                    .font(.labelMedium)
                    .foregroundColor(.secondary)
                Text("No overlay")
                    .font(.labelSmall)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            logger.debug("PillOnlyPreview appeared")
        }
    }
}
