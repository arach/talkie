//
//  FeatureFlags.swift
//  Talkie iOS
//
//  Runtime feature flags for gating functionality.
//  Set flags to false to hide features before App Store submission.
//

import Foundation

/// Feature flags for controlling app functionality
/// Toggle these to show/hide features without recompiling
enum FeatureFlags {
    private static let launchArguments = ProcessInfo.processInfo.arguments

    // MARK: - Connectivity

    /// Show Connection Center in Settings (Mac Mini bridge, etc.)
    /// Set to `false` for App Store builds
    static var showConnectionCenter: Bool {
        launchArguments.contains("--enableConnectionCenter")
    }

    // MARK: - On-Device AI (Foundation Models)
    //
    // Each non-sidecar Foundation Models feature has its own flag. They default
    // to OFF while we focus on the recording sidecar use case. Reasons:
    //   - Each LanguageModelSession variant compiles into the per-app
    //     com.apple.e5rt.e5bundlecache; on simulators that cache has no
    //     disk-pressure eviction signal and accumulates unbounded.
    //   - Bounding active features narrows the surface we exercise during dev.
    //
    // To opt-in for a build, pass the matching launch argument in the scheme.
    // Sidecar is always on; it's the feature we're building around.

    /// Recording sidecar (feedback + research modes). Always on.
    static var aiRecordingSidecarEnabled: Bool { true }

    /// Auto-titles for voice memos after transcription.
    static var aiMemoTitlesEnabled: Bool {
        launchArguments.contains("--enableAIMemoTitles")
    }

    /// Auto-titles for screenshots / captures (content-aware: detects social
    /// media, email, code, etc.).
    static var aiCaptureTitlesEnabled: Bool {
        launchArguments.contains("--enableAICaptureTitles")
    }

    /// 2-3 sentence summary of a voice-memo transcript.
    static var aiMemoSummariesEnabled: Bool {
        launchArguments.contains("--enableAIMemoSummaries")
    }

    /// User-triggered memo formatting in Compose. This is availability-gated
    /// at call time and does not run in the background.
    static var aiMemoFormattingEnabled: Bool { true }

    /// Task / action-item extraction from voice-memo transcripts.
    static var aiTaskExtractionEnabled: Bool {
        launchArguments.contains("--enableAITaskExtraction")
    }

    /// Apple Watch voice assistant (short conversational responses).
    static var aiWatchAssistantEnabled: Bool {
        launchArguments.contains("--enableAIWatchAssistant")
    }

    /// Claude Code session summaries (4-8 word session-list labels).
    static var aiSessionSummariesEnabled: Bool {
        launchArguments.contains("--enableAISessionSummaries")
    }

    /// Keyboard-extension smart transforms (summary / bullets / topics).
    static var aiKeyboardSmartTransformEnabled: Bool {
        launchArguments.contains("--enableAIKeyboardSmartTransform")
    }

    // MARK: - Future Flags

    // Add new feature flags here as needed
}
