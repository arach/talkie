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

// MARK: - Live Waveform View (for recording)
// Shows a fixed-width oscillating waveform that doesn't accumulate

struct LiveWaveformView: View {
    let levels: [Float]
    let height: CGFloat
    var color: Color = .red
    var barCount: Int = 70

    var body: some View {
        GeometryReader { geometry in
            let barWidth: CGFloat = 2.5
            let spacing: CGFloat = 1.5
            let totalBarWidth = barWidth + spacing
            let availableBars = min(barCount, Int(geometry.size.width / totalBarWidth))

            // Take only the most recent levels to fill the view
            let displayLevels = getRecentLevels(count: availableBars)

            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<availableBars, id: \.self) { index in
                    let level = index < displayLevels.count ? displayLevels[index] : 0.02

                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(color)
                        .frame(
                            width: barWidth,
                            height: max(3, CGFloat(level) * height * 0.95)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: height, alignment: .center)
            .animation(.easeOut(duration: 0.08), value: levels.count)
        }
        .frame(height: height)
    }

    private func getRecentLevels(count: Int) -> [Float] {
        guard !levels.isEmpty else {
            return Array(repeating: 0.02, count: count)
        }

        // Take the most recent 'count' levels
        let startIndex = max(0, levels.count - count)
        let recentLevels = Array(levels.suffix(from: startIndex))

        // Pad with low values if we don't have enough
        if recentLevels.count < count {
            let padding = Array(repeating: Float(0.02), count: count - recentLevels.count)
            return padding + recentLevels
        }

        return Array(recentLevels)
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
            height: 120,
            color: .red
        )
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    .padding()
}
