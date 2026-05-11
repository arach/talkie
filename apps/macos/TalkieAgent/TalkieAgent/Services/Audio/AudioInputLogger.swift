//
//  AudioInputLogger.swift
//  TalkieAgent
//
//  JSON Lines logger for audio input device diagnostics
//  File: ~/Library/Application Support/TalkieAgent/AudioInputLog.jsonl
//

import Foundation
import os.log

private let logger = Logger(subsystem: "jdi.talkie.agent", category: "AudioInputLogger")

/// JSON Lines logger for audio input diagnostics
/// Each line is a valid JSON object for easy parsing with tools like jq
final class AudioInputLogger {
    static let shared = AudioInputLogger()

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private var lastDeviceScan: [String: String]? // UID -> Name mapping for change detection

    private init() {
        // Setup log file in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let agentDir = appSupport.appendingPathComponent("TalkieAgent", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: agentDir, withIntermediateDirectories: true)

        fileURL = agentDir.appendingPathComponent("AudioInputLog.jsonl")

        // Configure encoder for compact JSON
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Event Types

    private struct DeviceScanEvent: Encodable {
        let event = "device_scan"
        let timestamp: Date
        let devices: [DeviceInfo]
        let defaultUID: String?
    }

    private struct DeviceInfo: Encodable {
        let uid: String
        let name: String
        let isDefault: Bool
    }

    private struct RecordingStartEvent: Encodable {
        let event = "recording_start"
        let timestamp: Date
        let deviceUID: String
        let deviceName: String
        let selectionReason: String
        let requestedUID: String?
        let requestedName: String?
    }

    // MARK: - Logging

    /// Log a device scan (only when devices have changed)
    func logDeviceScan(devices: [(uid: String, name: String, isDefault: Bool)]) {
        // Build current device map
        var currentDevices: [String: String] = [:]
        for device in devices {
            currentDevices[device.uid] = device.name
        }

        // Only log if devices changed
        if currentDevices == lastDeviceScan {
            return
        }
        lastDeviceScan = currentDevices

        let event = DeviceScanEvent(
            timestamp: Date(),
            devices: devices.map { DeviceInfo(uid: $0.uid, name: $0.name, isDefault: $0.isDefault) },
            defaultUID: devices.first(where: { $0.isDefault })?.uid
        )

        writeEvent(event)
        logger.debug("Logged device scan: \(devices.count) devices")
    }

    /// Log when recording starts with device selection details
    func logRecordingStart(
        deviceUID: String,
        deviceName: String,
        selectionReason: String,
        requestedUID: String?,
        requestedName: String?
    ) {
        let event = RecordingStartEvent(
            timestamp: Date(),
            deviceUID: deviceUID,
            deviceName: deviceName,
            selectionReason: selectionReason,
            requestedUID: requestedUID,
            requestedName: requestedName
        )

        writeEvent(event)
        logger.debug("Logged recording start: \(deviceName) (\(selectionReason))")
    }

    // MARK: - Private

    private func writeEvent<T: Encodable>(_ event: T) {
        do {
            let data = try encoder.encode(event)
            guard var line = String(data: data, encoding: .utf8) else { return }
            line += "\n"

            // Append to file
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8)!)
                handle.closeFile()
            } else {
                try line.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        } catch {
            logger.error("Failed to write audio input log: \(error.localizedDescription)")
        }
    }

    /// Get the log file path for diagnostics
    var logFilePath: String {
        fileURL.path
    }

    /// Rotate log file if it exceeds size limit (10MB)
    func rotateIfNeeded() {
        let maxSize: UInt64 = 10 * 1024 * 1024 // 10MB

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? UInt64,
              size > maxSize else {
            return
        }

        // Rename current log to .old and start fresh
        let oldURL = fileURL.deletingPathExtension().appendingPathExtension("old.jsonl")
        try? FileManager.default.removeItem(at: oldURL)
        try? FileManager.default.moveItem(at: fileURL, to: oldURL)

        logger.info("Rotated audio input log (was \(size) bytes)")
    }
}
