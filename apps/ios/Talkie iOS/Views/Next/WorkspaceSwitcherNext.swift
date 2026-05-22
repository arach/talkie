//
//  WorkspaceSwitcherNext.swift
//  Talkie iOS
//
//  Multi-account workspace switcher. Lists every signed-in identity
//  (personal · work · …), shows which is active, and lets the user
//  switch the active workspace over. WorkspaceStore now seeds from the
//  native Apple Sign-In keychain payload, persists the active identity,
//  and keeps the view off screenshot-only mock data.
//

import Security
import SwiftUI
import TalkieMobileKit

struct WorkspaceIdentity: Identifiable, Equatable {
    enum Role: Equatable {
        case personal
        case work
        case other(label: String)

        var displayLabel: String {
            switch self {
            case .personal: return "Personal"
            case .work:     return "Work"
            case .other(let label): return label
            }
        }
    }

    let id: String
    let displayName: String
    let email: String?
    let role: Role
    let isActive: Bool
    let lastUsedLabel: String
    let captureCount: Int
}

struct WorkspaceSwitcherNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var workspaceStore = WorkspaceStore.shared

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().background(theme.currentTheme.chrome.edgeFaint)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        intro
                        identityList
                        addAccountTile
                        Spacer(minLength: 96)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("TALKIE · WORKSPACES")
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
            .accessibilityLabel("Close workspaces")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.2")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.colors.textTertiary)
                    .accessibilityHidden(true)
                Text("· IDENTITIES")
                    .talkieType(.channelLabel)
                    .foregroundStyle(theme.colors.textTertiary)
                Spacer()
                Text("\(workspaceStore.activeIdentityCount) ACTIVE")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
            }

            Text("Each workspace is fully isolated — its own iCloud zone, its own Mac bridge pairing, its own AI key catalog.")
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    private var identityList: some View {
        VStack(spacing: 0) {
            ForEach(workspaceStore.identities.enumerated(), id: \.element.id) { index, identity in
                IdentityRow(
                    identity: identity,
                    isSwitching: workspaceStore.switchingID == identity.id,
                    showsDivider: index < workspaceStore.identities.index(before: workspaceStore.identities.endIndex),
                    onActivate: { activate(identity) }
                )
            }
        }
        .background(theme.colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                              lineWidth: theme.currentTheme.chrome.hairlineWidth)
        )
    }

    private var addAccountTile: some View {
        Button(action: addAccount) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.currentTheme.chrome.accent.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add another workspace")
                        .talkieType(.fieldLabel)
                        .foregroundStyle(theme.colors.textPrimary)
                    Text("Sign in with a different Apple ID to add it as a separate identity.")
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(theme.colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.colors.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.colors.cardBackground.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                theme.currentTheme.chrome.edgeFaint,
                                style: StrokeStyle(
                                    lineWidth: theme.currentTheme.chrome.hairlineWidth,
                                    dash: [5, 3]
                                )
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add another workspace")
    }

    private func activate(_ identity: WorkspaceIdentity) {
        Task { @MainActor in
            await workspaceStore.activate(identity)
        }
    }

    private func addAccount() {
        AppShellRouter.shared.openSignIn()
    }
}

@MainActor
final class WorkspaceStore: ObservableObject {
    static let shared = WorkspaceStore()

    @Published private(set) var identities: [WorkspaceIdentity] = []
    @Published private(set) var switchingID: String?

    var activeIdentityCount: Int {
        identities.filter(\.isActive).count
    }

    private let defaults: UserDefaults
    private let activeIdentityKey = "workspace.activeIdentityID"
    private let lastUsedPrefix = "workspace.lastUsed."
    private let appleAuthService = "to.talkie.native-apple-auth"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reload()
    }

    func reload() {
        let captureCount = currentCaptureCount()
        let signedInIdentities = loadAppleIdentities(captureCount: captureCount)
        let baseIdentities = signedInIdentities.isEmpty
            ? [localIdentity(captureCount: captureCount)]
            : signedInIdentities

        let requestedActiveID = defaults.string(forKey: activeIdentityKey)
        let activeID = baseIdentities.contains { $0.id == requestedActiveID }
            ? requestedActiveID
            : baseIdentities.first?.id
        identities = baseIdentities.map { identity in
            WorkspaceIdentity(
                id: identity.id,
                displayName: identity.displayName,
                email: identity.email,
                role: identity.role,
                isActive: identity.id == activeID,
                lastUsedLabel: lastUsedLabel(for: identity.id, fallback: identity.lastUsedLabel),
                captureCount: identity.captureCount
            )
        }
    }

    func activate(_ identity: WorkspaceIdentity) async {
        guard !identity.isActive, switchingID == nil else { return }
        switchingID = identity.id
        try? await Task.sleep(for: .milliseconds(450))

        defaults.set(identity.id, forKey: activeIdentityKey)
        defaults.set(Date(), forKey: lastUsedPrefix + identity.id)
        AppLogger.app.info("[Workspace] Activated workspace identity \(identity.id)")
        reload()
        switchingID = nil
    }

    private func loadAppleIdentities(captureCount: Int) -> [WorkspaceIdentity] {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: appleAuthService,
            kSecReturnAttributes: true,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitAll
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let items = result as? [[String: Any]] else {
            return []
        }

        let decoder = JSONDecoder()
        return items.compactMap { item in
            guard let data = item[kSecValueData as String] as? Data,
                  let credential = try? decoder.decode(StoredAppleCredential.self, from: data) else {
                return nil
            }

            return WorkspaceIdentity(
                id: credential.userIdentifier,
                displayName: credential.displayName,
                email: credential.email,
                role: credential.role,
                isActive: false,
                lastUsedLabel: "Signed in \(credential.updatedAt.formatted(.relative(presentation: .named)))",
                captureCount: captureCount
            )
        }
    }

    private func localIdentity(captureCount: Int) -> WorkspaceIdentity {
        WorkspaceIdentity(
            id: "local",
            displayName: defaults.bool(forKey: SignInStore.signedInDefaultsKey) ? "Apple ID" : "Local Workspace",
            email: nil,
            role: .personal,
            isActive: true,
            lastUsedLabel: "Active now",
            captureCount: captureCount
        )
    }

    private func currentCaptureCount() -> Int {
        CaptureStore.shared.reload()
        return CaptureStore.shared.all().count
    }

    private func lastUsedLabel(for id: String, fallback: String) -> String {
        guard let lastUsed = defaults.object(forKey: lastUsedPrefix + id) as? Date else {
            return fallback
        }
        return lastUsed.formatted(.relative(presentation: .named))
    }

    private struct StoredAppleCredential: Codable {
        let userIdentifier: String
        let email: String?
        let givenName: String?
        let familyName: String?
        let updatedAt: Date

        var displayName: String {
            let parts = [givenName, familyName]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !parts.isEmpty { return parts.joined(separator: " ") }
            if let email, let name = email.split(separator: "@").first {
                return String(name)
            }
            return "Apple ID"
        }

        var role: WorkspaceIdentity.Role {
            guard let email else { return .personal }
            if email.localizedCaseInsensitiveContains("work")
                || email.localizedCaseInsensitiveContains("company") {
                return .work
            }
            return .personal
        }
    }
}

private struct IdentityRow: View {
    let identity: WorkspaceIdentity
    let isSwitching: Bool
    let showsDivider: Bool
    let onActivate: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Button(action: onActivate) {
            HStack(alignment: .center, spacing: 12) {
                avatar

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(identity.displayName)
                            .talkieType(.fieldLabel)
                            .foregroundStyle(theme.colors.textPrimary)
                            .lineLimit(1)
                        rolePill
                    }
                    if let email = identity.email {
                        Text(email)
                            .talkieType(.channelLabelTiny)
                            .foregroundStyle(theme.colors.textTertiary)
                            .lineLimit(1)
                    }
                    Text("· \(identity.captureCount) CAPTURES · \(identity.lastUsedLabel.uppercased())")
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(theme.colors.textTertiary)
                }

                Spacer(minLength: 8)

                trailing
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                identity.isActive
                    ? theme.currentTheme.chrome.accent.opacity(0.07)
                    : Color.clear
            )
            .overlay(alignment: .bottom) {
                if showsDivider {
                    Rectangle()
                        .fill(theme.currentTheme.chrome.edgeSubtle)
                        .frame(height: theme.currentTheme.chrome.hairlineWidth)
                        .padding(.leading, 62)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(identity.isActive)
    }

    private var avatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.currentTheme.chrome.accent.opacity(identity.isActive ? 0.22 : 0.10))
                .frame(width: 40, height: 40)
            Text(initials)
                .talkieType(.chipLabel)
                .foregroundStyle(theme.currentTheme.chrome.accent)
        }
    }

    private var initials: String {
        let parts = identity.displayName.split(whereSeparator: { $0.isWhitespace })
        let firstTwo = parts.prefix(2)
        return firstTwo.compactMap { $0.first }.map { String($0) }.joined().uppercased()
    }

    private var rolePill: some View {
        Text(identity.role.displayLabel.uppercased())
            .talkieType(.channelLabelTiny)
            .foregroundStyle(theme.currentTheme.chrome.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(
                Capsule()
                    .strokeBorder(theme.currentTheme.chrome.accent.opacity(0.5),
                                  lineWidth: theme.currentTheme.chrome.hairlineWidth)
            )
    }

    @ViewBuilder
    private var trailing: some View {
        if isSwitching {
            ProgressView()
                .scaleEffect(0.6)
                .tint(theme.currentTheme.chrome.accent)
        } else if identity.isActive {
            Text("ACTIVE")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(Color(red: 0.36, green: 0.74, blue: 0.50))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .overlay(
                    Capsule()
                        .strokeBorder(Color(red: 0.36, green: 0.74, blue: 0.50).opacity(0.55),
                                      lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
        } else {
            Text("SWITCH")
                .talkieType(.chipLabel)
                .foregroundStyle(theme.colors.cardBackground)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(theme.currentTheme.chrome.accent))
        }
    }
}
