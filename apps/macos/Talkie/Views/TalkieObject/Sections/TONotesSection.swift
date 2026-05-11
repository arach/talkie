//
//  TONotesSection.swift
//  Talkie
//
//  User notes section — editable text area with auto-save.
//  Self-gates: renders nothing if notes are empty and mode is not editor.
//

import SwiftUI
import TalkieKit

struct TONotesSection: View {
    let slot: SectionSlot
    let recording: TalkieObject
    let settings: SettingsManager
    @Binding var editedNotes: String
    var showNotesSaved: Bool = false
    var onNotesChange: () -> Void = {}

    var body: some View {
        if !editedNotes.isEmpty || slot.mode == .editor {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .center, spacing: Spacing.xs) {
                    Text("SCRATCHPAD")
                        .font(settings.fontXSMedium)
                        .tracking(Tracking.wide)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    if showNotesSaved {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(settings.fontXS)
                            Text("Saved")
                                .font(settings.fontXS)
                        }
                        .foregroundColor(.green.opacity(0.7))
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xxs)
                        .background(Color.green.opacity(0.1))
                        .clipShape(Capsule())
                        .transition(.opacity.combined(with: .scale))
                    }
                }

                TextEditor(text: $editedNotes)
                    .font(settings.contentFontBody)
                    .foregroundColor(Theme.current.foreground)
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.automatic)
                    .frame(minHeight: 80, maxHeight: 400)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .fill(Theme.current.foreground.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .stroke(Theme.current.foreground.opacity(0.12), lineWidth: BorderWidth.thin)
                    )
                    .onChange(of: editedNotes) { _, _ in
                        onNotesChange()
                    }
            }
        }
    }
}
