//
//  VoiceIOSettings.swift
//  Talkie macOS
//
//  Dictation settings: Recording + Delivery tabs
//

import SwiftUI
import TalkieKit

private let log = Log(.ui)

// MARK: - Dictation Settings (Tabbed)

/// Dictation settings with Recording and Delivery tabs
struct VoiceIOSettingsView: View {
    @Environment(AgentSettings.self) private var liveSettings: AgentSettings
    @State private var expandedSection: VoiceIOSection? = .recording

    enum VoiceIOSection: String, CaseIterable {
        case recording = "RECORDING"
        case delivery = "DELIVERY"

        var icon: String {
            switch self {
            case .recording: return "mic.fill"
            case .delivery: return "arrow.right.doc.on.clipboard"
            }
        }

        var color: Color {
            switch self {
            case .recording: return .cyan
            case .delivery: return .blue
            }
        }

        var description: String {
            switch self {
            case .recording: return "Shortcuts, mic, sounds, HUD"
            case .delivery: return "Paste, drafts, context"
            }
        }
    }

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "mic.and.signal.meter",
                title: "DICTATION",
                subtitle: "Configure how dictation is captured and where transcribed text is delivered."
            )
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                // Tab bar
                HStack(spacing: 0) {
                    ForEach(VoiceIOSection.allCases, id: \.rawValue) { section in
                        tabItem(section)
                    }
                    Spacer()
                }
                .padding(.horizontal, Spacing.sm)

                // Tab indicator line
                Rectangle()
                    .fill(Theme.current.divider)
                    .frame(height: 1)

                // Content based on selected section
                ScrollView {
                    switch expandedSection {
                    case .recording:
                        DictationRecordingSettingsContent()
                            .padding(.top, Spacing.md)
                    case .delivery:
                        DictationDeliverySettingsContent()
                            .padding(.top, Spacing.md)
                    case .none:
                        Text("Select a tab above")
                            .font(Theme.current.fontSM)
                            .foregroundColor(Theme.current.foregroundSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(Spacing.xl)
                    }
                }
            }
        }
        .onAppear {
            log.debug("VoiceIOSettingsView appeared")
        }
    }

    @ViewBuilder
    private func tabItem(_ section: VoiceIOSection) -> some View {
        let isSelected = expandedSection == section

        Button(action: { expandedSection = section }) {
            VStack(spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: section.icon)
                        .font(.system(size: 11))

                    Text(section.rawValue)
                        .font(Theme.current.fontXSBold)
                }
                .foregroundColor(isSelected ? section.color : Theme.current.foregroundSecondary)
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xs)

                // Active indicator
                Rectangle()
                    .fill(isSelected ? section.color : Color.clear)
                    .frame(height: 2)
                    .cornerRadius(1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Voice I/O") {
    VoiceIOSettingsView()
        .environment(AgentSettings.shared)
        .frame(width: 600, height: 800)
}
