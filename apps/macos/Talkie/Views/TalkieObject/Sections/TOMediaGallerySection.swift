//
//  TOMediaGallerySection.swift
//  Talkie
//
//  Media gallery section — screenshots and clips.
//  Self-gates: renders nothing if no media.
//

import SwiftUI
import TalkieKit

struct TOMediaGallerySection: View {
    let slot: SectionSlot
    let recording: TalkieObject
    let settings: SettingsManager

    private var hasMedia: Bool {
        !recording.screenshots.isEmpty || !recording.clips.isEmpty
    }

    var body: some View {
        if hasMedia {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Section header
                HStack {
                    Text("MEDIA")
                        .font(settings.fontXSMedium)
                        .tracking(Tracking.wide)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    let totalCount = recording.screenshots.count + recording.clips.count
                    Text("\(totalCount)")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.current.foreground.opacity(0.08))
                        .clipShape(Capsule())

                    Spacer()
                }

                if slot.mode == .hero {
                    // Full-width layout for hero mode
                    VStack(spacing: Spacing.sm) {
                        ForEach(recording.screenshots, id: \.filename) { screenshot in
                            LargeAttachmentView(screenshot: screenshot)
                        }
                        ForEach(recording.clips, id: \.filename) { clip in
                            ClipThumbnailView(clip: clip, size: .large)
                        }
                    }
                } else {
                    // Compact horizontal scroll for non-hero
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.sm) {
                            ForEach(recording.screenshots, id: \.filename) { screenshot in
                                AttachmentThumbnail(screenshot: screenshot)
                            }
                            ForEach(recording.clips, id: \.filename) { clip in
                                ClipThumbnailView(clip: clip)
                            }
                        }
                        .padding(.vertical, Spacing.xs)
                    }
                }
            }
        }
    }
}
