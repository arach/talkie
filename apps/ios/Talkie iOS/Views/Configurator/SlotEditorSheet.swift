//
//  SlotEditorSheet.swift
//  Talkie iOS
//
//  Configuration sheet for editing a single keyboard slot.
//  Supports text, snippet, action, and empty slot types.
//

import SwiftUI
import TalkieMobileKit

struct SlotEditorSheet: View {
    let slot: Int
    let modeId: String
    let initialConfig: SlotConfig
    let defaultConfig: SlotConfig
    let isCustomized: Bool
    let mode: KeyboardMode

    var onSave: (SlotConfig) -> Void
    var onCancel: () -> Void

    @State private var slotType: SlotConfig.SlotType
    @State private var label: String
    @State private var content: String
    @State private var selectedActionLabel: String

    init(
        slot: Int,
        modeId: String,
        initialConfig: SlotConfig,
        defaultConfig: SlotConfig? = nil,
        isCustomized: Bool = false,
        mode: KeyboardMode? = nil,
        onSave: @escaping (SlotConfig) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.slot = slot
        self.modeId = modeId
        self.initialConfig = initialConfig
        self.defaultConfig = defaultConfig ?? initialConfig
        self.isCustomized = isCustomized
        self.mode = mode ?? KeyboardMode.builtIn.first { $0.id == modeId } ?? .fn
        self.onSave = onSave
        self.onCancel = onCancel

        _slotType = State(initialValue: initialConfig.type)
        _label = State(initialValue: initialConfig.label)
        _content = State(initialValue: initialConfig.content)
        _selectedActionLabel = State(initialValue: initialConfig.type == .action ? initialConfig.label : "TAB")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Configuration fields (scrollable)
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        // Slot number header
                        slotHeader

                        // Default vs. custom status
                        defaultSummary

                        // Type selector
                        typeSelector

                        // Dynamic fields based on type
                        Group {
                            switch slotType {
                            case .text:
                                textFields
                            case .snippet:
                                snippetFields
                            case .action:
                                actionPicker
                            case .space, .empty:
                                emptyStateHint
                            }
                        }

                        Spacer(minLength: Spacing.lg)
                    }
                    .padding(Spacing.md)
                }

                // Keyboard context (fixed at bottom)
                keyboardContextView
            }
            .background(Color.surfacePrimary)
            .navigationTitle("Configure Slot \(slot)")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: slotType) { oldType, newType in
                // Reset fields when switching types to avoid stale values
                if oldType == .action && newType != .action {
                    // Switching away from action — clear action label from text fields
                    if availableActions.contains(where: { $0.label == label }) {
                        label = ""
                        content = ""
                    }
                } else if newType == .action && oldType != .action {
                    // Switching to action — populate from selected action
                    label = selectedActionLabel
                    content = selectedActionLabel
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(buildConfig())
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Slot Header

    private var slotHeader: some View {
        HStack {
            Text("SLOT \(slot)")
                .font(.techLabel)
                .tracking(2)
                .foregroundColor(.textTertiary)

            Spacer()

            // Mode indicator
            Text(modeLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(ConfiguratorDesign.vermillion)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(ConfiguratorDesign.vermillion.opacity(0.1))
                .cornerRadius(4)
        }
    }

    private var modeLabel: String {
        switch modeId {
        case "minimal": return "MINIMAL"
        case "fn", "shortcuts": return "SHORTCUTS"
        case "numbers": return "NUMBERS"
        case "symbols": return "SYMBOLS"
        case "emoji": return "EMOJI"
        default: return modeId.uppercased()
        }
    }

    // MARK: - Default Summary

    private var defaultSummary: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: isCustomized ? "slider.horizontal.3" : "checkmark.circle")
                    .font(.system(size: 11, weight: .light))
                    .foregroundColor(isCustomized ? .accentColor.opacity(0.8) : .success.opacity(0.7))
                Text(isCustomized ? "Using custom value" : "Using default value")
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(.textSecondary)
            }

            Text("Default: \(defaultSummaryLabel)")
                .font(.system(size: 11, weight: .light))
                .foregroundColor(.textTertiary)

            if isCustomized {
                Button {
                    applyConfig(defaultConfig)
                } label: {
                    Label("Revert to Default", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .regular))
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(Color.surfaceSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .stroke(Color.textTertiary.opacity(0.12), lineWidth: 0.5)
        )
        .cornerRadius(CornerRadius.sm)
    }

    private var defaultSummaryLabel: String {
        switch defaultConfig.type {
        case .text:
            return "Text \"\(defaultConfig.label)\""
        case .snippet:
            return "Snippet \"\(defaultConfig.label)\""
        case .action:
            return "Action \"\(defaultConfig.label)\""
        case .space:
            return "Space"
        case .empty:
            return "Empty"
        }
    }

    private func applyConfig(_ config: SlotConfig) {
        slotType = config.type
        label = config.label
        content = config.content
        selectedActionLabel = config.type == .action ? config.label : selectedActionLabel
    }

    // MARK: - Type Selector

    private var typeSelector: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("TYPE")
                .font(.techLabel)
                .tracking(2)
                .foregroundColor(.textTertiary)

            HStack(spacing: 6) {
                TypeButton(label: "Text", icon: "character.cursor.ibeam", type: .text, selected: slotType) { slotType = .text }
                TypeButton(label: "Snippet", icon: "doc.text", type: .snippet, selected: slotType) { slotType = .snippet }
                TypeButton(label: "Action", icon: "keyboard", type: .action, selected: slotType) { slotType = .action }
                TypeButton(label: "Empty", icon: "square.dashed", type: .empty, selected: slotType) { slotType = .empty }
            }

            // Contextual description
            Text(typeDescription)
                .font(.system(size: 12, weight: .light))
                .foregroundColor(.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
    }

    private var typeDescription: String {
        switch slotType {
        case .text:
            return "Inserts a word or short phrase when tapped."
        case .snippet:
            return "Inserts longer or multi-line text — templates, signatures, etc."
        case .action:
            return "Performs a keyboard function like Tab, Enter, Copy, or Paste."
        case .empty:
            return "Slot is blank — no button shown."
        case .space:
            return "Inserts a space."
        }
    }

    // MARK: - Text Fields

    private var textFields: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Label field
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("LABEL")
                    .font(.techLabel)
                    .tracking(2)
                    .foregroundColor(.textTertiary)

                TextField("Button label", text: $label)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 16))
            }

            // Content field (optional - defaults to label)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text("INSERTS")
                        .font(.techLabel)
                        .tracking(2)
                        .foregroundColor(.textTertiary)

                    Text("(optional)")
                        .font(.system(size: 10))
                        .foregroundColor(.textTertiary)
                }

                TextField("Text to insert (defaults to label)", text: $content)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 16))
            }
        }
    }

    // MARK: - Snippet Fields

    private var snippetFields: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Label field
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("LABEL")
                    .font(.techLabel)
                    .tracking(2)
                    .foregroundColor(.textTertiary)

                TextField("Button label", text: $label)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 16))
            }

            // Multi-line content field
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("CONTENT")
                    .font(.techLabel)
                    .tracking(2)
                    .foregroundColor(.textTertiary)

                TextEditor(text: $content)
                    .font(.system(size: 14, design: .monospaced))
                    .frame(minHeight: 100)
                    .padding(4)
                    .background(Color.surfaceSecondary)
                    .cornerRadius(CornerRadius.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
                    )
            }
        }
    }

    // MARK: - Action Picker

    private var actionPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("ACTION")
                .font(.techLabel)
                .tracking(2)
                .foregroundColor(.textTertiary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(availableActions, id: \.label) { action in
                    ActionPickerButton(
                        label: action.label,
                        icon: action.icon,
                        isSelected: selectedActionLabel == action.label,
                        onTap: {
                            selectedActionLabel = action.label
                            label = action.label
                        }
                    )
                }
            }
        }
    }

    private var availableActions: [(label: String, icon: String)] {
        [
            ("TAB", "arrow.right.to.line"),
            ("COPY", "doc.on.doc"),
            ("PASTE", "doc.on.clipboard"),
            ("ENTER", "return"),
            ("DEL", "delete.left"),
            ("ESC", "escape"),
            ("SELECT", "selection.pin.in.out"),
            ("Aa", "textformat"),
            ("SPACE", "space")
        ]
    }

    // MARK: - Keyboard Context View

    private var keyboardContextView: some View {
        VStack(spacing: 0) {
            // Divider
            Rectangle()
                .fill(Color.borderPrimary)
                .frame(height: 0.5)

            if modeId == "minimal" {
                // Minimal layout: [1][2][ DICTATE ][3][4]
                minimalContextView
                    .padding(Spacing.sm)
                    .background(ConfiguratorDesign.background)
            } else {
                // Standard 3x4 grid layout + dictate row
                VStack(spacing: ConfiguratorDesign.gridSpacing) {
                    contextRow(slots: [9, 10, 11, 12])
                    contextRow(slots: [5, 6, 7, 8])
                    contextRow(slots: [1, 2, 3, 4])

                    // Dictate row: [1x slot 13][2x DICTATE][1x slot 14]
                    GeometryReader { geo in
                        let spacing = ConfiguratorDesign.gridSpacing
                        let totalSpacing = spacing * 3
                        let columnWidth = (geo.size.width - totalSpacing) / 4
                        let dictateWidth = columnWidth * 2 + spacing

                        HStack(spacing: spacing) {
                            contextSlot(13)
                                .frame(width: columnWidth)

                            // Fixed DICTATE (non-interactive)
                            HStack(spacing: 4) {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 12, weight: .medium))
                                Text("DICTATE")
                                    .font(.system(size: 8, weight: .semibold))
                            }
                            .foregroundColor(ConfiguratorDesign.vermillion.opacity(0.3))
                            .frame(width: dictateWidth, height: 36)
                            .background(ConfiguratorDesign.surfaceDark)
                            .cornerRadius(ConfiguratorDesign.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: ConfiguratorDesign.cornerRadius)
                                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                            )

                            contextSlot(14)
                                .frame(width: columnWidth)
                        }
                    }
                    .frame(height: 36)
                }
                .padding(Spacing.sm)
                .background(ConfiguratorDesign.background)
            }
        }
    }

    private var minimalContextView: some View {
        HStack(spacing: ConfiguratorDesign.gridSpacing) {
            contextSlot(1)
            contextSlot(2)

            // Fixed DICTATE (non-interactive)
            HStack(spacing: 4) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 12, weight: .medium))
                Text("DICTATE")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundColor(ConfiguratorDesign.vermillion.opacity(0.5))
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(ConfiguratorDesign.surfaceDark)
            .cornerRadius(ConfiguratorDesign.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: ConfiguratorDesign.cornerRadius)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )

            contextSlot(3)
            contextSlot(4)
        }
    }

    private func contextRow(slots: [Int]) -> some View {
        HStack(spacing: ConfiguratorDesign.gridSpacing) {
            ForEach(slots, id: \.self) { slotNum in
                contextSlot(slotNum)
            }
        }
    }

    private func contextSlot(_ slotNum: Int) -> some View {
        let isEditingSlot = slotNum == slot
        let config = isEditingSlot ? buildConfig() : mode.config(for: slotNum)

        return SlotButtonPreview(
            slot: slotNum,
            config: config,
            isSelected: isEditingSlot,
            onTap: {}  // Read-only in this context
        )
        .frame(height: 36)
        .opacity(isEditingSlot ? 1.0 : 0.4)
        .allowsHitTesting(false)  // Non-interactive
    }

    // MARK: - Empty State Hint

    private var emptyStateHint: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: slotType == .empty ? "square.dashed" : "space")
                .font(.system(size: 24))
                .foregroundColor(.textTertiary)

            Text(slotType == .empty ? "This slot will be empty" : "This slot will insert a space")
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
    }

    // MARK: - Build Config

    private func buildConfig() -> SlotConfig {
        switch slotType {
        case .text:
            let finalContent = content.isEmpty ? label : content
            return .text(label, inserts: finalContent)

        case .snippet:
            return .snippet(label, content: content, icon: nil)

        case .action:
            let icon = availableActions.first { $0.label == selectedActionLabel }?.icon ?? "questionmark"
            return .action(selectedActionLabel, icon: icon)

        case .space:
            return .space

        case .empty:
            return .empty
        }
    }
}

// MARK: - Type Button

private struct TypeButton: View {
    let label: String
    let icon: String
    let type: SlotConfig.SlotType
    let selected: SlotConfig.SlotType
    let onTap: () -> Void

    private var isSelected: Bool { type == selected }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : .textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(isSelected ? ConfiguratorDesign.vermillion : Color.surfaceSecondary)
            .cornerRadius(CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .strokeBorder(isSelected ? ConfiguratorDesign.vermillion : Color.borderPrimary, lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Action Picker Button

private struct ActionPickerButton: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isSelected ? .white : .textSecondary)

                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(isSelected ? .white : .textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(isSelected ? ConfiguratorDesign.vermillion : Color.surfaceSecondary)
            .cornerRadius(CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .strokeBorder(isSelected ? ConfiguratorDesign.vermillion : Color.borderPrimary, lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview("Slot Editor - Text") {
    SlotEditorSheet(
        slot: 9,
        modeId: "fn",
        initialConfig: .text("Best", inserts: "Best regards,\n"),
        defaultConfig: .text("Best", inserts: "Best regards,\n"),
        isCustomized: false,
        mode: .fn,
        onSave: { _ in },
        onCancel: {}
    )
}

#Preview("Slot Editor - Action") {
    SlotEditorSheet(
        slot: 4,
        modeId: "fn",
        initialConfig: .action("ENTER", icon: "return"),
        defaultConfig: .action("DEL", icon: "delete.left"),
        isCustomized: true,
        mode: .fn,
        onSave: { _ in },
        onCancel: {}
    )
}

#Preview("Slot Editor - Empty") {
    SlotEditorSheet(
        slot: 12,
        modeId: "symbols",
        initialConfig: .empty,
        defaultConfig: .action("DEL", icon: "delete.left"),
        isCustomized: true,
        mode: .symbols,
        onSave: { _ in },
        onCancel: {}
    )
}
