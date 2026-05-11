//
//  InterstitialCore.swift
//  TalkieKit
//
//  Internal state manager for the interstitial editor.
//  Not exposed publicly - consumers use TalkieInterstitial facade.
//

import SwiftUI
import AppKit

@MainActor
@Observable
final class InterstitialCore {
    static let shared = InterstitialCore()

    // MARK: - State

    private(set) var isVisible = false
    var text = ""
    var originalText = ""
    var dictationId: Int64?
    var isPolishing = false
    var polishError: String?

    private(set) var revisions: [InternalRevision] = []
    private(set) var config: TalkieInterstitial.Config = .init()
    private var panel: NSPanel?
    private var createdAt = Date()

    struct InternalRevision: Identifiable {
        let id = UUID()
        let instruction: String
        let before: String
        let after: String
        let accepted: Bool
        let timestamp: Date
    }

    // MARK: - Show/Dismiss

    func show(text: String, dictationId: Int64?, config: TalkieInterstitial.Config) {
        // Dismiss existing if any
        if panel != nil {
            dismiss()
        }

        self.text = text
        self.originalText = text
        self.dictationId = dictationId
        self.config = config
        self.revisions = []
        self.createdAt = Date()
        self.polishError = nil

        createPanel()

        // Notify draft created
        notifyDraftUpdate()
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        isVisible = false

        // Notify dismissal (default to discarded if no explicit action)
        config.onDismiss?(.discarded)

        // Reset state
        text = ""
        originalText = ""
        revisions = []
        dictationId = nil
        polishError = nil
    }

    // MARK: - Actions

    func copyAndDismiss() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        panel?.orderOut(nil)
        panel = nil
        isVisible = false

        config.onDismiss?(.copied)

        text = ""
        originalText = ""
        revisions = []
    }

    func polish(instruction: String) async {
        guard !isPolishing else { return }

        isPolishing = true
        polishError = nil
        let before = text

        do {
            let result = try await InterstitialLLMClient.shared.complete(
                text: text,
                instruction: instruction,
                provider: config.llmProvider,
                model: config.llmModel,
                apiKey: config.llmAPIKey
            )

            text = result

            // Record revision
            revisions.append(InternalRevision(
                instruction: instruction,
                before: before,
                after: result,
                accepted: true,
                timestamp: Date()
            ))

            // Notify update
            notifyDraftUpdate()

        } catch {
            polishError = error.localizedDescription
        }

        isPolishing = false
    }

    func resetText() {
        text = originalText
    }

    // MARK: - Private

    private func createPanel() {
        let content = InterstitialView(core: self)
        let hosting = NSHostingView(rootView: content)

        let width: CGFloat = 560
        let height: CGFloat = 400

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .resizable, .closable],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hosting
        panel.minSize = NSSize(width: 400, height: 300)
        panel.maxSize = NSSize(width: 800, height: 600)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true

        // Center on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - width / 2
            let y = screenFrame.midY - height / 2 + 50
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFrontRegardless()
        panel.makeKey()

        self.panel = panel
        self.isVisible = true
    }

    private func notifyDraftUpdate() {
        let draft = TalkieInterstitial.Draft(
            text: text,
            originalText: originalText,
            revisions: revisions.map { rev in
                TalkieInterstitial.Revision(
                    instruction: rev.instruction,
                    textBefore: rev.before,
                    textAfter: rev.after,
                    wasAccepted: rev.accepted,
                    timestamp: rev.timestamp
                )
            },
            dictationId: dictationId,
            createdAt: createdAt,
            updatedAt: Date()
        )
        config.onDraftUpdate?(draft)
    }
}
