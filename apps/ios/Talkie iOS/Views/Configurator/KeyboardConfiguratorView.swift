//
//  KeyboardConfiguratorView.swift
//  Talkie iOS
//
//  VIA-inspired keyboard configurator with WYSIWYG slot editing.
//  Users tap a slot in the grid to configure what it does.
//

import SwiftUI
import TalkieMobileKit

struct KeyboardConfiguratorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedModeId: String = "minimal"
    @State private var selectedSlot: Int?
    @State private var slotOverrides: [String: [Int: SlotConfig]] = [:]  // modeId -> (slot -> config)

    /// Only show modes that make sense to configure (exclude qwerty splits, abc has no slots)
    private static let configurableModeIds = ["minimal", "fn", "numbers", "symbols", "emoji"]

    private let configurationStore = TalkieAppConfigurationStore.shared

    private var configurableModes: [KeyboardMode] {
        KeyboardMode.builtIn.filter { Self.configurableModeIds.contains($0.id) }
    }

    var body: some View {
        ZStack {
            Color.surfacePrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top area: Configuration content
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        // Mode selector bar (filtered to configurable modes)
                        ModeSelectorBar(
                            modes: configurableModes,
                            selectedModeId: $selectedModeId,
                            onResetMode: resetMode
                        )

                        // Instructions and hints
                        configurationArea

                        Spacer(minLength: Spacing.xl)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.md)
                }

                // Bottom area: Keyboard (fixed, like a real keyboard)
                VStack(spacing: 0) {
                    // Divider
                    Rectangle()
                        .fill(Color.borderPrimary)
                        .frame(height: 0.5)

                    // WYSIWYG keyboard grid (minimal uses horizontal layout, others use 3x4 grid)
                    if selectedModeId == "minimal" {
                        MinimalKeyboardGridView(
                            mode: currentMode,
                            selectedSlot: selectedSlot,
                            onSlotTap: { slot in
                                selectedSlot = slot
                            },
                            slotOverrides: currentModeOverrides,
                            customizedSlots: Set(currentModeOverrides.keys)
                        )
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xs)
                        .background(ConfiguratorDesign.background)
                    } else {
                        KeyboardGridView(
                            mode: currentMode,
                            selectedSlot: selectedSlot,
                            onSlotTap: { slot in
                                selectedSlot = slot
                            },
                            slotOverrides: currentModeOverrides,
                            customizedSlots: Set(currentModeOverrides.keys)
                        )
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xs)
                        .background(ConfiguratorDesign.background)
                    }
                }
            }
        }
        .navigationTitle("Customize Slots")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if hasAnyCustomizations {
                    Menu {
                        Button(role: .destructive) {
                            resetAllModes()
                        } label: {
                            Label("Reset All Modes", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(item: $selectedSlot) { slot in
            let defaultConfig = currentMode.config(for: slot)
            let isCustomized = currentModeOverrides[slot] != nil
            SlotEditorSheet(
                slot: slot,
                modeId: selectedModeId,
                initialConfig: configForSlot(slot),
                defaultConfig: defaultConfig,
                isCustomized: isCustomized,
                mode: currentMode,
                onSave: { newConfig in
                    // If config matches default, clear the override
                    if newConfig == defaultConfig {
                        slotOverrides[selectedModeId]?.removeValue(forKey: slot)
                    } else {
                        saveSlotConfig(slot: slot, config: newConfig)
                    }
                    selectedSlot = nil
                },
                onCancel: {
                    selectedSlot = nil
                }
            )
        }
        .onAppear {
            loadAllCustomizations()
        }
        .onChange(of: selectedModeId) { _, _ in
            selectedSlot = nil
        }
    }

    // MARK: - Computed Properties

    private var currentMode: KeyboardMode {
        KeyboardMode.builtIn.first { $0.id == selectedModeId } ?? .fn
    }

    private var currentModeOverrides: [Int: SlotConfig] {
        slotOverrides[selectedModeId] ?? [:]
    }

    private var hasAnyCustomizations: Bool {
        !slotOverrides.isEmpty && slotOverrides.values.contains { !$0.isEmpty }
    }

    // MARK: - UI Components

    private var configurationArea: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("TAP A SLOT TO CONFIGURE")
                .font(.system(size: 10, weight: .regular))
                .tracking(1.5)
                .foregroundColor(.textTertiary.opacity(0.6))

            Text("Select any key below to customize what it does.")
                .font(.system(size: 13, weight: .light))
                .foregroundColor(.textSecondary)

            if !currentModeOverrides.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.success.opacity(0.7))
                    Text("Custom configurations active")
                        .font(.system(size: 11, weight: .light))
                        .foregroundColor(.textSecondary.opacity(0.8))
                }
            }

            HStack(spacing: 4) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 9, weight: .light))
                Text("Long-press a mode tab to reset")
                    .font(.system(size: 10, weight: .light))
            }
            .foregroundColor(.textTertiary.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(Color.surfaceSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .stroke(Color.textTertiary.opacity(0.12), lineWidth: 0.5)
        )
        .cornerRadius(CornerRadius.sm)
    }

    // MARK: - Configuration Methods

    private func configForSlot(_ slot: Int) -> SlotConfig {
        // Check for custom override first
        if let override = currentModeOverrides[slot] {
            return override
        }
        // Fall back to mode's built-in default
        return currentMode.config(for: slot)
    }

    private func saveSlotConfig(slot: Int, config: SlotConfig) {
        // Update local state
        if slotOverrides[selectedModeId] == nil {
            slotOverrides[selectedModeId] = [:]
        }
        slotOverrides[selectedModeId]?[slot] = config

        configurationStore.update { configuration in
            var modeOverrides = configuration.keyboard.modeSlotOverrides[selectedModeId] ?? [:]
            modeOverrides[String(slot)] = config
            configuration.keyboard.modeSlotOverrides[selectedModeId] = modeOverrides
        }
        TalkieAppSettings.shared.reloadFromDisk()
    }

    private func resetMode(_ modeId: String) {
        // Clear local state
        slotOverrides[modeId] = nil

        configurationStore.update { configuration in
            configuration.keyboard.modeSlotOverrides.removeValue(forKey: modeId)
        }
        TalkieAppSettings.shared.reloadFromDisk()
    }

    private func resetAllModes() {
        // Clear all local state
        slotOverrides.removeAll()

        configurationStore.update { configuration in
            configuration.keyboard.modeSlotOverrides.removeAll()
        }
        TalkieAppSettings.shared.reloadFromDisk()
    }

    private func loadAllCustomizations() {
        slotOverrides.removeAll()

        for (modeId, serializedSlots) in configurationStore.configuration.keyboard.modeSlotOverrides {
            let decodedSlots = serializedSlots.reduce(into: [Int: SlotConfig]()) { partial, entry in
                guard let slot = Int(entry.key) else { return }
                partial[slot] = entry.value
            }
            if !decodedSlots.isEmpty {
                slotOverrides[modeId] = decodedSlots
            }
        }
    }
}

// MARK: - Int Extension for Identifiable

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

// MARK: - Preview

#Preview("Keyboard Configurator") {
    NavigationStack {
        KeyboardConfiguratorView()
    }
}

#Preview("Keyboard Configurator - Dark") {
    NavigationStack {
        KeyboardConfiguratorView()
    }
    .preferredColorScheme(.dark)
}
