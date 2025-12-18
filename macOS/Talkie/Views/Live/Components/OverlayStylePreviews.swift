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
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.15))

            TimelineView(.animation(minimumInterval: 0.033)) { timeline in
                Canvas { context, size in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let centerY = size.height / 2

                    let calmFactor: CGFloat = calm ? 0.6 : 1.0
                    let baseSpeed: CGFloat = (calm ? 0.08 : 0.15) * calmFactor
                    let waveSpeed: CGFloat = (calm ? 1.5 : 2.5) * calmFactor
                    let amplitude: CGFloat = (calm ? 8 : 12) * calmFactor

                    for i in 0..<particleCount {
                        let seed = Double(i) * 1.618

                        // Horizontal flow
                        let speed = baseSpeed + CGFloat(seed.truncatingRemainder(dividingBy: 0.3))
                        let xProgress = (time * Double(speed) + seed).truncatingRemainder(dividingBy: 1.0)
                        let x = CGFloat(xProgress) * size.width

                        // Wavy vertical motion
                        let wave = sin(time * Double(waveSpeed) + seed * 4) * Double(amplitude)
                        let y = centerY + CGFloat(wave)

                        // Size and opacity
                        let particleSize: CGFloat = calm ? 2.5 : 2.0
                        let opacity = 0.4 + sin(seed * 3) * 0.3

                        let rect = CGRect(
                            x: x - particleSize / 2,
                            y: y - particleSize / 2,
                            width: particleSize,
                            height: particleSize
                        )

                        context.fill(
                            Circle().path(in: rect),
                            with: .color(Color.blue.opacity(opacity))
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
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.15))

            TimelineView(.animation(minimumInterval: 0.033)) { timeline in
                Canvas { context, size in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let barWidth: CGFloat = (size.width - CGFloat(barCount - 1) * 2) / CGFloat(barCount)
                    let centerY = size.height / 2
                    let maxHeight = size.height * 0.7

                    let amplitude: CGFloat = sensitive ? 0.9 : 0.6
                    let speed: CGFloat = sensitive ? 2.5 : 2.0

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

                        let opacity = 0.6 + wave * 0.3
                        context.fill(
                            RoundedRectangle(cornerRadius: 1).path(in: rect),
                            with: .color(Color.green.opacity(opacity))
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
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.15))

            VStack(spacing: 2) {
                Image(systemName: "minus")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("No overlay")
                    .font(.system(size: 7))
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            logger.debug("PillOnlyPreview appeared")
        }
    }
}
