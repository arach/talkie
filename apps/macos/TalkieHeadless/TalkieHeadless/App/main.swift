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

// Set as accessory app (no dock icon, no menu bar)
NSApplication.shared.setActivationPolicy(.accessory)

print("TalkieHeadless starting...")

// Initialize the headless server
let server = HeadlessServer.shared

Task {
    do {
        try await server.start(port: 7848)
        print("TalkieHeadless running on port 7848")
    } catch {
        print("Failed to start server: \(error)")
        exit(1)
    }
}

// Keep running
RunLoop.main.run()
