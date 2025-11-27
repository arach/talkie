//
//  WaveformView.swift
//  talkie
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI

struct WaveformView: View {
    let levels: [Float]
    let height: CGFloat
    var color: Color = .blue
    var barWidth: CGFloat = 2
    var spacing: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let barSpacing = barWidth + spacing
            let maxBars = Int(totalWidth / barSpacing)
            let displayLevels = sampleLevels(levels, targetCount: maxBars)

            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<displayLevels.count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(color)
                        .frame(
                            width: barWidth,
                            height: max(3, CGFloat(displayLevels[index]) * height)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: height, alignment: .center)
        }
        .frame(height: height)
    }

    // Sample levels to fit available width while maintaining shape
    private func sampleLevels(_ levels: [Float], targetCount: Int) -> [Float] {
        guard levels.count > targetCount else { return levels }

        let step = Float(levels.count) / Float(targetCount)
        var sampled: [Float] = []

        for i in 0..<targetCount {
            let index = Int(Float(i) * step)
            if index < levels.count {
                sampled.append(levels[index])
            }
        }

        return sampled
    }
}

// MARK: - Waveform Style Options

enum WaveformStyle: Hashable {
    case wave
    case spectrum
    case particles
}

// MARK: - Wave Style (Faked waveform using noise + amplitude)

struct WaveWaveformView: View {
    let levels: [Float]
    let height: CGFloat
    var color: Color = .red

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.016)) { timeline in
            Canvas { context, size in
                let midY = size.height / 2
                let time = timeline.date.timeIntervalSinceReferenceDate
                let pointCount = 200

                // Get recent levels
                let recentLevels: [Float]
                if levels.count >= pointCount {
                    recentLevels = Array(levels.suffix(pointCount))
                } else {
                    let padding = Array(repeating: Float(0), count: pointCount - levels.count)
                    recentLevels = padding + levels
                }

                let sliceWidth = size.width / CGFloat(pointCount - 1)
                var path = Path()

                for i in 0..<pointCount {
                    let level = CGFloat(recentLevels[i])
                    let x = CGFloat(i) * sliceWidth

                    // Multiple sine waves at different frequencies for organic feel
                    let wave1 = sin(CGFloat(i) * 0.15 + CGFloat(time) * 3)
                    let wave2 = sin(CGFloat(i) * 0.08 - CGFloat(time) * 2) * 0.5
                    let wave3 = sin(CGFloat(i) * 0.3 + CGFloat(time) * 5) * 0.25
                    let combinedWave = wave1 + wave2 + wave3

                    // Amplitude based on audio level
                    let amplitude = level * midY * 0.5
                    let y = midY + combinedWave * amplitude

                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }

                // Indigo gradient like React
                let gradient = Gradient(colors: [
                    Color(hex: "4f46e5"),
                    Color(hex: "818cf8"),
                    Color(hex: "4f46e5")
                ])

                context.stroke(
                    path,
                    with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: midY), endPoint: CGPoint(x: size.width, y: midY)),
                    lineWidth: 2.5
                )
            }
        }
        .frame(height: height)
    }
}

// MARK: - Spectrum Style (Bars from React)

struct SpectrumWaveformView: View {
    let levels: [Float]
    let height: CGFloat
    var color: Color = .red

    var body: some View {
        Canvas { context, size in
            let barCount = 48
            let gap: CGFloat = 4
            let padding: CGFloat = 20
            let totalGapSpace = CGFloat(barCount - 1) * gap
            let barWidth = (size.width - padding * 2 - totalGapSpace) / CGFloat(barCount)

            let recentLevels: [Float]
            if levels.count >= barCount {
                recentLevels = Array(levels.suffix(barCount))
            } else {
                let pad = Array(repeating: Float(0), count: barCount - levels.count)
                recentLevels = pad + levels
            }

            for i in 0..<barCount {
                let level = CGFloat(recentLevels[i])
                // Non-linear height like React version
                let barHeight = pow(level, 1.2) * (size.height * 0.7)

                if barHeight < 1 { continue }

                let x = padding + CGFloat(i) * (barWidth + gap)
                let y = size.height / 2 - barHeight / 2

                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                let roundedRect = RoundedRectangle(cornerRadius: 2).path(in: rect)

                // Color gradient based on position
                let hue = 0.64 + (Double(i) / Double(barCount)) * 0.11
                context.fill(roundedRect, with: .color(Color(hue: hue, saturation: 0.8, brightness: 0.65).opacity(0.9)))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Particles Style (Our original flowing particles)

struct ParticlesWaveformView: View {
    let levels: [Float]
    let height: CGFloat
    var color: Color = .red

    private var currentLevel: Float {
        levels.last ?? 0
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.016)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let centerY = size.height / 2
                let level = CGFloat(currentLevel)

                // More particles - base of 40, up to 100 with loud audio
                let baseCount = 40
                let bonusCount = Int(level * 60)
                let particleCount = baseCount + bonusCount

                for i in 0..<particleCount {
                    let seed = Double(i) * 1.618033988749

                    // Particle position based on time and seed
                    let speed = 0.2 + (seed.truncatingRemainder(dividingBy: 1.0)) * 0.6
                    let xProgress = (time * speed + seed).truncatingRemainder(dividingBy: 1.0)
                    let x = CGFloat(xProgress) * size.width

                    // Y position: oscillates around center, amplitude based on level
                    let baseY = sin(time * 2 + seed * 10) * Double(level) * Double(centerY) * 0.8
                    let y = centerY + CGFloat(baseY)

                    // Size pulses with level
                    let baseSize: CGFloat = 2.5
                    let levelBonus = level * 5
                    let particleSize = baseSize + levelBonus * CGFloat(0.5 + sin(seed * 5) * 0.5)

                    // Opacity varies
                    let opacity = 0.5 + Double(level) * 0.4 * (0.5 + sin(seed * 3) * 0.5)

                    let rect = CGRect(
                        x: x - particleSize / 2,
                        y: y - particleSize / 2,
                        width: particleSize,
                        height: particleSize
                    )
                    context.fill(Circle().path(in: rect), with: .color(color.opacity(opacity)))
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - Unified LiveWaveformView

struct LiveWaveformView: View {
    let levels: [Float]
    let height: CGFloat
    var color: Color = .red
    var style: WaveformStyle = .spectrum

    var body: some View {
        switch style {
        case .wave:
            WaveWaveformView(levels: levels, height: height, color: color)
        case .spectrum:
            SpectrumWaveformView(levels: levels, height: height, color: color)
        case .particles:
            ParticlesWaveformView(levels: levels, height: height, color: color)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        WaveformView(
            levels: [0.3, 0.5, 0.7, 0.9, 0.6, 0.4, 0.8, 0.5, 0.3, 0.7],
            height: 40
        )

        WaveformView(
            levels: Array(repeating: 0.0, count: 100).map { _ in Float.random(in: 0...1) },
            height: 120,
            color: .blue
        )
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)

        LiveWaveformView(
            levels: Array(repeating: 0.0, count: 30).map { _ in Float.random(in: 0.1...1) },
            height: 200,
            color: .red
        )
        .background(Color.black)
        .cornerRadius(16)
    }
    .padding()
}
