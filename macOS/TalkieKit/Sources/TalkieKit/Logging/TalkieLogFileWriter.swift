//
//  TalkieLogFileWriter.swift
//  TalkieKit
//
//  Unified log file writer for Talkie suite.
//  Writes logs in format compatible with Talkie's SystemLogsView.
//
//  Two modes:
//  - critical: immediate flush, crash-safe (for transcription errors)
//  - bestEffort: buffered writes, periodic flush (for everything else)
//

import Foundation

// MARK: - Types

/// Log source application
public enum LogSource: String, Sendable {
    case talkie = "Talkie"
    case talkieLive = "TalkieLive"
    case talkieEngine = "Engine"

    /// Directory name for Application Support
    var appSupportDirName: String {
        switch self {
        case .talkie: return "Talkie"
        case .talkieLive: return "TalkieLive"
        case .talkieEngine: return "TalkieEngine"
        }
    }
}

/// Log event type (matches SystemLogsView expectations)
public enum LogEventType: String, Sendable {
    case sync = "SYNC"
    case record = "RECORD"
    case transcribe = "WHISPER"
    case workflow = "WORKFLOW"
    case error = "ERROR"
    case system = "SYSTEM"
}

/// Write mode - determines durability vs performance tradeoff
public enum LogWriteMode: Sendable {
    /// Immediate flush to disk - crash-safe, use for critical errors
    case critical
    /// Buffered writes - faster, use for routine logging
    case bestEffort
}

// MARK: - TalkieLogFileWriter

/// Thread-safe log file writer with two-tier durability
public final class TalkieLogFileWriter: @unchecked Sendable {

    // MARK: - Configuration

    private let source: LogSource
    private let queue = DispatchQueue(label: "jdi.talkie.logwriter", qos: .utility)

    // Buffer settings
    private let maxBufferSize = 50
    private let flushInterval: TimeInterval = 0.5

    // MARK: - State (accessed only on queue)

    private var fileHandle: FileHandle?
    private var currentLogDate: String?
    private var buffer: [String] = []
    private var flushWorkItem: DispatchWorkItem?

    // MARK: - Paths

    private var logsDirectory: URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(source.appSupportDirName)
                .appendingPathComponent("logs", isDirectory: true)
        }
        return appSupport
            .appendingPathComponent(source.appSupportDirName)
            .appendingPathComponent("logs", isDirectory: true)
    }

    private func logFileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "talkie-\(formatter.string(from: date)).log"
    }

    private func logFilePath(for date: Date) -> URL {
        logsDirectory.appendingPathComponent(logFileName(for: date))
    }

    // MARK: - Initialization

    public init(source: LogSource) {
        self.source = source

        // Ensure logs directory exists
        queue.async { [weak self] in
            self?.ensureLogsDirectory()
        }
    }

    deinit {
        // Flush any remaining buffer on shutdown
        queue.sync {
            flushBufferSync()
            fileHandle?.closeFile()
        }
    }

    // MARK: - Public API

    /// Log a message with specified type and mode
    /// - Parameters:
    ///   - type: Event type category
    ///   - message: Main log message
    ///   - detail: Optional additional detail
    ///   - mode: Write mode (.critical for immediate flush, .bestEffort for buffered)
    public func log(_ type: LogEventType, _ message: String, detail: String? = nil, mode: LogWriteMode = .bestEffort) {
        let line = formatLogLine(type: type, message: message, detail: detail)

        queue.async { [weak self] in
            guard let self = self else { return }

            switch mode {
            case .critical:
                // Write immediately and flush to disk
                self.writeLineSync(line, flush: true)

            case .bestEffort:
                // Add to buffer
                self.buffer.append(line)

                // Flush if buffer is full
                if self.buffer.count >= self.maxBufferSize {
                    self.flushBufferSync()
                } else {
                    // Schedule flush if not already scheduled
                    self.scheduleFlush()
                }
            }
        }
    }

    /// Force flush any buffered logs to disk
    public func flush() {
        queue.async { [weak self] in
            self?.flushBufferSync()
        }
    }

    // MARK: - Private Implementation

    private func ensureLogsDirectory() {
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    }

    private func formatLogLine(type: LogEventType, message: String, detail: String?) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = isoFormatter.string(from: Date())

        // Escape pipe characters in message and detail
        let escapedMessage = message.replacingOccurrences(of: "|", with: "\\|")
        let escapedDetail = detail?.replacingOccurrences(of: "|", with: "\\|") ?? ""

        // Format: timestamp|source|type|message|detail
        return "\(timestamp)|\(source.rawValue)|\(type.rawValue)|\(escapedMessage)|\(escapedDetail)"
    }

    private func writeLineSync(_ line: String, flush: Bool) {
        // Check if we need to rotate to a new day's file
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let today = dateFormatter.string(from: Date())

        if currentLogDate != today {
            fileHandle?.closeFile()
            fileHandle = nil
            currentLogDate = today
        }

        // Open file handle if needed
        if fileHandle == nil {
            let path = logFilePath(for: Date())

            if !FileManager.default.fileExists(atPath: path.path) {
                ensureLogsDirectory()
                FileManager.default.createFile(atPath: path.path, contents: nil)
            }

            fileHandle = try? FileHandle(forWritingTo: path)
            fileHandle?.seekToEndOfFile()
        }

        // Write the line
        guard let data = (line + "\n").data(using: .utf8) else { return }
        fileHandle?.write(data)

        // Flush to disk if requested (for critical mode)
        if flush {
            try? fileHandle?.synchronize()
        }
    }

    private func flushBufferSync() {
        guard !buffer.isEmpty else { return }

        // Cancel any pending flush
        flushWorkItem?.cancel()
        flushWorkItem = nil

        // Write all buffered lines
        for line in buffer {
            writeLineSync(line, flush: false)
        }
        buffer.removeAll()

        // Single flush at the end for efficiency
        try? fileHandle?.synchronize()
    }

    private func scheduleFlush() {
        guard flushWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            self?.flushBufferSync()
            self?.flushWorkItem = nil
        }

        flushWorkItem = workItem
        queue.asyncAfter(deadline: .now() + flushInterval, execute: workItem)
    }
}
