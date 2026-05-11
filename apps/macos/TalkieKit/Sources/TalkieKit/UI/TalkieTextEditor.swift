//
//  TalkieTextEditor.swift
//  TalkieKit
//
//  NSTextView-backed text editor shared between Talkie and TalkieAgent.
//  Provides reliable cursor positioning, text selection, and keyboard shortcuts
//  in any window type including .nonactivatingPanel.
//

import SwiftUI
import AppKit

/// A text editor backed by NSTextView that properly handles cursor, selection,
/// and keyboard shortcuts (Cmd+A/C/V/X/Z) in all window types.
public struct TalkieTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange?

    var font: NSFont = .systemFont(ofSize: 14)
    var textColor: NSColor = .labelColor
    var insertionPointColor: NSColor = .controlAccentColor

    public init(
        text: Binding<String>,
        selectedRange: Binding<NSRange?>,
        font: NSFont = .systemFont(ofSize: 14),
        textColor: NSColor = .labelColor,
        insertionPointColor: NSColor = .controlAccentColor
    ) {
        self._text = text
        self._selectedRange = selectedRange
        self.font = font
        self.textColor = textColor
        self.insertionPointColor = insertionPointColor
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = TalkieNSTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = font
        textView.textColor = textColor
        textView.insertionPointColor = insertionPointColor

        // Text container setup
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        // Typography
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: 0, height: 0)

        scrollView.documentView = textView

        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Update text if changed externally
        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            // Try to preserve selection
            if selectedRange.location + selectedRange.length <= text.count {
                textView.setSelectedRange(selectedRange)
            }
        }

        // Update styling
        textView.font = font
        textView.textColor = textColor
        textView.insertionPointColor = insertionPointColor
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    public class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TalkieTextEditor

        init(_ parent: TalkieTextEditor) {
            self.parent = parent
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()

            // Only update if there's an actual selection (length > 0)
            // or clear it if selection is collapsed
            if range.length > 0 {
                parent.selectedRange = range
            } else {
                parent.selectedRange = nil
            }
        }
    }
}

// MARK: - Custom NSTextView

/// NSTextView subclass that handles keyboard shortcuts in all window types,
/// including .nonactivatingPanel where standard responder chain may not work.
public class TalkieNSTextView: NSTextView {
    override public func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Let standard shortcuts work (Cmd+A, Cmd+C, Cmd+V, etc.)
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "a": // Select all
                selectAll(nil)
                return true
            case "c": // Copy
                copy(nil)
                return true
            case "v": // Paste
                paste(nil)
                return true
            case "x": // Cut
                cut(nil)
                return true
            case "z": // Undo/Redo
                if event.modifierFlags.contains(.shift) {
                    undoManager?.redo()
                } else {
                    undoManager?.undo()
                }
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}
