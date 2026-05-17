//
//  KeyboardSettingsView.swift
//  Talkie iOS
//
//  Settings screen for TalkieKeys keyboard configuration.
//  Consolidates setup instructions, preferences, and testing in one place.
//

import SwiftUI
import TalkieMobileKit

struct KeyboardSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var headlessService = HeadlessDictationService.shared
    @State private var appSettings = TalkieAppSettings.shared

    @State private var showingPlayground = false
    @State private var setupExpanded = false

    var body: some View {
        @Bindable var appSettings = appSettings

        ZStack {
            Color.surfacePrimary
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Setup Instructions
                    setupSection

                    // Preferences
                    preferencesSection

                    // Customize
                    customizeSection

                    // Testing
                    testingSection

                    Spacer(minLength: 40)
                }
                .padding(.top, Spacing.md)
            }
        }
        .navigationTitle("Keyboard Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                KeyboardModeToggle(
                    isEnabled: Binding(
                        get: { headlessService.isActive },
                        set: { newValue in
                            if newValue {
                                headlessService.activate()
                            } else {
                                headlessService.deactivate(explicit: true)
                            }
                        }
                    )
                )
            }
        }
        .fullScreenCover(isPresented: $showingPlayground) {
            KeyboardView()
        }
    }

    // MARK: - Setup Section

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            TalkieEyebrow(text: "Setup Instructions")
                .padding(.horizontal, Spacing.md)

            VStack(spacing: 0) {
                // Expandable instructions
                DisclosureGroup(
                    isExpanded: $setupExpanded,
                    content: {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            setupStep(number: "1", text: "Go to Settings > General > Keyboard")
                            setupStep(number: "2", text: "Tap \"Keyboards\"")
                            setupStep(number: "3", text: "Tap \"Add New Keyboard...\"")
                            setupStep(number: "4", text: "Select \"Talkie\"")
                            setupStep(number: "5", text: "Tap Talkie and enable \"Allow Full Access\"")
                        }
                        .padding(.top, Spacing.sm)
                    },
                    label: {
                        HStack {
                            Image(systemName: "list.number")
                                .font(.system(size: 14, weight: .light))
                                .foregroundColor(.active)
                                .frame(width: 24, height: 24)

                            Text("How to add Talkie keyboard")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.textPrimary)

                            Spacer()
                        }
                    }
                )
                .padding(Spacing.sm)
                .tint(.textSecondary)

                Divider()
                    .background(Color.borderPrimary)

                // Open Settings button
                Button(action: openSettings) {
                    HStack {
                        Image(systemName: "gear")
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(.active)
                            .frame(width: 24, height: 24)

                        Text("Open Settings")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.textPrimary)

                        Spacer()

                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                    }
                    .padding(Spacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
            .background(Color.surfaceSecondary)
            .cornerRadius(CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
            )
            .padding(.horizontal, Spacing.md)
        }
    }

    private func setupStep(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Text(number)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Color.active)
                .cornerRadius(10)

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Preferences Section

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            TalkieEyebrow(text: "Preferences")
                .padding(.horizontal, Spacing.md)

            VStack(spacing: 0) {
                preferenceToggle(
                    icon: "light.max",
                    title: "LED Indicators",
                    description: "Visual feedback in keyboard",
                    isOn: $appSettings.keyboardLEDIndicatorsEnabled
                )

                Divider()
                    .background(Color.borderPrimary)

                preferenceToggle(
                    icon: "hand.tap",
                    title: "Haptic Feedback",
                    description: "Vibration on key presses",
                    isOn: $appSettings.keyboardHapticFeedbackEnabled
                )

                Divider()
                    .background(Color.borderPrimary)

                preferenceToggle(
                    icon: "textformat",
                    title: "Auto-Capitalize",
                    description: "Capitalize first letter of sentences",
                    isOn: $appSettings.keyboardAutoCapitalizeEnabled
                )

                Divider()
                    .background(Color.borderPrimary)

                gridPresetPickerRow
            }
            .background(Color.surfaceSecondary)
            .cornerRadius(CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
            )
            .padding(.horizontal, Spacing.md)
        }
    }

    private var gridPresetPickerRow: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "rectangle.grid.2x2")
                .font(.system(size: 14, weight: .light))
                .foregroundColor(.active)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("Keypad Format")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.textPrimary)

                Text("Choose command-grid density")
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            Picker("Keypad Format", selection: $appSettings.keyboardGridPreset) {
                ForEach(KeyboardGridPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(.textPrimary)
        }
        .padding(Spacing.sm)
    }

    private func preferenceToggle(
        icon: String,
        title: String,
        description: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .light))
                .foregroundColor(.active)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.textPrimary)

                Text(description)
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.active)
        }
        .padding(Spacing.sm)
    }

    // MARK: - Customize Section

    private var customizeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            TalkieEyebrow(text: "Customize")
                .padding(.horizontal, Spacing.md)

            NavigationLink(destination: KeyboardConfiguratorView()) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(.active)
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Customize Keys")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.textPrimary)

                        Text("Configure what each key does")
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                .padding(Spacing.sm)
                .background(Color.surfaceSecondary)
                .cornerRadius(CornerRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, Spacing.md)
        }
    }

    // MARK: - Testing Section

    private var testingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            TalkieEyebrow(text: "Testing")
                .padding(.horizontal, Spacing.md)

            VStack(spacing: 0) {
                Button(action: { showingPlayground = true }) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "rectangle.and.pencil.and.ellipsis")
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(.active)
                            .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Keyboard Playground")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.textPrimary)

                            Text("Test keyboard without switching apps")
                                .font(.system(size: 12, weight: .light))
                                .foregroundColor(.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                    }
                    .padding(Spacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())

                Divider()
                    .background(Color.borderPrimary)

                Button(action: openKeyboardLanding) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "arrowshape.turn.up.right")
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(.active)
                            .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open Keyboard")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.textPrimary)

                            Text("Jump straight to keyboard landing")
                                .font(.system(size: 12, weight: .light))
                                .foregroundColor(.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                    }
                    .padding(Spacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
            .background(Color.surfaceSecondary)
            .cornerRadius(CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
            )
            .padding(.horizontal, Spacing.md)
        }
    }

    // MARK: - Actions

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func openKeyboardLanding() {
        guard let url = URL(string: "talkie://keyboard") else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    NavigationView {
        KeyboardSettingsView()
    }
}
