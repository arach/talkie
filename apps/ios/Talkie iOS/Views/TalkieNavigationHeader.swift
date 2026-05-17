//
//  TalkieNavigationHeader.swift
//  Talkie iOS
//
//  Reusable navigation header for user-facing screens.
//  Theme-aware: TALKIE wordmark in primary ink, subtitle in theme accent.
//

import SwiftUI

struct TalkieNavigationHeader: View {
    let subtitle: String

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 1) {
            Text("TALKIE")
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .tracking(2)
                .foregroundColor(theme.colors.textPrimary)

            // Subtitle reads as quiet metadata, centered. No leading dot
            // (it visually offsets the center), no accent color, no glow —
            // the header should be a calm anchor, not a lit indicator.
            Text(subtitle.uppercased())
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(2)
                .foregroundColor(theme.colors.textTertiary)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        TalkieNavigationHeader(subtitle: "Memos")
        TalkieNavigationHeader(subtitle: "Claude")
    }
}
