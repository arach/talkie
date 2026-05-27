//
//  ScopeNoteDetailView.swift
//  Talkie
//
//  Editorial detail surface for a single Note. Used by ScopeLibraryView
//  when the selected item's type is .note, replacing TalkieView (which
//  carries audio chrome that doesn't apply to notes).
//
//  Studio source of truth:
//    design/studio/components/studies/MacNoteDetail.tsx
//
//  Composition: toolbar → eyebrow + serif title + mono byline →
//  comfortable body measure with marginal rule → right margin column
//  (provenance + tags) → attachment rail at the foot (replaces the
//  player rail).
//
//  Palette: Scope editorial tokens resolved through the active Talkie
//  theme. Scope keeps the cool-gray paper canon; dark themes receive
//  readable themed paper/ink instead of static Scope inks.
//

import SwiftUI
import TalkieKit

// MARK: - Typography helpers
//
// Note + Capture detail typography used to live here as a private
// `NoteFont` (and a parallel `CapFont` next door), both with system
// serif/mono — bypassing the Cormorant Garamond + JetBrains Mono
// lookup the rest of Scope uses. That's the resolution drift the
// design-system audit flagged. Both now route through `ScopeType`.

// MARK: - View

struct ScopeNoteDetailView: View {
    let note: TalkieObject
    /// Library passes through so Delete from the rail/menu can clear selection.
    var onDelete: (() -> Void)? = nil

    @State private var isEditing = false
    @State private var editedText: String = ""
    @State private var saveTask: Task<Void, Never>? = nil
    @State private var showShareSheet = false

    private var viewModel: RecordingsViewModel { .shared }
    private var repository: TalkieObjectRepository { TalkieObjectRepository() }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            // Margin column scales with width — 220pt at narrow, up to 300pt wide.
            let marginWidth: CGFloat = max(200, min(300, width * 0.18))
            let bodyPad: CGFloat = width < 1300 ? 56 : (width * 0.06)
            let proseMax: CGFloat = min(720, width - marginWidth - bodyPad * 2 - 40)

            VStack(spacing: 0) {
                // Top toolbar removed — actions migrated to the side
                // rail (marginColumn) where they sit alongside provenance
                // and stats. The eyebrow inside the body column carries
                // real source provenance when available.
                HStack(alignment: .top, spacing: 0) {
                    bodyColumn(bodyPad: bodyPad, proseMax: max(400, proseMax))
                    marginColumn(width: marginWidth)
                }
                attachmentRail(bodyPad: bodyPad)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(ThemedScopeCanvas.canvas)
        }
    }

    // MARK: - Computed display data

    private var sourceEyebrow: String? {
        let source = note.source.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return nil }
        return source.uppercased()
    }

    private var dateLabel: String {
        let f = DateFormatter()
        f.locale = .current
        if Calendar.current.isDateInToday(note.createdAt) { return "Today" }
        if Calendar.current.isDateInYesterday(note.createdAt) { return "Yesterday" }
        f.dateFormat = "MMM d"
        return f.string(from: note.createdAt)
    }

    private var timeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: note.createdAt)
    }

    private var bylineText: String {
        let words = note.wordCount
        let screenshots = note.screenshots.count
        let parts: [String] = [
            "\(words) word\(words == 1 ? "" : "s")",
            "\(screenshots) attachment\(screenshots == 1 ? "" : "s")",
            "edited \(dateLabel.lowercased()) · \(timeLabel)"
        ]
        return parts.joined(separator: " · ")
    }

    private var bodyParagraphs: [String] {
        let raw = note.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else {
            return ["(empty note — add content to start)"]
        }
        return raw
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Sections


    @ViewBuilder
    private func bodyColumn(bodyPad: CGFloat, proseMax: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Eyebrow — real source when available; date/time on the right.
            HStack(spacing: 10) {
                if let sourceEyebrow {
                    Text(sourceEyebrow)
                        .font(ScopeType.mono(size: 9, weight: .semibold))
                        .tracking(2.2)
                        .foregroundStyle(ThemedScopeInk.faint)
                }
                ThemedScopeRule(.subtle)
                Text("\(dateLabel) · \(timeLabel)")
                    .font(ScopeType.mono(size: 9, weight: .regular))
                    .tracking(1.8)
                    .foregroundStyle(ThemedScopeInk.faint)
            }

            // Title
            Text(note.displayTitle)
                .font(ScopeType.display(size: 26, weight: .medium))
                .tracking(-0.3)
                .foregroundStyle(ThemedScopeInk.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            // Byline
            Text(bylineText)
                .font(ScopeType.mono(size: 10, weight: .regular))
                .tracking(1.6)
                .foregroundStyle(ThemedScopeInk.faint)
                .padding(.top, 6)

            // Body — measure-capped. System sans (SF Pro) at regular
            // weight throughout. The earlier serif lead read heavy on
            // macOS rendering; switching to sans with more line spacing
            // gives the note body the airier feel intentional notes
            // want — closer to a notebook page than a printed article.
            Group {
                if isEditing {
                    TextEditor(text: $editedText)
                        .font(.system(size: 13.5, weight: .regular, design: .default))
                        .foregroundStyle(ThemedScopeInk.primary)
                        .lineSpacing(7)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .frame(minHeight: 220, idealHeight: 320, alignment: .topLeading)
                        .padding(.leading, -5)  // counter TextEditor's insets
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(bodyParagraphs.enumerated()), id: \.offset) { _, paragraph in
                            Text(paragraph)
                                .font(.system(size: 13.5, weight: .regular, design: .default))
                                .foregroundStyle(ThemedScopeInk.dim)
                                .lineSpacing(7)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: proseMax, alignment: .leading)
            .overlay(alignment: .leading) {
                // Marginal rule — like a printed page's gutter. Softer
                // now that the prose itself is lighter.
                Rectangle()
                    .fill(ThemedScopeAccent.note.opacity(0.22))
                    .frame(width: 1)
                    .offset(x: -16)
            }
            .padding(.top, 28)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, bodyPad)
        .padding(.top, 44)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func marginColumn(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            actionsBlock
            metaBlock(
                title: "Provenance",
                rows: [
                    ("created", "\(dateLabel) · \(timeLabel)", false),
                    ("source", note.source.displayName, false),
                ]
            )
            if note.wordCount > 0 {
                metaBlock(
                    title: "Stats",
                    rows: [
                        ("words", "\(note.wordCount)", true),
                        ("attachments", "\(note.screenshots.count)", false),
                    ]
                )
            }
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
            NoteRailAction(
                label: isEditing ? "Done" : "Edit",
                icon:  isEditing ? "checkmark" : "pencil",
                isPrimary: true,
                action: { toggleEdit() }
            )
            NoteRailAction(
                label: note.isStarred ? "Starred" : "Star",
                icon:  note.isStarred ? "star.fill" : "star",
                isActive: note.isStarred,
                action: { Task { await viewModel.toggleStar(note) } }
            )
            NoteRailAction(
                label: note.isPinned ? "Pinned" : "Pin",
                icon:  note.isPinned ? "pin.fill" : "pin",
                isActive: note.isPinned,
                action: { Task { await viewModel.togglePin(note) } }
            )
            NoteRailAction(label: "Share",  icon: "square.and.arrow.up", action: { shareNote() })
            NoteRailAction(label: "Export", icon: "arrow.down.doc",      action: { exportNote() })
            ThemedScopeRule(.subtle)
                .padding(.vertical, 4)
            Menu {
                Button {
                    copyNote()
                } label: {
                    Label("Copy text", systemImage: "doc.on.doc")
                }
                if onDelete != nil {
                    Divider()
                    Button(role: .destructive) {
                        Task {
                            await viewModel.deleteRecording(note)
                            onDelete?()
                        }
                    } label: {
                        Label("Delete note", systemImage: "trash")
                    }
                }
            } label: {
                NoteRailAction.menuLabel
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Action handlers

    private func toggleEdit() {
        if isEditing {
            persistEditedText()
            isEditing = false
        } else {
            editedText = note.text ?? ""
            isEditing = true
        }
    }

    private func persistEditedText() {
        let trimmed = editedText
        guard trimmed != (note.text ?? "") else { return }
        saveTask?.cancel()
        saveTask = Task {
            do {
                var updated = note
                updated.text = trimmed
                updated.lastModified = Date()
                try await repository.saveRecording(updated)
            } catch {
                await MainActor.run {
                    ToastService.shared.showError("Couldn't save note: \(error.localizedDescription)")
                }
            }
        }
    }

    private func shareNote() {
        let text = note.text ?? ""
        guard !text.isEmpty else { return }
        let picker = NSSharingServicePicker(items: [text])
        if let window = NSApp.keyWindow,
           let content = window.contentView {
            picker.show(relativeTo: .zero, of: content, preferredEdge: .minY)
        }
    }

    private func copyNote() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(note.text ?? "", forType: .string)
    }

    private func exportNote() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        let base = note.displayTitle
            .components(separatedBy: CharacterSet(charactersIn: "/:\\"))
            .joined(separator: "-")
        panel.nameFieldStringValue = "\(base).md"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let header = "# \(note.displayTitle)\n\n"
            let body = note.text ?? ""
            let content = header + body + "\n"
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                ToastService.shared.showSuccess("Exported to \(url.lastPathComponent)")
            } catch {
                ToastService.shared.showError("Export failed: \(error.localizedDescription)")
            }
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
                            .foregroundStyle(row.2 ? ThemedScopeAccent.brass : ThemedScopeInk.primary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func attachmentRail(bodyPad: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 8) {
                Text("· ATTACHMENTS")
                    .font(ScopeType.mono(size: 9, weight: .semibold))
                    .tracking(2.8)
                    .foregroundStyle(ThemedScopeInk.faint)
                Text("\(note.screenshots.count)")
                    .font(ScopeType.mono(size: 9, weight: .regular))
                    .foregroundStyle(ThemedScopeInk.faint)
            }
            if note.screenshots.isEmpty {
                Text("none yet")
                    .font(ScopeType.mono(size: 9, weight: .regular))
                    .tracking(1.6)
                    .foregroundStyle(ThemedScopeInk.faint)
            } else {
                ForEach(Array(note.screenshots.prefix(6).enumerated()), id: \.offset) { _, ss in
                    attachmentChip(filename: ss.filename, meta: "\(ss.width ?? 0)×\(ss.height ?? 0)")
                }
            }
            Spacer()
            Button(action: pickAttachment) {
                Text("+ ADD")
                    .font(ScopeType.mono(size: 9, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(ThemedScopeAccent.note)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(ThemedScopeCanvas.canvasAlt.opacity(0.65))
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(ThemedScopeEdge.faint, lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, bodyPad)
        .padding(.vertical, 14)
        .background(
            Rectangle().fill(ThemedScopeCanvas.surface)
                .overlay(ThemedScopeRule(.row), alignment: .top)
        )
    }

    // MARK: - Attachment picker

    private func pickAttachment() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.message = "Attach files to this note"
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                addAttachment(from: url)
            }
        }
    }

    private func addAttachment(from url: URL) {
        guard let result = AttachmentStorage.save(from: url, recordingId: note.id) else { return }
        let kind = AttachmentKind.from(extension: url.pathExtension)
        var width: Int?
        var height: Int?
        if kind == .image, let image = NSImage(contentsOf: url) {
            width = Int(image.size.width)
            height = Int(image.size.height)
        }
        let attachment = RecordingAttachment(
            filename: result.filename,
            originalName: url.lastPathComponent,
            kind: kind,
            fileSizeBytes: result.size,
            width: width,
            height: height
        )
        Task {
            do {
                let fresh = try await repository.fetchRecording(id: note.id)
                var assets = fresh?.assets ?? TalkieObjectAssets()
                var list = assets.attachments ?? []
                list.append(attachment)
                assets.attachments = list
                try await repository.updateAssets(id: note.id, assetsJSON: assets.toJSON())
                await MainActor.run {
                    ToastService.shared.showSuccess("Attached \(attachment.originalName)")
                }
            } catch {
                await MainActor.run {
                    ToastService.shared.showError("Couldn't attach: \(error.localizedDescription)")
                }
            }
        }
    }

    @ViewBuilder
    private func attachmentChip(filename: String, meta: String) -> some View {
        HStack(spacing: 8) {
            Text("▢")
                .font(ScopeType.mono(size: 11, weight: .regular))
                .foregroundStyle(ThemedScopeAccent.capture)
            VStack(alignment: .leading, spacing: 1) {
                Text(filename)
                    .font(.system(size: 11))
                    .foregroundStyle(ThemedScopeInk.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(meta.uppercased())
                    .font(ScopeType.mono(size: 8.5, weight: .regular))
                    .tracking(1.4)
                    .foregroundStyle(ThemedScopeInk.faint)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(ThemedScopeAccent.capture.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(ThemedScopeAccent.capture.opacity(0.28), lineWidth: 0.5)
                )
        )
        .frame(maxWidth: 220)
    }
}

// MARK: - Side-rail action row
//
// Full-width row in the margin column. Icon + label, hover background.
// Primary action (Edit) gets an amber accent so the most common action
// reads first.

private struct NoteRailAction: View {
    let label: String
    let icon: String
    var isPrimary: Bool = false
    /// When true, render the row as a sticky toggled state (used for
    /// Pin/Star when the value is set). Distinct from `isPrimary`,
    /// which signals the most-common action regardless of state.
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
