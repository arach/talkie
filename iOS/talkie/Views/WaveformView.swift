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
    }
    .padding()
}
