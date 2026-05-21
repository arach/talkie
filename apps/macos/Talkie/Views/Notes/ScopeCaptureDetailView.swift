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
//  Palette: PEARL on FROST. The cool mat reads cleaner behind a
//  screenshot than warm cream does.
//

import AppKit
import SwiftUI
import TalkieKit

private enum CapFont {
    static func display(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        Font.system(size: size, weight: weight, design: .serif)
    }
    static func displayItalic(size: CGFloat) -> Font {
        Font.system(size: size, weight: .regular, design: .serif).italic()
    }
    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - View

struct ScopeCaptureDetailView: View {
    let capture: TalkieObject

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
            .background(ScopeCanvas.canvas)
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

    private var sequence: String {
        let prefix = isTextCapture ? "S-" : "C-"
        return prefix + String(abs(capture.id.hashValue) % 10000).leftPadded(to: 4, with: "0")
    }

    private var sourceLabel: String {
        if isTextCapture {
            return "Quick Selection · text"
        }
        let mode = primaryShot?.captureMode ?? "screenshot"
        return "Hyper+S · \(mode)"
    }

    private var channelLabel: String {
        isTextCapture ? "CH-05 · SELECTION" : "CH-05 · CAPTURE"
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
        primaryShot?.filename ?? "capture-\(sequence.lowercased()).png"
    }

    private var derivedCaption: String? {
        // For now derive from window title or app name; OCR not yet wired.
        if let t = primaryShot?.windowTitle, !t.isEmpty { return t }
        if let a = primaryShot?.appName, !a.isEmpty { return "From \(a)" }
        return nil
    }

    // MARK: - Sections

    private func openInDefault() {
        guard let url = imageURL else { return }
        NSWorkspace.shared.open(url)
    }

    @ViewBuilder
    private func heroColumn(bodyPad: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Eyebrow — sequence + channel + source on the left, date/
            // time on the right. Replaces the old top toolbar identity.
            HStack(spacing: 10) {
                Text(sequence)
                    .font(CapFont.mono(size: 9, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(ScopeKind.capture)
                Text("· \(channelLabel)")
                    .font(CapFont.mono(size: 9, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(ScopeInk.faint)
                ScopeRule(.subtle)
                Text("\(dateLabel) · \(timeLabel)")
                    .font(CapFont.mono(size: 9))
                    .tracking(1.8)
                    .foregroundStyle(ScopeInk.faint)
            }

            // Title — serif for text captures (it's the passage title),
            // mono for image captures (it's a filename).
            if isTextCapture {
                Text(capture.displayTitle)
                    .font(CapFont.display(size: 22, weight: .medium))
                    .tracking(-0.3)
                    .foregroundStyle(ScopeInk.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                Text(bylineTextCapture)
                    .font(CapFont.mono(size: 10))
                    .tracking(1.6)
                    .foregroundStyle(ScopeInk.faint)
                    .padding(.top, 6)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(filename)
                        .font(CapFont.mono(size: 18, weight: .medium))
                        .foregroundStyle(ScopeInk.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(dimensions) · \(fileSize)")
                        .font(CapFont.mono(size: 10))
                        .tracking(1.6)
                        .foregroundStyle(ScopeInk.faint)
                }
                .padding(.top, 12)
            }

            // Derived caption — italic, greyed (image captures only;
            // text captures don't need a "derived" tag since the body
            // IS the content).
            if !isTextCapture, let caption = derivedCaption {
                HStack(spacing: 8) {
                    Text("· DERIVED")
                        .font(CapFont.mono(size: 8.5, weight: .semibold))
                        .tracking(2.8)
                        .foregroundStyle(ScopeInk.faint)
                    Text(caption)
                        .font(CapFont.displayItalic(size: 12.5))
                        .foregroundStyle(ScopeInk.faint)
                        .lineLimit(2)
                }
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
                            .font(CapFont.mono(size: 10, weight: .semibold))
                            .tracking(2.2)
                            .foregroundStyle(ScopeBrass.solid)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(ScopeAmber.solid.opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(ScopeAmber.solid.opacity(0.40), lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)
                Text("⌘N")
                    .font(CapFont.mono(size: 9))
                    .tracking(1.8)
                    .foregroundStyle(ScopeInk.faint)
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
                    .foregroundStyle(ScopeInk.primary)
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
                .fill(ScopeCanvas.surface.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(ScopeEdge.subtle, lineWidth: 0.5)
                )
        )
        .overlay(alignment: .leading) {
            // Marginal rule (blockquote-style)
            Rectangle()
                .fill(ScopeKind.capture.opacity(0.45))
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
                        .fill(ScopeCanvas.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(ScopeEdge.faint, lineWidth: 0.5)
                )
                .shadow(color: Color(red: 46/255, green: 68/255, blue: 82/255).opacity(0.10), radius: 12, y: 6)
        } else {
            // Placeholder mat when image isn't available — cool checker
            Rectangle()
                .fill(ScopeCanvas.surface)
                .aspectRatio(16/10, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay(
                    Text("(image unavailable)")
                        .font(CapFont.displayItalic(size: 12))
                        .foregroundStyle(ScopeInk.subtle)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(ScopeEdge.faint, lineWidth: 0.5)
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
            ScopeRule(.subtle, axis: .vertical)
        }
    }

    @ViewBuilder
    private var actionsBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("· ACTIONS")
                .font(CapFont.mono(size: 8.5, weight: .semibold))
                .tracking(2.8)
                .foregroundStyle(ScopeInk.faint)
                .padding(.bottom, 4)
            CapRailAction(label: "Copy",  icon: "doc.on.doc",            isPrimary: true, action: {})
            CapRailAction(label: "Open",  icon: "arrow.up.right.square", action: openInDefault)
            CapRailAction(label: "Pin",   icon: "pin",                   action: {})
            CapRailAction(label: "Share", icon: "square.and.arrow.up",   action: {})
            ScopeRule(.subtle)
                .padding(.vertical, 4)
            CapRailAction(label: "More",  icon: "ellipsis",              action: {})
        }
    }

    @ViewBuilder
    private func metaBlock(title: String, rows: [(String, String, Bool)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("· \(title.uppercased())")
                .font(CapFont.mono(size: 8.5, weight: .semibold))
                .tracking(2.8)
                .foregroundStyle(ScopeInk.faint)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.0)
                            .font(CapFont.mono(size: 9))
                            .tracking(1.4)
                            .foregroundStyle(ScopeInk.faint)
                        Spacer()
                        Text(row.1)
                            .font(CapFont.mono(size: 10))
                            .tracking(0.6)
                            .foregroundStyle(row.2 ? ScopeKind.capture : ScopeInk.primary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func footRail(bodyPad: CGFloat) -> some View {
        HStack(spacing: 16) {
            Text("· \(dimensions) · \(fileSize) · \(sourceLabel)")
                .font(CapFont.mono(size: 9))
                .tracking(2.2)
                .foregroundStyle(ScopeInk.faint)
            Spacer()
            HStack(spacing: 4) {
                footAction(label: "Reveal in Finder", tone: ScopeInk.muted, action: revealInFinder)
                ScopeRule(.subtle, axis: .vertical)
                    .frame(height: 12)
                    .padding(.horizontal, 4)
                footAction(label: "Delete", tone: Color.hex("A0494D"), action: {})
            }
        }
        .padding(.horizontal, bodyPad)
        .padding(.vertical, 12)
        .background(
            Rectangle().fill(ScopeCanvas.surface)
                .overlay(ScopeRule(.row), alignment: .top)
        )
    }

    @ViewBuilder
    private func footAction(label: String, tone: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label.uppercased())
                .font(CapFont.mono(size: 9, weight: .semibold))
                .tracking(2.2)
                .foregroundStyle(tone)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func revealInFinder() {
        guard let url = imageURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
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
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: isPrimary ? .semibold : .regular))
                    .frame(width: 14, alignment: .center)
                Text(label)
                    .font(.system(size: 12, weight: isPrimary ? .medium : .regular))
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
        .buttonStyle(.plain)
        .onHover { hovered = $0; if hovered { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() } }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    private var foregroundColor: Color {
        if isPrimary { return hovered ? ScopeAmber.solid : ScopeBrass.solid }
        if hovered { return ScopeInk.primary }
        return ScopeInk.faint
    }

    private var backgroundFill: Color {
        if isPrimary {
            return hovered ? ScopeAmber.solid.opacity(0.14) : ScopeAmber.solid.opacity(0.07)
        }
        return hovered ? ScopeEdge.subtle : Color.clear
    }
}

// MARK: - String helper

private extension String {
    func leftPadded(to length: Int, with pad: Character) -> String {
        guard count < length else { return self }
        return String(repeating: pad, count: length - count) + self
    }
}
