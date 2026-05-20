//
//  BridgeDetailNext.swift
//  Talkie iOS
//
//  STUB — Phase-1 placeholder. To be implemented by a dedicated
//  Codex stream:
//    - Replace the legacy `BridgeSettingsView` sheet (the last donor
//      surface alive in the new system, opened from
//      `ConnectionCenterNext`'s Mac Bridge row).
//    - Live status from `BridgeManager` (already published).
//    - Pairing flow: nearby Mac discovery via `NearbyMacBrowser`,
//      QR-pair flow via `SSHPrivateKeyQRCodePayload`.
//    - Session list (saved hosts) → row links into `TerminalNext`.
//    - Visual: SettingsNext-style sections (status header + action
//      rows), TalkieTypeStyle tokens.
//    - After this lands, `BridgeSettingsView`, `SessionListView`,
//      `SessionDetailView`, `DebugToolbar` (if no other callers)
//      can be retired — final donor cleanup.
//

import SwiftUI

struct BridgeDetailNext: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()
            VStack(spacing: 12) {
                Text("MAC BRIDGE")
                    .talkieType(.channelLabel)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                Text("Stub — implementation pending")
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
    }
}
