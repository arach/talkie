//
//  OnboardingNext.swift
//  Talkie iOS
//
//  Faithful port of OnboardingView (apps/ios/Talkie iOS/Views/
//  OnboardingView.swift, 1401 lines). Donor structure:
//
//  - 4 paged TabView slides — Welcome / Capture / Sync / GetStarted
//  - SKIP top-right, page dots + back/forward chevron at bottom
//  - Each page: hero + title + body + feature hints / status panel
//  - GetStartedPage has a System Status checklist (App / Storage /
//    Encryption / iCloud), a TAP TO TRY record button, an optional
//    "Enable iCloud for sync" deep-link, and a "GET STARTED" CTA
//
//  Decorations intentionally deferred (call out in code, not faked):
//  - GridPatternView background + CornerBrackets decoration
//  - TalkieLogoRibbon on the Welcome page
//  - Animated phone illustration + REC pulse on Capture
//  - Interactive iPhone↔iCloud↔Mac architecture diagram on Sync
//  - ArchitectureWalkthrough modal sheet
//  - AnimatedStatusRow check animations on GetStarted
//
//  iCloud account status is via CKContainer.accountStatus (native
//  CloudKit, not Clerk). No auth-manager touch in this surface —
//  the rebuild is removing Clerk; see project memory.
//

import CloudKit
import SwiftUI

struct OnboardingNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @State private var currentPage: Int = 0
    @State private var iCloudStatus: CKAccountStatus = .couldNotDetermine

    private let totalPages = 4

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                skipBar

                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    capturePage.tag(1)
                    syncPage.tag(2)
                    getStartedPage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentPage)

                pageNav
            }
        }
        .onAppear { checkICloudStatus() }
    }

    // MARK: - Top SKIP bar

    private var skipBar: some View {
        HStack {
            Spacer()
            Button(action: complete) {
                Text("SKIP")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(theme.colors.textTertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Bottom nav (back chevron · dots · forward/checkmark)

    private var pageNav: some View {
        HStack(spacing: 18) {
            Button(action: { if currentPage > 0 { currentPage -= 1 } }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .opacity(currentPage > 0 ? 1 : 0)
            .disabled(currentPage == 0)

            Spacer()

            HStack(spacing: 7) {
                ForEach(0..<totalPages, id: \.self) { idx in
                    Circle()
                        .fill(idx == currentPage ? theme.currentTheme.chrome.accent : theme.currentTheme.chrome.edgeFaint)
                        .frame(width: idx == currentPage ? 8 : 6, height: idx == currentPage ? 8 : 6)
                        .animation(.spring(response: 0.3), value: currentPage)
                }
            }

            Spacer()

            Button(action: advanceOrComplete) {
                Image(systemName: currentPage < totalPages - 1 ? "chevron.right" : "checkmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.colors.cardBackground)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(theme.currentTheme.chrome.accent))
                    .shadow(color: theme.currentTheme.chrome.accentGlow,
                            radius: theme.currentTheme.chrome.glowRadius)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private func advanceOrComplete() {
        if currentPage < totalPages - 1 {
            currentPage += 1
        } else {
            complete()
        }
    }

    private func complete() {
        // Codex wires the @AppStorage hasSeenOnboarding flag (same
        // key as the donor) so re-launch doesn't re-show this.
        AppShellRouter.shared.openHome()
    }

    private func checkICloudStatus() {
        #if targetEnvironment(simulator)
        iCloudStatus = .couldNotDetermine
        #else
        // Codex wires the real CKContainer accountStatus call
        // against TalkieMobileRuntimeIdentifiers.cloudKitContainerIdentifier.
        iCloudStatus = .couldNotDetermine
        #endif
    }

    // MARK: - Welcome page

    private var welcomePage: some View {
        VStack(spacing: 16) {
            Spacer()

            // TODO: TalkieLogo asset + TalkieLogoRibbon (";) Talkie"
            // chip rotated 12°). Placeholder hero until brought across.
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(theme.colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .strokeBorder(theme.currentTheme.chrome.edgeFaint, lineWidth: 1)
                    )
                    .frame(width: 140, height: 140)
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(theme.currentTheme.chrome.accent)
            }

            HStack(spacing: 8) {
                Text("VOICE")
                    .font(.system(size: 36, weight: .black))
                    .foregroundStyle(theme.colors.textPrimary)
                Text("+ AI")
                    .font(.system(size: 36, weight: .black))
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .shadow(color: theme.currentTheme.chrome.accentGlow,
                            radius: theme.currentTheme.chrome.glowRadius)
            }
            .padding(.top, 6)

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    taglineWord("Record")
                    taglineSep
                    taglineWord("Dictate")
                    taglineSep
                    taglineWord("Transcribe")
                }

                HStack(spacing: 5) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                    Text("On-device. Private. Yours.")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(theme.colors.textTertiary)
            }
            .padding(.top, 12)

            Spacer()

            VStack(spacing: 4) {
                Text("usetalkie.com")
                    .font(.system(size: 10, design: .monospaced))
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .opacity(0.7)
            }
            .foregroundStyle(theme.colors.textTertiary)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
    }

    private func taglineWord(_ word: String) -> some View {
        Text(word)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .tracking(1.6)
            .foregroundStyle(theme.colors.textSecondary)
    }
    private var taglineSep: some View {
        Text("·")
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(theme.colors.textTertiary)
    }

    // MARK: - Capture page

    private var capturePage: some View {
        VStack(spacing: 22) {
            Spacer()

            // TODO: Donor has an embedded phone illustration with a
            // REC pulse animation. Simplified hero here.
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(theme.colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(theme.currentTheme.chrome.edgeFaint, lineWidth: 1)
                    )
                    .frame(width: 200, height: 160)
                VStack(spacing: 12) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                        .shadow(color: theme.currentTheme.chrome.accentGlow,
                                radius: theme.currentTheme.chrome.glowRadius)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(theme.currentTheme.chrome.accent)
                            .frame(width: 6, height: 6)
                        Text("REC")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(theme.currentTheme.chrome.accent)
                    }
                }
            }

            VStack(spacing: 8) {
                Text("Capture Your Voice")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(theme.colors.textPrimary)
                Text("Record memos, dictate into any app,\nor let the keyboard type as you speak.\nAll on-device. Always ready.")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            VStack(alignment: .leading, spacing: 10) {
                featureHint(icon: "mic.fill",   text: "Voice memos with instant transcription")
                featureHint(icon: "keyboard",   text: "Talkie keyboard — dictate anywhere you type")
                featureHint(icon: "waveform",   text: "On-device speech recognition, no servers")
            }
            .padding(.top, 4)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    // MARK: - Sync page

    private var syncPage: some View {
        VStack(spacing: 22) {
            Spacer()

            // TODO: Donor has an interactive iPhone↔iCloud↔Mac
            // diagram with animated arrows, tappable nodes, and
            // tooltip cards. Static node row here.
            HStack(spacing: 0) {
                syncNode(icon: "iphone",       label: "iPhone")
                syncArrow
                syncNode(icon: "icloud.fill",  label: "iCloud")
                syncArrow
                syncNode(icon: "macbook",      label: "Mac")
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 14)
            .overlay(alignment: .top) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.system(size: 8))
                    Text("USER OWNED DATA")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(2)
                }
                .foregroundStyle(theme.currentTheme.chrome.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(theme.colors.background)
                        .overlay(Capsule().strokeBorder(
                            theme.currentTheme.chrome.accent.opacity(0.5),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                        ))
                )
                .offset(y: -10)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                theme.currentTheme.chrome.accent.opacity(0.5),
                                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                            )
                    )
            )

            VStack(spacing: 8) {
                Text("The Magic of Sync")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(theme.colors.textPrimary)
                Text("Record anywhere on your iPhone.\nSync locally, via iCloud, or direct to Mac.\nMac processes with on-device AI.\nAll encrypted, all yours.")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            // Donor's "Works perfectly fine locally without iCloud" disclaimer
            HStack(spacing: 5) {
                Image(systemName: "info.circle").font(.system(size: 10))
                Text("Works perfectly fine locally without iCloud")
                    .font(.system(size: 10, design: .monospaced))
            }
            .foregroundStyle(theme.colors.textTertiary)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private func syncNode(icon: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(theme.colors.textPrimary)
                .frame(width: 48, height: 48)
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(theme.colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
    private var syncArrow: some View {
        Image(systemName: "arrow.left.and.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.currentTheme.chrome.accent.opacity(0.6))
    }

    // MARK: - GetStarted page

    private var getStartedPage: some View {
        VStack(spacing: 18) {
            Spacer()

            Text("· SYSTEM STATUS")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(2.4)
                .foregroundStyle(theme.colors.textTertiary)

            // System status panel — donor uses AnimatedStatusRow with
            // staggered check animations. Static rows here.
            VStack(spacing: 10) {
                statusRow(label: "App",         value: "Ready",       active: true)
                statusRow(label: "Storage",     value: "Local",       active: true)
                statusRow(label: "Encryption",  value: "On-Device",   active: true)
                statusRow(label: "iCloud",
                          value: iCloudStatus == .available ? "Connected" : "Offline",
                          active: iCloudStatus == .available,
                          highlight: true)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(theme.currentTheme.chrome.edgeFaint, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 4)

            // TAP TO TRY record affordance
            Button(action: complete) {
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(theme.currentTheme.chrome.accent)
                            .frame(width: 52, height: 52)
                            .shadow(color: theme.currentTheme.chrome.accentGlow,
                                    radius: theme.currentTheme.chrome.glowRadius)
                        Image(systemName: "mic.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(theme.colors.cardBackground)
                    }
                    Text("TAP TO TRY")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(theme.colors.textTertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            Spacer()

            if iCloudStatus != .available {
                Button(action: openICloudSettings) {
                    HStack(spacing: 4) {
                        Image(systemName: "icloud.slash").font(.system(size: 10))
                        Text("Enable iCloud for sync")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                        Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(theme.colors.textTertiary)
                }
                .buttonStyle(.plain)
            }

            Button(action: complete) {
                HStack(spacing: 8) {
                    Text("GET STARTED")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(2)
                    Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(theme.colors.cardBackground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 8).fill(theme.currentTheme.chrome.accent))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 12)
    }

    private func statusRow(label: String, value: String, active: Bool, highlight: Bool = false) -> some View {
        HStack {
            Image(systemName: active ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13))
                .foregroundStyle(active ? theme.currentTheme.chrome.accent : theme.colors.textTertiary)

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.colors.textPrimary)

            Spacer()

            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(highlight && active
                    ? theme.currentTheme.chrome.accent
                    : theme.colors.textSecondary)
        }
    }

    private func openICloudSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func featureHint(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(theme.currentTheme.chrome.accent)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.colors.textSecondary)
        }
    }
}
