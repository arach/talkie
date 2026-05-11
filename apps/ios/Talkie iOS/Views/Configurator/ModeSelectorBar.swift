//
//  ModeSelectorBar.swift
//  Talkie iOS
//
//  Horizontal mode selector bar with tabs for each keyboard mode.
//  Supports switching between modes and resetting to defaults.
//

import SwiftUI
import TalkieMobileKit

struct ModeSelectorBar: View {
    let modes: [KeyboardMode]
    @Binding var selectedModeId: String
    var onResetMode: ((String) -> Void)?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(modes) { mode in
                ModeTab(
                    mode: mode,
                    isSelected: mode.id == selectedModeId,
                    onTap: { selectedModeId = mode.id },
                    onReset: { onResetMode?(mode.id) }
                )
            }
        }
        .padding(3)
        .background(ConfiguratorDesign.surfaceDark)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .cornerRadius(8)
    }
}

// MARK: - Mode Tab

private struct ModeTab: View {
    let mode: KeyboardMode
    let isSelected: Bool
    let onTap: () -> Void
    let onReset: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Circle()
                    .fill(isSelected ? ConfiguratorDesign.vermillion.opacity(0.8) : ConfiguratorDesign.textMuted.opacity(0.2))
                    .frame(width: 4, height: 4)

                Text(shortLabel)
                    .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? ConfiguratorDesign.textPrimary : ConfiguratorDesign.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? ConfiguratorDesign.vermillion.opacity(0.15) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button(action: onReset) {
                Label("Reset to Default", systemImage: "arrow.counterclockwise")
            }
        }
    }

    private var shortLabel: String {
        switch mode.id {
        case "minimal": return "MIN"
        case "fn", "shortcuts": return "SHORT"
        case "numbers": return "123"
        case "symbols": return "#+="
        case "emoji": return "😀"
        default: return String(mode.name.prefix(3)).uppercased()
        }
    }
}

// MARK: - Preview

#Preview("Mode Selector") {
    VStack {
        ModeSelectorBar(
            modes: KeyboardMode.builtIn,
            selectedModeId: .constant("fn"),
            onResetMode: { mode in print("Reset \(mode)") }
        )

        ModeSelectorBar(
            modes: KeyboardMode.builtIn,
            selectedModeId: .constant("numbers"),
            onResetMode: nil
        )

        ModeSelectorBar(
            modes: KeyboardMode.builtIn,
            selectedModeId: .constant("symbols"),
            onResetMode: nil
        )
    }
    .padding()
    .background(ConfiguratorDesign.background)
}
