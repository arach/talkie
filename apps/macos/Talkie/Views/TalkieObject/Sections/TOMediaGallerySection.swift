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
                // Section header — editorial "· MEDIA · count" eyebrow
                // followed by a trailing hairline. Mirrors the section
                // treatment in the new Note / Capture detail surfaces.
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("· MEDIA")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(2.8)
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(0.62))

                    let totalCount = recording.screenshots.count + recording.clips.count
                    Text("\(totalCount)")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .tracking(1.4)
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(0.48))

                    ThemedScopeRule(.subtle)
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
