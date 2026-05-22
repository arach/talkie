//
//  AICredentialsNext.swift
//  Talkie iOS
//
//  Manage API keys for cloud AI providers. List view with per-provider
//  status + tap-to-edit modal. Paint pass — Keychain storage is a
//  Codex contract via `AICredentialStore.set(key:for:)` /
//  `AICredentialStore.key(for:)` / `AICredentialStore.clear(_:)`. The
//  view is backed by AICredentialStore.
//
//  Donor cue: AIProviderCredentialReviewSheet (OCR-driven entry). This
//  surface replaces the broader manage-keys flow that lived inside the
//  legacy AIProviderManager screen.
//

import SwiftUI

/// Lightweight provider catalog used by the paint side. Codex can
/// replace with a live provider registry (TalkieAIProvider enum) once
/// the store + service wiring lands.
struct AIProviderEntry: Identifiable, Equatable {
    let id: String
    let displayName: String
    let blurb: String
    let placeholder: String

    static let catalog: [AIProviderEntry] = [
        AIProviderEntry(
            id: "openai",
            displayName: "OpenAI",
            blurb: "GPT-4, o-series, embeddings",
            placeholder: "sk-…"
        ),
        AIProviderEntry(
            id: "anthropic",
            displayName: "Anthropic",
            blurb: "Claude 4 (Opus, Sonnet, Haiku)",
            placeholder: "sk-ant-…"
        ),
        AIProviderEntry(
            id: "groq",
            displayName: "Groq",
            blurb: "Llama, Mixtral, Whisper",
            placeholder: "gsk_…"
        ),
        AIProviderEntry(
            id: "openrouter",
            displayName: "OpenRouter",
            blurb: "Multi-provider routing",
            placeholder: "sk-or-…"
        )
    ]
}

struct AICredentialsNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var credentials = AICredentialStore.shared
    @State private var editing: AIProviderEntry?

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().background(theme.currentTheme.chrome.edgeFaint)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Keys are stored locally in Keychain. Talkie never proxies through its own servers — requests go directly from this device to the provider.")
                            .talkieType(.preview)
                            .foregroundStyle(theme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20)
                            .padding(.top, 18)
                            .padding(.bottom, 14)

                        VStack(spacing: 0) {
                            ForEach(AIProviderEntry.catalog) { entry in
                                providerRow(entry)
                            }
                        }
                        .padding(.horizontal, 16)

                        Text("· REQUEST DELIVERY")
                            .talkieType(.channelLabelTiny)
                            .foregroundStyle(theme.colors.textTertiary)
                            .padding(.horizontal, 20)
                            .padding(.top, 28)
                            .padding(.bottom, 6)

                        deliveryRow(label: "Network egress", value: "Direct to provider")
                        deliveryRow(label: "Talkie proxy",   value: "Disabled")
                        deliveryRow(label: "Bridge fallback", value: "Off")

                        Spacer(minLength: 100)
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .sheet(item: $editing) { provider in
            CredentialEditor(
                provider: provider,
                initial: credentials.key(for: provider.id) ?? "",
                onSave: { value in
                    if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        try? credentials.clear(provider.id)
                    } else {
                        try? credentials.set(value, for: provider.id)
                    }
                    editing = nil
                },
                onClear: {
                    try? credentials.clear(provider.id)
                    editing = nil
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack {
            Text("TALKIE · AI KEYS")
                .talkieType(.wordmark)
                .foregroundStyle(theme.colors.textPrimary.opacity(0.78))

            Spacer()

            Button(action: { AppShellRouter.shared.openSettings() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(theme.currentTheme.chrome.edgeFaint.opacity(0.5))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close AI keys")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func providerRow(_ entry: AIProviderEntry) -> some View {
        Button(action: { editing = entry }) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .talkieType(.fieldLabel)
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(entry.blurb)
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(theme.colors.textTertiary)
                }
                Spacer(minLength: 8)
                statusPill(for: entry)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.colors.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 14)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(theme.currentTheme.chrome.edgeFaint)
                    .frame(height: theme.currentTheme.chrome.hairlineWidth)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func statusPill(for entry: AIProviderEntry) -> some View {
        let isSet = credentials.setProviderIDs.contains(entry.id)
        let label = isSet ? "SET" : "NOT SET"
        let color = isSet
            ? Color(red: 0.36, green: 0.74, blue: 0.50)
            : theme.colors.textTertiary
        Text(label)
            .talkieType(.channelLabelTiny)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(
                Capsule()
                    .strokeBorder(color.opacity(0.55),
                                  lineWidth: theme.currentTheme.chrome.hairlineWidth)
            )
    }

    private func deliveryRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .talkieType(.fieldLabel)
                .foregroundStyle(theme.colors.textPrimary)
            Spacer()
            Text(value)
                .talkieType(.fieldValue)
                .foregroundStyle(theme.currentTheme.chrome.accent)
        }
        .frame(height: 40)
        .padding(.horizontal, 20)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: theme.currentTheme.chrome.hairlineWidth)
        }
    }
}

private struct CredentialEditor: View {
    let provider: AIProviderEntry
    let initial: String
    let onSave: (String) -> Void
    let onClear: () -> Void

    @ObservedObject private var theme = ThemeManager.shared
    @State private var draft: String = ""
    @State private var isMasked: Bool = true
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                header
                fieldRow
                hintRow
                Spacer(minLength: 8)
                actionRow
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 28)
        }
        .onAppear {
            draft = initial
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                fieldFocused = true
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("· \(provider.displayName.uppercased()) KEY")
                .talkieType(.channelLabel)
                .foregroundStyle(theme.colors.textTertiary)
            Text(provider.blurb)
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textPrimary)
        }
    }

    private var fieldRow: some View {
        HStack(spacing: 10) {
            Group {
                if isMasked {
                    SecureField(provider.placeholder, text: $draft)
                        .focused($fieldFocused)
                } else {
                    TextField(provider.placeholder, text: $draft)
                        .focused($fieldFocused)
                }
            }
            .talkieType(.fieldValue)
            .foregroundStyle(theme.colors.textPrimary)
            .tint(theme.currentTheme.chrome.accent)
            .textContentType(.password)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

            Button(action: { isMasked.toggle() }) {
                Image(systemName: isMasked ? "eye" : "eye.slash")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            Button(action: { draft = UIPasteboard.general.string ?? draft }) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(theme.currentTheme.chrome.edgeFaint.opacity(0.35))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(theme.currentTheme.chrome.accent.opacity(0.4),
                              lineWidth: theme.currentTheme.chrome.hairlineWidth)
        )
    }

    private var hintRow: some View {
        Text("The key is stored locally in Keychain. No part of it is ever sent to Talkie servers.")
            .talkieType(.channelLabelTiny)
            .foregroundStyle(theme.colors.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            if !initial.isEmpty {
                Button(action: onClear) {
                    Text("CLEAR")
                        .talkieType(.chipLabel)
                        .foregroundStyle(Color(red: 0.85, green: 0.46, blue: 0.34))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .overlay(
                            Capsule()
                                .strokeBorder(Color(red: 0.85, green: 0.46, blue: 0.34).opacity(0.55),
                                              lineWidth: theme.currentTheme.chrome.hairlineWidth)
                        )
                }
                .buttonStyle(.plain)
            }

            Button(action: { onSave(draft) }) {
                Text("SAVE")
                    .talkieType(.chipLabel)
                    .foregroundStyle(theme.colors.cardBackground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Capsule().fill(theme.currentTheme.chrome.accent))
            }
            .buttonStyle(.plain)
        }
    }
}
