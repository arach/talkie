//
//  AppDelegate.swift
//  TalkieEngine
//
//  Background app that hosts the transcription XPC service
//  Now with menu bar presence and status dashboard
//

import Cocoa
import SwiftUI
import os

private let logger = Logger(subsystem: "jdi.talkie.engine", category: "AppDelegate")

// Note: @main is in main.swift which sets up XPC before NSApplication
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var statusWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("TalkieEngine app delegate ready")

        // Set up menu bar item
        setupMenuBar()

        // Log to status manager
        EngineStatusManager.shared.log(.info, "AppDelegate", "TalkieEngine ready")
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("TalkieEngine shutting down")
        EngineStatusManager.shared.log(.info, "AppDelegate", "Shutting down...")
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            // Use a gear/engine icon
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let image = NSImage(systemSymbolName: "engine.combustion", accessibilityDescription: "TalkieEngine")
            image?.isTemplate = true
            button.image = image?.withSymbolConfiguration(config)
            button.action = #selector(toggleStatusWindow)
            button.target = self
        }

        // Build menu
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "TalkieEngine", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let statusMenuItem = NSMenuItem(title: "Show Status...", action: #selector(showStatusWindow), keyEquivalent: "s")
        statusMenuItem.target = self
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit TalkieEngine", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func toggleStatusWindow() {
        if statusWindow?.isVisible == true {
            statusWindow?.close()
        } else {
            showStatusWindow()
        }
    }

    @objc private func showStatusWindow() {
        if statusWindow == nil {
            let contentView = EngineStatusView()

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "TalkieEngine Status"
            window.contentView = NSHostingView(rootView: contentView)
            window.center()
            window.setFrameAutosaveName("TalkieEngineStatus")
            window.isReleasedWhenClosed = false

            // Dark appearance
            window.appearance = NSAppearance(named: .darkAqua)

            statusWindow = window
        }

        statusWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
