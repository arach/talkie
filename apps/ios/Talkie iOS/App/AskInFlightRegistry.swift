//
//  AskInFlightRegistry.swift
//  Talkie iOS
//
//  What the phone is currently doing with an ask spoken from the Watch.
//
//  The Watch already receives every step of this over WatchConnectivity, but
//  the phone itself had no surface for it: an ask could be transcribing,
//  answering, or failing outright with nothing on screen. This registry is fed
//  from the same funnel that emits those updates — `sendMemoUpdate` — so the
//  two views of an ask cannot drift apart.
//

import Foundation
import SwiftUI

@MainActor
final class AskInFlightRegistry: ObservableObject {
    static let shared = AskInFlightRegistry()

    struct Entry: Identifiable, Equatable {
        /// The memo id the Watch minted, which is also the key the agent
        /// session and the memo detail surface are stored under.
        let id: String
        var phase: WatchSessionManager.AskPhase
        /// The question while it is still being answered, then the answer.
        var text: String?
        var updatedAt: Date

        var isTerminal: Bool { phase == .answered || phase == .failed }
    }

    /// Newest first. Ordinarily holds zero or one entry — asks are spoken one
    /// at a time — but a second ask arriving before the first settles must not
    /// evict it silently.
    @Published private(set) var entries: [Entry] = []

    /// A finished answer stays up long enough to read the phase change and
    /// reach for it, then gets out of the way. Failures do not decay: a silent
    /// failure with no visible trace is the exact problem this surface exists
    /// to fix.
    private static let answeredLinger: TimeInterval = 4

    private var decayTasks: [String: Task<Void, Never>] = [:]

    private init() {}

    var current: Entry? { entries.first }

    /// Phases that mean "this is an ask", as opposed to an ordinary Watch memo
    /// passing through the same update funnel. An entry is only ever created by
    /// one of these; `received` and `queued` are shared with plain dictation and
    /// would otherwise light the pill for every memo sent from the wrist.
    private static let askOnlyPhases: Set<WatchSessionManager.AskPhase> = [
        .transcribing, .answering, .answered, .failed
    ]

    func record(
        memoId: String,
        phase: WatchSessionManager.AskPhase,
        text: String?
    ) {
        guard !memoId.isEmpty else { return }

        let existingIndex = entries.firstIndex { $0.id == memoId }
        guard existingIndex != nil || Self.askOnlyPhases.contains(phase) else { return }

        if let index = existingIndex {
            entries[index].phase = phase
            // A phase that carries no text must not blank out text an earlier
            // phase supplied — `answering` sends the question, and the pill
            // keeps showing it until the answer replaces it.
            if let text, !text.isEmpty {
                entries[index].text = text
            }
            entries[index].updatedAt = Date()
        } else {
            entries.insert(
                Entry(id: memoId, phase: phase, text: text, updatedAt: Date()),
                at: 0
            )
        }

        // The lock-screen half of the same story. Driven from here rather
        // than from `sendMemoUpdate` directly so the banner and the pill
        // are fed by one funnel and cannot disagree about an ask.
        AskLiveActivityController.shared.record(memoId: memoId, phase: phase, text: text)

        scheduleDecayIfNeeded(memoId: memoId, phase: phase)
    }

    /// The wearer swatted the pill away. That is a statement about the ask,
    /// not about this surface, so the lock-screen banner goes with it.
    func dismiss(_ memoId: String) {
        retire(memoId)
        AskLiveActivityController.shared.end(memoId)
    }

    /// The pill's own linger elapsed. The banner keeps its separate, longer
    /// linger — an answer you never looked at on the lock screen should not
    /// vanish because a surface you were not looking at timed out.
    private func retire(_ memoId: String) {
        decayTasks.removeValue(forKey: memoId)?.cancel()
        entries.removeAll { $0.id == memoId }
    }

    private func scheduleDecayIfNeeded(memoId: String, phase: WatchSessionManager.AskPhase) {
        decayTasks.removeValue(forKey: memoId)?.cancel()
        guard phase == .answered else { return }

        decayTasks[memoId] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.answeredLinger))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            // Only retire it if it is still the answer we scheduled against; a
            // later update on the same memo owns its own timing.
            guard self.entries.first(where: { $0.id == memoId })?.phase == .answered else { return }
            self.retire(memoId)
        }
    }
}

// MARK: - Presentation

extension WatchSessionManager.AskPhase {
    var pillLabel: String {
        switch self {
        case .queued: return "Queued"
        case .sending: return "Sending"
        case .received: return "Received from Watch"
        case .transcribing: return "Transcribing your ask"
        case .answering: return "Answering"
        case .answered: return "Answer ready"
        case .failed: return "Ask failed"
        }
    }

    var isSettled: Bool { self == .answered || self == .failed }
}
