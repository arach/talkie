//
//  SyncConflictNext.swift
//  Talkie iOS
//
//  iCloud sync conflict resolution surface. Surfaces when CloudKit
//  reports a divergence between local and remote versions of the
//  same capture/memo and the user needs to pick which side wins.
//  Paint pass — Codex wires SyncConflictStore.pending: [Conflict]
//  from CKModifyRecordsOperation errors, plus the resolve(_:)
//  callbacks that fold the choice back into the store.
//

import SwiftUI

/// Conflicting representations of a single record. Paint side mocks
/// these; Codex feeds real CloudKit conflict records into the store
/// once the operation-level conflict path is wired.
struct SyncConflict: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case capture
        case memo
    }

    enum Resolution: Equatable {
        case keepLocal
        case keepRemote
        case keepBoth
    }

    let id: String
    let kind: Kind
    let titleLocal: String
    let titleRemote: String
    let previewLocal: String
    let previewRemote: String
    let editedLocalLabel: String
    let editedRemoteLabel: String
    let deviceLocalLabel: String
    let deviceRemoteLabel: String
}

struct SyncConflictNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @State private var pending: [SyncConflict] = SyncConflictNext.mockPending
    @State private var resolvingID: String?

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().background(theme.currentTheme.chrome.edgeFaint)

                if pending.isEmpty {
                    resolvedState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            countBanner
                            ForEach(pending) { conflict in
                                ConflictCard(
                                    conflict: conflict,
                                    isResolving: resolvingID == conflict.id,
                                    onResolve: { choice in resolve(conflict, choice: choice) }
                                )
                            }
                            Spacer(minLength: 96)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("TALKIE · SYNC CONFLICTS")
                .talkieType(.wordmark)
                .foregroundStyle(theme.colors.textPrimary.opacity(0.78))

            Spacer()

            Button(action: { AppShellRouter.shared.openConnectionCenter() }) {
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
            .accessibilityLabel("Close sync conflicts")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var countBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "icloud.and.arrow.up")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.currentTheme.chrome.accent)
                .accessibilityHidden(true)
            Text("· \(pending.count) CONFLICT\(pending.count == 1 ? "" : "S")")
                .talkieType(.channelLabel)
                .foregroundStyle(theme.colors.textTertiary)
            Spacer()
            Text("iCloud · choose a version below")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.colors.textTertiary)
        }
    }

    private var resolvedState: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 60)

            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.36, green: 0.74, blue: 0.50).opacity(0.12))
                    .frame(width: 68, height: 68)
                Image(systemName: "checkmark")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Color(red: 0.36, green: 0.74, blue: 0.50))
            }

            Text("All synced")
                .talkieType(.headlineSecondary)
                .foregroundStyle(theme.colors.textPrimary)

            Text("No conflicts to resolve. Local and iCloud are in agreement.")
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resolve(_ conflict: SyncConflict, choice: SyncConflict.Resolution) {
        guard resolvingID == nil else { return }
        resolvingID = conflict.id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            pending.removeAll { $0.id == conflict.id }
            resolvingID = nil
        }
    }

    static let mockPending: [SyncConflict] = [
        SyncConflict(
            id: "c1",
            kind: .memo,
            titleLocal: "Migration timeline — updated",
            titleRemote: "Migration timeline",
            previewLocal: "alex pushed back on q2; we're slipping to q3 with a friday spec deadline. analytics rewrite blocked downstream.",
            previewRemote: "alex pushed back on q2. team aligned on q3 timeline.",
            editedLocalLabel: "Today · 11:42 AM",
            editedRemoteLabel: "Yesterday · 6:18 PM",
            deviceLocalLabel: "iPhone",
            deviceRemoteLabel: "iCloud (Mac mini)"
        ),
        SyncConflict(
            id: "c2",
            kind: .capture,
            titleLocal: "Hyper Scan · resilience playbook",
            titleRemote: "Hyper Scan · resilience playbook",
            previewLocal: "Edited transcription with corrections to provider name & two timestamps.",
            previewRemote: "Original OCR text with a few wobbly chunks at the bottom.",
            editedLocalLabel: "Today · 9:08 AM",
            editedRemoteLabel: "Today · 9:06 AM",
            deviceLocalLabel: "iPhone",
            deviceRemoteLabel: "iCloud (Mac mini)"
        )
    ]
}

private struct ConflictCard: View {
    let conflict: SyncConflict
    let isResolving: Bool
    let onResolve: (SyncConflict.Resolution) -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Text("· \(conflict.kind.rawValue.uppercased())")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
                Spacer()
                if isResolving {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(theme.currentTheme.chrome.accent)
                }
            }

            VStack(spacing: 10) {
                versionPanel(
                    label: "LOCAL",
                    title: conflict.titleLocal,
                    preview: conflict.previewLocal,
                    editedLabel: conflict.editedLocalLabel,
                    deviceLabel: conflict.deviceLocalLabel,
                    isOlder: false
                )
                versionPanel(
                    label: "iCLOUD",
                    title: conflict.titleRemote,
                    preview: conflict.previewRemote,
                    editedLabel: conflict.editedRemoteLabel,
                    deviceLabel: conflict.deviceRemoteLabel,
                    isOlder: true
                )
            }

            actionRow
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                      lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
        )
    }

    private func versionPanel(
        label: String,
        title: String,
        preview: String,
        editedLabel: String,
        deviceLabel: String,
        isOlder: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(label)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                Text("· \(deviceLabel)")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
                Spacer()
                Text(editedLabel)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
            }

            Text(title)
                .talkieType(.fieldLabel)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(2)

            Text(preview)
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(isOlder ? 0.78 : 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.currentTheme.chrome.edgeFaint.opacity(0.3))
        )
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            choiceChip(title: "Keep local", primary: true) { onResolve(.keepLocal) }
            choiceChip(title: "Keep iCloud", primary: false) { onResolve(.keepRemote) }
            choiceChip(title: "Keep both", primary: false) { onResolve(.keepBoth) }
        }
        .disabled(isResolving)
        .opacity(isResolving ? 0.55 : 1)
    }

    private func choiceChip(title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .talkieType(.fieldLabel)
                .foregroundStyle(primary ? theme.colors.cardBackground : theme.colors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(primary ? theme.currentTheme.chrome.accent : Color.clear)
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    primary ? Color.clear : theme.currentTheme.chrome.edgeFaint,
                                    lineWidth: theme.currentTheme.chrome.hairlineWidth
                                )
                        )
                )
        }
        .buttonStyle(.plain)
    }
}
