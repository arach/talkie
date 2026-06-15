//
//  WorkflowLibrarySelectorSheet.swift
//  Talkie macOS
//

import SwiftUI
import TalkieKit

struct WorkflowLibrarySelectorSheet: View {
    let workflow: WorkflowDefinition
    let onSelect: (TalkieObject) -> Void
    let onCancel: () -> Void

    private let repository = TalkieObjectRepository()

    @State private var objects: [TalkieObject] = []
    @State private var selectedObject: TalkieObject?
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var isVisualWorkflow: Bool {
        workflow.inputs.requiredAssets.contains(.screenshot)
        || workflow.inputs.requiredAssets.contains(.image)
        || workflow.inputs.requiredAssets.contains(.clip)
    }

    private var selectorName: String {
        if isVisualWorkflow { return "Visual Library" }
        if workflow.startsWithTranscribe { return "Audio Library" }
        return "Library"
    }

    private var filteredObjects: [TalkieObject] {
        let eligible = objects.filter(matchesWorkflowInput)
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return eligible }

        return eligible.filter { object in
            object.displayTitle.localizedStandardContains(trimmed)
            || (object.text?.localizedStandardContains(trimmed) ?? false)
            || (object.notes?.localizedStandardContains(trimmed) ?? false)
            || object.type.displayName.localizedStandardContains(trimmed)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 560, height: 560)
        .background(Theme.current.surfaceInput)
        .task { await loadObjects() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Run Workflow")
                    .font(Theme.current.fontTitleBold)

                HStack(spacing: 6) {
                    Image(systemName: workflow.icon)
                        .foregroundStyle(workflow.color.color)
                    Text(workflow.name)
                        .font(Theme.current.fontBody)
                        .foregroundStyle(Theme.current.foregroundSecondary)
                }
            }

            Spacer()

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(Theme.current.fontHeadline)
                    .foregroundStyle(Theme.current.foregroundSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.lg)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(Theme.current.fontSM)
                .foregroundStyle(Theme.current.foregroundSecondary)

            TextField("Search \(selectorName.lowercased())...", text: $searchText)
                .textFieldStyle(.plain)
                .font(Theme.current.fontBody)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(Theme.current.fontSM)
                        .foregroundStyle(Theme.current.foregroundSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.sm)
        .background(Theme.current.surface1)
        .clipShape(.rect(cornerRadius: CornerRadius.sm))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: Spacing.sm) {
                BrailleSpinner(size: 14)
                Text("Loading \(selectorName.lowercased())...")
                    .font(Theme.current.fontSM)
                    .foregroundStyle(Theme.current.foregroundSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            emptyState(icon: "exclamationmark.triangle", title: "Library unavailable", detail: errorMessage)
        } else if filteredObjects.isEmpty {
            let title = isVisualWorkflow ? "No visual library items" : "No matching library items"
            let detail = isVisualWorkflow
                ? "Capture or attach an image, then run this workflow against it."
                : "Create a memo, note, dictation, or capture that matches this workflow."
            emptyState(icon: isVisualWorkflow ? "photo.on.rectangle.angled" : "square.stack.3d.up", title: title, detail: detail)
        } else {
            List(selection: $selectedObject) {
                ForEach(filteredObjects) { object in
                    Button {
                        selectedObject = object
                    } label: {
                        WorkflowLibraryObjectRow(object: object, isVisualWorkflow: isVisualWorkflow)
                    }
                    .buttonStyle(.plain)
                    .tag(object)
                }
            }
            .listStyle(.inset)
        }
    }

    private var footer: some View {
        HStack {
            Text("\(filteredObjects.count) \(filteredObjects.count == 1 ? "item" : "items")")
                .font(Theme.current.fontXS)
                .foregroundStyle(Theme.current.foregroundSecondary)

            Spacer()

            Button("Cancel") {
                onCancel()
            }
            .keyboardShortcut(.escape, modifiers: [])

            Button("Run") {
                if let selectedObject {
                    onSelect(selectedObject)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedObject == nil)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(Spacing.lg)
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.current.foregroundMuted.opacity(0.5))

            Text(title)
                .font(Theme.current.fontBodyMedium)
                .foregroundStyle(Theme.current.foregroundSecondary)

            Text(detail)
                .font(Theme.current.fontSM)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.current.foregroundMuted)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadObjects() async {
        do {
            let loaded = try await repository.fetchRecordings(limit: 500)
            let initialSelection = loaded.first(where: matchesWorkflowInput)
            await MainActor.run {
                objects = loaded
                selectedObject = initialSelection
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func matchesWorkflowInput(_ object: TalkieObject) -> Bool {
        guard object.type != .segment else { return false }

        if isVisualWorkflow {
            return workflow.inputs.requiredAssets.allSatisfy { asset in
                switch asset {
                case .screenshot:
                    return !object.screenshots.isEmpty
                case .image:
                    return hasImage(object)
                case .clip:
                    return !object.clips.isEmpty
                case .transcript, .text:
                    return hasText(object)
                case .audio:
                    return object.hasAudio
                }
            }
        }

        if workflow.startsWithTranscribe {
            return object.hasAudio
        }

        if workflow.inputs.requiredAssets.contains(.transcript)
            || workflow.inputs.requiredAssets.contains(.text) {
            return hasText(object)
        }

        guard let recordType = WorkflowRecordType(object.type) else { return false }
        return workflow.inputs.acceptedRecordTypes.contains(recordType)
    }

    private func hasText(_ object: TalkieObject) -> Bool {
        !(object.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        || !(object.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private func hasImage(_ object: TalkieObject) -> Bool {
        !object.screenshots.isEmpty
        || object.attachments.contains { $0.kind == .image }
    }
}

private struct WorkflowLibraryObjectRow: View {
    let object: TalkieObject
    let isVisualWorkflow: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: rowIcon)
                .font(Theme.current.fontSM)
                .foregroundStyle(Theme.current.foregroundSecondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(object.displayTitle)
                    .font(Theme.current.fontBodyMedium)
                    .foregroundStyle(Theme.current.foreground)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(object.type.displayName)
                    Text("·")
                    Text(object.createdAt, format: .dateTime.month().day().hour().minute())

                    if object.screenshots.count > 0 {
                        Text("·")
                        Text("\(object.screenshots.count) screenshot\(object.screenshots.count == 1 ? "" : "s")")
                    }

                    if imageAttachmentCount > 0 {
                        Text("·")
                        Text("\(imageAttachmentCount) image\(imageAttachmentCount == 1 ? "" : "s")")
                    }
                }
                .font(Theme.current.fontXS)
                .foregroundStyle(Theme.current.foregroundSecondary)

                if let preview = object.transcriptPreview, !isVisualWorkflow {
                    Text(preview)
                        .font(Theme.current.fontXS)
                        .foregroundStyle(Theme.current.foregroundMuted)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    private var rowIcon: String {
        if isVisualWorkflow { return "photo.on.rectangle" }
        return object.type.icon
    }

    private var imageAttachmentCount: Int {
        object.attachments.filter { $0.kind == .image }.count
    }
}
