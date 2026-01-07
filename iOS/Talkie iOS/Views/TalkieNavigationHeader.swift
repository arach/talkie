//
//  TalkieNavigationHeader.swift
//  Talkie iOS
//
//  Reusable navigation header for user-facing screens (Memos, Claude, etc.)
//

import SwiftUI

/// Reusable navigation header component
/// Displays "TALKIE" with a subtitle (e.g., "Memos" or "Claude")
struct TalkieNavigationHeader: View {
    let subtitle: String
    var showConnectionIndicator: Bool = false
    var isConnected: Bool = false

    var body: some View {
        VStack(spacing: 1) {
            Text("TALKIE")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)

            HStack(spacing: 4) {
                Text(subtitle)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundColor(.secondary)
                    .tracking(0.5)

                // Optional connection indicator (for screens that sync with Mac)
                if showConnectionIndicator && isConnected {
                    Circle()
                        .fill(Color.success)
                        .frame(width: 5, height: 5)
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        TalkieNavigationHeader(subtitle: "Memos")
        TalkieNavigationHeader(subtitle: "Claude")
        TalkieNavigationHeader(subtitle: "Memos", showConnectionIndicator: true, isConnected: true)
    }
}
