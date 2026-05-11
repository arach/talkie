//
//  SelectionOCRFlow.swift
//  TalkieAgent
//
//  Orchestrates the OCR fallback tier for selection capture:
//  region picker → screen capture → Vision OCR → confirm/edit sheet.
//

import AppKit
import SwiftUI
import TalkieKit

private let log = Log(.system)

@MainActor
final class SelectionOCRFlow {
    static let shared = SelectionOCRFlow()
    private init() {}

    private var inFlight = false

    /// Run the OCR fallback flow end-to-end.
    /// Returns the user-approved text (possibly edited) or nil if cancelled/failed.
    func capture() async -> String? {
        guard !inFlight else {
            log.debug("SelectionOCRFlow: already in flight, skipping")
            return nil
        }
        inFlight = true
        defer { inFlight = false }

        // 1. Region pick
        let picker = RegionPickerOverlay()
        guard let rect = await picker.pickRegion() else {
            log.debug("SelectionOCRFlow: region pick cancelled")
            return nil
        }

        // 2. Pixel grab
        guard let image = await VisionOCRService.shared.captureScreenRegion(rect) else {
            log.error("SelectionOCRFlow: screen capture returned nil for \(String(describing: rect))")
            return nil
        }

        // 3. OCR
        let ocrText: String
        do {
            ocrText = try await VisionOCRService.shared.recognizeText(in: image)
        } catch {
            log.error("SelectionOCRFlow: OCR failed: \(error.localizedDescription)")
            // Still show the confirm sheet with empty text so the user can type it in
            return await presentConfirm(initialText: "", image: image)
        }

        log.info("SelectionOCRFlow: recognized \(ocrText.count) chars from region")

        // 4. Confirm / edit
        return await presentConfirm(initialText: ocrText, image: image)
    }

    private func presentConfirm(initialText: String, image: CGImage) async -> String? {
        await withCheckedContinuation { continuation in
            var resumed = false
            let controller = SelectionOCRConfirmController(
                initialText: initialText,
                image: image
            ) { result in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: result)
            }
            controller.show()
        }
    }
}

// MARK: - Confirm sheet controller

@MainActor
private final class SelectionOCRConfirmController {
    private var window: NSPanel?
    private let initialText: String
    private let image: CGImage
    private let completion: (String?) -> Void

    init(initialText: String, image: CGImage, completion: @escaping (String?) -> Void) {
        self.initialText = initialText
        self.image = image
        self.completion = completion
    }

    func show() {
        let view = SelectionOCRConfirmView(
            initialText: initialText,
            image: image,
            onConfirm: { [weak self] text in
                self?.finish(with: text)
            },
            onCancel: { [weak self] in
                self?.finish(with: nil)
            }
        )

        let hosting = NSHostingController(rootView: view)
        hosting.view.setFrameSize(NSSize(width: 520, height: 440))

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Confirm OCR'd text"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.contentViewController = hosting
        panel.center()
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.orderFrontRegardless()
        panel.makeKey()

        self.window = panel
    }

    private func finish(with text: String?) {
        window?.close()
        window = nil
        completion(text)
    }
}

// MARK: - SwiftUI confirm view

private struct SelectionOCRConfirmView: View {
    let initialText: String
    let image: CGImage
    var onConfirm: (String) -> Void
    var onCancel: () -> Void

    @State private var text: String

    init(initialText: String, image: CGImage, onConfirm: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.initialText = initialText
        self.image = image
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _text = State(initialValue: initialText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "text.viewfinder")
                    .font(.title3)
                Text("Review recognized text")
                    .font(.headline)
                Spacer()
                Text("\(text.count) chars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            thumbnail
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .background(Color.black.opacity(0.2))
                .cornerRadius(6)

            TextEditor(text: $text)
                .font(.system(size: 13))
                .frame(minHeight: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            HStack {
                Text("Edit before sending if OCR made mistakes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Use") { onConfirm(text) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
    }

    private var thumbnail: some View {
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        return Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }
}
