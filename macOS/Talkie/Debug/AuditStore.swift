//
//  AuditStore.swift
//  Talkie macOS
//
//  Simple JSON-based persistence for design audit runs.
//  Stores an index of all runs with quick access to metadata.
//
//  IMPORTANT: This entire file is DEBUG-only. Nothing ships to production.
//

import Foundation

#if DEBUG

/// Lightweight audit run index entry (for quick listing without loading full reports)
struct AuditRunEntry: Codable, Identifiable {
    let id: Int  // run number
    let timestamp: Date
    let appVersion: String?
    let gitBranch: String?
    let gitCommit: String?
    let themeName: String?
    let overallScore: Int
    let grade: String
    let totalIssues: Int
    let screenCount: Int
    let screenshotDirectory: String

    /// Path to the full audit.json file
    var auditJsonPath: String {
        let runDir = URL(fileURLWithPath: screenshotDirectory).deletingLastPathComponent()
        return runDir.appendingPathComponent("audit.json").path
    }
}

/// Simple JSON-based store for audit run history
/// Maintains an index file for quick listing without parsing every audit.json
actor AuditStore {
    static let shared = AuditStore()

    private let storeDirectory: URL
    private let indexFile: URL
    private var cachedIndex: [AuditRunEntry] = []
    private var indexLoaded = false

    init() {
        // Store in Application Support for persistence
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storeDirectory = appSupport.appendingPathComponent("Talkie/audit")
        indexFile = storeDirectory.appendingPathComponent("index.json")

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// Get all audit runs, sorted by timestamp (newest first)
    func listRuns() -> [AuditRunEntry] {
        loadIndexIfNeeded()
        return cachedIndex.sorted { $0.timestamp > $1.timestamp }
    }

    /// Get the latest audit run
    func latestRun() -> AuditRunEntry? {
        listRuns().first
    }

    /// Get a specific run by number
    func getRun(_ runNumber: Int) -> AuditRunEntry? {
        loadIndexIfNeeded()
        return cachedIndex.first { $0.id == runNumber }
    }

    /// Load the full audit report for a run
    func loadReport(for entry: AuditRunEntry) -> FullAuditReport? {
        guard FileManager.default.fileExists(atPath: entry.auditJsonPath) else { return nil }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: entry.auditJsonPath))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(FullAuditReport.self, from: data)
        } catch {
            print("❌ AuditStore: Failed to load report: \(error)")
            return nil
        }
    }

    /// Load the full audit report by run number
    func loadReport(runNumber: Int) -> FullAuditReport? {
        guard let entry = getRun(runNumber) else { return nil }
        return loadReport(for: entry)
    }

    /// Add or update an audit run in the index
    func indexRun(_ report: FullAuditReport, runNumber: Int) {
        loadIndexIfNeeded()

        let entry = AuditRunEntry(
            id: runNumber,
            timestamp: report.timestamp,
            appVersion: report.appVersion,
            gitBranch: report.gitBranch,
            gitCommit: report.gitCommit,
            themeName: report.themeName,
            overallScore: report.overallScore,
            grade: report.grade,
            totalIssues: report.totalIssues,
            screenCount: report.screens.count,
            screenshotDirectory: report.screenshotDirectory ?? ""
        )

        // Remove existing entry with same run number
        cachedIndex.removeAll { $0.id == runNumber }
        cachedIndex.append(entry)

        saveIndex()
    }

    /// Remove a run from the index
    func removeRun(_ runNumber: Int) {
        loadIndexIfNeeded()
        cachedIndex.removeAll { $0.id == runNumber }
        saveIndex()
    }

    /// Rebuild index by scanning the audit directory
    func rebuildIndex() {
        cachedIndex = []

        // Scan ~/Desktop/talkie-audit for run directories
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let auditDir = desktop.appendingPathComponent("talkie-audit")

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: auditDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            print("⚠️ AuditStore: No audit directory found at \(auditDir.path)")
            saveIndex()
            return
        }

        for item in contents {
            let dirname = item.lastPathComponent

            // Parse run number from directory name (e.g., "run-001")
            guard dirname.hasPrefix("run-"),
                  let runNumber = Int(dirname.dropFirst(4)) else {
                continue
            }

            // Load audit.json to get metadata
            let auditJsonPath = item.appendingPathComponent("audit.json")
            guard let data = try? Data(contentsOf: auditJsonPath) else {
                continue
            }

            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let report = try decoder.decode(FullAuditReport.self, from: data)

                let entry = AuditRunEntry(
                    id: runNumber,
                    timestamp: report.timestamp,
                    appVersion: report.appVersion,
                    gitBranch: report.gitBranch,
                    gitCommit: report.gitCommit,
                    themeName: report.themeName,
                    overallScore: report.overallScore,
                    grade: report.grade,
                    totalIssues: report.totalIssues,
                    screenCount: report.screens.count,
                    screenshotDirectory: report.screenshotDirectory ?? item.appendingPathComponent("screenshots").path
                )

                cachedIndex.append(entry)
            } catch {
                print("⚠️ AuditStore: Failed to parse \(auditJsonPath.path): \(error)")
            }
        }

        print("✅ AuditStore: Rebuilt index with \(cachedIndex.count) runs")
        saveIndex()
    }

    // MARK: - Private

    private func loadIndexIfNeeded() {
        guard !indexLoaded else { return }

        if FileManager.default.fileExists(atPath: indexFile.path) {
            do {
                let data = try Data(contentsOf: indexFile)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                cachedIndex = try decoder.decode([AuditRunEntry].self, from: data)
                indexLoaded = true
                print("✅ AuditStore: Loaded index with \(cachedIndex.count) runs")
                return
            } catch {
                print("⚠️ AuditStore: Failed to load index, rebuilding: \(error)")
            }
        }

        // No index or failed to load - rebuild from disk
        rebuildIndex()
        indexLoaded = true
    }

    private func saveIndex() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(cachedIndex)
            try data.write(to: indexFile)
        } catch {
            print("❌ AuditStore: Failed to save index: \(error)")
        }
    }
}

#endif
