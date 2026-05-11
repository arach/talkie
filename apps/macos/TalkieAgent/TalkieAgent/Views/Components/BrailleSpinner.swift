//
//  BrailleSpinner.swift
//  TalkieAgent
//
//  Minimal braille spinner for loading states
//

import SwiftUI

struct BrailleSpinner: View {
    let size: CGFloat
    let speed: Double

    // Classic braille spinner sequence
    private static let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    init(size: CGFloat = 14, speed: Double = 0.08) {
        self.size = size
        self.speed = speed
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: speed)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let frame = Int(elapsed / speed) % Self.frames.count
            Text(Self.frames[frame])
                .font(.system(size: size, weight: .medium, design: .monospaced))
                .accessibilityLabel("Loading")
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
