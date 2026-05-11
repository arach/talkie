//
//  AccountSettings.swift
//  Talkie macOS
//
//  User account and authentication settings
//
//  Philosophy: Show users which "mode" they're in based on their configuration.
//  The Data Sovereignty Spectrum:
//
//    ┌─────────────────────────────────────────────────────────────────────┐
//    │  PRIVATE       iCLOUD         TALKIE        HACKER*      BYOK*     │
//    │    ●━━━━━━━━━━━━━●━━━━━━━━━━━━━●             ●            ●         │
//    │  Local        Apple         Full          VPN/Local    Your S3    │
//    │  Only         Cloud         Cloud         Sync         Storage    │
//    └─────────────────────────────────────────────────────────────────────┘
//                                                              * Future
//
//  Each mode represents a different data sovereignty posture. Users can see
//  exactly where they sit and what trade-offs they're making.
//

import SwiftUI
import TalkieKit

private let log = Log(.ui)

// MARK: - Operating Mode

enum TalkieMode: String {
    case `private`  // No external sync, no account - single device
    case sync       // External sync service only, no Talkie account
    case talkie     // Talkie account
    // Future: case hacker - local sync via MacBridge/VPN

    var title: String {
        switch self {
        case .private: return "Private Mode"
        case .sync: return "Sync Mode"
        case .talkie: return "Talkie Mode"
        }
    }

    var icon: String {
        switch self {
        case .private: return "eye.slash.fill"
        case .sync: return "arrow.triangle.2.circlepath.circle.fill"
        case .talkie: return "person.crop.circle.badge.checkmark"
        }
    }

    var color: Color {
        switch self {
        case .private: return .gray
        case .sync: return .blue
        case .talkie: return Color.accentColor
        }
    }

    var description: String {
        switch self {
        case .private:
            return "Single device, completely private. Nothing leaves your Mac."
        case .sync:
            return "Your recordings sync across devices via TalkieSync."
        case .talkie:
            return "Full features unlocked. Cloud services and direct support from Talkie."
        }
    }
}
// MARK: - Mode List View

/// Shows all three modes as a list, with the current one highlighted
/// Style inspired by the philosophy/principles section on the website
///
/// Philosophy text is CONTEXTUAL based on where the user currently is:
/// - Looking "down" explains what you'd trade (lose sync, gain sovereignty)
/// - Looking "up" explains what you'd unlock (more features, convenience)
struct ModeListView: View {
    let currentMode: TalkieMode
    let isSignedIn: Bool
    let onSignIn: () -> Void
    @Binding var expandedMode: TalkieMode?

    private struct ModeInfo {
        let mode: TalkieMode
        let number: String
        let category: String
        let headline: String
        let description: String
    }

    private let allModes: [ModeInfo] = [
        ModeInfo(
            mode: .private,
            number: "001",
            category: "PRIVATE",
            headline: "YOUR DATA STAYS HERE.",
            description: "Single device. No sync. Maximum sovereignty."
        ),
        ModeInfo(
            mode: .sync,
            number: "002",
            category: "SYNC",
            headline: "TALKIESYNC HANDLES YOUR SYNC.",
            description: "Multi-device sync via external service."
        ),
        ModeInfo(
            mode: .talkie,
            number: "003",
            category: "CONNECTED",
            headline: "UNLOCK THE FULL EXPERIENCE.",
            description: "Cloud features, AI polish, direct support from Talkie."
        )
    ]

    /// Generates contextual philosophy text based on where the user is
    /// and which mode they're exploring
    private func philosophyText(for targetMode: TalkieMode) -> String {
        let modeOrder: [TalkieMode] = [.private, .sync, .talkie]
        let currentIndex = modeOrder.firstIndex(of: currentMode) ?? 0
        let targetIndex = modeOrder.firstIndex(of: targetMode) ?? 0

        // Viewing current mode - explain what it means
        if targetMode == currentMode {
            switch targetMode {
            case .private:
                return "You're in the most private configuration. Everything stays on this Mac with no external sync."
            case .sync:
                return "Your recordings sync across devices through TalkieSync. The desktop app stays focused on local usage."
            case .talkie:
                return "You have access to all Talkie features including cloud AI, priority support, and future capabilities. Your recordings still live where you choose."
            }
        }

        // Looking DOWN the ladder (toward more privacy)
        if targetIndex < currentIndex {
            switch targetMode {
            case .private:
                if currentMode == .sync {
                    return "Going private means your recordings stay only on this Mac. You'd lose cross-device sync, but keep everything local."
                } else { // from .talkie
                    return "Going private means your recordings stay only on this Mac. You'd lose cross-device sync and cloud features, but keep everything local."
                }
            case .sync:
                // From .talkie looking at .sync
                return "Disconnecting your Talkie account removes cloud AI features and priority support. TalkieSync can still handle cross-device sync."
            case .talkie:
                return "" // Can't look down at talkie
            }
        }

        // Looking UP the ladder (toward more features)
        switch targetMode {
        case .private:
            return "" // Can't look up at private
        case .sync:
            // From .private looking at .sync
            return "Enable TalkieSync to sync recordings between your Mac and iPhone."
        case .talkie:
            if currentMode == .private {
                return "Connect a Talkie account to unlock cloud features like AI polish and priority support. Sync can stay separate."
            } else { // from .sync
                return "Connect a Talkie account to unlock cloud features like AI polish, priority support, and future capabilities. Sync can continue independently."
            }
        }
    }

    /// Action text for modes you can switch to
    private func actionText(for targetMode: TalkieMode) -> String? {
        let modeOrder: [TalkieMode] = [.private, .sync, .talkie]
        let currentIndex = modeOrder.firstIndex(of: currentMode) ?? 0
        let targetIndex = modeOrder.firstIndex(of: targetMode) ?? 0

        if targetMode == currentMode { return nil }

        // Looking down - these would be downgrades
        if targetIndex < currentIndex {
            switch targetMode {
            case .private:
                return nil
            case .sync:
                return nil // Would need to sign out
            case .talkie:
                return nil
            }
        }

        // Looking up - these are upgrades
        switch targetMode {
        case .private:
            return nil
        case .sync:
            return nil
        case .talkie:
            return nil // Handled by showSignIn logic
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack {
                Text("> DATA SOVEREIGNTY")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(SemanticColor.success)

                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.sm)

            // Mode list
            ForEach(allModes, id: \.mode) { item in
                modeRow(item)

                if item.mode != .talkie {
                    Divider()
                        .padding(.leading, 136)
                }
            }
        }
        .background(Theme.current.backgroundSecondary.opacity(0.3))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .stroke(Theme.current.border.opacity(0.5), lineWidth: 1)
        }
        .cornerRadius(CornerRadius.sm)
    }

    private func modeRow(_ item: ModeInfo) -> some View {
        let isActive = item.mode == currentMode
        let isExpanded = expandedMode == item.mode
        let showSignIn = item.mode == .talkie && !isSignedIn

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedMode == item.mode {
                        expandedMode = nil
                    } else {
                        expandedMode = item.mode
                    }
                }
            } label: {
                HStack(alignment: .center, spacing: Spacing.lg) {
                    // Number and category
                    HStack(spacing: 0) {
                        Text(item.number)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(isActive ? item.mode.color : Theme.current.foregroundMuted.opacity(0.5))

                        Text(" / ")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.current.foregroundMuted.opacity(0.3))

                        Text(item.category)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(isActive ? item.mode.color : Theme.current.foregroundMuted.opacity(0.5))
                    }
                    .frame(width: 120, alignment: .leading)

                    // Headline and description
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.headline)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(isActive ? Theme.current.foreground : Theme.current.foregroundMuted.opacity(0.6))

                        Text(item.description)
                            .font(.system(size: 11))
                            .foregroundColor(isActive ? Theme.current.foregroundSecondary : Theme.current.foregroundMuted.opacity(0.4))
                    }

                    Spacer()

                    // Status or action
                    if isActive && !showSignIn {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(item.mode.color)
                                .frame(width: 6, height: 6)
                            Text("Active")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(item.mode.color)
                        }
                    } else if showSignIn {
                        Text("Sign In →")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Theme.current.accent)
                    }

                    // Expand indicator
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Theme.current.foregroundMuted.opacity(0.5))
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(alignment: .top, spacing: Spacing.lg) {
                        Color.clear
                            .frame(width: 120)

                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Text(philosophyText(for: item.mode))
                                .font(.system(size: 11))
                                .foregroundColor(Theme.current.foregroundMuted)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)

                            // Sign in button for Connected mode
                            if showSignIn {
                                ConnectAccountButton(action: onSignIn)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, Spacing.md)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(isActive ? Theme.current.backgroundTertiary.opacity(0.3) : Color.clear)
    }
}

// MARK: - User Architecture View

/// Shows the user's actual setup as an architecture diagram
/// Inspired by the Security Architecture visualization on the website
struct UserArchitectureView: View {
    let externalSyncAvailable: Bool
    let isSignedIn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header
            HStack(spacing: Spacing.sm) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 14))
                    .foregroundColor(SemanticColor.success)

                Text("YOUR SETUP")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(Theme.current.foreground)

                Spacer()

                // Legend
                HStack(spacing: Spacing.md) {
                    legendItem(color: .blue, label: "Active")
                    legendItem(color: Theme.current.foregroundMuted.opacity(0.3), label: "Available")
                }
            }

            // Architecture diagram
            HStack(alignment: .top, spacing: 0) {
                // User Owned Zone
                userOwnedZone
                    .frame(maxWidth: .infinity)

                // Barrier (if external services shown)
                if isSignedIn {
                    barrierView
                    externalServicesZone
                        .frame(width: 160)
                }
            }
            .padding(Spacing.md)
            .background(Theme.current.backgroundSecondary.opacity(0.5))
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .stroke(Theme.current.border, lineWidth: 1)
            }
            .cornerRadius(CornerRadius.sm)
        }
    }

    // MARK: - User Owned Zone

    private var userOwnedZone: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Zone header
            HStack(spacing: Spacing.xs) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.current.foregroundMuted)
                Text("USER OWNED ZONE")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            // External sync row
            architectureNode(
                icon: "arrow.triangle.2.circlepath.circle.fill",
                title: "TalkieSync",
                subtitle: "External Sync Service",
                isActive: externalSyncAvailable,
                badges: externalSyncAvailable ? ["SYNC READY"] : []
            )

            // Devices row
            HStack(spacing: Spacing.md) {
                // iPhone - active if sync is available
                deviceNode(
                    icon: "iphone",
                    title: "iPhone",
                    subtitle: "Input Context",
                    isActive: externalSyncAvailable
                )

                // Mac (always active - you're using it)
                deviceNode(
                    icon: "desktopcomputer",
                    title: "Mac",
                    subtitle: "Processing",
                    isActive: true
                )
            }
        }
    }

    private func architectureNode(icon: String, title: String, subtitle: String, isActive: Bool, badges: [String]) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(isActive ? .blue : Theme.current.foregroundMuted.opacity(0.3))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isActive ? Theme.current.foreground : Theme.current.foregroundMuted)
                Text(subtitle)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            Spacer()

            if !badges.isEmpty {
                HStack(spacing: Spacing.xs) {
                    ForEach(badges, id: \.self) { badge in
                        Text(badge)
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.current.foregroundMuted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Theme.current.backgroundTertiary)
                            .cornerRadius(2)
                    }
                }
            }
        }
        .padding(Spacing.sm)
        .background(isActive ? Theme.current.backgroundTertiary.opacity(0.5) : Color.clear)
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .stroke(isActive ? Theme.current.border : Theme.current.border.opacity(0.3), lineWidth: 1)
        }
        .cornerRadius(CornerRadius.xs)
    }

    private func deviceNode(icon: String, title: String, subtitle: String, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(isActive ? .blue : Theme.current.foregroundMuted.opacity(0.3))

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isActive ? Theme.current.foreground : Theme.current.foregroundMuted)
            }

            Text(subtitle)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(Theme.current.foregroundMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(isActive ? Theme.current.backgroundTertiary.opacity(0.5) : Color.clear)
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .stroke(isActive ? Theme.current.border : Theme.current.border.opacity(0.3), lineWidth: 1)
        }
        .cornerRadius(CornerRadius.xs)
    }

    // MARK: - Barrier

    private var barrierView: some View {
        VStack {
            Spacer()
            ZStack {
                Rectangle()
                    .fill(Theme.current.backgroundTertiary)
                    .frame(width: 2)

                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.current.foregroundMuted)
                    .padding(6)
                    .background(Theme.current.backgroundSecondary)
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .stroke(Theme.current.border, lineWidth: 1)
                    }
            }
            Spacer()
        }
        .frame(width: 32)
    }

    // MARK: - External Services

    private var externalServicesZone: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "globe")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
                Text("SERVICES")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.orange)
            }

            VStack(spacing: 4) {
                serviceBadge("OpenAI")
                serviceBadge("Anthropic")
                serviceBadge("Google")
            }

            Text("Text-only stream")
                .font(.system(size: 7, design: .monospaced))
                .foregroundColor(Theme.current.foregroundMuted)
        }
    }

    private func serviceBadge(_ name: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(Theme.current.foregroundMuted.opacity(0.3))
                .frame(width: 6, height: 6)
            Text(name)
                .font(.system(size: 9))
                .foregroundColor(Theme.current.foregroundMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.current.backgroundTertiary.opacity(0.5))
        .cornerRadius(4)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(Theme.current.foregroundMuted)
        }
    }
}

// MARK: - Account Settings View

struct AccountSettingsView: View {
    @State private var auth = AuthManager.shared
    @State private var externalSyncAvailable = false
    @State private var externalSyncStatus = "Checking..."
    @State private var expandedMode: TalkieMode? = nil

    private var currentMode: TalkieMode {
        if auth.isSignedIn {
            return .talkie
        } else if externalSyncAvailable {
            return .sync
        } else {
            return .private
        }
    }

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "person.circle",
                title: "ACCOUNT",
                subtitle: "How Talkie works for you."
            )
        } content: {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Mode list - shows all three modes with current highlighted
                ModeListView(
                    currentMode: currentMode,
                    isSignedIn: auth.isSignedIn,
                    onSignIn: {
                        Task {
                            do {
                                try await auth.signIn()
                            } catch AuthError.cancelled {
                                // User cancelled
                            } catch {
                                log.error("Sign in failed: \(error)")
                                auth.error = error.localizedDescription
                            }
                        }
                    },
                    expandedMode: $expandedMode
                )

                // Architecture visualization - shows their actual setup
                UserArchitectureView(
                    externalSyncAvailable: externalSyncAvailable,
                    isSignedIn: auth.isSignedIn
                )

                // Sign in progress (if loading)
                if auth.isLoading {
                    signInProgressSection
                }

                // Account details (if signed in)
                if currentMode == .talkie {
                    talkieModeDetails
                }
            }
        }
        .task {
            await checkExternalSyncStatus()
        }
    }

    // MARK: - Talkie Mode

    private var talkieModeDetails: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // User info
            if let user = auth.user {
                GlassCard {
                    HStack(spacing: Spacing.md) {
                        Circle()
                            .fill(Theme.current.accent.opacity(0.2))
                            .frame(width: 44, height: 44)
                            .overlay {
                                Text(avatarInitial)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(Theme.current.accent)
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.email ?? "Signed In")
                                .font(Theme.current.fontSMMedium)
                                .foregroundColor(Theme.current.foreground)

                            Text(user.plan.rawValue.capitalized)
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundMuted)
                        }

                        Spacer()

                        SignOutButton {
                            auth.signOut()
                        }
                    }
                    .padding(Spacing.md)
                }
            }

            // Features
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("YOUR FEATURES")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    if let user = auth.user {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            featureRow("Cloud Sync", enabled: user.hasCloudSync)
                            featureRow("AI Polish", enabled: user.features.contains(.aiPolish))
                            featureRow("Priority Support", enabled: user.features.contains(.prioritySupport))
                            featureRow("Beta Features", enabled: user.features.contains(.betaFeatures))
                        }

                        if user.plan == .free {
                            Divider()
                                .padding(.vertical, Spacing.xs)

                            UpgradeButton {
                                // TODO: Open upgrade flow
                            }
                        }
                    }
                }
                .padding(Spacing.md)
            }
        }
    }

    // MARK: - Sign In Progress

    private var signInProgressSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    BrailleSpinner()
                        .font(.system(size: 14))
                        .foregroundColor(Theme.current.accent)

                    Text("Signing in...")
                        .font(Theme.current.fontBodyMedium)
                        .foregroundColor(Theme.current.foreground)
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(auth.authSteps) { step in
                        authStepRow(step)
                    }
                }

                if let error = auth.error {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(SemanticColor.error)
                        Text(error)
                            .font(Theme.current.fontXS)
                            .foregroundColor(SemanticColor.error)
                    }
                    .padding(.top, Spacing.xs)
                }
            }
            .padding(Spacing.md)
        }
        .frame(maxWidth: 400)
    }

    private func authStepRow(_ step: AuthStep) -> some View {
        // Check if this is a browser/external action step
        let isBrowserStep = step.name.lowercased().contains("browser")

        return HStack(spacing: Spacing.sm) {
            Group {
                switch step.status {
                case .pending:
                    Image(systemName: "circle")
                        .foregroundColor(Theme.current.foregroundMuted)
                case .inProgress:
                    if isBrowserStep {
                        // External action - show arrow.up.forward instead of spinner
                        Image(systemName: "arrow.up.forward.circle.fill")
                            .foregroundColor(Theme.current.accent)
                    } else {
                        BrailleSpinner(speed: 0.06)
                            .font(.system(size: 10))
                            .foregroundColor(Theme.current.accent)
                    }
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(SemanticColor.success)
                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(SemanticColor.error)
                }
            }
            .font(.system(size: 12))
            .frame(width: 16)

            Text(step.name)
                .font(Theme.current.fontXS)
                .foregroundColor(step.status == .pending ? Theme.current.foregroundMuted : Theme.current.foregroundSecondary)

            Spacer()

            if let detail = step.detail {
                Text(detail)
                    .font(Theme.current.fontXS)
                    .foregroundColor(isBrowserStep && step.status == .inProgress ? Theme.current.accent : Theme.current.foregroundMuted)
            }
        }
    }

    // MARK: - Helper Views

    private func featureRow(_ name: String, enabled: Bool) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                .foregroundColor(enabled ? SemanticColor.success : Theme.current.foregroundMuted)
                .font(.system(size: 14))

            Text(name)
                .font(Theme.current.fontSM)
                .foregroundColor(enabled ? Theme.current.foreground : Theme.current.foregroundMuted)
        }
    }

    // MARK: - Sync Helpers

    private func checkExternalSyncStatus() async {
        let availability = await SyncClient.shared.checkiCloudAvailability()
        externalSyncAvailable = availability.available
        externalSyncStatus = availability.error ?? "Available"
        if !availability.available {
            log.warning("External sync unavailable: \(externalSyncStatus)")
        }
    }

    private var avatarInitial: String {
        guard let email = auth.user?.email, let first = email.first else { return "?" }
        return String(first).uppercased()
    }
}

// MARK: - Interactive Buttons with Hover States

/// Connect account button with clear hover feedback
private struct ConnectAccountButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "person.badge.plus")
                Text("Connect Talkie Account")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(isHovered ? Theme.current.accent.opacity(0.85) : Theme.current.accent)
            .cornerRadius(CornerRadius.xs)
            .shadow(color: isHovered ? Theme.current.accent.opacity(0.3) : .clear, radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

/// Sign out button with clear hover feedback
private struct SignOutButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text("Sign Out")
                .font(Theme.current.fontXS)
                .foregroundColor(isHovered ? Theme.current.foreground : Theme.current.foregroundMuted)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(isHovered ? Theme.current.backgroundTertiary.opacity(0.8) : Theme.current.backgroundTertiary.opacity(0.5))
                .cornerRadius(CornerRadius.xs)
                .overlay {
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .stroke(isHovered ? Theme.current.border : Color.clear, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

/// Upgrade button with clear hover feedback
private struct UpgradeButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "arrow.up.circle")
                Text("Upgrade to Pro")
            }
            .font(Theme.current.fontSMMedium)
            .foregroundColor(isHovered ? Theme.current.accent : Theme.current.accent.opacity(0.8))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(isHovered ? Theme.current.accent.opacity(0.15) : Color.clear)
            .cornerRadius(CornerRadius.xs)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AccountSettingsView()
        .frame(width: 600, height: 700)
        .environment(SettingsManager.shared)
}
