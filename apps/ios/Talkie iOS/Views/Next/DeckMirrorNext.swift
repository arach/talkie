//
//  DeckMirrorNext.swift
//  Talkie iOS
//
//  iOS-side mirror of the macOS Command Deck. Renders the same 4×4
//  shortcut grid the user has on the Mac, with Space tabs along the
//  top. Single-tap a tile to fire the slot on the Mac via the bridge.
//
//  Paint pass — view reads `DeckMirrorStore.shared`. Codex wires the
//  store from the bridge event stream + the send-slot endpoint.
//

import SwiftUI

struct DeckMirrorNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var deck = DeckMirrorStore.shared
    @State private var bridgeManager = BridgeManager.shared
    @State private var selectedSpaceID: String?

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().background(theme.currentTheme.chrome.edgeFaint)

                if let board = deck.board, !board.spaces.isEmpty {
                    boardContent(board)
                } else {
                    emptyState
                }
            }
        }
        .onAppear {
            if selectedSpaceID == nil {
                selectedSpaceID = deck.board?.activeSpaceID ?? deck.board?.spaces.first?.id
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("TALKIE · DECK")
                .talkieType(.wordmark)
                .foregroundStyle(theme.colors.textPrimary.opacity(0.78))

            if let macName = bridgeManager.pairedMacDisplayName {
                Text("· \(macName)")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(action: { AppShellRouter.shared.openHome() }) {
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
            .accessibilityLabel("Close deck")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Board

    @ViewBuilder
    private func boardContent(_ board: DeckBoardSnapshot) -> some View {
        VStack(spacing: 0) {
            spaceTabs(board.spaces, mirroredActiveID: board.activeSpaceID)

            if let space = currentSpace(in: board) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let error = deck.lastErrorMessage {
                            errorBanner(error)
                                .padding(.horizontal, 16)
                        }

                        tileGrid(space.tiles)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        Spacer(minLength: 96)
                    }
                }
                .scrollIndicators(.hidden)
            } else {
                Spacer()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 60)

            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(theme.currentTheme.chrome.accent.opacity(0.10))
                    .frame(width: 68, height: 68)
                Image(systemName: "square.grid.3x3")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(theme.currentTheme.chrome.accent)
            }

            Text("Deck not available")
                .talkieType(.headlineSecondary)
                .foregroundStyle(theme.colors.textPrimary)

            Text(emptyStateMessage)
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateMessage: String {
        if !bridgeManager.isPaired {
            return "Pair a Mac to mirror its Command Deck here."
        }
        if bridgeManager.status != .connected {
            return "Waiting for the Mac to come online so it can ship the deck state across."
        }
        return "The Mac hasn't sent a deck snapshot yet. Open the deck on the Mac side to populate this surface."
    }

    // MARK: - Space tabs

    private func spaceTabs(_ spaces: [DeckSpace], mirroredActiveID: String?) -> some View {
        HStack(spacing: 0) {
            ForEach(spaces) { space in
                let isSelected = space.id == (selectedSpaceID ?? mirroredActiveID)
                let isMacActive = space.id == mirroredActiveID
                Button(action: { selectedSpaceID = space.id }) {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Text(space.title.uppercased())
                                .talkieType(.channelLabel)
                                .foregroundStyle(isSelected ? theme.colors.textPrimary : theme.colors.textTertiary)
                            if isMacActive {
                                Circle()
                                    .fill(Color(red: 0.36, green: 0.74, blue: 0.50))
                                    .frame(width: 5, height: 5)
                                    .accessibilityLabel("Active on Mac")
                            }
                        }
                        Rectangle()
                            .fill(isSelected ? theme.currentTheme.chrome.accent : Color.clear)
                            .frame(height: 1.5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: theme.currentTheme.chrome.hairlineWidth)
        }
    }

    private func currentSpace(in board: DeckBoardSnapshot) -> DeckSpace? {
        let target = selectedSpaceID ?? board.activeSpaceID
        return board.spaces.first { $0.id == target } ?? board.spaces.first
    }

    // MARK: - Tile grid

    private func tileGrid(_ tiles: [DeckTile]) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
            spacing: 10
        ) {
            ForEach(tiles) { tile in
                tileView(tile)
            }
        }
    }

    private func tileView(_ tile: DeckTile) -> some View {
        let isFiring = deck.firingSlotID == tile.slotID
        let isEmpty = tile.slotID == nil
        return Button(action: {
            guard let slot = tile.slotID else { return }
            deck.fire(slotID: slot)
        }) {
            VStack(spacing: 6) {
                Image(systemName: tile.icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(
                        isEmpty
                            ? theme.colors.textTertiary.opacity(0.45)
                            : theme.currentTheme.chrome.accent
                    )
                    .frame(height: 24)

                Text(tile.label)
                    .talkieType(.fieldLabel)
                    .foregroundStyle(
                        isEmpty
                            ? theme.colors.textTertiary
                            : theme.colors.textPrimary
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                if let hint = tile.hint {
                    Text(hint.uppercased())
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(theme.colors.textTertiary)
                } else {
                    Color.clear.frame(height: 10)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        isFiring
                            ? theme.currentTheme.chrome.accent.opacity(0.22)
                            : theme.colors.cardBackground.opacity(isEmpty ? 0.4 : 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                isFiring
                                    ? theme.currentTheme.chrome.accent
                                    : (isEmpty
                                        ? theme.currentTheme.chrome.edgeFaint.opacity(0.5)
                                        : theme.currentTheme.chrome.edgeFaint),
                                style: isEmpty
                                    ? StrokeStyle(
                                        lineWidth: theme.currentTheme.chrome.hairlineWidth,
                                        dash: [3, 3]
                                    )
                                    : StrokeStyle(lineWidth: theme.currentTheme.chrome.hairlineWidth)
                            )
                    )
            )
            .shadow(
                color: isFiring ? theme.currentTheme.chrome.accentGlow : .clear,
                radius: isFiring ? 4 : 0
            )
        }
        .buttonStyle(.plain)
        .disabled(isEmpty || deck.firingSlotID != nil)
        .accessibilityLabel(isEmpty ? "Empty slot" : tile.label)
        .accessibilityHint(isEmpty ? "" : "Fires on the Mac")
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(red: 0.85, green: 0.46, blue: 0.34))
                .accessibilityHidden(true)
            Text(message)
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(red: 0.85, green: 0.46, blue: 0.34).opacity(0.45),
                                      lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
        )
    }
}
