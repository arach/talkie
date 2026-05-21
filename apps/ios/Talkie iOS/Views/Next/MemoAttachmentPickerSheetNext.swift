//
//  MemoAttachmentPickerSheetNext.swift
//  Talkie iOS
//
//  Next-style add surface for memo image attachments.
//

import Photos
import SwiftUI
import UIKit

struct MemoAttachmentPickerSheetNext: View {
    let recentAssets: [PHAsset]
    let photoAuthorizationStatus: PHAuthorizationStatus
    let onChooseFromLibrary: () -> Void
    let onTakePhoto: () -> Void
    let onScanText: () -> Void
    let onSelectRecentAsset: (PHAsset) -> Void

    @ObservedObject private var theme = ThemeManager.shared
    private let thumbnailManager = PHCachingImageManager()

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Capsule()
                    .fill(theme.colors.textTertiary.opacity(0.45))
                    .frame(width: 36, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Add Attachment")
                        .talkieType(.headlineSecondary)
                        .foregroundStyle(theme.colors.textPrimary)

                    Text("Pick a recent screenshot, choose from Photos, take a new photo, or scan text.")
                        .talkieType(.preview)
                        .foregroundStyle(theme.colors.textSecondary)
                }

                HStack(spacing: 10) {
                    AttachmentPickerActionCardNext(
                        icon: "camera.fill",
                        title: "Camera",
                        subtitle: "Take photo",
                        tint: .red,
                        action: onTakePhoto
                    )

                    AttachmentPickerActionCardNext(
                        icon: "photo.on.rectangle",
                        title: "Library",
                        subtitle: "Choose image",
                        tint: theme.currentTheme.chrome.accent,
                        action: onChooseFromLibrary
                    )
                }

                AttachmentPickerActionCardNext(
                    icon: "text.viewfinder",
                    title: "Scan Text",
                    subtitle: "Extract OCR and append it to notes",
                    tint: .purple,
                    action: onScanText
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("RECENT")
                        .talkieType(.channelLabel)
                        .foregroundStyle(theme.colors.textTertiary)

                    if recentAssets.isEmpty {
                        AttachmentPickerEmptyStateNext(photoAuthorizationStatus: photoAuthorizationStatus)
                    } else {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(recentAssets, id: \.localIdentifier) { asset in
                                    MemoAttachmentRecentAssetButtonNext(
                                        asset: asset,
                                        thumbnailManager: thumbnailManager,
                                        action: { onSelectRecentAsset(asset) }
                                    )
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .scrollIndicators(.hidden)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
    }
}

private struct AttachmentPickerActionCardNext: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    let action: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(tint.opacity(0.14))
                        .frame(width: 42, height: 42)

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .talkieType(.preview)
                        .foregroundStyle(theme.colors.textPrimary)

                    Text(subtitle)
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(theme.colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                theme.currentTheme.chrome.edgeFaint,
                                lineWidth: theme.currentTheme.chrome.hairlineWidth
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct MemoAttachmentRecentAssetButtonNext: View {
    let asset: PHAsset
    let thumbnailManager: PHCachingImageManager
    let action: () -> Void

    @ObservedObject private var theme = ThemeManager.shared
    @State private var image: UIImage?

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.colors.cardBackground)
                    .frame(width: 84, height: 84)

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(theme.colors.textTertiary)
                        .frame(width: 84, height: 84)
                }

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    .padding(6)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        theme.currentTheme.chrome.edgeFaint,
                        lineWidth: theme.currentTheme.chrome.hairlineWidth
                    )
            )
        }
        .buttonStyle(.plain)
        .task(id: asset.localIdentifier) {
            await loadThumbnail()
        }
    }

    @MainActor
    private func loadThumbnail() async {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            thumbnailManager.requestImage(
                for: asset,
                targetSize: CGSize(width: 168, height: 168),
                contentMode: .aspectFill,
                options: options
            ) { result, _ in
                Task { @MainActor in
                    image = result
                    continuation.resume()
                }
            }
        }
    }
}

private struct AttachmentPickerEmptyStateNext: View {
    let photoAuthorizationStatus: PHAuthorizationStatus

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(theme.currentTheme.chrome.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(messageTitle)
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textPrimary)

                Text(messageBody)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
            }

            Spacer()
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            theme.currentTheme.chrome.edgeFaint,
                            lineWidth: theme.currentTheme.chrome.hairlineWidth
                        )
                )
        )
    }

    private var messageTitle: String {
        switch photoAuthorizationStatus {
        case .denied, .restricted:
            return "Recent photos unavailable"
        default:
            return "No recent screenshots yet"
        }
    }

    private var messageBody: String {
        switch photoAuthorizationStatus {
        case .denied, .restricted:
            return "Use Library or Camera to attach an image."
        default:
            return "Library and Camera are still ready whenever you need them."
        }
    }
}
