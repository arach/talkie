//
//  TalkieApp.swift
//  Talkie macOS
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI
import AppKit

// MARK: - Sidebar Toggle Action

struct SidebarToggleAction {
    let toggle: () -> Void
}

struct SidebarToggleKey: FocusedValueKey {
    typealias Value = SidebarToggleAction
}

extension FocusedValues {
    var sidebarToggle: SidebarToggleAction? {
        get { self[SidebarToggleKey.self] }
        set { self[SidebarToggleKey.self] = newValue }
    }
}

// MARK: - Settings Navigation Action

struct SettingsNavigationAction {
    let showSettings: () -> Void
}

struct SettingsNavigationKey: FocusedValueKey {
    typealias Value = SettingsNavigationAction
}

extension FocusedValues {
    var settingsNavigation: SettingsNavigationAction? {
        get { self[SettingsNavigationKey.self] }
        set { self[SettingsNavigationKey.self] = newValue }
    }
}

@main
struct TalkieApp: App {
    // Wire up AppDelegate for push notification handling
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    let persistenceController = PersistenceController.shared
    @ObservedObject private var settingsManager = SettingsManager.shared
    @FocusedValue(\.sidebarToggle) var sidebarToggle
    @FocusedValue(\.settingsNavigation) var settingsNavigation

    var body: some Scene {
        WindowGroup {
            TalkieNavigationView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .frame(minWidth: 900, minHeight: 600)
                .tint(settingsManager.accentColor.color)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {}

            // Add sidebar toggle to View menu
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    sidebarToggle?.toggle()
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }

            // Replace default Settings menu item with inline navigation
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    settingsNavigation?.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
