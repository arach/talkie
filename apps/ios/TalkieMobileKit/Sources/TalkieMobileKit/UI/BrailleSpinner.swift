//
//  BrailleSpinner.swift
//  TalkieMobileKit
//
//  Animated braille-character spinner for loading states.
//

import SwiftUI

public struct BrailleSpinner: View {
    public var size: CGFloat
    public var speed: Double
    public var color: Color

    @State private var frame = 0

    // Braille spinner frames (classic dots pattern)
    private let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    public init(size: CGFloat = 14, speed: Double = 0.08, color: Color = .secondary) {
        self.size = size
        self.speed = speed
        self.color = color
    }

    public var body: some View {
        Text(frames[frame])
            .font(.system(size: size, weight: .medium, design: .monospaced))
            .foregroundColor(color)
            .onAppear { startAnimation() }
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: speed, repeats: true) { _ in
            frame = (frame + 1) % frames.count
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        BrailleSpinner()
        BrailleSpinner(size: 20, color: .blue)
        HStack(spacing: 8) {
            BrailleSpinner(size: 14, color: .gray)
            Text("Loading...")
                .font(.system(size: 14))
                .foregroundColor(.gray)
        }
    }
    .padding()
}
