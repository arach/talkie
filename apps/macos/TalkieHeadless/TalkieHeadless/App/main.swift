//
//  main.swift
//  TalkieHeadless
//
//  Headless server for Talkie extensions.
//  Provides HTTP/WebSocket API for transcription, diffs, storage.
//  Runs as background process (no UI).
//

import Foundation
import AppKit
import TalkieKit

// Set as accessory app (no dock icon, no menu bar)
NSApplication.shared.setActivationPolicy(.accessory)

TalkieLogger.configure(source: .talkie)

HeadlessConsole.info("TalkieHeadless starting...")

// Initialize the headless server
let server = HeadlessServer.shared

Task {
    do {
        try await server.start(port: 7848)
        HeadlessConsole.info("TalkieHeadless running on port 7848")
    } catch {
        HeadlessConsole.info("Failed to start server: \(error)")
        exit(1)
    }
}

// Keep running
RunLoop.main.run()
