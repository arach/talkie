//
//  DeterministicSplitView.swift
//  Talkie
//
//  AppKit-backed NSSplitView that respects an exact split ratio.
//  Reads initial position from LayoutStore and writes back on drag.
//  No SwiftUI HSplitView — no guessing, no resetting.
//

import SwiftUI
import AppKit

/// A two-pane horizontal split view backed by NSSplitView.
/// The divider position is driven by `ratio` (0…1, fraction for the left pane).
struct DeterministicSplitView<Left: View, Right: View>: NSViewRepresentable {
    var ratio: Double
    var minLeftWidth: CGFloat = 240
    var minRightWidth: CGFloat = 400
    var onRatioChange: (Double) -> Void

    @ViewBuilder var left: () -> Left
    @ViewBuilder var right: () -> Right

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = true  // side-by-side
        splitView.dividerStyle = .thin
        splitView.delegate = context.coordinator

        let leftHost = NSHostingView(rootView: left())
        let rightHost = NSHostingView(rootView: right())

        splitView.addArrangedSubview(leftHost)
        splitView.addArrangedSubview(rightHost)

        // Apply initial ratio after layout
        DispatchQueue.main.async {
            let totalWidth = splitView.bounds.width
            if totalWidth > 0 {
                let leftWidth = totalWidth * CGFloat(ratio)
                splitView.setPosition(leftWidth, ofDividerAt: 0)
            }
        }

        context.coordinator.splitView = splitView

        return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
        context.coordinator.parent = self

        // Update hosted SwiftUI views
        if let leftHost = splitView.arrangedSubviews.first as? NSHostingView<Left> {
            leftHost.rootView = left()
        }
        if splitView.arrangedSubviews.count > 1,
           let rightHost = splitView.arrangedSubviews[1] as? NSHostingView<Right> {
            rightHost.rootView = right()
        }

        // Only reposition if the ratio changed externally (not from drag)
        if !context.coordinator.isDragging {
            let totalWidth = splitView.bounds.width
            if totalWidth > 0 {
                let targetLeft = totalWidth * CGFloat(ratio)
                let currentLeft = splitView.arrangedSubviews.first?.frame.width ?? 0
                // Threshold to avoid fighting with AppKit
                if abs(targetLeft - currentLeft) > 2 {
                    splitView.setPosition(targetLeft, ofDividerAt: 0)
                }
            }
        }
    }

    class Coordinator: NSObject, NSSplitViewDelegate {
        var parent: DeterministicSplitView
        weak var splitView: NSSplitView?
        var isDragging = false

        init(parent: DeterministicSplitView) {
            self.parent = parent
        }

        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            parent.minLeftWidth
        }

        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            splitView.bounds.width - parent.minRightWidth
        }

        func splitViewWillResizeSubviews(_ notification: Notification) {
            isDragging = true
        }

        func splitViewDidResizeSubviews(_ notification: Notification) {
            guard let splitView = notification.object as? NSSplitView,
                  let leftView = splitView.arrangedSubviews.first else { return }

            let totalWidth = splitView.bounds.width
            guard totalWidth > 0 else { return }

            let newRatio = Double(leftView.frame.width / totalWidth)
            // Clamp to same range as LayoutStore
            let clamped = min(max(newRatio, 0.2), 0.8)
            parent.onRatioChange(clamped)

            // Reset drag flag after a brief delay so updateNSView
            // can reposition the divider on external ratio changes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.isDragging = false
            }
        }

        func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
            // On window resize, keep the ratio proportional
            // Return true for both subviews so AppKit distributes proportionally
            true
        }
    }
}
