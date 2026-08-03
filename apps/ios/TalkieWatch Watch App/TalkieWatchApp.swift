//
//  TalkieWatchApp.swift
//  TalkieWatch Watch App
//
//  Created by Arach Tchoupani on 2025-12-12.
//

import SwiftUI
import WatchKit
import TalkieMobileKit

// MARK: - Deep Link Handler

@MainActor
final class DeepLinkHandler: ObservableObject {
    static let shared = DeepLinkHandler()

    @Published var pendingPresetId: String?

    func handle(url: URL) {
        WatchConsole.info("⌚️ [Watch] Deep link received: \(url)")

        // URL format: talkie://record/quick or talkie://record/thought
        guard url.scheme == "talkie",
              url.host == "record" else {
            return
        }

        // Get preset ID from path
        let presetId = url.pathComponents.count > 1 ? url.pathComponents[1] : "quick"
        WatchConsole.info("⌚️ [Watch] Starting recording with preset: \(presetId)")

        pendingPresetId = presetId

        // Haptic feedback
        WKInterfaceDevice.current().play(.start)
    }

    func consumePendingPreset() -> WatchPreset? {
        guard let presetId = pendingPresetId else { return nil }
        pendingPresetId = nil

        return WatchPreset.presets.first { $0.id == presetId } ?? .go
    }
}

// MARK: - App

@main
struct TalkieWatchApp: App {
    @StateObject private var sessionManager = WatchSessionManager.shared
    @StateObject private var deepLinkHandler = DeepLinkHandler.shared

    init() {
        TalkieLogger.configure(source: .talkieWatch)
    }

    var body: some Scene {
        WindowGroup {
            MainWatchView()
                .environmentObject(sessionManager)
                .environmentObject(deepLinkHandler)
                .environment(
                    \.watchThemeName,
                    WatchThemeName(rawValue: sessionManager.appearanceThemeName) ?? .porcelain
                )
                .onOpenURL { url in
                    deepLinkHandler.handle(url: url)
                }
        }
    }
}

// MARK: - Main Watch View

struct MainWatchView: View {
    /// Capture stays the landing page. Asks sits one swipe left and Codex one
    /// swipe right, so the two "what is happening elsewhere" surfaces bracket
    /// the one thing the wearer came here to do.
    private enum PrimaryPage: Hashable {
        case asks
        case capture
        case codex
    }

    @EnvironmentObject var sessionManager: WatchSessionManager
    @EnvironmentObject var deepLinkHandler: DeepLinkHandler
    @Environment(\.watchThemeName) private var themeName
    @State private var selectedPreset: WatchPreset?
    @State private var isRecording = false
    @State private var primaryPage: PrimaryPage = .capture

    var body: some View {
        NavigationStack {
            Group {
                if isRecording, let preset = selectedPreset {
                    PresetRecordingView(
                        preset: preset,
                        isRecording: $isRecording,
                        onComplete: {
                            selectedPreset = nil
                        }
                    )
                } else {
                    TabView(selection: $primaryPage) {
                        AsksWatchView(isActive: primaryPage == .asks)
                            .tag(PrimaryPage.asks)

                        PresetPickerView(
                            selectedPreset: $selectedPreset,
                            isRecording: $isRecording,
                            onOpenAsks: { primaryPage = .asks }
                        )
                        .tag(PrimaryPage.capture)

                        CodexWatchView(isActive: primaryPage == .codex)
                            .tag(PrimaryPage.codex)
                    }
                    // Three pages need a page indicator; with two the swipe was
                    // discoverable enough without one.
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                }
            }
            .toolbar {
                if !isRecording {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            WatchMoreView()
                        } label: {
                            let capture = themeName.captureStyle
                            ZStack {
                                Circle()
                                    .fill(capture.material.secondaryFill.opacity(0.72))
                                    .overlay {
                                        Circle()
                                            .stroke(
                                                capture.material.secondaryEdge.opacity(0.58),
                                                lineWidth: 0.5
                                            )
                                    }
                                    .frame(width: 31, height: 31)

                                Image(systemName: "gearshape")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(capture.material.inkFaint.opacity(0.78))
                            }
                            .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Talkie settings")
                    }
                }
            }
        }
        .onAppear {
            checkPendingDeepLink()
        }
        .onChange(of: deepLinkHandler.pendingPresetId) { _, newValue in
            if newValue != nil {
                checkPendingDeepLink()
            }
        }
    }

    private func checkPendingDeepLink() {
        if let preset = deepLinkHandler.consumePendingPreset() {
            // Start recording immediately with this preset
            primaryPage = .capture
            selectedPreset = preset
            isRecording = true
        }
    }
}

private struct WatchMoreView: View {
    var body: some View {
        List {
            NavigationLink {
                WatchAppearanceView()
            } label: {
                Label("Style", systemImage: "circle.lefthalf.filled")
            }

            NavigationLink {
                RecentMemosView()
            } label: {
                Label("Recent", systemImage: "clock.arrow.circlepath")
            }

            NavigationLink {
                AboutView()
            } label: {
                Label("About", systemImage: "info.circle")
            }
        }
        .navigationTitle("Talkie")
    }
}

private struct WatchAppearanceView: View {
    @EnvironmentObject private var sessionManager: WatchSessionManager

    var body: some View {
        List {
            Button {
                sessionManager.setLocalAppearanceTheme(nil)
            } label: {
                appearanceRow(
                    title: "Follow iPhone",
                    theme: WatchTheme.syncedName,
                    isSelected: WatchTheme.localOverrideName == nil
                )
            }

            ForEach(WatchThemeName.allCases) { theme in
                Button {
                    sessionManager.setLocalAppearanceTheme(theme)
                } label: {
                    appearanceRow(
                        title: theme.displayName,
                        theme: theme,
                        isSelected: WatchTheme.localOverrideName == theme
                    )
                }
            }
        }
        .buttonStyle(.plain)
        .navigationTitle("Style")
    }

    private func appearanceRow(
        title: String,
        theme: WatchThemeName,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 9) {
            let style = theme.captureStyle
            Circle()
                .fill(style.material.field)
                .overlay {
                    Circle()
                        .trim(from: 0.08, to: 0.42)
                        .stroke(style.trace, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-24))
                        .padding(3)
                }
                .overlay {
                    Circle().stroke(Color.white.opacity(0.16), lineWidth: 0.5)
                }
                .frame(width: 24, height: 24)

            Text(title)
                .foregroundStyle(.primary)

            Spacer(minLength: 4)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.captureStyle.trace)
            }
        }
        .contentShape(Rectangle())
    }
}
