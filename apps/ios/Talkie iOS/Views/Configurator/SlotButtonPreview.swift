//
//  SlotButtonPreview.swift
//  Talkie iOS
//
//  Individual slot button preview for the keyboard configurator.
//  Matches the actual keyboard styling exactly for WYSIWYG editing.
//

import SwiftUI
import TalkieMobileKit

// MARK: - Design Constants (Match KeyboardViewController.Design)

enum ConfiguratorDesign {
    // Colors matching keyboard extension
    static let background = Color(hex: "141414")
    static let surfaceDark = Color(hex: "1F1F1F")
    static let surfaceLight = Color(hex: "2E2E2E")
    static let vermillion = Color(hex: "E84D3D")
    static let textPrimary = Color.white.opacity(0.95)
    static let textSecondary = Color.white.opacity(0.5)
    static let textMuted = Color.white.opacity(0.35)

    // Layout
    static let gridSpacing: CGFloat = 4
    static let cornerRadius: CGFloat = 4
    static let buttonHeight: CGFloat = 44
    static let recordButtonHeight: CGFloat = 56

    // Selection
    static let selectionBorderColor = Color(hex: "0070F3")
    static let selectionBorderWidth: CGFloat = 2
}

// MARK: - Slot Button Preview

struct SlotButtonPreview: View {
    let slot: Int
    let config: SlotConfig
    let isSelected: Bool
    let onTap: () -> Void
    var isCustomized: Bool = false
    var isEditable: Bool = true

    var body: some View {
        Button(action: onTap) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(isSelected ? selectedBackgroundColor : backgroundColor)
                .cornerRadius(ConfiguratorDesign.cornerRadius)
                .overlay(selectionOverlay)
                .overlay(customizedBadge, alignment: .topLeading)
                .overlay(lockBadge, alignment: .topTrailing)
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(isEditable ? 1.0 : 0.5)
        .disabled(!isEditable)
        .shadow(
            color: isSelected ? ConfiguratorDesign.selectionBorderColor.opacity(0.4) : .clear,
            radius: 6,
            x: 0,
            y: 0
        )
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    @ViewBuilder
    private var content: some View {
        switch config.type {
        case .text, .snippet:
            Text(config.label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(ConfiguratorDesign.textPrimary)

        case .action:
            VStack(spacing: 1) {
                if let icon = config.icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(ConfiguratorDesign.textPrimary)
                }
                Text(config.label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(ConfiguratorDesign.textSecondary)
            }

        case .space:
            VStack(spacing: 1) {
                Image(systemName: "space")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(ConfiguratorDesign.textPrimary)
                Text("SPACE")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(ConfiguratorDesign.textSecondary)
            }

        case .empty:
            Text("")
                .foregroundColor(ConfiguratorDesign.textMuted)
        }
    }

    private var backgroundColor: Color {
        switch config.type {
        case .text, .snippet:
            return ConfiguratorDesign.surfaceLight
        case .action, .space, .empty:
            return ConfiguratorDesign.surfaceDark
        }
    }

    private var selectedBackgroundColor: Color {
        // Brighter background when selected
        ConfiguratorDesign.vermillion.opacity(0.25)
    }

    @ViewBuilder
    private var selectionOverlay: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: ConfiguratorDesign.cornerRadius)
                .strokeBorder(ConfiguratorDesign.selectionBorderColor, lineWidth: 2)
        } else if isCustomized && isEditable {
            RoundedRectangle(cornerRadius: ConfiguratorDesign.cornerRadius)
                .strokeBorder(ConfiguratorDesign.selectionBorderColor.opacity(0.5), lineWidth: 1)
        } else {
            RoundedRectangle(cornerRadius: ConfiguratorDesign.cornerRadius)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private var customizedBadge: some View {
        if isEditable && isCustomized && !isSelected {
            Text("C")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 12, height: 12)
                .background(ConfiguratorDesign.selectionBorderColor.opacity(0.7))
                .cornerRadius(3)
                .padding(2)
        }
    }

    @ViewBuilder
    private var lockBadge: some View {
        if !isEditable {
            Image(systemName: "lock.fill")
                .font(.system(size: 6))
                .foregroundColor(ConfiguratorDesign.textMuted.opacity(0.5))
                .padding(3)
        }
    }
}

// MARK: - Record Button Preview (Non-Interactive)

struct RecordButtonPreview: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white)

            Text("RECORD")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .frame(height: ConfiguratorDesign.recordButtonHeight)
        .background(ConfiguratorDesign.vermillion.opacity(0.6))
        .cornerRadius(ConfiguratorDesign.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: ConfiguratorDesign.cornerRadius)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }
}

// MARK: - Preview

#Preview("Slot Button - Text") {
    SlotButtonPreview(
        slot: 9,
        config: .text("Best", inserts: "Best regards,\n"),
        isSelected: false,
        onTap: {}
    )
    .frame(width: 80, height: 44)
    .padding()
    .background(ConfiguratorDesign.background)
}

#Preview("Slot Button - Action") {
    SlotButtonPreview(
        slot: 4,
        config: .action("ENTER", icon: "return"),
        isSelected: true,
        onTap: {}
    )
    .frame(width: 80, height: 44)
    .padding()
    .background(ConfiguratorDesign.background)
}

#Preview("Record Button") {
    RecordButtonPreview()
        .padding()
        .background(ConfiguratorDesign.background)
}
