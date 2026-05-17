//
//  ActionDock.swift
//  Talkie iOS
//
//  Bottom action bar with Terminal, Record, and Keyboard buttons.
//  Supports push-to-talk with expandable visualization.
//

import SwiftUI
import UIKit

enum ActionDockTerminalState {
    case pair
    case open
    case resume
}

// MARK: - Live-Adjustable Layout Settings

#if DEBUG
/// Singleton for live-tweaking dock layout in debug builds
class DockLayoutSettings: ObservableObject {
    static let shared = DockLayoutSettings()

    // Direct padding controls
    @Published var topPadding: CGFloat = 18
    @Published var bottomPadding: CGFloat = 20
    @Published var horizontalPadding: CGFloat = 14

    // Button sizes
    @Published var recordButtonSize: CGFloat = 70
    @Published var sideButtonSize: CGFloat = 48

    // Scroll content padding (how much space to leave for the dock)
    @Published var reservedScrollSpace: CGFloat = 84

    // Whether buttons extend into safe area
    @Published var ignoreBottomSafeArea: Bool = true

    private init() {}
}
#endif

// Shared by Action dock and compose tray; DEBUG values track `DockLayoutSettings`.
enum DockLayout {
    #if DEBUG
    static var topPadding: CGFloat { DockLayoutSettings.shared.topPadding }
    static var bottomPadding: CGFloat { DockLayoutSettings.shared.bottomPadding }
    static var horizontalPadding: CGFloat { DockLayoutSettings.shared.horizontalPadding }
    static var recordButtonSize: CGFloat { DockLayoutSettings.shared.recordButtonSize }
    static var sideButtonSize: CGFloat { DockLayoutSettings.shared.sideButtonSize }
    #else
    static let topPadding: CGFloat = 18
    static let bottomPadding: CGFloat = 20
    static let horizontalPadding: CGFloat = 14
    static let recordButtonSize: CGFloat = 70
    static let sideButtonSize: CGFloat = 48
    #endif
}

/// Bottom action dock - the primary control bar for the app
/// Contains: Terminal (left) - Record (center) - Keyboard (right)
struct ActionDock: View {
    // MARK: - Layout Settings (for live updates)
    #if DEBUG
    @ObservedObject private var layoutSettings = DockLayoutSettings.shared
    #endif

    @ObservedObject private var themeManager = ThemeManager.shared
    private var themeColors: ThemeColors { themeManager.colors }
    private var chrome: ChromeTokens { themeManager.chrome }
    private var isScopeTheme: Bool { themeManager.currentTheme.isScope }

    // MARK: - Bindings
    @Binding var showingRecordingView: Bool
    @Binding var showingKeyboard: Bool
    @Binding var showingSSHTerminal: Bool
    @Binding var showingCaptureLauncher: Bool
    @Binding var showingCaptureCompose: Bool
    @Binding var showingCompose: Bool
    @Binding var contentFilter: ContentFilter

    // MARK: - Entry state
    let terminalState: ActionDockTerminalState

    // MARK: - Callbacks
    var onTerminalTapped: (() -> Void)?

    // MARK: - Initializer

    init(
        showingRecordingView: Binding<Bool>,
        showingKeyboard: Binding<Bool>,
        showingSSHTerminal: Binding<Bool>,
        showingCaptureLauncher: Binding<Bool>,
        showingCaptureCompose: Binding<Bool>,
        showingCompose: Binding<Bool>,
        contentFilter: Binding<ContentFilter>,
        terminalState: ActionDockTerminalState,
        onTerminalTapped: (() -> Void)? = nil
    ) {
        self._showingRecordingView = showingRecordingView
        self._showingKeyboard = showingKeyboard
        self._showingSSHTerminal = showingSSHTerminal
        self._showingCaptureLauncher = showingCaptureLauncher
        self._showingCaptureCompose = showingCaptureCompose
        self._showingCompose = showingCompose
        self._contentFilter = contentFilter
        self.terminalState = terminalState
        self.onTerminalTapped = onTerminalTapped
    }

    var body: some View {
        buttonRow
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .background {
            if isScopeTheme {
                ZStack {
                    ScopeMobile.canvas.opacity(0.94)
                    ScopeMobileGraticuleBackground(
                        pitch: 32,
                        color: ScopeMobile.edgeSubtle,
                        opacity: 0.58
                    )
                }
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(ScopeMobile.edgeFaint)
                        .frame(height: 1)
                }
            } else if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 0))
                    .ignoresSafeArea(edges: .bottom)
            } else {
                themeColors.cardBackground.opacity(0.95)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .background {
            if #unavailable(iOS 26.0), !isScopeTheme {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(chrome.edgeFaint)
                        .frame(height: chrome.hairlineWidth)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Button Row

    private var buttonRow: some View {
        HStack(spacing: 0) {
            terminalButton
                .frame(width: DockLayout.sideButtonSize, height: DockLayout.sideButtonSize)

            Spacer()

            // Center button (context-aware: mic for memos, + for captures)
            centerButton

            Spacer()

            composeButton
                .frame(width: DockLayout.sideButtonSize, height: DockLayout.sideButtonSize)
        }
        .padding(.horizontal, DockLayout.horizontalPadding)
        .padding(.top, DockLayout.topPadding)
        .padding(.bottom, DockLayout.bottomPadding)
        #if DEBUG
        .padding(.bottom, layoutSettings.ignoreBottomSafeArea ? -34 : 0)
        #endif
    }

    private var terminalButton: some View {
        BottomCircleButton(
            icon: terminalIcon,
            isActive: terminalState == .resume
        ) {
            if let onTerminalTapped {
                onTerminalTapped()
            } else {
                showingSSHTerminal = true
            }
        }
        .accessibilityIdentifier("dock.ssh")
        .accessibilityLabel(terminalAccessibilityLabel)
        .accessibilityHint(terminalAccessibilityHint)
    }

    // MARK: - Compose Button

    private var composeButton: some View {
        BottomCircleButton(
            icon: "square.and.pencil",
            isActive: false
        ) {
            showingCompose = true
        }
        .accessibilityIdentifier("dock.compose")
        .accessibilityLabel("Open compose")
        .accessibilityHint("Opens the compose tool for drafting, editing, and revising text with AI.")
    }

    // MARK: - Center Button (context-aware)

    private var centerButton: some View {
        ZStack {
            Circle()
                .fill(centerButtonColor)
                .frame(width: DockLayout.recordButtonSize, height: DockLayout.recordButtonSize)
                .overlay(
                    Circle()
                        .strokeBorder(centerButtonGlowColor.opacity(0.4), lineWidth: 1)
                )

            Image(systemName: centerButtonIcon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: DockLayout.recordButtonSize, height: DockLayout.recordButtonSize)
        .contentShape(Circle())
        .gesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    let impact = UIImpactFeedbackGenerator(style: .rigid)
                    impact.impactOccurred()
                    showingCaptureCompose = true
                }
                .exclusively(
                    before: TapGesture()
                        .onEnded {
                            triggerCurrentMode()
                        }
                )
        )
        .accessibilityIdentifier("dock.center")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Tap to start the selected input mode. Long press to open Capture.")
    }

    private func triggerCurrentMode() {
        switch contentFilter {
        case .memos:
            showingRecordingView = true
        case .dictations:
            showingKeyboard = true
        case .captures:
            showingCaptureCompose = true
        }
    }

    private var centerButtonIcon: String {
        switch contentFilter {
        case .memos: return "mic.fill"
        case .dictations: return "character.cursor.ibeam"
        case .captures: return "plus"
        }
    }

    private var centerButtonColor: Color {
        if isScopeTheme {
            return ScopeMobile.amber
        }

        switch contentFilter {
        case .memos: return .memoAccent
        case .dictations: return .brandAccent
        case .captures: return .accentColor
        }
    }

    private var centerButtonGlowColor: Color {
        if isScopeTheme {
            return ScopeMobile.amberGlow
        }

        switch contentFilter {
        case .memos: return .memoAccentGlow
        case .dictations: return .brandAccent
        case .captures: return .accentColor
        }
    }

    // MARK: - Helpers

    private var terminalIcon: String {
        "terminal"
    }

    private var terminalAccessibilityLabel: String {
        "Terminal"
    }

    private var terminalAccessibilityHint: String {
        switch terminalState {
        case .pair:
            return "Open Mac pairing and terminal setup."
        case .open:
            return "Choose a Mac and terminal session."
        case .resume:
            return "Return to your most recent terminal session."
        }
    }

}

// MARK: - Bottom Circle Button

/// Circular button used in the action dock
struct BottomCircleButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void

    @ObservedObject private var themeManager = ThemeManager.shared
    private var chrome: ChromeTokens { themeManager.chrome }
    private var isScopeTheme: Bool { themeManager.currentTheme.isScope }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(buttonForeground)
                .frame(width: 44, height: 44)
                .background {
                    if isScopeTheme {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(ScopeMobile.surface.opacity(0.84))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(ScopeMobile.edgeFaint, lineWidth: 0.75)
                            }
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isActive ? chrome.accentTint : Color.clear)
                            .glassEffect(.regular.interactive())
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(
                                        isActive ? chrome.accent.opacity(0.40) : chrome.edgeFaint,
                                        lineWidth: chrome.hairlineWidth
                                    )
                            }
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var buttonForeground: Color {
        if isScopeTheme {
            return isActive ? ScopeMobile.amber : ScopeMobile.inkMuted
        }

        return isActive ? chrome.accent : themeManager.colors.textSecondary
    }
}

// MARK: - Debug Controls

#if DEBUG
/// Debug content for adjusting dock layout in real-time
struct DockLayoutDebugContent: View {
    @ObservedObject private var settings = DockLayoutSettings.shared

    var body: some View {
        DebugSection(title: "ACTION DOCK") {
            VStack(spacing: 8) {
                DebugSlider(label: "Top Pad", value: $settings.topPadding, range: 0...40)
                DebugSlider(label: "Bot Pad", value: $settings.bottomPadding, range: 0...20)
                DebugSlider(label: "H Pad", value: $settings.horizontalPadding, range: 0...30)
                DebugSlider(label: "Rec Size", value: $settings.recordButtonSize, range: 44...80)
                DebugSlider(label: "Side Size", value: $settings.sideButtonSize, range: 32...60)
                DebugSlider(label: "Reserved", value: $settings.reservedScrollSpace, range: 60...120)

                // Reset button
                Button(action: resetToDefaults) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10))
                        Text("Reset")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(.orange)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func resetToDefaults() {
        settings.topPadding = 18
        settings.bottomPadding = 20
        settings.horizontalPadding = 14
        settings.recordButtonSize = 70
        settings.sideButtonSize = 48
        settings.reservedScrollSpace = 84
    }
}

/// Floating inline overlay for live tweaking - drag to reposition
struct DockLayoutInlineOverlay: View {
    @ObservedObject private var settings = DockLayoutSettings.shared
    @State private var isExpanded = true
    @State private var offset: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header - tap to collapse
            HStack {
                Text("DOCK LAYOUT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.blue)
            .onTapGesture { withAnimation { isExpanded.toggle() } }

            if isExpanded {
                VStack(spacing: 6) {
                    // Padding controls
                    Text("PADDING")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    DebugSlider(label: "Top", value: $settings.topPadding, range: 0...40)
                    DebugSlider(label: "Bottom", value: $settings.bottomPadding, range: 0...30)
                    DebugSlider(label: "Scroll", value: $settings.reservedScrollSpace, range: 50...130)

                    Divider().background(Color.white.opacity(0.2)).padding(.vertical, 4)

                    // Button sizes
                    Text("BUTTONS")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    DebugSlider(label: "Record", value: $settings.recordButtonSize, range: 44...80)
                    DebugSlider(label: "Side", value: $settings.sideButtonSize, range: 32...60)

                    Divider().background(Color.white.opacity(0.2)).padding(.vertical, 4)

                    // Safe area toggle
                    Toggle(isOn: $settings.ignoreBottomSafeArea) {
                        Text("Ignore Safe Area")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .blue))

                    Button("Reset") {
                        settings.topPadding = 18
                        settings.bottomPadding = 20
                        settings.horizontalPadding = 14
                        settings.recordButtonSize = 70
                        settings.sideButtonSize = 48
                        settings.reservedScrollSpace = 84
                        settings.ignoreBottomSafeArea = true
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.orange)
                    .padding(.top, 4)
                }
                .padding(10)
                .background(Color.black.opacity(0.85))
            }
        }
        .frame(width: 200)
        .cornerRadius(8)
        .shadow(radius: 10)
        .offset(offset)
        .gesture(
            DragGesture()
                .onChanged { offset = $0.translation }
                .onEnded { _ in }
        )
    }
}

/// Compact slider for debug panel
struct DebugSlider: View {
    let label: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(Color.textSecondary)
                .frame(width: 55, alignment: .leading)

            Slider(value: $value, in: range)
                .tint(Color.active)

            Text("\(Int(value))")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(Color.textPrimary)
                .frame(width: 24, alignment: .trailing)
        }
    }
}
#endif

#Preview {
    VStack(spacing: 0) {
        Spacer()
        ActionDock(
            showingRecordingView: .constant(false),
            showingKeyboard: .constant(false),
            showingSSHTerminal: .constant(false),
            showingCaptureLauncher: .constant(false),
            showingCaptureCompose: .constant(false),
            showingCompose: .constant(false),
            contentFilter: .constant(.memos),
            terminalState: .open
        )
    }
    .background(Color.black.ignoresSafeArea())
}
