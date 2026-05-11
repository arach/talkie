//
//  KeyboardView.swift
//  Talkie
//
//  In-app keyboard playground for testing TalkieKeys,
//  learning features, and adjusting keyboard settings.
//
//  This screen helps validate keyboard behavior and inspect shared state
//  while HeadlessDictationService remains the only dictation request handler.
//

import SwiftUI
import TalkieMobileKit
import UIKit

struct KeyboardView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var composeText = Self.defaultComposePracticeText
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var headlessDictation = HeadlessDictationService.shared

    private let bridge = KeyboardBridge.shared
    private static let defaultComposePracticeText = """
    Cursor practice draft:
    Move through this sentence word by word, then edit it in place.

    Launch checklist:
    1. Verify keyboard picker opens Talkie reliably.
    2. Use joystick to jump left and right through this list.
    3. Insert a quick update after item two.
    """

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surfacePrimary
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Compose area
                    composeSection

                    Divider()
                        .background(Color.borderPrimary)

                    // Main content
                    ScrollView {
                        VStack(spacing: Spacing.lg) {
                            actionButtons
                            howItWorksSection
                            switchKeyboardHint
                        }
                        .padding(.vertical, Spacing.lg)
                        .frame(maxWidth: isIPad ? 600 : .infinity)
                        .frame(maxWidth: .infinity)
                    }
                }

                // Recording overlay removed - keyboard handles its own UI
            }
            .navigationTitle("Keyboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        cleanup()
                        dismiss()
                    }
                    .foregroundColor(.textPrimary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    KeyboardModeToggle(
                        isEnabled: Binding(
                            get: { headlessDictation.isActive },
                            set: { newValue in
                                if newValue {
                                    headlessDictation.activate()
                                } else {
                                    headlessDictation.deactivate(explicit: true)
                                }
                            }
                        )
                    )
                }
            }
        }
        .onAppear {
            setupKeyboard()
        }
        .onDisappear {
            cleanup()
        }
    }

    // MARK: - Compose Section

    private var composeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("COMPOSE")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.textTertiary.opacity(0.7))
                    .tracking(1.5)

                Spacer()

                if headlessDictation.isActive {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green.opacity(0.7))
                            .frame(width: 5, height: 5)
                        Text("READY")
                            .font(.system(size: 9, weight: .regular))
                            .foregroundColor(.green.opacity(0.7))
                    }
                }

                if !composeText.isEmpty {
                    Button(action: clearText) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.textTertiary.opacity(0.5))
                    }
                }
            }

            DarkKeyboardTextEditor(text: $composeText, placeholder: "Tap here to test the keyboard...")
                .frame(minHeight: isIPad ? 200 : 120, maxHeight: isIPad ? 360 : 200)
                .background(Color.surfaceSecondary)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.textTertiary.opacity(0.12), lineWidth: 0.5)
                )
                .accessibilityIdentifier("keyboard.compose")
        }
        .padding(Spacing.md)
        .frame(maxWidth: isIPad ? 600 : .infinity)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Action Buttons (side by side)

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button(action: {
                if let url = URL(string: "talkie://dictate") {
                    UIApplication.shared.open(url)
                }
            }) {
                actionCard(icon: "mic.fill", label: "Start Dictation")
            }

            NavigationLink(destination: KeyboardConfiguratorView()) {
                actionCard(icon: "slider.horizontal.3", label: "Edit Shortcuts")
            }
        }
        .padding(.horizontal, Spacing.md)
    }

    private func actionCard(icon: String, label: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .light))
                .foregroundColor(.textSecondary)
            Text(label)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .background(Color.surfaceSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.textTertiary.opacity(0.15), lineWidth: 0.5)
        )
        .cornerRadius(12)
    }

    // MARK: - How It Works

    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("HOW IT WORKS")

            VStack(spacing: 0) {
                howItWorksRow(icon: "globe", text: "Switch to Talkie keyboard via globe key")
                Divider().opacity(0.3).padding(.leading, 38)
                howItWorksRow(icon: "mic.fill", text: "Tap mic to dictate or use shortcuts")
                Divider().opacity(0.3).padding(.leading, 38)
                howItWorksRow(icon: "dpad.fill", text: "Use joystick long-press to move cursor")
            }
            .background(Color.surfaceSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.textTertiary.opacity(0.12), lineWidth: 0.5)
            )
            .cornerRadius(12)
        }
        .padding(.horizontal, Spacing.md)
    }

    private func howItWorksRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .light))
                .foregroundColor(.textTertiary.opacity(0.7))
                .frame(width: 20)

            Text(text)
                .font(.system(size: 13, weight: .light))
                .foregroundColor(.textSecondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: - Switch Keyboard Hint

    private var switchKeyboardHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.system(size: 13, weight: .light))
                .foregroundColor(.textTertiary.opacity(0.6))

            Text("Hold the globe key to switch keyboards")
                .font(.system(size: 12, weight: .light))
                .foregroundColor(.textTertiary.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Color.surfaceSecondary.opacity(0.4))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.textTertiary.opacity(0.1), lineWidth: 0.5)
        )
        .cornerRadius(10)
        .padding(.horizontal, Spacing.md)
    }

    // MARK: - Setup

    private func setupKeyboard() {
        AppLogger.app.info("Keyboard: Setting up")

        // Auto-enable keyboard mode via the service (single source of truth).
        // HeadlessDictationService owns bridge requests and shared-store state transitions.
        if !headlessDictation.isActive {
            headlessDictation.activate()
        }
    }

    private func cleanup() {
        AppLogger.app.info("Keyboard: Cleaning up")
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .regular))
            .foregroundColor(.textTertiary.opacity(0.6))
            .tracking(1.5)
    }

    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }

    private func clearText() {
        withAnimation {
            composeText = ""
        }
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
}

// MARK: - Dark Keyboard Text Editor

/// UITextView wrapper that sets keyboardAppearance = .dark so the
/// keyboard extension receives dark traits in our dark-themed app.
/// Forces dark interface style on the text view itself so all
/// dynamic colors resolve correctly without hardcoding.
private struct DarkKeyboardTextEditor: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()

        // Force dark trait resolution on this view — all UIColor dynamic
        // colors (label, secondarySystemBackground, etc.) resolve to dark values
        tv.overrideUserInterfaceStyle = .dark
        tv.keyboardAppearance = .dark

        // Match the SwiftUI TextEditor styling
        tv.font = .systemFont(ofSize: 15, weight: .light)
        tv.textColor = UIColor(Color.textPrimary)
        tv.backgroundColor = UIColor(Color.surfaceSecondary)
        tv.tintColor = UIColor(Color.textPrimary)
        tv.textContainerInset = UIEdgeInsets(top: 10, left: 4, bottom: 10, right: 4)
        tv.delegate = context.coordinator

        // Placeholder
        let label = UILabel()
        label.text = placeholder
        label.font = .systemFont(ofSize: 15, weight: .light)
        label.textColor = UIColor(Color.textTertiary).withAlphaComponent(0.5)
        label.tag = 100
        label.translatesAutoresizingMaskIntoConstraints = false
        tv.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: tv.leadingAnchor, constant: 9),
            label.topAnchor.constraint(equalTo: tv.topAnchor, constant: 10)
        ])
        label.isHidden = !text.isEmpty

        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text {
            tv.text = text
        }
        (tv.viewWithTag(100) as? UILabel)?.isHidden = !text.isEmpty
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: DarkKeyboardTextEditor

        init(_ parent: DarkKeyboardTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            (textView.viewWithTag(100) as? UILabel)?.isHidden = !textView.text.isEmpty
        }
    }
}

#Preview {
    KeyboardView()
}
