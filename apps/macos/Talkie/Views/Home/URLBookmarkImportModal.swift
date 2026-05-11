//
//  URLBookmarkImportModal.swift
//  Talkie
//
//  Small homepage modal for saving a URL as a bookmark capture.
//

import AppKit
import SwiftUI
import TalkieKit

struct URLBookmarkImportModal: View {
    @Environment(\.dismiss) private var dismiss

    @State private var urlString: String
    @State private var titleOverride: String = ""
    @State private var isImporting = false
    @State private var errorMessage: String?

    init(initialURL: String = URLBookmarkImportModal.clipboardURLString ?? "") {
        _urlString = State(initialValue: initialURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("SAVE URL AS CAPTURE")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Text("Talkie will fetch the page title, site details, and Open Graph image, then save it as a bookmark-style capture.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Web URL")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foreground)

                TextField("https://example.com/article", text: $urlString)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.current.fontSM)
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Optional Title Override")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foreground)

                TextField("Leave blank to use the page title", text: $titleOverride)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.current.fontSM)
            }

            if let errorMessage {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(errorMessage)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foreground)
                }
                .padding(Spacing.sm)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(CornerRadius.sm)
            }

            Spacer()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    saveBookmark()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        if isImporting {
                            BrailleSpinner(size: 12)
                        } else {
                            Image(systemName: "bookmark")
                                .font(.system(size: 12))
                        }
                        Text(isImporting ? "Saving..." : "Save Bookmark")
                            .font(Theme.current.fontSMMedium)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background(canSave ? Theme.current.accent : Theme.current.foregroundMuted)
                    .cornerRadius(CornerRadius.sm)
                }
                .buttonStyle(.plain)
                .disabled(!canSave || isImporting)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.lg)
        .frame(width: 520, height: 300)
    }

    private var canSave: Bool {
        normalizedURL != nil
    }

    private var normalizedURL: URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return url
        }

        if !trimmed.contains("://"),
           let url = URL(string: "https://\(trimmed)") {
            return url
        }

        return nil
    }

    private func saveBookmark() {
        guard let normalizedURL else {
            errorMessage = "Enter a valid http or https URL."
            return
        }

        errorMessage = nil
        isImporting = true

        Task { @MainActor in
            defer { isImporting = false }

            do {
                _ = try await URLBookmarkImportService.shared.importBookmark(
                    from: normalizedURL,
                    suggestedTitle: titleOverride.trimmedNonEmpty
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private static var clipboardURLString: String? {
        guard let string = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            let url = URL(string: string),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https" else {
            return nil
        }
        return string
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
