//
//  NotchParticles.swift
//  Talkie
//
//  Particle system for notch recording visualization.
//  Copied 1:1 from Agent's NotchOverlay.swift.
//

import SwiftUI

// MARK: - Particle Flow Direction

enum ParticleFlowDirection {
    case left   // Flow from right to left
    case right  // Flow from left to right
}

// MARK: - Precomputed Particle Constants

/// Per-particle values derived from index. Computed once, reused every frame.
private struct ParticleConst {
    let speed: Double
    let phaseOffset: Double
    let laneOffset: Double
    let sizeScale: CGFloat
    let opacityScale: Double
}

/// Build the lookup table for a given count. Pure function, no per-frame cost.
private func buildParticleConstants(_ count: Int, baseSpeed: Double) -> [ParticleConst] {
    (0..<count).map { i in
        let seed = Double(i) * 1.618033988749
        let speedVar = seed.truncatingRemainder(dividingBy: 1.0) * 0.02
        return ParticleConst(
            speed: (baseSpeed + speedVar) * 1.5,
            phaseOffset: seed * 4,
            laneOffset: (Double(i % 10) / 10.0 - 0.5) * 0.25,
            sizeScale: CGFloat(0.7 + sin(seed * 5) * 0.3),
            opacityScale: 0.6 + sin(seed * 3) * 0.4
        )
    }
}

// MARK: - Notch Particles

struct NotchParticles: View {
    let audioLevel: Float
    var flowDirection: ParticleFlowDirection = .right

    private let tuning = NotchTuning.shared
    @State private var smoothedLevel: CGFloat = 0.15
    @State private var constants: [ParticleConst] = []
    @State private var lastParticleCount: Int = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.016)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let adjustedCenterY = size.height * 0.45
                let baseSize = CGFloat(tuning.particleSize)
                let baseOpacity = tuning.particleOpacity
                let level = max(0.15, smoothedLevel)
                let flowRight = flowDirection == .right

                // Amplitude: tight when quiet, expands with voice
                let waveAmplitude = (0.08 + Double(level) * 0.55) * Double(size.height) * 0.5

                let levelBonus = level * 2.0

                for p in constants {
                    // X: horizontal travel
                    let xProgress = (time * p.speed + p.phaseOffset).truncatingRemainder(dividingBy: 1.0)
                    let x = flowRight
                        ? CGFloat(xProgress) * size.width
                        : size.width - CGFloat(xProgress) * size.width

                    // Y: single wave + lane offset (1 sin per particle)
                    let wave = sin(time * 2.0 + p.phaseOffset)
                    let y = adjustedCenterY + CGFloat((wave + p.laneOffset) * waveAmplitude)

                    // Size: base + audio-reactive bonus
                    let particleSize = baseSize + levelBonus * p.sizeScale

                    // Opacity: base + audio, edge fade for trail, per-particle variation
                    let edgeFade = flowRight
                        ? min(xProgress * 3, 1.0) * min((1.0 - xProgress) * 2, 1.0)
                        : min((1.0 - xProgress) * 3, 1.0) * min(xProgress * 2, 1.0)
                    let opacity = (baseOpacity + Double(level) * 0.35) * edgeFade * p.opacityScale

                    let rect = CGRect(
                        x: x - particleSize / 2,
                        y: y - particleSize / 2,
                        width: particleSize,
                        height: particleSize
                    )
                    context.fill(Circle().path(in: rect), with: .color(.white.opacity(max(0.12, opacity))))
                }
            }
        }
        .onAppear {
            rebuildConstantsIfNeeded()
            updateSmoothedLevel(from: audioLevel)
        }
        .onChange(of: audioLevel) { _, newLevel in
            updateSmoothedLevel(from: newLevel)
        }
        .onChange(of: tuning.particleCount) { _, _ in
            rebuildConstantsIfNeeded()
        }
    }

    private func rebuildConstantsIfNeeded() {
        let count = tuning.particleCount
        guard count != lastParticleCount else { return }
        lastParticleCount = count
        constants = buildParticleConstants(count, baseSpeed: tuning.particleSpeed)
    }

    private func updateSmoothedLevel(from sourceLevel: Float) {
        let targetLevel = min(1.0, CGFloat(sourceLevel) * 3.0)
        if targetLevel > smoothedLevel {
            smoothedLevel = smoothedLevel * 0.5 + targetLevel * 0.5
        } else {
            smoothedLevel = smoothedLevel * 0.88 + targetLevel * 0.12
        }
    }
}

// MARK: - Processing Dots (animated ellipsis for transcribing state)

struct ProcessingDots: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.35)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let currentPhase = Int(t * 2.8) % 4

            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(color.opacity(dotOpacity(for: i, phase: currentPhase)))
                        .frame(width: 3, height: 3)
                }
            }
        }
    }

    private func dotOpacity(for index: Int, phase: Int) -> Double {
        if phase == 0 { return 0.4 }
        return index == (phase - 1) ? 1.0 : 0.4
    }
}

// MARK: - Line Pulse Modifier

struct LinePulseModifier: ViewModifier {
    let isAnimating: Bool
    var speed: Double = 1.2

    @State private var opacity: Double = 1.0
    @State private var scaleX: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .scaleEffect(x: scaleX, y: 1.0)
            .onAppear {
                guard isAnimating else { return }
                withAnimation(.easeInOut(duration: speed).repeatForever(autoreverses: true)) {
                    opacity = 0.7
                    scaleX = 0.92
                }
            }
            .onChange(of: isAnimating) { _, newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: speed).repeatForever(autoreverses: true)) {
                        opacity = 0.7
                        scaleX = 0.92
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        opacity = 1.0
                        scaleX = 1.0
                    }
                }
            }
    }
}

// MARK: - Vertical Pulse Modifier (for hover pill)

struct VerticalPulseModifier: ViewModifier {
    let isAnimating: Bool
    var speed: Double = 1.0

    @State private var offsetY: CGFloat = 0
    @State private var opacity: Double = 0.5

    func body(content: Content) -> some View {
        content
            .offset(y: offsetY)
            .opacity(opacity)
            .onAppear {
                guard isAnimating else { return }
                withAnimation(.easeInOut(duration: speed).repeatForever(autoreverses: true)) {
                    offsetY = 3
                    opacity = 0.8
                }
            }
            .onChange(of: isAnimating) { _, newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: speed).repeatForever(autoreverses: true)) {
                        offsetY = 3
                        opacity = 0.8
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        offsetY = 0
                        opacity = 0.5
                    }
                }
            }
    }
}
