//
//  TalkieWatchApp.swift
//  TalkieWatch Watch App
//
//  Created by Arach Tchoupani on 2025-12-12.
//

import SwiftUI
import WatchKit

// MARK: - Deep Link Handler

@MainActor
final class DeepLinkHandler: ObservableObject {
    static let shared = DeepLinkHandler()

    @Published var pendingPresetId: String?

    func handle(url: URL) {
        print("⌚️ [Watch] Deep link received: \(url)")

        // URL format: talkie://record/quick or talkie://record/thought
        guard url.scheme == "talkie",
              url.host == "record" else {
            return
        }

        // Get preset ID from path
        let presetId = url.pathComponents.count > 1 ? url.pathComponents[1] : "quick"
        print("⌚️ [Watch] Starting recording with preset: \(presetId)")

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
    @EnvironmentObject var sessionManager: WatchSessionManager
    @EnvironmentObject var deepLinkHandler: DeepLinkHandler
    @State private var selectedPreset: WatchPreset?
    @State private var isRecording = false

    var body: some View {
        Group {
            if isRecording, let preset = selectedPreset {
                // Recording with preset
                PresetRecordingView(
                    preset: preset,
                    isRecording: $isRecording,
                    onComplete: {
                        selectedPreset = nil
                    }
                )
            } else {
                // Main navigation
                TabView {
                    // Preset picker (like Timer)
                    PresetPickerView(
                        selectedPreset: $selectedPreset,
                        isRecording: $isRecording
                    )
                    .tag(0)

                    // Recent memos
                    RecentMemosView()
                        .tag(1)

                    // About / diagnostics
                    AboutView()
                        .tag(2)
                }
                .tabViewStyle(.verticalPage)
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
            selectedPreset = preset
            isRecording = true
        }
    }
}
