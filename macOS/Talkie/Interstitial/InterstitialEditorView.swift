//
//  InterstitialEditorView.swift
//  Talkie
//
//  Floating panel UI for editing transcribed text and applying LLM polish
//

import SwiftUI

struct InterstitialEditorView: View {
    @ObservedObject var manager: InterstitialManager
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()
                .background(Color.white.opacity(0.1))

            // Text editor
            textEditorSection

            Divider()
                .background(Color.white.opacity(0.1))

            // Action bar
            actionBar
        }
        .frame(width: 520, height: 360)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .onAppear {
            // Focus the text editor on appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Edit Transcription")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Text("Polish with AI or send to your favorite apps")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Close button
            Button(action: { manager.dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.secondary.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Text Editor

    private var textEditorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Character count
            HStack {
                Spacer()
                Text("\(manager.editedText.count) chars")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                if manager.editedText != manager.originalText {
                    Button("Reset") {
                        manager.resetText()
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.accentColor)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)

            // Text editor
            TextEditor(text: $manager.editedText)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                        )
                )
                .focused($isTextFieldFocused)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        VStack(spacing: 10) {
            // Top row: Polish button + destinations
            HStack(spacing: 12) {
                // Polish button (LLM)
                Button(action: {
                    Task {
                        await manager.polishText()
                    }
                }) {
                    HStack(spacing: 4) {
                        if manager.isPolishing {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                        }
                        Text("Polish")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .disabled(manager.isPolishing || manager.editedText.isEmpty)
                .buttonStyle(.bordered)
                .help("Use AI to improve grammar and clarity")

                // Error message
                if let error = manager.polishError {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                        .lineLimit(1)
                }

                Spacer()

                // Quick destinations bar
                QuickOpenBar(
                    content: manager.editedText,
                    showCopyButton: false,
                    compactMode: true
                )
            }

            // Bottom row: Open in Talkie + Copy/Paste
            HStack(spacing: 12) {
                // Open in Talkie button (escape hatch)
                Button(action: { manager.openInTalkie() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up.on.square")
                            .font(.system(size: 10))
                        Text("Open in Talkie")
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Promote to full memo in Talkie")

                Spacer()

                // Copy button
                Button(action: { manager.copyAndDismiss() }) {
                    Text("Copy")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("c", modifiers: .command)

                // Paste button (primary action)
                Button(action: { manager.pasteAndDismiss() }) {
                    Text("Paste")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    InterstitialEditorView(manager: InterstitialManager.shared)
        .frame(width: 520, height: 360)
}
