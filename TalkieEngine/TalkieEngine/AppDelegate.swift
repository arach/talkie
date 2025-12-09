//
//  AppDelegate.swift
//  TalkieEngine
//
//  Background app that hosts the transcription XPC service
//

import Cocoa
import os

private let logger = Logger(subsystem: "live.talkie.engine", category: "AppDelegate")

// Note: @main is in main.swift which sets up XPC before NSApplication
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("TalkieEngine app delegate ready")
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("TalkieEngine shutting down")
    }
}
