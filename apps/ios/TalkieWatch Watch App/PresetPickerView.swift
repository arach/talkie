//
//  PresetPickerView.swift
//  TalkieWatch
//
//  Timer-style preset picker for quick recording
//

import SwiftUI
import WatchKit

struct PresetPickerView: View {
    @EnvironmentObject var sessionManager: WatchSessionManager
    @Binding var selectedPreset: WatchPreset?
    @Binding var isRecording: Bool

    private var goPreset: WatchPreset { .go }
    private var aiPreset: WatchPreset { .ai }
    private var otherPresets: [WatchPreset] {
        WatchPreset.presets.filter { $0.id != "go" && $0.id != "ai" }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Title — themed eyebrow, accent tint
                WatchEyebrow(text: "Talkie", tint: .accent, showLeader: false)
                    .padding(.top, 6)

                // Big GO button
                GoButton {
                    selectAndRecord(goPreset)
                }

                TalkToAIButton {
                    selectAndRecord(aiPreset)
                }
                .padding(.horizontal, 4)

                // Other presets in a row
                HStack(spacing: 6) {
                    ForEach(otherPresets) { preset in
                        SmallPresetButton(preset: preset) {
                            selectAndRecord(preset)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
    }

    private func selectAndRecord(_ preset: WatchPreset) {
        WKInterfaceDevice.current().play(.click)
        selectedPreset = preset
        isRecording = true
    }
}

// MARK: - Talk to AI Button

struct TalkToAIButton: View {
    let action: () -> Void

    var body: some View {
        let chrome = WatchTheme.current
        Button(action: action) {
            HStack(spacing: 6) {
                // sparkles stays cyan — it's the AI signal across platforms
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.cyan)

                Text("Talk to AI")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(chrome.panelInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(chrome.panel.opacity(0.55))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(chrome.panelEdge, lineWidth: chrome.hairlineWidth)
            )
            .clipShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Big GO Button

struct GoButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // Glow
                Circle()
                    .fill(Color.red)
                    .frame(width: 90, height: 90)
                    .blur(radius: 20)
                    .opacity(0.5)

                // Filled circle (familiar start button)
                Circle()
                    .fill(Color.red)
                    .frame(width: 80, height: 80)

                // Bright white mic icon
                Image(systemName: "mic.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Small Preset Button

struct SmallPresetButton: View {
    let preset: WatchPreset
    let action: () -> Void

    var body: some View {
        let chrome = WatchTheme.current
        Button(action: action) {
            VStack(spacing: 4) {
                // preset.color is each preset's own identity — keep.
                Image(systemName: preset.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(preset.color)

                Text(preset.name)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(chrome.panelInk.opacity(0.85))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(preset.color.opacity(0.15))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preset Button

struct PresetButton: View {
    let preset: WatchPreset
    let action: () -> Void

    var body: some View {
        let chrome = WatchTheme.current
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(preset.color.opacity(0.2))
                        .frame(width: 44, height: 44)

                    Image(systemName: preset.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(preset.color)
                }

                Text(preset.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(chrome.panelInk)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(chrome.panel.opacity(0.40))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PresetPickerView(
        selectedPreset: .constant(nil),
        isRecording: .constant(false)
    )
    .environmentObject(WatchSessionManager.shared)
}
