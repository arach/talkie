//
//  TerminalNext.swift
//  Talkie iOS
//
//  STUB — Phase-1 placeholder. To be implemented by a dedicated
//  Codex stream:
//    - Top-level list surface for SSH terminal sessions.
//    - List of saved hosts from `SSHTerminalSavedHostStore`. Each
//      row shows hostname/alias, last-connected timestamp, status
//      dot. Source rail glyph (terminal icon).
//    - Tap row → presents `SSHTerminalView` for that host (modal or
//      pushed; same SSHTerminalView still alive in the project).
//    - Empty state: "No saved hosts" + "Add Host" action that opens
//      the QR-pair flow via `SSHPrivateKeyQRCodeImportView`.
//    - Entry points: `ConnectionCenterNext` Mac Bridge row action
//      ("Open Terminal"), BridgeDetailNext session row tap.
//    - Visual: SettingsNext-style sections + TalkieTypeStyle tokens.
//

import SwiftUI

struct TerminalNext: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()
            VStack(spacing: 12) {
                Text("TERMINAL")
                    .talkieType(.channelLabel)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                Text("Stub — implementation pending")
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
    }
}
