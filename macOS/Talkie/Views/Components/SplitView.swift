//
//  SplitView.swift
//  Talkie macOS
//
//  Native NSSplitView wrapper for SwiftUI
//  Provides proper macOS split view behavior with resizable dividers
//

import SwiftUI
import AppKit

/// Native macOS split view with resizable dividers
/// Uses NSSplitView for proper native behavior and appearance
struct SplitView<Content: View>: NSViewRepresentable {
    let orientation: NSUserInterfaceLayoutOrientation
    let dividerThickness: CGFloat
    @ViewBuilder let content: () -> Content

    init(
        orientation: NSUserInterfaceLayoutOrientation = .horizontal,
        dividerThickness: CGFloat = 1,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.orientation = orientation
        self.dividerThickness = dividerThickness
        self.content = content
    }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = (orientation == .horizontal)
        splitView.dividerStyle = .thin

        // Extract child views from Content
        let hostingView = NSHostingView(rootView: content())
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        // For now, add the hosting view as a single pane
        // In a real implementation, we'd need to parse the content tuple
        splitView.addArrangedSubview(hostingView)

        return splitView
    }

    func updateNSView(_ nsView: NSSplitView, context: Context) {
        // Update if needed
    }
}

// MARK: - Split Pane (for use within SplitView)

struct SplitPane<Content: View>: View {
    let minWidth: CGFloat?
    let maxWidth: CGFloat?
    let content: Content

    init(
        minWidth: CGFloat? = nil,
        maxWidth: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.content = content()
    }

    var body: some View {
        content
            .frame(
                minWidth: minWidth,
                maxWidth: maxWidth
            )
    }
}
