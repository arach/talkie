//
//  MinimalKeyboardGridView.swift
//  Talkie iOS
//
//  Horizontal 5-slot preview for the minimal keyboard layout in the configurator.
//  Layout: [slot1][slot2][ DICTATE ][slot3][slot4]
//  DICTATE is fixed/non-editable; slots 1-4 are tappable for configuration.
//

import SwiftUI
import TalkieMobileKit

struct MinimalKeyboardGridView: View {
    let mode: KeyboardMode
    let selectedSlot: Int?
    let onSlotTap: (Int) -> Void

    var slotOverrides: [Int: SlotConfig] = [:]
    var customizedSlots: Set<Int> = []

    var body: some View {
        VStack(spacing: ConfiguratorDesign.gridSpacing) {
            // Single row: [1][2][ DICTATE ][3][4]
            HStack(spacing: ConfiguratorDesign.gridSpacing) {
                // Slot 1
                SlotButtonPreview(
                    slot: 1,
                    config: configForSlot(1),
                    isSelected: selectedSlot == 1,
                    onTap: { onSlotTap(1) },
                    isCustomized: customizedSlots.contains(1)
                )
                .frame(height: ConfiguratorDesign.buttonHeight)

                // Slot 2
                SlotButtonPreview(
                    slot: 2,
                    config: configForSlot(2),
                    isSelected: selectedSlot == 2,
                    onTap: { onSlotTap(2) },
                    isCustomized: customizedSlots.contains(2)
                )
                .frame(height: ConfiguratorDesign.buttonHeight)

                // Fixed DICTATE button (non-editable, wider)
                HStack(spacing: 4) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .medium))
                    Text("DICTATE")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(ConfiguratorDesign.vermillion.opacity(0.8))
                .frame(maxWidth: .infinity)
                .frame(height: ConfiguratorDesign.buttonHeight)
                .background(ConfiguratorDesign.surfaceDark)
                .cornerRadius(ConfiguratorDesign.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: ConfiguratorDesign.cornerRadius)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                )

                // Slot 3
                SlotButtonPreview(
                    slot: 3,
                    config: configForSlot(3),
                    isSelected: selectedSlot == 3,
                    onTap: { onSlotTap(3) },
                    isCustomized: customizedSlots.contains(3)
                )
                .frame(height: ConfiguratorDesign.buttonHeight)

                // Slot 4
                SlotButtonPreview(
                    slot: 4,
                    config: configForSlot(4),
                    isSelected: selectedSlot == 4,
                    onTap: { onSlotTap(4) },
                    isCustomized: customizedSlots.contains(4)
                )
                .frame(height: ConfiguratorDesign.buttonHeight)
            }
        }
        .padding(ConfiguratorDesign.gridSpacing)
        .background(ConfiguratorDesign.background)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .cornerRadius(8)
    }

    private func configForSlot(_ slot: Int) -> SlotConfig {
        if let override = slotOverrides[slot] {
            return override
        }
        return mode.config(for: slot)
    }
}

// MARK: - Preview

#Preview("Minimal Keyboard Grid") {
    MinimalKeyboardGridView(
        mode: .minimal,
        selectedSlot: 1,
        onSlotTap: { _ in }
    )
    .padding()
    .background(Color.black)
}

#Preview("Minimal Keyboard Grid - No Selection") {
    MinimalKeyboardGridView(
        mode: .minimal,
        selectedSlot: nil,
        onSlotTap: { _ in }
    )
    .padding()
    .background(Color.black)
}
