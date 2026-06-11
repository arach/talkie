//
//  AgentLiveTrayItem+Paste.swift
//  TalkieAgent
//
//  Lightweight AppKit helpers for Agent-owned Hyper+V quick paste UI.
//

import AppKit
import AVFoundation
import ImageIO
import TalkieKit

extension AgentLiveTrayItem {
    var tempURL: URL { fileURL }

    var image: NSImage? {
        switch kind {
        case .screenshot:
            return Self.thumbnail(forImageAt: fileURL)
        case .clip:
            return Self.thumbnail(forClipAt: fileURL) ?? NSWorkspace.shared.icon(forFile: fileURL.path)
        }
    }

    var previewText: String? {
        guard let text = ocrText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    private static func thumbnail(forImageAt url: URL, maxSize: CGFloat = 180) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private static func thumbnail(forClipAt url: URL, maxSize: CGFloat = 180) -> NSImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSize, height: maxSize)

        do {
            let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            return nil
        }
    }
}
