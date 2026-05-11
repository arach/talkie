//
//  KeyboardGridView.swift
//  Talkie iOS
//
//  WYSIWYG 3×4 grid view that matches the actual keyboard layout exactly.
//  Used in the configurator for visual slot editing.
//

import SwiftUI
import TalkieMobileKit

struct KeyboardGridView: View {
    let mode: KeyboardMode
    let selectedSlot: Int?
    let onSlotTap: (Int) -> Void

    /// Custom slot overrides (slot -> SlotConfig)
    var slotOverrides: [Int: SlotConfig] = [:]

    /// Which slots have custom overrides
    var customizedSlots: Set<Int> = []

    var body: some View {
        VStack(spacing: ConfiguratorDesign.gridSpacing) {
            // Row C (top): Slots 9-12 - Quick inputs
            slotRow(slots: [9, 10, 11, 12])

            // Row B (middle): Slots 5-8
            slotRow(slots: [5, 6, 7, 8])

            // Row A (bottom): Slots 1-4 - TAB, COPY, PASTE, ENTER
            slotRow(slots: [1, 2, 3, 4])

            // Dictate row: [slot 13][DICTATE][slot 14]
            dictateRow
        }
        .padding(ConfiguratorDesign.gridSpacing)
        .background(ConfiguratorDesign.background)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .cornerRadius(8)
    }

    private func slotRow(slots: [Int]) -> some View {
        HStack(spacing: ConfiguratorDesign.gridSpacing) {
            ForEach(slots, id: \.self) { slot in
                SlotButtonPreview(
                    slot: slot,
                    config: configForSlot(slot),
                    isSelected: selectedSlot == slot,
                    onTap: { onSlotTap(slot) },
                    isCustomized: customizedSlots.contains(slot)
                )
                .frame(height: ConfiguratorDesign.buttonHeight)
            }
        }
    }

    /// Dictate row matches actual keyboard: [1x slot][2x DICTATE][1x slot]
    private var dictateRow: some View {
        GeometryReader { geo in
            let spacing = ConfiguratorDesign.gridSpacing
            let totalSpacing = spacing * 3  // 3 gaps between 4 logical columns
            let columnWidth = (geo.size.width - totalSpacing) / 4
            let dictateWidth = columnWidth * 2 + spacing  // spans 2 columns + 1 inner gap

            HStack(spacing: spacing) {
                // Slot 13 (left of DICTATE)
                SlotButtonPreview(
                    slot: 13,
                    config: configForSlot(13),
                    isSelected: selectedSlot == 13,
                    onTap: { onSlotTap(13) },
                    isCustomized: customizedSlots.contains(13)
                )
                .frame(width: columnWidth, height: ConfiguratorDesign.buttonHeight)

                // Fixed DICTATE (non-editable, 2x width)
                HStack(spacing: 4) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .medium))
                    Text("DICTATE")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(ConfiguratorDesign.vermillion.opacity(0.8))
                .frame(width: dictateWidth, height: ConfiguratorDesign.buttonHeight)
                .background(ConfiguratorDesign.surfaceDark)
                .cornerRadius(ConfiguratorDesign.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: ConfiguratorDesign.cornerRadius)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                )

                // Slot 14 (right of DICTATE)
                SlotButtonPreview(
                    slot: 14,
                    config: configForSlot(14),
                    isSelected: selectedSlot == 14,
                    onTap: { onSlotTap(14) },
                    isCustomized: customizedSlots.contains(14)
                )
                .frame(width: columnWidth, height: ConfiguratorDesign.buttonHeight)
            }
        }
        .frame(height: ConfiguratorDesign.buttonHeight)
    }

    private func configForSlot(_ slot: Int) -> SlotConfig {
        if let override = slotOverrides[slot] {
            return override
        }
        return mode.config(for: slot)
    }
}

// MARK: - Preview

#Preview("Keyboard Grid - Shortcuts") {
    KeyboardGridView(
        mode: .shortcuts,
        selectedSlot: 9,
        onSlotTap: { _ in }
    )
    .padding()
    .background(Color.black)
}

#Preview("Keyboard Grid - Numbers") {
    KeyboardGridView(
        mode: .numbers,
        selectedSlot: nil,
        onSlotTap: { _ in }
    )
    .padding()
    .background(Color.black)
}

#Preview("Keyboard Grid - Symbols") {
    KeyboardGridView(
        mode: .symbols,
        selectedSlot: 5,
        onSlotTap: { _ in }
    )
    .padding()
    .background(Color.black)
}
