//
//  TalkieChromeBar.swift
//  Talkie
//
//  Chrome-anchored Talkie button + hover-reveal nav strip.
//  Replaces GlobalActionBar at the top-center of the content area.
//
//  Visual identity comes from the studio Shape A prototype:
//    `design/studio/components/studies/MacTalkieButton.tsx` →
//    HoverRevealStrip + InteractiveChrome + InteractiveStrip.
//  Tonally: cream paper, amber accent (Scope palette), not gunmetal.
//
//  Interaction model:
//    - Default       : horizontal pill — [amber mark][TALKIE][⌘K]
//    - Hover         : nav strip drops in below (cream paper row,
//                      amber-bordered selected slot)
//    - Click pill    : starts (or stops) memo recording directly.
//                      Intent recognition happens *inside* the memo
//                      — the primary verb is record, not search.
//
//  Recording / processing state lives in the notch — this bar stays
//  visually quiet so the chrome doesn't compete with the notch.
//

import SwiftUI
import TalkieKit

// MARK: - Strip taxonomy

private struct ChromeNavSlot: Identifiable {
    let id: String
    let label: String
    let icon: String
    let section: NavigationSection

    init(label: String, icon: String, section: NavigationSection) {
        self.id = label
        self.label = label
        self.icon = icon
        self.section = section
    }
}

// Settings sits in the window toolbar's trailing slot — not in the
// chrome bar strip. The strip is for primary section navigation; settings
// is configuration, a different register. With Settings out, the strip
// is 6 chips that split naturally 3+3 around the pill.
private let chromeNavSlots: [ChromeNavSlot] = [
    .init(label: "Home",       icon: "house",             section: .home),
    .init(label: "Library",    icon: "square.grid.2x2",   section: .recordings),
    .init(label: "Compose",    icon: "square.and.pencil", section: .drafts),
    .init(label: "Learn",      icon: "lightbulb",         section: .liveDashboard),
    .init(label: "Workflows",  icon: "wand.and.stars",    section: .workflows),
    .init(label: "Terminal",   icon: "terminal",          section: .systemConsole)
]

// MARK: - Tuning constants

private enum ChromeMetrics {
    static let pillHeight: CGFloat = 26
    static let slotWidth: CGFloat = 112       // Matches studio Shape A
    static let stripChipSize: CGFloat = 22
    static let barRadius: CGFloat = 10
    static let popResponse: Double = 0.24
    static let popDamping: Double = 0.78

    // Inline-with-pill chip metrics. With Settings moved to the window
    // toolbar, the strip is 3+3 around the pill — naturally symmetric,
    // so the cluster width is just the natural sum of 3 chips.
    static let inlineChipWidth: CGFloat = 92
    static let inlineChipSpacing: CGFloat = 4
    static let inlineClusterWidth: CGFloat = 3 * inlineChipWidth + 2 * inlineChipSpacing  // 284
}

private enum ChromeTone {
    // Warm cream/paper/ink palette — matches studio Shape A.
    static let paper      = Color(red: 0.957, green: 0.945, blue: 0.918)  // #F4F1EA
    static let paperHover = Color(red: 0.949, green: 0.937, blue: 0.902)  // #F2EFE6
    static let ink        = Color(red: 0.165, green: 0.149, blue: 0.125)  // #2A2620
    static let cream      = Color(red: 0.984, green: 0.984, blue: 0.980)  // #FBFBFA
    static let edge       = Color(red: 0.878, green: 0.863, blue: 0.827)  // #E0DCD3
    static let mutedInk   = Color(red: 0.353, green: 0.333, blue: 0.298)  // #5A554C
    static let subtleInk  = Color(red: 0.659, green: 0.635, blue: 0.592)  // #A8A29E
}

// MARK: - Chrome bar

struct TalkieChromeBar: View {
    private var nav: NavigationState { NavigationState.shared }
    private let controller = MemoRecordingController.shared
    private let header = ChromeBarHeader.shared

    private var isRecording: Bool { controller.state.isRecording }
    private var isProcessing: Bool { controller.state.isProcessing }

    // Split chips 3 + 3 around the pill — naturally symmetric so the
    // pill sits at the geometric center without needing fixed cluster
    // widths to balance.
    private static let leftSlots = Array(chromeNavSlots.prefix(3))
    private static let rightSlots = Array(chromeNavSlots.suffix(3))

    var body: some View {
        HStack(spacing: 0) {
            // Left cluster — fixed width, chips right-aligned against pill.
            // Equal cluster widths on both sides keep the pill at the
            // HStack's geometric center even though the chip split is 3+4.
            HStack(spacing: ChromeMetrics.inlineChipSpacing) {
                Spacer(minLength: 0)
                if header.hovered {
                    ForEach(Self.leftSlots) { slot in
                        ChromeNavInlineChip(slot: slot, isSelected: nav.selectedSection == slot.section) {
                            nav.navigate(to: slot.section)
                        }
                    }
                }
            }
            .frame(width: header.hovered ? ChromeMetrics.inlineClusterWidth : 0)
            .clipped()

            TalkieChromePill(
                isRecording: isRecording,
                isProcessing: isProcessing,
                elapsedTime: controller.elapsedTime,
                audioLevel: controller.audioLevel,
                onTap: toggleMemoRecording
            )
            .padding(.horizontal, header.hovered ? 8 : 0)

            // Right cluster — fixed width, chips left-aligned against pill.
            HStack(spacing: ChromeMetrics.inlineChipSpacing) {
                if header.hovered {
                    ForEach(Self.rightSlots) { slot in
                        ChromeNavInlineChip(slot: slot, isSelected: nav.selectedSection == slot.section) {
                            nav.navigate(to: slot.section)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(width: header.hovered ? ChromeMetrics.inlineClusterWidth : 0)
            .clipped()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: ChromeMetrics.barRadius)
                .fill(ChromeTone.paper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ChromeMetrics.barRadius)
                .strokeBorder(ChromeTone.edge, lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
        .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
        .onHover { hovering in
            withAnimation(.spring(response: ChromeMetrics.popResponse,
                                  dampingFraction: ChromeMetrics.popDamping)) {
                header.hovered = hovering
            }
        }
    }

    private func toggleMemoRecording() {
        if isRecording {
            controller.stopRecording()
        } else {
            controller.startRecording()
        }
    }
}

// MARK: - Central pill — [mark][TALKIE][⌘K]

private struct TalkieChromePill: View {
    let isRecording: Bool
    let isProcessing: Bool
    let elapsedTime: TimeInterval
    let audioLevel: Float
    let onTap: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                TalkieMark(glow: hovered, isActive: isRecording || isProcessing)

                if isRecording {
                    Text("REC")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(2.0)
                        .foregroundStyle(Color.red.opacity(0.92))

                    Text(formatElapsed(elapsedTime))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(ChromeTone.cream)
                        .monospacedDigit()

                    LiveWaveformBars(
                        audioLevel: audioLevel,
                        isRecording: true,
                        color: ChromeTone.cream
                    )
                    .frame(width: 70, height: 16)
                } else {
                    Text("TALKIE")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(2.0)
                        .foregroundStyle(ChromeTone.cream)

                    Text("⌘K")
                        .font(.system(size: 9, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(ChromeTone.cream.opacity(0.5))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: ChromeMetrics.pillHeight)
            .background(
                Capsule()
                    .fill(ChromeTone.ink)
            )
            .overlay(
                // Stroke only appears on hover — recording state is
                // already conveyed by REC text + live waveform inside
                // the pill; an outer ring just adds chrome on chrome.
                Capsule()
                    .strokeBorder(ScopeAmber.solid, lineWidth: hovered ? 1.5 : 0)
                    .opacity(0.30)
            )
            .shadow(color: Color.black.opacity(0.14), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovered = $0 }
        .help(helpText)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isRecording)
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: hovered)
    }

    private var ringColor: Color {
        if isRecording { return Color.red }
        return ScopeAmber.solid
    }

    private var helpText: String {
        if isRecording { return "Stop recording memo" }
        return "Record memo — click to start"
    }

    private func formatElapsed(_ time: TimeInterval) -> String {
        let total = Int(time)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Talkie mark (amber concentric ring + dot)

private struct TalkieMark: View {
    let glow: Bool
    let isActive: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(ScopeAmber.solid.opacity(0.45), lineWidth: 1)
                .frame(width: 11, height: 11)

            Circle()
                .fill(ScopeAmber.solid)
                .frame(width: 6, height: 6)
                .shadow(
                    // Amber glow only on hover. During recording, the
                    // REC label + waveform carry the signal — adding
                    // an amber light reads as noise alongside the red
                    // recording cue.
                    color: glow ? ScopeAmber.glowStrong : .clear,
                    radius: glow ? 4 : 0
                )
        }
    }
}

// MARK: - Nav strip slot (horizontal icon + label, amber accent)

private struct ChromeNavInlineChip: View {
    let slot: ChromeNavSlot
    let isSelected: Bool
    let action: () -> Void

    @State private var hovered = false

    private var isActive: Bool { isSelected || hovered }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: slot.icon)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isActive ? ScopeAmber.solid : ChromeTone.subtleInk)
                    .frame(width: 12)

                Text(slot.label.uppercased())
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(isActive ? ChromeTone.ink : ChromeTone.mutedInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 4)
            .frame(width: ChromeMetrics.inlineChipWidth, height: ChromeMetrics.pillHeight)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(hovered ? ChromeTone.paperHover : Color.clear)
            )
            .overlay(alignment: .bottom) {
                if isSelected {
                    Rectangle()
                        .fill(ScopeAmber.solid)
                        .frame(height: 1.5)
                        .padding(.horizontal, 4)
                }
            }
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovered = $0 }
        .help(slot.label)
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}
