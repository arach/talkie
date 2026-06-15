//
//  WorkflowMemoSelectorSheet.swift
//  Talkie macOS
//

import SwiftUI
import TalkieKit

// MARK: - Workflow Memo Selector Sheet

struct WorkflowMemoSelectorSheet: View {
    let workflow: WorkflowDefinition
    let memos: [MemoModel]
    let onSelect: (MemoModel) -> Void
    let onCancel: () -> Void

    @State private var selectedMemo: MemoModel?
    @State private var searchText = ""

    private var filteredMemos: [MemoModel] {
        if searchText.isEmpty {
            return memos
        }
        let query = searchText.lowercased()
        return memos.filter {
            $0.displayTitle.lowercased().contains(query) ||
            ($0.transcription?.lowercased().contains(query) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
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

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(Theme.current.fontSM)
                    .foregroundStyle(Theme.current.foregroundSecondary)

                TextField("Search memos...", text: $searchText)
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

            Divider()

            if memos.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "waveform.slash")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.secondary.opacity(0.4))

                    Text("No Transcribed Memos")
                        .font(Theme.current.fontBodyMedium)
                        .foregroundStyle(Theme.current.foregroundSecondary)

                    Text("Record and transcribe a voice memo first")
                        .font(Theme.current.fontSM)
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredMemos.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(Theme.current.fontTitle)
                        .foregroundStyle(.secondary.opacity(0.4))

                    Text("No matching memos")
                        .font(Theme.current.fontBody)
                        .foregroundStyle(Theme.current.foregroundSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedMemo) {
                    ForEach(filteredMemos) { memo in
                        WorkflowMemoRow(memo: memo)
                            .tag(memo)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                onSelect(memo)
                            }
                            .onTapGesture(count: 1) {
                                selectedMemo = memo
                            }
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            // Footer with action button
            HStack {
                Text("\(filteredMemos.count) memo\(filteredMemos.count == 1 ? "" : "s")")
                    .font(Theme.current.fontXS)
                    .foregroundStyle(Theme.current.foregroundSecondary)

                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("Run") {
                    if let memo = selectedMemo {
                        onSelect(memo)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedMemo == nil)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(Spacing.lg)
        }
        .frame(width: 500, height: 500)
        .background(Theme.current.surfaceInput)
    }
}

// MARK: - Workflow Memo Row (MemoModel-compatible)

private struct WorkflowMemoRow: View {
    let memo: MemoModel

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(memo.displayTitle)
                    .font(Theme.current.fontBodyMedium)
                    .foregroundStyle(Theme.current.foreground)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if memo.source != .unknown {
                        Image(systemName: memo.source.icon)
                            .font(.system(size: 9))
                            .foregroundStyle(memo.source.color)
                    }

                    Text(formatDuration(memo.duration))
                        .font(Theme.current.fontXS)

                    Text("·")
                        .font(Theme.current.fontXS)
                        .foregroundStyle(Theme.current.foregroundMuted)

                    Text(memo.createdAt, style: .relative)
                        .font(Theme.current.fontXS)
                }
                .foregroundStyle(Theme.current.foregroundSecondary)
            }

            Spacer()

            if memo.isTranscribing {
                BrailleSpinner(size: 10)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return "\(minutes):\(seconds.formatted(.number.precision(.integerLength(2))))"
    }
}
