//
//  OCRPreviewSheet.swift
//  Talkie iOS
//
//  Review screen for OCR captures before saving.
//  Shows the scanned photo + extracted text, lets user confirm or cancel.
//

import SwiftUI

struct OCRPreviewData: Identifiable {
    let id = UUID()
    let image: UIImage
    let imageData: Data
    let text: String

    var wordCount: Int {
        text.split(separator: " ").count
    }
}

struct OCRPreviewSheet: View {
    let preview: OCRPreviewData
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surfacePrimary
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        // Photo
                        Image(uiImage: preview.image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 260)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.borderPrimary.opacity(0.3), lineWidth: 0.5)
                            )

                        // OCR result
                        if preview.text.isEmpty {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.orange)
                                Text("No text detected in this image")
                                    .foregroundColor(.textSecondary)
                            }
                            .font(.system(size: 14))
                            .padding(Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.surfaceSecondary)
                            .cornerRadius(12)
                        } else {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                HStack {
                                    TalkieEyebrow(text: "Extracted Text")
                                    Spacer()
                                    Text("\(preview.wordCount) words")
                                        .font(.system(size: 10))
                                        .foregroundColor(.textTertiary)
                                }

                                Text(preview.text)
                                    .font(.body)
                                    .foregroundColor(.textPrimary)
                                    .textSelection(.enabled)
                            }
                            .padding(Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.surfaceSecondary)
                            .cornerRadius(12)
                        }

                        // Save button
                        Button(action: onSave) {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "tray.and.arrow.down.fill")
                                Text("Save Capture")
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.accentColor)
                            .cornerRadius(14)
                        }
                        .padding(.top, Spacing.sm)
                    }
                    .padding(Spacing.md)
                }
            }
            .navigationTitle("Scan Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.textPrimary)
                }
            }
        }
    }
}
