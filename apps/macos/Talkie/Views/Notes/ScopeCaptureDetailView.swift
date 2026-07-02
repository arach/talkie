//
//  ScopeCaptureDetailView.swift
//  Talkie
//
//  Image-first detail surface for a single Capture (standalone screenshot).
//  Used by ScopeLibraryView when the selected item's type is .capture.
//
//  Captures are the low-ceremony bucket — "anything grabbed in passing."
//  The detail puts the image at center stage with a derived caption that
//  promotes the Capture to a Note the moment it gets edited.
//
//  Studio source of truth:
//    design/studio/components/studies/MacCaptureDetail.tsx
//
//  Palette: Scope editorial tokens resolved through the active Talkie
//  theme. Scope keeps the cool-gray paper canon; dark themes receive
//  readable themed paper/ink instead of static Scope inks.
//

import AppKit
import SwiftUI
import TalkieKit

// Capture typography routed through ScopeType — see TalkieKit/UI/ScopeDesign.swift.

private enum CapturePreviewMedia {
    case image(URL)
    case video(URL, CGFloat)
    case file(URL, RecordingAttachment)
    case unavailable

    var url: URL? {
        switch self {
        case .image(let url), .video(let url, _), .file(let url, _):
            return url
        case .unavailable:
            return nil
        }
    }
}

// MARK: - View

struct ScopeCaptureDetailView: View {
    let capture: TalkieObject
    /// Library passes through so Delete from the rail/foot can clear selection.
    var onDelete: (() -> Void)? = nil

    private var viewModel: RecordingsViewModel { .shared }
    private var workflowService: WorkflowService { .shared }

    // In-window markup takeover target (vs. the old floating panel).
    @State private var markupURL: URL?
    @State private var runningWorkflowID: UUID?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let marginWidth: CGFloat = max(200, min(300, width * 0.18))
            let bodyPad: CGFloat = width < 1300 ? 56 : (width * 0.06)

            VStack(spacing: 0) {
                // Top toolbar removed — actions live in the side rail.
                // Sequence + channel migrated into the body eyebrow.
                HStack(alignment: .top, spacing: 0) {
                    heroColumn(bodyPad: bodyPad)
                    marginColumn(width: marginWidth)
                }
                footRail(bodyPad: bodyPad)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(ThemedScopeCanvas.canvas)
        }
        .captureMarkupHost(url: $markupURL)
    }

    // MARK: - Derived data

    private var primaryShot: RecordingScreenshot? {
        capture.screenshots.first
    }

    private var primaryClip: RecordingClip? {
        capture.clips.first
    }

    private var primaryVisualContext: RecordingVisualContext? {
        capture.visualContexts.first
    }

    private var primaryMediaAsset: CaptureMediaAsset? {
        CaptureMediaFileResolver.primaryMedia(for: capture)
    }

    private var primaryAttachment: RecordingAttachment? {
        if let mediaURL = primaryMediaAsset?.url,
           let mediaAttachment = capture.attachments.first(where: { attachment in
               CaptureMediaFileResolver.mediaAsset(for: attachment)?.url == mediaURL
           }) {
            return mediaAttachment
        }
        return capture.attachments.first
    }

    private var primaryAttachmentURL: URL? {
        guard let primaryAttachment else { return nil }
        return CaptureMediaFileResolver.attachmentURL(filename: primaryAttachment.filename)
    }

    private var primaryPreviewMedia: CapturePreviewMedia {
        switch primaryMediaAsset {
        case .image(let url):
            return .image(url)
        case .video(let url):
            return .video(url, mediaAspectRatio)
        case .none:
            break
        }
        if let primaryAttachment, let url = primaryAttachmentURL {
            return .file(url, primaryAttachment)
        }
        return .unavailable
    }

    private var primaryMediaURL: URL? {
        primaryPreviewMedia.url
    }

    private var hasPreviewMedia: Bool {
        primaryMediaAsset != nil || primaryAttachmentURL != nil
    }

    /// True when this capture is a text passage (Quick Selection) rather
    /// than a screenshot. Drives the hero branch.
    private var isTextCapture: Bool {
        if capture.type == .selection { return !hasPreviewMedia }
        if !hasPreviewMedia, let text = capture.text, !text.isEmpty { return true }
        return false
    }

    private var sourceLabel: String {
        if let primaryAttachment {
            let label = mediaLabel(for: primaryAttachment)
            if capture.type == .selection {
                return "Quick Selection · \(label)"
            }
            return "Attachment · \(label)"
        }
        if isTextCapture {
            return "Quick Selection · text"
        }
        if let shot = primaryShot {
            return "Hyper+S · \(shot.captureMode)"
        }
        if let clip = primaryClip {
            let mode = clip.captureMode ?? "clip"
            return "Capture · \(mode) video"
        }
        if let visualContext = primaryVisualContext {
            return "Capture · \(visualContext.captureMode) video"
        }
        return "Capture · media"
    }

    private var channelLabel: String {
        capture.type == .selection ? "SELECTION" : "CAPTURE"
    }

    private var dimensions: String {
        guard let w = mediaWidth, let h = mediaHeight else { return "—" }
        return "\(w) × \(h)"
    }

    private var mediaWidth: Int? {
        primaryShot?.width ?? primaryClip?.width ?? primaryVisualContext?.width ?? primaryAttachment?.width
    }

    private var mediaHeight: Int? {
        primaryShot?.height ?? primaryClip?.height ?? primaryVisualContext?.height ?? primaryAttachment?.height
    }

    private var mediaAspectRatio: CGFloat {
        guard let width = mediaWidth, let height = mediaHeight, width > 0, height > 0 else {
            return 16.0 / 10.0
        }
        return CGFloat(width) / CGFloat(height)
    }

    private var fileSize: String {
        if let primaryAttachment {
            return primaryAttachment.formattedSize
        }
        guard let url = primaryMediaURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let bytes = attrs[.size] as? Int else { return "—" }
        return formatBytes(bytes)
    }

    private var sizeSummary: String {
        let parts = [fileSize, dimensions].filter { $0 != "—" && !$0.isEmpty }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private var footerSummary: String {
        [dimensions, fileSize, sourceLabel]
            .filter { $0 != "—" && !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var dateLabel: String {
        if Calendar.current.isDateInToday(capture.createdAt) { return "Today" }
        if Calendar.current.isDateInYesterday(capture.createdAt) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: capture.createdAt)
    }

    private var timeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: capture.createdAt)
    }

    private var filename: String {
        if let primaryAttachment {
            return primaryAttachment.originalName
        }
        if let url = primaryMediaURL { return url.lastPathComponent }
        return primaryShot?.filename
            ?? primaryClip?.filename
            ?? primaryVisualContext?.sourceClipFilename
            ?? (isTextCapture ? "selection" : "capture")
    }

    private var derivedCaption: String? {
        // For now derive from window title or app name; OCR not yet wired.
        if let t = primaryShot?.windowTitle, !t.isEmpty { return t }
        if let a = primaryShot?.appName, !a.isEmpty { return "From \(a)" }
        if let t = primaryClip?.windowTitle, !t.isEmpty { return t }
        if let a = primaryClip?.appName, !a.isEmpty { return "From \(a)" }
        if let t = primaryVisualContext?.windowTitle, !t.isEmpty { return t }
        if let a = primaryVisualContext?.appName, !a.isEmpty { return "From \(a)" }
        return nil
    }

    private var imageHeadline: String {
        derivedCaption ?? capture.displayTitle
    }

    private var imageByline: String {
        [filename, dimensions, fileSize]
            .filter { $0 != "—" && !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var workflowAssetKind: WorkflowAssetKind? {
        if primaryShot != nil {
            return .screenshot
        }
        if primaryClip != nil || primaryVisualContext != nil {
            return .clip
        }
        if isTextCapture {
            return .text
        }
        if let primaryAttachment {
            switch primaryAttachment.kind {
            case .image: return .image
            case .video: return .clip
            case .audio: return .audio
            case .pdf, .document, .other: return nil
            }
        }
        return nil
    }

    private var captureWorkflows: [Workflow] {
        guard let workflowAssetKind else { return [] }
        return workflowService.workflowsAccepting(
            capture.type,
            assetKind: workflowAssetKind,
            surface: .captureContextMenu
        )
    }

    // MARK: - Sections

    private func openInDefault() {
        guard let url = primaryMediaURL else { return }
        NSWorkspace.shared.open(url)
    }

    @ViewBuilder
    private func heroColumn(bodyPad: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Eyebrow — channel + date. The synthetic C-/S- sequence chip
            // is intentionally withheld until a real persistent display
            // ID exists.
            HStack(spacing: 10) {
                Text("· \(channelLabel)")
                    .font(ScopeType.mono(size: 9, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(ThemedScopeAccent.capture)
                ThemedScopeRule(.subtle)
                Text("\(dateLabel) · \(timeLabel)")
                    .font(ScopeType.mono(size: 9, weight: .regular))
                    .tracking(1.8)
                    .foregroundStyle(ThemedScopeInk.faint)
            }

            // Title — serif for authored/captioned material; filename is
            // provenance metadata below the headline for image captures.
            if isTextCapture {
                Text(capture.displayTitle)
                    .font(ScopeType.display(size: 22, weight: .medium))
                    .tracking(-0.3)
                    .foregroundStyle(ThemedScopeInk.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                Text(bylineTextCapture)
                    .font(ScopeType.mono(size: 10, weight: .regular))
                    .tracking(1.6)
                    .foregroundStyle(ThemedScopeInk.faint)
                    .padding(.top, 6)
            } else {
                Text(imageHeadline)
                    .font(ScopeType.display(size: 22, weight: .medium))
                    .tracking(-0.3)
                    .foregroundStyle(ThemedScopeInk.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                Text(imageByline)
                    .font(ScopeType.mono(size: 10, weight: .regular))
                    .tracking(1.6)
                    .foregroundStyle(ThemedScopeInk.faint)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.top, 6)
            }

            // Hero — branches on content kind. Image for screenshots,
            // text passage for selections.
            Group {
                if isTextCapture {
                    textPassageHero
                } else {
                    mediaHeroStack
                }
            }
            .padding(.top, 20)
            .frame(maxWidth: .infinity, alignment: .center)

            // Promote-to-Note CTA. The capture stays in the same row
            // in the library — it just changes shape, so the user can
            // start composing on top of it (caption, follow-on notes,
            // workflows). Library will re-route to ScopeNoteDetailView
            // on next selection because the type switched.
            HStack(spacing: 12) {
                Button(action: promoteToNote) {
                    HStack(spacing: 8) {
                        Text("＋ ADD CAPTION")
                            .font(ScopeType.mono(size: 10, weight: .semibold))
                            .tracking(2.2)
                            .foregroundStyle(ThemedScopeAccent.brass)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(ThemedScopeAccent.amber.opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(ThemedScopeAccent.amber.opacity(0.40), lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: .command)
                Text("⌘N")
                    .font(ScopeType.mono(size: 9, weight: .regular))
                    .tracking(1.8)
                    .foregroundStyle(ThemedScopeInk.faint)
            }
            .padding(.top, 20)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, bodyPad)
        .padding(.top, 40)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bylineTextCapture: String {
        let words = capture.wordCount
        var parts = ["\(words) word\(words == 1 ? "" : "s")"]
        if let appName = primaryShot?.appName ?? primaryClip?.appName ?? primaryVisualContext?.appName,
           !appName.isEmpty {
            parts.append("from \(appName)")
        }
        parts.append("captured \(dateLabel.lowercased())")
        return parts.joined(separator: " · ")
    }

    private var textPassageParagraphs: [String] {
        let raw = capture.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return ["(empty selection)"] }
        return raw
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    @ViewBuilder
    private var textPassageHero: some View {
        // Captured passage rendered as a quoted block on the PEARL mat.
        // Mono-ish reading face — captured text is "as-grabbed" content,
        // not authored prose. Left rule mimics a blockquote.
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(textPassageParagraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.system(size: 13, design: .default))
                    .foregroundStyle(ThemedScopeInk.primary)
                    .lineSpacing(5)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .frame(maxWidth: 720, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(ThemedScopeCanvas.surface.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(ThemedScopeEdge.subtle, lineWidth: 0.5)
                )
        )
        .overlay(alignment: .leading) {
            // Marginal rule (blockquote-style)
            Rectangle()
                .fill(ThemedScopeAccent.capture.opacity(0.45))
                .frame(width: 2)
        }
    }

    private var mediaHeroStack: some View {
        VStack(spacing: 12) {
            heroMedia
            selectionTextNote
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var heroMedia: some View {
        switch primaryPreviewMedia {
        case .image(let url):
            if let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(ThemedScopeCanvas.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(ThemedScopeEdge.faint, lineWidth: 0.5)
                    )
                    .shadow(
                        color: Color(red: 46/255, green: 68/255, blue: 82/255).opacity(0.10),
                        radius: 12,
                        y: 6
                    )
                    // Drag the media file out to other apps (Slack /
                    // Messages / Finder). Pasteboard carries the on-disk URL
                    // so receivers treat it as a real file, not bitmap data.
                    .onDrag {
                        TalkieInternalDrag.mark(NSItemProvider(contentsOf: url) ?? NSItemProvider())
                    }
            } else {
                unavailableMediaHero
            }
        case .video(let url, let aspectRatio):
            CaptureVideoHero(url: url, aspectRatio: aspectRatio)
                .onDrag {
                    TalkieInternalDrag.mark(NSItemProvider(contentsOf: url) ?? NSItemProvider())
                }
        case .file(let url, let attachment):
            attachmentFileHero(url: url, attachment: attachment)
                .onDrag {
                    TalkieInternalDrag.mark(NSItemProvider(contentsOf: url) ?? NSItemProvider())
                }
        case .unavailable:
            unavailableMediaHero
        }
    }

    private func attachmentFileHero(url: URL, attachment: RecordingAttachment) -> some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(ThemedScopeCanvas.surface.opacity(0.88))
                    .frame(width: 122, height: 86)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(ThemedScopeEdge.faint, lineWidth: 0.7)
                    )

                if attachment.kind == .audio {
                    CaptureAttachmentWaveform(seed: attachment.filename.hashValue)
                        .frame(width: 76, height: 34)
                } else {
                    Image(systemName: attachment.kind.icon)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(ThemedScopeAccent.capture.opacity(0.80))
                }

                if let extensionLabel = extensionLabel(for: attachment) {
                    Text(extensionLabel)
                        .font(ScopeType.mono(size: 8, weight: .semibold))
                        .tracking(1.0)
                        .foregroundStyle(ThemedScopeInk.primary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 2)
                                .fill(ThemedScopeCanvas.canvas.opacity(0.92))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(ThemedScopeEdge.faint, lineWidth: 0.5)
                        )
                        .padding(8)
                        .frame(width: 122, height: 86, alignment: .topTrailing)
                }
            }

            VStack(spacing: 5) {
                Text(mediaLabel(for: attachment).uppercased())
                    .font(ScopeType.mono(size: 9, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(ThemedScopeAccent.capture)
                Text(url.lastPathComponent == attachment.filename ? attachment.originalName : url.lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ThemedScopeInk.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(attachment.formattedSize)
                    .font(ScopeType.mono(size: 9, weight: .regular))
                    .tracking(1.4)
                    .foregroundStyle(ThemedScopeInk.faint)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 34)
        .frame(maxWidth: 720)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(ThemedScopeCanvas.surface.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(ThemedScopeEdge.faint, lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private var selectionTextNote: some View {
        if capture.type == .selection,
           let text = capture.text?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            Text(text)
                .font(.system(size: 12, design: .default))
                .foregroundStyle(ThemedScopeInk.subtle)
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(maxWidth: 720, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(ThemedScopeCanvas.surface.opacity(0.42))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(ThemedScopeEdge.faint, lineWidth: 0.5)
                        )
                )
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(ThemedScopeAccent.capture.opacity(0.35))
                        .frame(width: 2)
                }
        }
    }

    private var unavailableMediaHero: some View {
        // Placeholder mat when media isn't available.
        Rectangle()
            .fill(ThemedScopeCanvas.surface)
            .aspectRatio(16/10, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay(
                Text("(media unavailable)")
                    .font(ScopeType.displayItalic(size: 12))
                    .foregroundStyle(ThemedScopeInk.subtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(ThemedScopeEdge.faint, lineWidth: 0.5)
            )
    }

    @ViewBuilder
    private func marginColumn(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            actionsBlock
            workflowsBlock
            metaBlock(
                title: "Capture",
                rows: [
                    ("source", sourceLabel, true),
                    ("captured", "\(dateLabel) · \(timeLabel)", false),
                    ("size", sizeSummary, false),
                ]
            )
            metaBlock(
                title: "Tray",
                rows: [
                    ("pinned", "no", false),
                    ("draining", "next recording", false),
                ]
            )
            Spacer(minLength: 0)
        }
        .padding(.leading, 20)
        .padding(.trailing, 32)
        .padding(.top, 40)
        .padding(.bottom, 28)
        .frame(width: width, alignment: .topLeading)
        .overlay(alignment: .leading) {
            ThemedScopeRule(.subtle, axis: .vertical)
        }
    }

    @ViewBuilder
    private var actionsBlock: some View {
        railSection(title: "Actions") {
            CapRailAction(label: "Copy",  icon: "doc.on.doc",            isPrimary: true, action: copyCapture)
            if case .image = primaryPreviewMedia {
                CapRailAction(label: "Export", icon: "arrow.down.doc", action: exportCapture)
            }
            CapRailAction(label: "Annotate", icon: "sparkles.rectangle.stack", action: openMarkup)
            CapRailAction(label: "Open",  icon: "arrow.up.right.square", action: openInDefault)
            CapRailAction(
                label: capture.isPinned ? "Pinned" : "Pin",
                icon:  capture.isPinned ? "pin.fill" : "pin",
                isActive: capture.isPinned,
                action: { Task { await viewModel.togglePin(capture) } }
            )
            CapRailAction(label: "Share", icon: "square.and.arrow.up", action: shareCapture)
            ThemedScopeRule(.subtle)
                .padding(.vertical, 4)
            Menu {
                Button {
                    revealInFinder()
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                if onDelete != nil {
                    Divider()
                    Button(role: .destructive) {
                        Task {
                            await viewModel.deleteRecording(capture)
                            onDelete?()
                        }
                    } label: {
                        Label("Delete capture", systemImage: "trash")
                    }
                }
            } label: {
                CapRailAction.menuLabel
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var workflowsBlock: some View {
        let workflows = captureWorkflows
        if !workflows.isEmpty {
            railSection(title: "Workflows") {
                ForEach(Array(workflows.prefix(4))) { workflow in
                    CapWorkflowAction(
                        workflow: workflow,
                        isRunning: runningWorkflowID == workflow.id,
                        action: { runWorkflow(workflow) }
                    )
                }

                if workflows.count > 4 {
                    Menu {
                        ForEach(Array(workflows.dropFirst(4))) { workflow in
                            Button {
                                runWorkflow(workflow)
                            } label: {
                                Label(workflow.name, systemImage: workflow.icon)
                            }
                        }
                    } label: {
                        CapRailMoreLabel(label: "\(workflows.count - 4) more")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func railSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            railTitle(title)
                .padding(.bottom, 4)
            content()
        }
    }

    private func railTitle(_ title: String) -> some View {
        Text("· \(title.uppercased())")
            .font(ScopeType.mono(size: 8.5, weight: .semibold))
            .tracking(2.8)
            .foregroundStyle(ThemedScopeInk.faint)
    }

    @ViewBuilder
    private func metaBlock(title: String, rows: [(String, String, Bool)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            railTitle(title)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.0)
                            .font(ScopeType.mono(size: 9, weight: .regular))
                            .tracking(1.4)
                            .foregroundStyle(ThemedScopeInk.faint)
                        Spacer()
                        Text(row.1)
                            .font(ScopeType.mono(size: 10, weight: .regular))
                            .tracking(0.6)
                            .foregroundStyle(row.2 ? ThemedScopeAccent.capture : ThemedScopeInk.primary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func footRail(bodyPad: CGFloat) -> some View {
        HStack(spacing: 16) {
            Text("· \(footerSummary)")
                .font(ScopeType.mono(size: 9, weight: .regular))
                .tracking(2.2)
                .foregroundStyle(ThemedScopeInk.faint)
            Spacer()
            HStack(spacing: 4) {
                footAction(label: "Reveal in Finder", tone: ThemedScopeInk.muted, action: revealInFinder)
                ThemedScopeRule(.subtle, axis: .vertical)
                    .frame(height: 12)
                    .padding(.horizontal, 4)
                footAction(label: "Delete", tone: .red, action: deleteCapture)
            }
        }
        .padding(.horizontal, bodyPad)
        .padding(.vertical, 12)
        .background(
            Rectangle().fill(ThemedScopeCanvas.surface)
                .overlay(ThemedScopeRule(.row), alignment: .top)
        )
    }

    @ViewBuilder
    private func footAction(label: String, tone: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label.uppercased())
                .font(ScopeType.mono(size: 9, weight: .semibold))
                .tracking(2.2)
                .foregroundStyle(tone)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func openMarkup() {
        guard case .image(let url) = primaryPreviewMedia else { return }
        CaptureMarkupCoordinator.shared.openAgentOwnedSession(imageURL: url)
    }

    private func exportCapture() {
        guard case .image(let url) = primaryPreviewMedia else {
            ToastService.shared.showInfo("Export is available for screenshots first.")
            return
        }
        ShareExportPanelController.shared.open(
            imageURL: url,
            title: imageHeadline,
            sourceLabel: sourceLabel,
            detail: fileSize
        )
    }

    private func copyCapture() {
        if isTextCapture, let text = capture.text, !text.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return
        }

        NSPasteboard.general.clearContents()
        switch primaryPreviewMedia {
        case .image(let url):
            if let image = NSImage(contentsOf: url) {
                NSPasteboard.general.writeObjects([image])
            }
        case .video(let url, _):
            NSPasteboard.general.writeObjects([url as NSURL])
        case .file(let url, _):
            NSPasteboard.general.writeObjects([url as NSURL])
        case .unavailable:
            break
        }
    }

    private func revealInFinder() {
        guard let url = primaryMediaURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func shareCapture() {
        let items: [Any]
        if let url = primaryMediaURL {
            items = [url]
        } else if let text = capture.text, !text.isEmpty {
            items = [text]
        } else {
            return
        }
        let picker = NSSharingServicePicker(items: items)
        if let window = NSApp.keyWindow,
           let content = window.contentView {
            picker.show(relativeTo: .zero, of: content, preferredEdge: .minY)
        }
    }

    private func runWorkflow(_ workflow: Workflow) {
        guard runningWorkflowID == nil else { return }
        runningWorkflowID = workflow.id

        Task { @MainActor in
            do {
                let outputs = try await WorkflowExecutor.shared.executeWorkflow(workflow.definition, for: capture)
                let result = primaryOutput(from: outputs, workflow: workflow.definition)
                runningWorkflowID = nil
                ToastService.shared.showSuccess(
                    workflowToastSummary(result, fallback: "\(workflow.name) completed")
                )
            } catch {
                runningWorkflowID = nil
                ToastService.shared.showError("\(workflow.name) failed: \(error.localizedDescription)")
            }
        }
    }

    private func primaryOutput(from outputs: [String: String], workflow: WorkflowDefinition) -> String {
        if let outputKey = workflow.steps.last?.outputKey,
           let output = outputs[outputKey] {
            return output
        }

        if let last = workflow.steps.reversed().compactMap({ step in
            outputs[step.outputKey]
        }).first {
            return last
        }

        return outputs["result"] ?? outputs["summary"] ?? ""
    }

    private func workflowToastSummary(_ output: String, fallback: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        if trimmed.count <= 140 { return trimmed }
        return "\(trimmed.prefix(140))..."
    }

    private func deleteCapture() {
        Task {
            await viewModel.deleteRecording(capture)
            onDelete?()
        }
    }

    /// Promote this capture into a note so the user can author a
    /// caption / follow-on content. The screenshot stays attached;
    /// the library re-routes to ScopeNoteDetailView on the same id
    /// since the type now reads as `.note`.
    private func promoteToNote() {
        Task {
            do {
                var updated = capture
                updated.type = .note
                updated.lastModified = Date()
                let repository = TalkieObjectRepository()
                try await repository.saveRecording(updated)
                await viewModel.loadRecordings()
                ToastService.shared.showSuccess("Promoted to note")
            } catch {
                ToastService.shared.showError("Couldn't promote: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func mediaLabel(for attachment: RecordingAttachment) -> String {
        switch attachment.kind {
        case .image:
            return "image"
        case .video:
            return "video"
        case .audio:
            return "audio"
        case .pdf:
            return "PDF"
        case .document:
            return "document"
        case .other:
            return "attachment"
        }
    }

    private func extensionLabel(for attachment: RecordingAttachment) -> String? {
        let originalExtension = (attachment.originalName as NSString).pathExtension
        let storedExtension = (attachment.filename as NSString).pathExtension
        let ext = originalExtension.isEmpty ? storedExtension : originalExtension
        guard !ext.isEmpty else { return nil }
        return String(ext.uppercased().prefix(5))
    }

}

private struct CaptureAttachmentWaveform: View {
    let seed: Int

    var body: some View {
        Canvas { ctx, size in
            var rng = SplitMix(seed: UInt64(bitPattern: Int64(seed)))
            let barCount = 15
            let gap: CGFloat = 2
            let barWidth = (size.width - gap * CGFloat(barCount - 1)) / CGFloat(barCount)
            for index in 0..<barCount {
                let x = CGFloat(index) * (barWidth + gap)
                let unit = CGFloat(rng.nextUnit())
                let height = max(5, size.height * (0.18 + unit * 0.76))
                let y = (size.height - height) / 2
                let rect = CGRect(x: x, y: y, width: barWidth, height: height)
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                ctx.fill(path, with: .color(ThemedScopeAccent.capture.opacity(index % 3 == 0 ? 0.90 : 0.62)))
            }
        }
        .allowsHitTesting(false)
    }

    private struct SplitMix {
        var state: UInt64

        init(seed: UInt64) {
            state = seed == 0 ? 0xDEADBEEF : seed
        }

        mutating func nextUnit() -> Double {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            z = z ^ (z >> 31)
            return Double(z >> 11) / Double(UInt64(1) << 53)
        }
    }
}

private struct CaptureVideoHero: View {
    let url: URL
    let aspectRatio: CGFloat

    var body: some View {
        ZStack {
            Rectangle()
                .fill(ThemedScopeCanvas.surface)
            InlineClipPlayer(url: url)
                .id(url)
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(ThemedScopeEdge.faint, lineWidth: 0.5)
        )
        .shadow(
            color: Color(red: 46/255, green: 68/255, blue: 82/255).opacity(0.10),
            radius: 12,
            y: 6
        )
    }
}

// MARK: - Side-rail action row

private struct CapRailAction: View {
    let label: String
    let icon: String
    var isPrimary: Bool = false
    /// Sticky toggled state (Pin "on"). Distinct from `isPrimary`.
    var isActive: Bool = false
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            content
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0; if hovered { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() } }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .animation(.easeOut(duration: 0.12), value: isActive)
    }

    private var content: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: (isPrimary || isActive) ? .semibold : .regular))
                .frame(width: 14, alignment: .center)
            Text(label)
                .font(.system(size: 12, weight: (isPrimary || isActive) ? .medium : .regular))
            Spacer(minLength: 0)
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(backgroundFill)
        )
    }

    /// Reusable label for the rail's "More" menu button so the visual
    /// rhythm matches the rest of the rail rows.
    static var menuLabel: some View {
        CapRailMoreLabel(label: "More")
    }

    private var foregroundColor: Color {
        if isActive { return ThemedScopeAccent.amber }
        if isPrimary { return hovered ? ThemedScopeAccent.amber : ThemedScopeAccent.brass }
        if hovered { return ThemedScopeInk.primary }
        return ThemedScopeInk.faint
    }

    private var backgroundFill: Color {
        if isActive { return ThemedScopeAccent.amber.opacity(hovered ? 0.18 : 0.1) }
        if isPrimary {
            return hovered ? ThemedScopeAccent.amber.opacity(0.14) : ThemedScopeAccent.amber.opacity(0.07)
        }
        return hovered ? ThemedScopeEdge.subtle : Color.clear
    }
}

private struct CapRailMoreLabel: View {
    let label: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .regular))
                .frame(width: 14, alignment: .center)
            Text(label)
                .font(.system(size: 12, weight: .regular))
            Spacer(minLength: 0)
        }
        .foregroundStyle(ThemedScopeInk.faint)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private struct CapWorkflowAction: View {
    let workflow: Workflow
    let isRunning: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: isRunning ? "hourglass" : workflow.icon)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 14, alignment: .center)
                    .foregroundStyle(workflow.color.color)
                Text(workflow.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if workflow.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(workflow.color.color.opacity(0.75))
                }
            }
            .foregroundStyle(hovered || isRunning ? ThemedScopeInk.primary : ThemedScopeInk.faint)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(isRunning ? workflow.color.color.opacity(0.14) : (hovered ? workflow.color.color.opacity(0.10) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(workflow.color.color.opacity(isRunning || hovered ? 0.24 : 0), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
        .onHover { hovered = $0 }
        .help(workflow.description.isEmpty ? workflow.name : workflow.description)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .animation(.easeOut(duration: 0.12), value: isRunning)
    }
}
