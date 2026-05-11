//
//  NotchTrayDrawer.swift
//  Talkie
//
//  Expandable drawer that slides down from the left wing during recording.
//  Shows thumbnail previews of tray items (screenshots + clips).
//  Tap a thumbnail to open TrayViewer; recording continues uninterrupted.
//

import SwiftUI

struct NotchTrayDrawer: View {
    let isExpanded: Bool
    var onHoverChanged: (Bool) -> Void = { _ in }

    private let thumbnailSize: CGFloat = 36
    private let drawerWidth: CGFloat = 160
    private let maxDrawerHeight: CGFloat = 120

    private var screenshots: [TrayScreenshot] {
        ScreenshotTray.shared.items
    }

    private var clips: [TrayClip] {
        ClipTray.shared.items
    }

    private var totalCount: Int {
        screenshots.count + clips.count
    }

    var body: some View {
        if isExpanded && totalCount > 0 {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: thumbnailSize, maximum: thumbnailSize + 8), spacing: 4)
                    ],
                    spacing: 4
                ) {
                    ForEach(screenshots) { item in
                        thumbnailView(image: item.thumbnail, isClip: false)
                            .onTapGesture {
                                TrayViewer.shared.show()
                            }
                            .onDrag {
                                dragProvider(for: item.tempURL)
                            }
                    }

                    ForEach(clips) { item in
                        thumbnailView(image: item.thumbnail, isClip: true)
                            .onTapGesture {
                                TrayViewer.shared.show()
                            }
                            .onDrag {
                                dragProvider(for: item.tempURL)
                            }
                    }
                }
                .padding(6)
            }
            .frame(width: drawerWidth)
            .frame(maxHeight: maxDrawerHeight)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 10,
                    bottomTrailingRadius: 10,
                    topTrailingRadius: 0
                )
                .fill(.ultraThinMaterial)
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 10,
                        bottomTrailingRadius: 10,
                        topTrailingRadius: 0
                    )
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                )
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 10,
                    bottomTrailingRadius: 10,
                    topTrailingRadius: 0
                )
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.15), Color.white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
            )
            .onHover { hovering in
                onHoverChanged(hovering)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func thumbnailView(image: NSImage?, isClip: Bool) -> some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: thumbnailSize, height: thumbnailSize * 0.75)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: thumbnailSize, height: thumbnailSize * 0.75)
            }

            if isClip {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "video.fill")
                            .font(.system(size: 6))
                            .foregroundColor(.white)
                            .padding(2)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                            .padding(2)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }

    private func dragProvider(for url: URL) -> NSItemProvider {
        let provider = NSItemProvider(contentsOf: url) ?? NSItemProvider()
        provider.suggestedName = url.lastPathComponent
        return TalkieInternalDrag.mark(provider)
    }
}
