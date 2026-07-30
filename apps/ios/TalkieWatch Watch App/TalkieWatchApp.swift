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
                .onOpenURL { url in
                    deepLinkHandler.handle(url: url)
                }
        }
    }
}

// MARK: - Main Watch View

struct MainWatchView: View {
    private enum PrimaryPage: Hashable {
        case capture
        case codex
    }

    @EnvironmentObject var sessionManager: WatchSessionManager
    @EnvironmentObject var deepLinkHandler: DeepLinkHandler
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
                        PresetPickerView(
                            selectedPreset: $selectedPreset,
                            isRecording: $isRecording
                        )
                        .tag(PrimaryPage.capture)

                        CodexWatchView(isActive: primaryPage == .codex)
                            .tag(PrimaryPage.codex)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .toolbar {
                if !isRecording {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            WatchMoreView()
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("More Talkie screens")
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
