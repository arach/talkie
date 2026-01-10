//
//  ListKeyboardNavigator.swift
//  Talkie macOS
//
//  Reusable keyboard navigation for list views
//  Provides arrow keys, Enter, Tab, Shift+arrows for range selection, Cmd+A
//

import SwiftUI
import AppKit

/// Focus region for Tab cycling
enum ListFocusRegion: Equatable {
    case search
    case filters
    case list
    case detail
}

/// Keyboard navigation state and handler for list views
@MainActor @Observable
final class ListKeyboardNavigator<ItemID: Hashable> {
    // MARK: - State

    /// Currently focused index in the list (separate from selection)
    var focusedIndex: Int?

    /// Current focus region for Tab navigation
    var focusRegion: ListFocusRegion = .list

    /// Whether keyboard navigation is active
    var isActive = false

    // MARK: - Configuration

    /// Total item count (set by the view)
    var itemCount: Int = 0

    /// Callback to get item ID at index
    var itemAtIndex: ((Int) -> ItemID)?

    /// Callback when selection should change
    var onSelect: ((Set<ItemID>, Bool) -> Void)?  // (ids, isRangeSelection)

    /// Callback when item should be activated (Enter)
    var onActivate: ((ItemID) -> Void)?

    /// Callback to scroll to index
    var onScrollTo: ((Int) -> Void)?

    /// Callback when focus region changes
    var onFocusRegionChange: ((ListFocusRegion) -> Void)?

    /// All item IDs (for Cmd+A)
    var allItemIDs: (() -> Set<ItemID>)?

    // MARK: - Private

    private var keyMonitor: Any?
    private var rangeStartIndex: Int?

    // MARK: - Lifecycle

    func activate() {
        guard !isActive else { return }
        isActive = true
        setupKeyMonitor()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        removeKeyMonitor()
    }

    deinit {
        removeKeyMonitor()
    }

    // MARK: - Key Monitor

    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.focusRegion == .list else { return event }
            return self.handleKeyEvent(event)
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        let hasShift = event.modifierFlags.contains(.shift)
        let hasCmd = event.modifierFlags.contains(.command)

        switch event.keyCode {
        case 125: // Down arrow
            moveDown(extendSelection: hasShift)
            return nil

        case 126: // Up arrow
            moveUp(extendSelection: hasShift)
            return nil

        case 36: // Return/Enter
            activateFocused()
            return nil

        case 48: // Tab
            if hasShift {
                moveToPreviousRegion()
            } else {
                moveToNextRegion()
            }
            return nil

        case 0: // A key
            if hasCmd {
                selectAll()
                return nil
            }
            return event

        case 53: // Escape
            clearFocus()
            return nil

        case 115: // Home
            moveToFirst()
            return nil

        case 119: // End
            moveToLast()
            return nil

        case 116: // Page Up
            pageUp()
            return nil

        case 121: // Page Down
            pageDown()
            return nil

        default:
            return event
        }
    }

    // MARK: - Navigation Actions

    private func moveDown(extendSelection: Bool) {
        guard itemCount > 0 else { return }

        let newIndex: Int
        if let current = focusedIndex {
            newIndex = min(current + 1, itemCount - 1)
        } else {
            newIndex = 0
        }

        setFocus(to: newIndex, extendSelection: extendSelection)
    }

    private func moveUp(extendSelection: Bool) {
        guard itemCount > 0 else { return }

        let newIndex: Int
        if let current = focusedIndex {
            newIndex = max(current - 1, 0)
        } else {
            newIndex = itemCount - 1
        }

        setFocus(to: newIndex, extendSelection: extendSelection)
    }

    private func moveToFirst() {
        guard itemCount > 0 else { return }
        setFocus(to: 0, extendSelection: false)
    }

    private func moveToLast() {
        guard itemCount > 0 else { return }
        setFocus(to: itemCount - 1, extendSelection: false)
    }

    private func pageUp() {
        guard itemCount > 0, let current = focusedIndex else {
            moveToFirst()
            return
        }
        let newIndex = max(current - 10, 0)
        setFocus(to: newIndex, extendSelection: false)
    }

    private func pageDown() {
        guard itemCount > 0, let current = focusedIndex else {
            moveToFirst()
            return
        }
        let newIndex = min(current + 10, itemCount - 1)
        setFocus(to: newIndex, extendSelection: false)
    }

    private func setFocus(to index: Int, extendSelection: Bool) {
        let previousIndex = focusedIndex
        focusedIndex = index

        // Scroll to focused item
        onScrollTo?(index)

        // Handle selection
        guard let itemAtIndex = itemAtIndex else { return }

        if extendSelection {
            // Range selection from start to current
            if rangeStartIndex == nil {
                rangeStartIndex = previousIndex ?? index
            }

            guard let startIndex = rangeStartIndex else { return }
            let range = min(startIndex, index)...max(startIndex, index)
            var ids = Set<ItemID>()
            for i in range {
                ids.insert(itemAtIndex(i))
            }
            onSelect?(ids, true)
        } else {
            // Single selection
            rangeStartIndex = index
            let id = itemAtIndex(index)
            onSelect?(Set([id]), false)
        }
    }

    private func activateFocused() {
        guard let index = focusedIndex, let itemAtIndex = itemAtIndex else { return }
        let id = itemAtIndex(index)
        onActivate?(id)
    }

    private func selectAll() {
        guard let allIDs = allItemIDs?() else { return }
        onSelect?(allIDs, false)
    }

    private func clearFocus() {
        focusedIndex = nil
        rangeStartIndex = nil
        onSelect?(Set(), false)
    }

    // MARK: - Region Navigation

    private func moveToNextRegion() {
        let regions: [ListFocusRegion] = [.search, .list, .detail]
        if let currentIdx = regions.firstIndex(of: focusRegion) {
            let nextIdx = (currentIdx + 1) % regions.count
            focusRegion = regions[nextIdx]
            onFocusRegionChange?(focusRegion)
        }
    }

    private func moveToPreviousRegion() {
        let regions: [ListFocusRegion] = [.search, .list, .detail]
        if let currentIdx = regions.firstIndex(of: focusRegion) {
            let prevIdx = (currentIdx - 1 + regions.count) % regions.count
            focusRegion = regions[prevIdx]
            onFocusRegionChange?(focusRegion)
        }
    }

    // MARK: - External Interface

    /// Call when user clicks on an item to sync focus with selection
    func syncFocusToIndex(_ index: Int) {
        focusedIndex = index
        rangeStartIndex = index
    }

    /// Focus the list region
    func focusList() {
        focusRegion = .list
        if focusedIndex == nil && itemCount > 0 {
            focusedIndex = 0
        }
    }
}

// MARK: - Focus Ring Modifier

/// Adds a visual focus ring to a view
struct FocusRingModifier: ViewModifier {
    let isFocused: Bool
    var color: Color = .accentColor
    var cornerRadius: CGFloat = 4

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(color, lineWidth: isFocused ? 2 : 0)
                    .padding(1)
            )
            .animation(.easeOut(duration: 0.1), value: isFocused)
    }
}

extension View {
    /// Adds a keyboard focus ring indicator
    func keyboardFocusRing(_ isFocused: Bool, color: Color = .accentColor, cornerRadius: CGFloat = 4) -> some View {
        modifier(FocusRingModifier(isFocused: isFocused, color: color, cornerRadius: cornerRadius))
    }
}
