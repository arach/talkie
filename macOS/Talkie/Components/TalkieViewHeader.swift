//
//  TalkieViewHeader.swift
//  Talkie
//
//  Reusable header component for main views (Memos, Claude, etc.)
//  Provides consistent wordmark, subtitle, and debug button positioning
//

import SwiftUI
import TalkieKit

#if DEBUG
import DebugKit
#endif

/// Reusable header for main content views (Memos, Claude, Live, etc.)
struct TalkieViewHeader<DebugContent: View>: View {
    let subtitle: String
    let debugInfo: () -> [String: String]
    let debugContent: DebugContent

    #if DEBUG
    init(
        subtitle: String,
        debugInfo: @escaping () -> [String: String] = { [:] },
        @ViewBuilder debugContent: () -> DebugContent = { EmptyView() }
    ) where DebugContent == EmptyView {
        self.subtitle = subtitle
        self.debugInfo = debugInfo
        self.debugContent = EmptyView()
    }

    init(
        subtitle: String,
        debugInfo: @escaping () -> [String: String] = { [:] },
        @ViewBuilder debugContent: () -> DebugContent
    ) {
        self.subtitle = subtitle
        self.debugInfo = debugInfo
        self.debugContent = debugContent()
    }
    #else
    init(subtitle: String) {
        self.subtitle = subtitle
        self.debugInfo = { [:] }
        self.debugContent = EmptyView() as! DebugContent
    }
    #endif

    var body: some View {
        ZStack {
            // Main header content - centered wordmark
            VStack(spacing: 2) {
                Text("TALKIE")
                    .font(.system(size: 18, weight: .black, design: .default))
                    .tracking(-0.5)
                    .foregroundColor(Theme.current.foreground)

                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(0.8)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Theme.current.background)
            .overlay(
                Rectangle()
                    .fill(Theme.current.foregroundSecondary.opacity(0.1))
                    .frame(height: 1),
                alignment: .bottom
            )

            // Debug button overlay (right side)
            #if DEBUG
            HStack {
                Spacer()
                TalkieDebugToolbar {
                    debugContent
                } debugInfo: {
                    var info = debugInfo()
                    info["View"] = subtitle
                    return info
                }
                .offset(x: -8, y: 0)
            }
            #endif
        }
    }
}

// Convenience init for headers without custom debug content
#if DEBUG
extension TalkieViewHeader where DebugContent == EmptyView {
    init(
        subtitle: String,
        debugInfo: @escaping () -> [String: String] = { [:] }
    ) {
        self.subtitle = subtitle
        self.debugInfo = debugInfo
        self.debugContent = EmptyView()
    }
}
#endif

#Preview {
    VStack(spacing: 20) {
        TalkieViewHeader(
            subtitle: "with Claude",
            debugInfo: {
                ["Sessions": "5", "Messages": "42"]
            }
        )

        TalkieViewHeader(subtitle: "Memos")
    }
    .frame(width: 800)
}
