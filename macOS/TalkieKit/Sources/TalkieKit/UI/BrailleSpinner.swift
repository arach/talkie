//
//  BrailleSpinner.swift
//  TalkieKit
//
//  Minimal braille spinner for loading states
//

import SwiftUI

public struct BrailleSpinner: View {
    let speed: Double

    @State private var frame = 0

    // Classic braille spinner sequence
    private let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    public init(speed: Double = 0.08) {
        self.speed = speed
    }

    public var body: some View {
        Text(frames[frame])
            .monospacedDigit()
            .onAppear {
                startAnimation()
            }
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: speed, repeats: true) { _ in
            frame = (frame + 1) % frames.count
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack {
            BrailleSpinner()
            Text("Loading...")
        }

        HStack {
            BrailleSpinner(speed: 0.05)
            Text("Fast")
        }

        HStack {
            BrailleSpinner(speed: 0.12)
            Text("Slow")
        }
    }
    .padding()
}
