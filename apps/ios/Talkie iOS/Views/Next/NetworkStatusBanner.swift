//
//  NetworkStatusBanner.swift
//  Talkie iOS
//
//  Shared offline / network-error banner for surfaces that depend on
//  the internet (AskAI, ReadAloud cloud TTS, sync). Paint pass — the
//  banner is fully driven by the host surface's state. Codex wires a
//  shared NetworkReachability observer that surfaces can subscribe to
//  for the .offline branch.
//

import SwiftUI

enum NetworkStatus: Equatable {
    /// All good — banner hides.
    case ok
    /// Reachability lost. Show "You're offline" with no retry CTA.
    case offline
    /// A specific network request just failed. Show its message + RETRY.
    case requestFailed(message: String)
}

struct NetworkStatusBanner: View {
    let status: NetworkStatus
    var onRetry: (() -> Void)? = nil

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        if status == .ok {
            EmptyView()
        } else {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(accent)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(headline)
                        .talkieType(.fieldLabel)
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(detail)
                        .talkieType(.preview)
                        .foregroundStyle(theme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if case .requestFailed = status, let onRetry {
                    Button(action: onRetry) {
                        Text("RETRY")
                            .talkieType(.chipLabel)
                            .foregroundStyle(accent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .overlay(
                                Capsule()
                                    .strokeBorder(accent.opacity(0.55),
                                                  lineWidth: theme.currentTheme.chrome.hairlineWidth)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(accent.opacity(0.45),
                                          lineWidth: theme.currentTheme.chrome.hairlineWidth)
                    )
            )
        }
    }

    private var icon: String {
        switch status {
        case .ok: return "checkmark.circle"
        case .offline: return "wifi.slash"
        case .requestFailed: return "exclamationmark.triangle.fill"
        }
    }

    private var headline: String {
        switch status {
        case .ok: return ""
        case .offline: return "You're offline"
        case .requestFailed: return "Request failed"
        }
    }

    private var detail: String {
        switch status {
        case .ok: return ""
        case .offline:
            return "Talkie can't reach the network. Reconnect to send Ask AI prompts or sync captures."
        case .requestFailed(let message):
            return message
        }
    }

    private var accent: Color {
        switch status {
        case .offline:
            return Color(red: 0.85, green: 0.46, blue: 0.34)
        case .requestFailed:
            return Color(red: 0.85, green: 0.46, blue: 0.34)
        case .ok:
            return theme.currentTheme.chrome.accent
        }
    }
}
