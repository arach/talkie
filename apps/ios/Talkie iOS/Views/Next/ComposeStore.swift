//
//  ComposeStore.swift
//  Talkie iOS
//
//  M2 paint stub. Owns ComposeNextView's state machine and presents
//  mock data so all five states render. Codex replaces this body in
//  M2 wire with: AudioRecorderManager (inline dictation), AI provider
//  routing (voice command → diff), Persistence load/save, and the
//  bridge from ShellChrome.longPressEnded → voiceCommandReceived.
//
//  Public surface (held stable for M2 wire):
//    @Published var state: ComposeState
//    @Published var document: Document
//    @Published var livePartialTranscript: String?
//    @Published var lastCommandTranscript: String?
//    @Published var generatingETA: String?
//    @Published var pendingDiff: Diff?
//    func toggleDictation()
//    func voiceCommandReceived(_ text: String)
//    func applyTransform(_ transform: QuickTransform)
//    func acceptDiff() / discardDiff()
//

import Foundation
import SwiftUI

@MainActor
final class ComposeStore: ObservableObject {
    @Published var state: ComposeState = .idle
    @Published var document: Document
    @Published var livePartialTranscript: String?
    @Published var lastCommandTranscript: String?
    @Published var generatingETA: String?
    @Published var pendingDiff: Diff?

    let modelLabel: String = "Sonnet 4.6"
    let documentID: String

    init(documentID: String) {
        self.documentID = documentID
        self.document = Self.mockDocument

        // Launch-arg state override for screenshot harness — same
        // pattern as AppShellNext's --screenshotChromeState.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--composeState"), i + 1 < args.count {
            switch args[i + 1].lowercased() {
            case "idle":       seed(.idle)
            case "dictating":  seed(.dictating)
            case "listening":  seed(.listening)
            case "generating": seed(.generating)
            case "diff":       seed(.diff)
            default: break
            }
        }
    }

    // MARK: - Mutations (M2 paint = mocked; M2 wire replaces bodies)

    func toggleDictation() {
        if state == .dictating {
            state = .idle
            livePartialTranscript = nil
        } else {
            state = .dictating
            livePartialTranscript = "and that's when the model surfaced"
        }
    }

    /// Entry point used by ShellChrome.longPressEnded once the
    /// Compose screen is current. M2 paint just stages a mock diff
    /// after a short delay so the full flow is observable.
    func voiceCommandReceived(_ text: String) {
        lastCommandTranscript = text
        state = .listening
        generatingETA = "~3s"

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let self, self.state == .listening else { return }
            self.state = .generating
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard self.state == .generating else { return }
            self.pendingDiff = Self.mockDiff
            self.state = .diff
        }
    }

    func applyTransform(_ transform: QuickTransform) {
        voiceCommandReceived(transform.commandLabel)
    }

    func acceptDiff() {
        guard let diff = pendingDiff else { state = .idle; return }
        // Replace the original paragraph in the document.
        document = document.replacing(diff.original, with: diff.proposed)
        pendingDiff = nil
        lastCommandTranscript = nil
        state = .idle
    }

    func discardDiff() {
        pendingDiff = nil
        lastCommandTranscript = nil
        state = .idle
    }

    // MARK: - Types

    struct Document {
        let title: String
        var paragraphs: [String]

        func replacing(_ original: String, with proposed: String) -> Document {
            var copy = paragraphs
            if let idx = copy.firstIndex(of: original) {
                copy[idx] = proposed
            }
            return Document(title: title, paragraphs: copy)
        }
    }

    struct Diff {
        let original: String
        let proposed: String
        let removedCount: Int
        let addedCount: Int
    }

    enum QuickTransform: CaseIterable {
        case shorter, polish, connect, grammar

        var label: String {
            switch self {
            case .shorter: return "Shorter"
            case .polish:  return "Polish"
            case .connect: return "Connect"
            case .grammar: return "Fix grammar"
            }
        }

        var commandLabel: String {
            switch self {
            case .shorter: return "make it shorter"
            case .polish:  return "polish the tone"
            case .connect: return "connect the ideas more clearly"
            case .grammar: return "fix any grammar issues"
            }
        }
    }

    // MARK: - Mock fixtures

    private static let mockDocument = Document(
        title: "Bio",
        paragraphs: [
            "I build tools at the seam between people and the systems they rely on \u{2014} the bits of an interface that quietly decide whether software feels obvious or hostile.",
            "Most of my work lately sits in two places: editor surfaces that take dictation seriously, and ambient AI that earns its place on a phone screen instead of grabbing for it.",
            "Before that, a stretch of years building infra most people never see. I learned to value boring reliability the hard way, on systems where every alert was someone's worst day."
        ]
    )

    private static let mockDiff = Diff(
        original: "Most of my work lately sits in two places: editor surfaces that take dictation seriously, and ambient AI that earns its place on a phone screen instead of grabbing for it.",
        proposed: "Lately my work splits cleanly: editor surfaces built around real dictation, and ambient AI that earns its place on a phone screen rather than grabbing for it.",
        removedCount: 9,
        addedCount: 6
    )

    // Seed for launch-arg-driven screenshot states. Keeps the diff
    // and command strings deterministic across themes.
    private func seed(_ target: ComposeState) {
        switch target {
        case .idle:
            state = .idle
        case .dictating:
            state = .dictating
            livePartialTranscript = "and that's when the model surfaced"
        case .listening:
            state = .listening
            lastCommandTranscript = "tighten the second paragraph"
        case .generating:
            state = .generating
            lastCommandTranscript = "tighten the second paragraph"
            generatingETA = "~3s"
        case .diff:
            state = .diff
            lastCommandTranscript = "tighten the second paragraph"
            pendingDiff = Self.mockDiff
        }
    }
}
