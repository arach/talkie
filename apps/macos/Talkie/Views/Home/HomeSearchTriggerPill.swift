//
//  HomeSearchTriggerPill.swift
//  Talkie
//
//  Search and command palette trigger for Home header.
//

import SwiftUI
import TalkieKit

// MARK: - Search Trigger Pill

struct SearchTriggerPill: View {
    @State private var isSearchHovered = false
    @State private var isPaletteHovered = false

    var body: some View {
        HStack(spacing: 6) {
            // Content search pill
            Button {
                NotificationCenter.default.post(name: .showContentSearch, object: nil)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.current.foregroundMuted)

                    Text("Search...")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.current.foregroundMuted)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Theme.current.surface1)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Theme.current.border.opacity(isSearchHovered ? 0.25 : 0.1), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .onHover { isSearchHovered = $0 }

            // Command palette chip
            Button {
                NotificationCenter.default.post(name: .showCommandPalette, object: nil)
            } label: {
                Text("\u{2325}\u{2318}K")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.current.foregroundMuted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Theme.current.surface1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Theme.current.border.opacity(isPaletteHovered ? 0.25 : 0.1), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .onHover { isPaletteHovered = $0 }
        }
    }
}
