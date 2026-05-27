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

// MARK: - View

struct ScopeCaptureDetailView: View {
    let capture: TalkieObject
    /// Library passes through so Delete from the rail/foot can clear selection.
    var onDelete: (() -> Void)? = nil

    private var viewModel: RecordingsViewModel { .shared }

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
    }

    // MARK: - Derived data

    private var primaryShot: RecordingScreenshot? {
        capture.screenshots.first
    }

    private var imageURL: URL? {
        guard let filename = primaryShot?.filename else { return nil }
        return ScreenshotStorage.screenshotsDirectory.appendingPathComponent(filename)
    }

    /// True when this capture is a text passage (Quick Selection) rather
    /// than a screenshot. Drives the hero branch.
    private var isTextCapture: Bool {
        if capture.type == .selection { return true }
        if primaryShot == nil, let text = capture.text, !text.isEmpty { return true }
        return false
    }

    private var sourceLabel: String {
        if isTextCapture {
            return "Quick Selection · text"
        }
        let mode = primaryShot?.captureMode ?? "screenshot"
        return "Hyper+S · \(mode)"
    }

    private var channelLabel: String {
        isTextCapture ? "SELECTION" : "CAPTURE"
    }

    private var dimensions: String {
        guard let w = primaryShot?.width, let h = primaryShot?.height else { return "—" }
        return "\(w) × \(h)"
    }

    private var fileSize: String {
        guard let url = imageURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let bytes = attrs[.size] as? Int else { return "—" }
        return formatBytes(bytes)
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
        primaryShot?.filename ?? (isTextCapture ? "selection" : "capture")
    }

    private var derivedCaption: String? {
        // For now derive from window title or app name; OCR not yet wired.
        if let t = primaryShot?.windowTitle, !t.isEmpty { return t }
        if let a = primaryShot?.appName, !a.isEmpty { return "From \(a)" }
        return nil
    }

    private var imageHeadline: String {
        derivedCaption ?? capture.displayTitle
    }

    private var imageByline: String {
        "\(filename) · \(dimensions) · \(fileSize)"
    }

    // MARK: - Sections

    private func openInDefault() {
        guard let url = imageURL else { return }
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
                    heroImage
                }
            }
            .padding(.top, 20)
            .frame(maxWidth: .infinity, alignment: .center)

            // Promote-to-Note CTA
            HStack(spacing: 12) {
                Button(action: {}) {
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
        if let appName = primaryShot?.appName, !appName.isEmpty {
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

    @ViewBuilder
    private var heroImage: some View {
        if let url = imageURL, let nsImage = NSImage(contentsOf: url) {
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
                .shadow(color: Color(red: 46/255, green: 68/255, blue: 82/255).opacity(0.10), radius: 12, y: 6)
                // Drag the screenshot file out to other apps (Slack /
                // Messages / Finder). Pasteboard carries the on-disk URL
                // so receivers treat it as a real file, not bitmap data.
                .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        } else {
            // Placeholder mat when image isn't available — cool checker
            Rectangle()
                .fill(ThemedScopeCanvas.surface)
                .aspectRatio(16/10, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay(
                    Text("(image unavailable)")
                        .font(ScopeType.displayItalic(size: 12))
                        .foregroundStyle(ThemedScopeInk.subtle)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(ThemedScopeEdge.faint, lineWidth: 0.5)
                )
        }
    }

    @ViewBuilder
    private func marginColumn(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            actionsBlock
            metaBlock(
                title: "Capture",
                rows: [
                    ("source", sourceLabel, true),
                    ("captured", "\(dateLabel) · \(timeLabel)", false),
                    ("size", "\(fileSize) · \(dimensions)", false),
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
        .padding(.top, 44)
        .padding(.bottom, 28)
        .frame(width: width, alignment: .topLeading)
        .overlay(alignment: .leading) {
            ThemedScopeRule(.subtle, axis: .vertical)
        }
    }

    @ViewBuilder
    private var actionsBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("· ACTIONS")
                .font(ScopeType.mono(size: 8.5, weight: .semibold))
                .tracking(2.8)
                .foregroundStyle(ThemedScopeInk.faint)
                .padding(.bottom, 4)
            CapRailAction(label: "Copy",  icon: "doc.on.doc",            isPrimary: true, action: copyCapture)
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
    private func metaBlock(title: String, rows: [(String, String, Bool)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("· \(title.uppercased())")
                .font(ScopeType.mono(size: 8.5, weight: .semibold))
                .tracking(2.8)
                .foregroundStyle(ThemedScopeInk.faint)
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
            Text("· \(dimensions) · \(fileSize) · \(sourceLabel)")
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
        guard let url = imageURL else { return }
        CaptureMarkupCoordinator.shared.openSession(imageURL: url)
    }

    private func copyCapture() {
        guard let url = imageURL,
              let image = NSImage(contentsOf: url) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    private func revealInFinder() {
        guard let url = imageURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func shareCapture() {
        let items: [Any]
        if let url = imageURL {
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

    private func deleteCapture() {
        Task {
            await viewModel.deleteRecording(capture)
            onDelete?()
        }
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
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
        HStack(spacing: 9) {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .regular))
                .frame(width: 14, alignment: .center)
            Text("More")
                .font(.system(size: 12, weight: .regular))
            Spacer(minLength: 0)
        }
        .foregroundStyle(ThemedScopeInk.faint)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
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
