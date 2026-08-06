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

        guard url.scheme == "talkie" else { return }
        // The first path component is always "/", so the payload is at index 1.
        let payload = url.pathComponents.count > 1 ? url.pathComponents[1] : nil

        switch url.host {
        // talkie://record/go, talkie://record/ai, talkie://record/thought…
        case "record":
            let presetId = payload ?? "quick"
            WatchConsole.info("⌚️ [Watch] Starting recording with preset: \(presetId)")
            pendingPresetId = presetId
            // Haptic feedback
            WKInterfaceDevice.current().play(.start)

        // talkie://ask/<uuid> — a complication showing a waiting answer. Routed
        // through the notifier because it already owns "which answer are we
        // opening, and does it start speaking"; a second parallel mechanism
        // would only give the two of them a way to disagree.
        case "ask":
            guard let payload, let askID = UUID(uuidString: payload) else { return }
            WatchConsole.info("⌚️ [Watch] Opening ask from deep link: \(askID)")
            WatchAnswerNotifier.shared.requestOpen(askID: askID, play: false)

        default:
            return
        }
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
    @StateObject private var answerNotifier = WatchAnswerNotifier.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        TalkieLogger.configure(source: .talkieWatch)
        // Before the first scene exists: a notification can cold-start the app,
        // and the delegate has to be in place to catch which one it was.
        WatchAnswerNotifier.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            MainWatchView()
                .environmentObject(sessionManager)
                .environmentObject(deepLinkHandler)
                .environmentObject(answerNotifier)
                .environment(
                    \.watchThemeName,
                    WatchThemeName(rawValue: sessionManager.appearanceThemeName) ?? .porcelain
                )
                .onOpenURL { url in
                    deepLinkHandler.handle(url: url)
                }
                // `onChange` never reports the phase the app launched in, and
                // launching *is* the wrist coming up — the case where speaking
                // aloud is most obviously wanted.
                .onAppear {
                    sessionManager.noteForegroundState(scenePhase == .active)
                    answerNotifier.requestAuthorizationIfNeeded()
                }
        }
        // Whether an arriving answer speaks on its own turns on whether anyone
        // is there to hear it, and the scene phase is the only wrist-up signal
        // watchOS offers. `.inactive` counts as away: it is what a lowering
        // wrist reports on its way to `.background`.
        .onChange(of: scenePhase) { _, phase in
            sessionManager.noteForegroundState(phase == .active)
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
    @EnvironmentObject var answerNotifier: WatchAnswerNotifier
    @Environment(\.watchThemeName) private var themeName
    @State private var selectedPreset: WatchPreset?
    @State private var isRecording = false
    @State private var primaryPage: PrimaryPage = .capture
    /// Asks pushed from outside the Asks page — today that means a notification
    /// the wearer opened from the watch face.
    @State private var askPath: [UUID] = []

    var body: some View {
        NavigationStack(path: $askPath) {
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
            .navigationDestination(for: UUID.self) { askID in
                AskDetailView(askId: askID)
            }
            // The face draws its own header row and takes the height back.
            //
            // The clock is not part of that trade, and it is worth writing down
            // why so nobody spends another afternoon on it: watchOS draws the
            // time itself, at its own size, and there is no public way to change
            // that. Hiding the bar does not remove it. Restoring the bar with an
            // empty title does not shrink it. A single-space title does not
            // either — all three were tried, all three render the same large
            // overlay clock. The top-right corner belongs to the system.
            //
            // So the pages below claim the height and leave that corner empty on
            // purpose, which is the only part of the arrangement this app gets a
            // vote on.
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            checkPendingDeepLink()
            checkPendingAnswer()
        }
        .onChange(of: deepLinkHandler.pendingPresetId) { _, newValue in
            if newValue != nil {
                checkPendingDeepLink()
            }
        }
        .onChange(of: answerNotifier.pendingAskID) { _, newValue in
            if newValue != nil {
                checkPendingAnswer()
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

    /// Opens the ask a notification was tapped for.
    ///
    /// The Asks page is selected underneath rather than left on capture, so
    /// backing out of the answer lands where the rest of them are instead of
    /// somewhere the wearer never chose to be.
    private func checkPendingAnswer() {
        // A notification arriving mid-recording is not a reason to throw away
        // what is being recorded. Left unconsumed, so it is still honoured once
        // the recording finishes and this view comes back.
        guard !isRecording else { return }
        guard let pending = answerNotifier.consumePendingAsk() else { return }

        primaryPage = .asks
        askPath = [pending.askID]
        if pending.play {
            sessionManager.toggleAnswerPlayback(memoID: pending.askID)
        }
    }
}

/// Reachable from the capture face's own header now that watchOS's bar — and
/// the toolbar item that used to push this — is gone.
struct WatchMoreView: View {
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
