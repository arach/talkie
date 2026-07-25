//
//  CaptureTargetController.swift
//  TalkieAgent
//
//  Keeps an in-memory bookmark to the app, window, and focused input that
//  should receive subsequent screenshots.
//

import AppKit
import Observation
import TalkieKit

private let captureTargetLog = Log(.ui)

@MainActor @Observable
final class CaptureTargetController {
    enum FeedbackEvent: Equatable {
        case locked
        case caught
        case switched
    }

    static let shared = CaptureTargetController()

    private(set) var insertionTarget: TranscriptInsertionTarget?
    private(set) var pendingCaptures: [AgentLiveTrayItem] = []
    private(set) var captureCount = 0
    private(set) var lastFailure: String?
    private(set) var feedbackSequence = 0
    private(set) var lastFeedback: FeedbackEvent?

    var isLocked: Bool {
        insertionTarget != nil
    }

    var appName: String? {
        insertionTarget?.label
    }

    var windowTitle: String? {
        insertionTarget?.windowTitle
    }

    var inputRole: String? {
        insertionTarget?.inputRole
    }

    var inputFrame: CGRect? {
        insertionTarget?.inputFrame
    }

    var appIcon: NSImage? {
        insertionTarget?.app.icon
    }

    var targetApplication: NSRunningApplication? {
        insertionTarget?.app
    }

    private init() {}

    @discardableResult
    func lock(on app: NSRunningApplication?) -> Bool {
        guard pendingCaptures.isEmpty else {
            return fail("Deliver or clear the queued screenshots before changing targets")
        }

        guard let app,
              !app.isTerminated,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return fail("Focus an app input before locking a capture target")
        }

        guard let candidate = TranscriptInsertionTarget.capture(from: app),
              candidate.hasFocusedInput else {
            return fail("No focused input was available in \(app.localizedName ?? "this app")")
        }

        insertionTarget = candidate
        pendingCaptures = []
        captureCount = 0
        lastFailure = nil
        registerFeedback(.locked)
        captureTargetLog.info(
            "Capture target locked",
            detail: "app=\(candidate.label) window=\(candidate.windowTitle ?? "unknown") role=\(candidate.inputRole ?? "unknown")"
        )
        return true
    }

    func clear() {
        guard let insertionTarget else { return }
        captureTargetLog.info(
            "Capture target cleared",
            detail: "app=\(insertionTarget.label) discarded=\(pendingCaptures.count)"
        )
        self.insertionTarget = nil
        pendingCaptures = []
        captureCount = 0
        lastFailure = nil
        lastFeedback = nil
    }

    @discardableResult
    func jump() async -> Bool {
        guard let insertionTarget else {
            return fail("No capture target is locked")
        }
        guard await insertionTarget.prepareForPaste() else {
            clearInvalidTarget(message: "The capture target is no longer available")
            return false
        }
        lastFailure = nil
        registerFeedback(.switched)
        return true
    }

    func prepareForPaste() async -> NSRunningApplication? {
        guard let insertionTarget else { return nil }
        guard await insertionTarget.prepareForPaste() else {
            clearInvalidTarget(message: "The capture target is no longer available")
            return nil
        }
        lastFailure = nil
        return insertionTarget.app
    }

    @discardableResult
    func stage(_ item: AgentLiveTrayItem) -> Bool {
        guard let insertionTarget else {
            return fail("No capture target is locked")
        }

        pendingCaptures.append(item)
        captureCount = pendingCaptures.count
        lastFailure = nil
        registerFeedback(.caught)
        captureTargetLog.info(
            "Screenshot queued for capture target",
            detail: "app=\(insertionTarget.label) count=\(captureCount)"
        )
        return true
    }

    func recordSuccessfulPaste(itemID: UUID) async {
        guard let insertionTarget else { return }

        // Let the receiving composer advance its caret or attachment state,
        // then refresh the bookmark so a later capture session lands after it.
        try? await Task.sleep(for: .milliseconds(140))
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == insertionTarget.processIdentifier,
           let refreshed = TranscriptInsertionTarget.capture(from: insertionTarget.app),
           refreshed.hasFocusedInput {
            self.insertionTarget = refreshed
        }

        pendingCaptures.removeAll { $0.id == itemID }
        captureCount = pendingCaptures.count
        lastFailure = nil
        captureTargetLog.info(
            "Queued screenshot delivered",
            detail: "app=\(insertionTarget.label) remaining=\(captureCount)"
        )
    }

    @discardableResult
    private func fail(_ message: String) -> Bool {
        lastFailure = message
        captureTargetLog.warning("Capture target action failed", detail: message)
        return false
    }

    private func clearInvalidTarget(message: String) {
        let label = insertionTarget?.label ?? "unknown"
        insertionTarget = nil
        pendingCaptures = []
        captureCount = 0
        lastFailure = message
        captureTargetLog.warning("Capture target invalidated", detail: "app=\(label) reason=\(message)")
    }

    private func registerFeedback(_ event: FeedbackEvent) {
        lastFeedback = event
        feedbackSequence += 1
    }
}
