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

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<min(levels.count, Int(geometry.size.width / 3)), id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: 2, height: max(2, CGFloat(levels[index]) * height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: height)
        }
        .frame(height: height)
    }
}

#Preview {
    WaveformView(
        levels: [0.3, 0.5, 0.7, 0.9, 0.6, 0.4, 0.8, 0.5, 0.3, 0.7],
        height: 40
    )
    .padding()
}
