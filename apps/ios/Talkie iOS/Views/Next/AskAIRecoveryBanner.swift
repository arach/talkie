import SwiftUI

struct AskAIRecoveryBanner: View {
    let headline: String
    let detail: String
    let onOpenAIKeys: () -> Void
    let onPairMac: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "key.horizontal.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.currentTheme.chrome.accent)
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
            }

            HStack(spacing: 8) {
                Button("AI KEYS", action: onOpenAIKeys)
                    .talkieType(.chipLabel)
                    .foregroundStyle(theme.colors.cardBackground)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(theme.currentTheme.chrome.accent))
                    .accessibilityIdentifier("askai.open-ai-keys")

                Button("PAIR MAC", action: onPairMac)
                    .talkieType(.chipLabel)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .overlay {
                        Capsule().strokeBorder(
                            theme.currentTheme.chrome.accent.opacity(0.55),
                            lineWidth: theme.currentTheme.chrome.hairlineWidth
                        )
                    }
                    .accessibilityIdentifier("askai.pair-mac")
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.colors.cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            theme.currentTheme.chrome.accent.opacity(0.4),
                            lineWidth: theme.currentTheme.chrome.hairlineWidth
                        )
                }
        }
    }
}
