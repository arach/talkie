//
//  StatusBarButtons.swift
//  Talkie
//
//  Button components for the status bar
//  Extracted from StatusBar.swift for better organization
//

import SwiftUI
import TalkieKit

// MARK: - Console Button

struct ConsoleButton: View {
    let errorCount: Int
    let warningCount: Int
    let infoCount: Int
    @Binding var showPopover: Bool

    @State private var isHovered = false

    var body: some View {
        Button(action: { showPopover.toggle() }) {
            Image(systemName: "terminal")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isHovered ? TalkieTheme.textSecondary : TalkieTheme.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHovered ? TalkieTheme.hover : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            SystemLogsView()
                .frame(width: 600, height: 350)
        }
        .help("Logs - \(errorCount) errors, \(warningCount) warnings")
    }
}

// MARK: - Dev Badge Button

#if DEBUG
struct DevBadgeButton: View {
    @Binding var showConsole: Bool
    @State private var isHovered = false

    private var badgeText: String {
        isHovered ? "DEV" : "D"
    }

    var body: some View {
        Button(action: { showConsole.toggle() }) {
            Text(badgeText)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.orange.opacity(isHovered ? 1.0 : 0.7))
                .padding(.horizontal, isHovered ? 6 : 4)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(isHovered ? 0.25 : 0.15))
                .cornerRadius(3)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Debug build - Click to open logs")
    }
}
#endif
