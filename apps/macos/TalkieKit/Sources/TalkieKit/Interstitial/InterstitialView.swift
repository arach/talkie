//
//  InterstitialView.swift
//  TalkieKit
//
//  Internal SwiftUI view for the interstitial editor.
//  Self-contained with no external dependencies.
//

import SwiftUI

struct InterstitialView: View {
    @Bindable var core: InterstitialCore
    @FocusState private var isTextFocused: Bool
    @State private var instruction = ""
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    // MARK: - Colors

    private var panelBackground: Color {
        isDark ? Color(white: 0.12) : Color(white: 0.98)
    }

    private var contentBackground: Color {
        isDark ? Color(white: 0.15) : Color.white
    }

    private var inputBackground: Color {
        isDark ? Color(white: 0.18) : Color(white: 0.95)
    }

    private var borderColor: Color {
        isDark ? Color(white: 0.25) : Color(white: 0.85)
    }

    private var textPrimary: Color {
        isDark ? .white : Color(white: 0.1)
    }

    private var textSecondary: Color {
        isDark ? Color(white: 0.6) : Color(white: 0.45)
    }

    private var accentColor: Color { .blue }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerBar

            // Content
            contentArea

            // Footer
            footerBar
        }
        .frame(minWidth: 400, idealWidth: 560, maxWidth: 800,
               minHeight: 300, idealHeight: 400, maxHeight: 600)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(panelBackground)
                .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 1)
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFocused = true
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            // Model indicator
            modelIndicator

            Spacer()

            // Status
            if core.isPolishing {
                HStack(spacing: 4) {
                    BrailleSpinner(size: 12)
                    Text("Polishing...")
                        .font(.system(size: 11))
                        .foregroundColor(textSecondary)
                }
            }

            // Revision count
            if !core.revisions.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10))
                    Text("\(core.revisions.count)")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(inputBackground))
            }

            // Close button
            Button(action: { core.dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(textSecondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(inputBackground))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var modelIndicator: some View {
        HStack(spacing: 6) {
            // Provider icon
            Image(systemName: providerIcon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(providerColor)

            // Model name
            Text(displayModelName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(inputBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(borderColor, lineWidth: 1)
                )
        )
    }

    private var providerIcon: String {
        switch core.config.llmProvider {
        case .anthropic: return "brain"
        case .openai: return "sparkle"
        }
    }

    private var providerColor: Color {
        switch core.config.llmProvider {
        case .anthropic: return Color(red: 0.85, green: 0.55, blue: 0.35)
        case .openai: return Color(red: 0.3, green: 0.7, blue: 0.5)
        }
    }

    private var displayModelName: String {
        let model = core.config.llmModel
        return model
            .replacingOccurrences(of: "claude-3-haiku-20240307", with: "Haiku")
            .replacingOccurrences(of: "claude-3-5-sonnet", with: "Sonnet")
            .replacingOccurrences(of: "claude-3-opus", with: "Opus")
            .replacingOccurrences(of: "gpt-4o-mini", with: "4o-mini")
            .replacingOccurrences(of: "gpt-4o", with: "4o")
    }

    // MARK: - Content

    private var contentArea: some View {
        VStack(spacing: 0) {
            // Text editor
            TextEditor(text: $core.text)
                .font(.system(size: 14))
                .foregroundColor(textPrimary)
                .scrollContentBackground(.hidden)
                .padding(12)
                .focused($isTextFocused)
                .frame(maxHeight: .infinity)

            Divider()

            // Instruction input
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundColor(accentColor)

                TextField("Tell AI what to do (e.g., 'make it formal')", text: $instruction)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit { submitInstruction() }

                if core.isPolishing {
                    BrailleSpinner(size: 12)
                } else if !instruction.isEmpty {
                    Button(action: submitInstruction) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                    .fill(inputBackground)
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(contentBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(borderColor, lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            // Reset button
            if core.text != core.originalText {
                Button(action: { core.resetText() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10))
                        Text("Reset")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(textSecondary)
                }
                .buttonStyle(.plain)
            }

            // Error
            if let error = core.polishError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .lineLimit(1)
            }

            Spacer()

            // Quick actions
            HStack(spacing: 8) {
                // Formal
                quickActionButton("Formal", icon: "briefcase") {
                    Task { await core.polish(instruction: "Make it more formal and professional") }
                }

                // Concise
                quickActionButton("Concise", icon: "scissors") {
                    Task { await core.polish(instruction: "Make it more concise, remove filler words") }
                }

                // Copy
                Button(action: { core.copyAndDismiss() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                        Text("Copy")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(accentColor))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("c", modifiers: .command)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func quickActionButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11))
            }
            .foregroundColor(textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(inputBackground)
                    .overlay(Capsule().stroke(borderColor, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .disabled(core.isPolishing)
    }

    private func submitInstruction() {
        guard !instruction.isEmpty, !core.isPolishing else { return }
        let inst = instruction
        instruction = ""
        Task { await core.polish(instruction: inst) }
    }
}
