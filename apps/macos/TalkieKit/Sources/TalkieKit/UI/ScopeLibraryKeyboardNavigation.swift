//
//  ScopeLibraryKeyboardNavigation.swift
//  TalkieKit
//
//  Shared j/k and arrow-key navigation for Scope-style library lists.
//

import AppKit
import SwiftUI

public extension View {
    func scopeLibraryKeyboardNavigation(
        isEnabled: Bool = true,
        onMoveUp: @escaping () -> Void,
        onMoveDown: @escaping () -> Void
    ) -> some View {
        modifier(ScopeLibraryKeyboardNavigationModifier(
            isEnabled: isEnabled,
            onMoveUp: onMoveUp,
            onMoveDown: onMoveDown
        ))
    }
}

private struct ScopeLibraryKeyboardNavigationModifier: ViewModifier {
    let isEnabled: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                if isEnabled {
                    installMonitorIfNeeded()
                }
            }
            .onDisappear { removeMonitor() }
            .onChange(of: isEnabled) { _, enabled in
                removeMonitor()
                if enabled {
                    installMonitorIfNeeded()
                }
            }
    }

    private func installMonitorIfNeeded() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isEnabled,
                  Self.shouldHandle(event),
                  !Self.textInputHasFocus else {
                return event
            }

            switch Self.navigationIntent(for: event) {
            case .up:
                onMoveUp()
                return nil
            case .down:
                onMoveDown()
                return nil
            case nil:
                return event
            }
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private static func shouldHandle(_ event: NSEvent) -> Bool {
        let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        return event.modifierFlags.intersection(blockedModifiers).isEmpty
    }

    private static var textInputHasFocus: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSTextView
            || responder is NSTextField
            || responder is NSSearchField
    }

    private static func navigationIntent(for event: NSEvent) -> ScopeLibraryKeyboardIntent? {
        switch event.keyCode {
        case 125:
            return .down
        case 126:
            return .up
        default:
            break
        }

        guard let character = event.charactersIgnoringModifiers?.lowercased() else {
            return nil
        }

        switch character {
        case "j":
            return .down
        case "k":
            return .up
        default:
            return nil
        }
    }
}

private enum ScopeLibraryKeyboardIntent {
    case up
    case down
}
