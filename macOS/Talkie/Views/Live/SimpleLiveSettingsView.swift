//
//  SimpleLiveSettingsView.swift
//  Talkie
//
//  Simplified Live settings view that reuses Talkie components
//

import SwiftUI

/// Simple Live settings view for Talkie integration
struct SimpleLiveSettingsView: View {
    @ObservedObject private var liveSettings = LiveSettings.shared
    @State private var selectedTab: LiveSettingsTab = .general

    enum LiveSettingsTab: String, CaseIterable {
        case general = "General"
        case shortcuts = "Shortcuts"
        case audio = "Audio"
        case transcription = "Transcription"

        var icon: String {
            switch self {
            case .general: return "gear"
            case .shortcuts: return "command"
            case .audio: return "mic"
            case .transcription: return "waveform"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(alignment: .leading, spacing: 8) {
                Text("LIVE SETTINGS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                ForEach(LiveSettingsTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12))
                                .frame(width: 20)
                            Text(tab.rawValue)
                                .font(.system(size: 13))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .frame(width: 180)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedTab {
                    case .general:
                        generalSettings
                    case .shortcuts:
                        shortcutsSettings
                    case .audio:
                        audioSettings
                    case .transcription:
                        transcriptionSettings
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General")
                .font(.title2)
                .bold()

            Text("Live recording is always running in the background, capturing your voice when you speak.")
                .foregroundColor(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Show overlay when recording", isOn: $liveSettings.showOverlay)
                    Toggle("Auto-paste transcriptions", isOn: $liveSettings.autoPasteEnabled)
                    Toggle("Play sounds", isOn: $liveSettings.playSounds)
                }
                .padding(8)
            }
        }
    }

    private var shortcutsSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Shortcuts")
                .font(.title2)
                .bold()

            Text("Configure keyboard shortcuts for Live actions.")
                .foregroundColor(.secondary)

            Text("⚠️ Shortcut configuration coming soon")
                .foregroundColor(.orange)
        }
    }

    private var audioSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Audio")
                .font(.title2)
                .bold()

            Text("Configure microphone and audio settings.")
                .foregroundColor(.secondary)

            Text("⚠️ Audio device selection coming soon")
                .foregroundColor(.orange)
        }
    }

    private var transcriptionSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcription")
                .font(.title2)
                .bold()

            Text("Configure the transcription engine.")
                .foregroundColor(.secondary)

            Text("⚠️ Engine configuration coming soon")
                .foregroundColor(.orange)
        }
    }
}
