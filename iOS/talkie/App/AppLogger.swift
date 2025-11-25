//
//  AppLogger.swift
//  talkie
//
//  Centralized logging using os.Logger for the Talkie app.
//

import os

/// Centralized loggers for different subsystems of the app
enum AppLogger {
    private static let subsystem = "jdi.talkie-os"

    /// General app lifecycle and background tasks
    static let app = Logger(subsystem: subsystem, category: "App")

    /// Audio recording operations
    static let recording = Logger(subsystem: subsystem, category: "Recording")

    /// Audio playback operations
    static let playback = Logger(subsystem: subsystem, category: "Playback")

    /// Speech transcription
    static let transcription = Logger(subsystem: subsystem, category: "Transcription")

    /// Core Data and persistence
    static let persistence = Logger(subsystem: subsystem, category: "Persistence")

    /// UI and view-related logging
    static let ui = Logger(subsystem: subsystem, category: "UI")
}
