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
    private var otherPresets: [WatchPreset] {
        WatchPreset.presets.filter { $0.id != "go" }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Title
                Text("TALKIE")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white)
                    .padding(.top, 6)

                // Big GO button
                GoButton {
                    selectAndRecord(goPreset)
                }

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
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: preset.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(preset.color)

                Text(preset.name)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
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
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.08))
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
