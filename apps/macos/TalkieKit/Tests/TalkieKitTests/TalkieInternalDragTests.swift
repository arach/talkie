import AppKit
import Testing
@testable import TalkieKit

@Test("Internal drag marker tags item providers")
func internalDragMarkerTagsItemProviders() {
    let provider = NSItemProvider()

    #expect(!TalkieInternalDrag.isInternal([provider]))

    TalkieInternalDrag.mark(provider)

    #expect(TalkieInternalDrag.isInternal([provider]))
}

@Test("Internal drag pasteboard item carries file URL and marker")
func internalDragPasteboardItemCarriesFileURLAndMarker() throws {
    let url = URL(fileURLWithPath: "/Users/example/Desktop/capture.png")
    let item = TalkieInternalDrag.pasteboardItem(for: url)

    #expect(item.string(forType: TalkieInternalDrag.pasteboardType) == "1")
    #expect(item.string(forType: NSPasteboard.PasteboardType("public.file-url")) == url.absoluteString)
    #expect(item.string(forType: NSPasteboard.PasteboardType("public.url")) == url.absoluteString)
}
