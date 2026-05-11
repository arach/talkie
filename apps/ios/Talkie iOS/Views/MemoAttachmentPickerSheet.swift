//
//  MemoAttachmentPickerSheet.swift
//  Talkie iOS
//
//  Quick add surface for memo image attachments.
//

import SwiftUI
import Photos

struct MemoAttachmentPickerSheet: View {
    let recentAssets: [PHAsset]
    let photoAuthorizationStatus: PHAuthorizationStatus
    let onChooseFromLibrary: () -> Void
    let onTakePhoto: () -> Void
    let onScanText: (() -> Void)?
    let onSelectRecentAsset: (PHAsset) -> Void

    init(
        recentAssets: [PHAsset],
        photoAuthorizationStatus: PHAuthorizationStatus,
        onChooseFromLibrary: @escaping () -> Void,
        onTakePhoto: @escaping () -> Void,
        onScanText: (() -> Void)? = nil,
        onSelectRecentAsset: @escaping (PHAsset) -> Void
    ) {
        self.recentAssets = recentAssets
        self.photoAuthorizationStatus = photoAuthorizationStatus
        self.onChooseFromLibrary = onChooseFromLibrary
        self.onTakePhoto = onTakePhoto
        self.onScanText = onScanText
        self.onSelectRecentAsset = onSelectRecentAsset
    }

    private let thumbnailManager = PHCachingImageManager()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Capsule()
                .fill(Color.textTertiary.opacity(0.45))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, Spacing.sm)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Add Attachment")
                    .font(.bodyLarge)
                    .foregroundColor(.textPrimary)

                Text("Pick a recent screenshot, choose from your library, or take a new photo.")
                    .font(.bodySmall)
                    .foregroundColor(.textSecondary)
            }

            HStack(spacing: Spacing.sm) {
                AttachmentPickerActionCard(
                    icon: "camera.fill",
                    title: "Camera",
                    subtitle: "Take a new photo",
                    tint: .recording,
                    action: onTakePhoto
                )

                AttachmentPickerActionCard(
                    icon: "photo.on.rectangle",
                    title: "Library",
                    subtitle: "Choose from Photos",
                    tint: .active,
                    action: onChooseFromLibrary
                )
            }

            if let onScanText {
                AttachmentPickerActionCard(
                    icon: "text.viewfinder",
                    title: "Scan Text",
                    subtitle: "Extract text from an image",
                    tint: .purple,
                    action: onScanText
                )
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Recent")
                    .font(.techLabel)
                    .tracking(1.5)
                    .foregroundColor(.textSecondary)

                if !recentAssets.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.xs) {
                            ForEach(recentAssets, id: \.localIdentifier) { asset in
                                MemoAttachmentRecentAssetButton(
                                    asset: asset,
                                    thumbnailManager: thumbnailManager,
                                    action: { onSelectRecentAsset(asset) }
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } else {
                    AttachmentPickerEmptyState(
                        photoAuthorizationStatus: photoAuthorizationStatus
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.lg)
        .presentationBackground(Color.surfaceSecondary.opacity(0.94))
    }
}

struct AttachmentPickerActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .fill(tint.opacity(0.14))
                        .frame(width: 42, height: 42)

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.bodySmall)
                        .foregroundColor(.textPrimary)

                    Text(subtitle)
                        .font(.techLabelSmall)
                        .foregroundColor(.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
            .background(Color.surfacePrimary.opacity(0.72))
            .cornerRadius(CornerRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .strokeBorder(Color.borderPrimary.opacity(0.45), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct MemoAttachmentRecentAssetButton: View {
    let asset: PHAsset
    let thumbnailManager: PHCachingImageManager
    let action: () -> Void

    @State private var image: UIImage?

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(Color.surfacePrimary.opacity(0.8))
                    .frame(width: 84, height: 84)

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.textTertiary)
                }

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    .padding(6)
            }
        }
        .buttonStyle(.plain)
        .task(id: asset.localIdentifier) {
            await loadThumbnail()
        }
    }

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
                image = result
                continuation.resume()
            }
        }
    }
}

private struct AttachmentPickerEmptyState: View {
    let photoAuthorizationStatus: PHAuthorizationStatus

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.active)

            VStack(alignment: .leading, spacing: 2) {
                Text(messageTitle)
                    .font(.bodySmall)
                    .foregroundColor(.textPrimary)

                Text(messageBody)
                    .font(.techLabelSmall)
                    .foregroundColor(.textTertiary)
            }

            Spacer()
        }
        .padding(Spacing.md)
        .background(Color.surfacePrimary.opacity(0.6))
        .cornerRadius(CornerRadius.md)
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
