//
//  TalkieInternalDrag.swift
//  TalkieKit
//
//  Private pasteboard marker for drags that originate inside Talkie surfaces.
//

import AppKit
import UniformTypeIdentifiers

public enum TalkieInternalDrag {
    public static let typeIdentifier = "to.talkie.app.internal-drag"
    public static let utType = UTType(exportedAs: typeIdentifier)
    public static let pasteboardType = NSPasteboard.PasteboardType(typeIdentifier)

    public static func isInternal(_ providers: [NSItemProvider]) -> Bool {
        providers.contains { provider in
            provider.registeredTypeIdentifiers.contains(typeIdentifier)
                || provider.hasItemConformingToTypeIdentifier(typeIdentifier)
        }
    }

    @discardableResult
    public static func mark(_ provider: NSItemProvider) -> NSItemProvider {
        provider.registerDataRepresentation(
            forTypeIdentifier: typeIdentifier,
            visibility: .all
        ) { completion in
            completion(Data("talkie-internal-drag".utf8), nil)
            return nil
        }
        return provider
    }

    public static func pasteboardItem(for url: URL) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: NSPasteboard.PasteboardType(UTType.fileURL.identifier))
        item.setString(url.absoluteString, forType: NSPasteboard.PasteboardType(UTType.url.identifier))
        item.setString("1", forType: pasteboardType)
        return item
    }
}
