//
//  WorkflowFileRepository.swift
//  Talkie macOS
//
//  File-based workflow storage with hot-reload support
//  Workflows are stored as JSON files in three directories:
//  - system/: Protected workflows (Transcribe, Hey Talkie) - always overwritten on update
//  - starters/: Template workflows - overwritten unless duplicated to user/
//  - user/: User-created workflows - never touched by app updates
//

import Foundation
import Observation
import TalkieKit

private let log = Log(.workflow)

// MARK: - Workflow Source

/// Identifies where a workflow came from
enum WorkflowSource: String, Codable {
    case system     // Protected, always overwritten on update
    case starter    // Template, overwritten unless user duplicated
    case user       // User-created, never touched

    var directoryName: String {
        switch self {
        case .system: return "system"
        case .starter: return "starters"
        case .user: return "user"
        }
    }

    var isEditable: Bool {
        switch self {
        case .system: return false  // Can only enable/disable, duplicate
        case .starter, .user: return true
        }
    }
}

// MARK: - Loaded Workflow

/// A workflow loaded from a file, with source tracking
struct LoadedWorkflow: Identifiable {
    let definition: WorkflowDefinition
    let source: WorkflowSource
    let filePath: URL

    var id: UUID { definition.id }
    var slug: String { filePath.deletingPathExtension().lastPathComponent }
}

// MARK: - Workflow File Repository

/// Manages file-based workflow storage with FSEvents hot-reload
@MainActor
@Observable
final class WorkflowFileRepository {
    static let shared = WorkflowFileRepository()

    // MARK: - State

    /// All loaded workflows (from all sources)
    private(set) var loadedWorkflows: [LoadedWorkflow] = []

    /// Quick access by ID
    private var workflowsByID: [UUID: LoadedWorkflow] = [:]

    // MARK: - Paths

    private static var workflowsBaseURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return appSupport
            .appendingPathComponent("Talkie", isDirectory: true)
            .appendingPathComponent("workflows", isDirectory: true)
    }

    private static func directoryURL(for source: WorkflowSource) -> URL {
        workflowsBaseURL.appendingPathComponent(source.directoryName, isDirectory: true)
    }

    // MARK: - File Watching

    private var fileWatchSources: [DispatchSourceFileSystemObject] = []
    private var directoryDescriptors: [Int32] = []

    // MARK: - Initialization

    private init() {}

    /// Initialize repository and load workflows
    func initialize() async {
        log.info("Initializing WorkflowFileRepository")

        // Create directories
        ensureDirectoriesExist()

        // Sync bundled workflows to system/starters
        await syncBundledWorkflows()

        // Load all workflows
        await reloadAll()

        // Start watching for changes
        startFileWatching()

        log.info("Loaded \(loadedWorkflows.count) workflows")
    }

    // MARK: - Directory Setup

    private func ensureDirectoriesExist() {
        let fm = FileManager.default

        for source in [WorkflowSource.system, .starter, .user] {
            let url = Self.directoryURL(for: source)
            if !fm.fileExists(atPath: url.path) {
                do {
                    try fm.createDirectory(at: url, withIntermediateDirectories: true)
                    log.debug("Created directory: \(source.directoryName)")
                } catch {
                    log.error("Failed to create \(source.directoryName) directory: \(error)")
                }
            }
        }
    }

    // MARK: - Bundle Sync

    /// Sync bundled workflow files to system/ and starters/
    private func syncBundledWorkflows() async {
        guard let resourcePath = Bundle.main.resourcePath else { return }

        // System workflows (always overwrite)
        let systemBundlePath = (resourcePath as NSString).appendingPathComponent("SystemWorkflows")
        await syncBundleDirectory(from: systemBundlePath, to: .system, alwaysOverwrite: true)

        // Starter workflows (overwrite only if not duplicated to user/)
        let starterBundlePath = (resourcePath as NSString).appendingPathComponent("StarterWorkflows")
        await syncBundleDirectory(from: starterBundlePath, to: .starter, alwaysOverwrite: false)
    }

    private func syncBundleDirectory(from bundlePath: String, to source: WorkflowSource, alwaysOverwrite: Bool) async {
        let fm = FileManager.default
        let destDir = Self.directoryURL(for: source)

        guard fm.fileExists(atPath: bundlePath) else {
            log.debug("No bundle directory at \(bundlePath)")
            return
        }

        do {
            let files = try fm.contentsOfDirectory(atPath: bundlePath)
            let jsonFiles = files.filter { $0.hasSuffix(".json") || $0.hasSuffix(".twf.json") }

            for filename in jsonFiles {
                let srcURL = URL(fileURLWithPath: bundlePath).appendingPathComponent(filename)
                let destFilename = filename.replacingOccurrences(of: ".twf.json", with: ".json")
                let destURL = destDir.appendingPathComponent(destFilename)

                // Check if we should skip (user has duplicated this workflow)
                if !alwaysOverwrite {
                    if hasUserCopy(of: srcURL) {
                        log.debug("Skipping \(filename) - user has modified copy")
                        continue
                    }
                }

                // Copy/overwrite
                try? fm.removeItem(at: destURL)
                try fm.copyItem(at: srcURL, to: destURL)
                log.debug("Synced \(filename) to \(source.directoryName)/")
            }
        } catch {
            log.error("Failed to sync bundle directory: \(error)")
        }
    }

    /// Check if user has a copy of a workflow (by slug)
    private func hasUserCopy(of bundleURL: URL) -> Bool {
        // Extract slug from filename
        let slug = bundleURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: ".twf", with: "")

        // Check if a file with this slug exists in user/
        let userDir = Self.directoryURL(for: .user)
        let userFile = userDir.appendingPathComponent("\(slug).json")

        return FileManager.default.fileExists(atPath: userFile.path)
    }

    // MARK: - Loading

    /// Reload all workflows from disk
    func reloadAll() async {
        var all: [LoadedWorkflow] = []

        for source in [WorkflowSource.system, .starter, .user] {
            let workflows = await loadWorkflows(from: source)
            all.append(contentsOf: workflows)
        }

        loadedWorkflows = all
        workflowsByID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }

    private func loadWorkflows(from source: WorkflowSource) async -> [LoadedWorkflow] {
        let dir = Self.directoryURL(for: source)
        let fm = FileManager.default

        guard fm.fileExists(atPath: dir.path) else { return [] }

        var results: [LoadedWorkflow] = []

        do {
            let files = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            let jsonFiles = files.filter { $0.pathExtension == "json" }

            for fileURL in jsonFiles {
                do {
                    let workflow = try await loadWorkflow(from: fileURL)
                    results.append(LoadedWorkflow(
                        definition: workflow,
                        source: source,
                        filePath: fileURL
                    ))
                } catch {
                    log.error("Failed to load \(fileURL.lastPathComponent): \(error)")
                }
            }
        } catch {
            log.error("Failed to read \(source.directoryName) directory: \(error)")
        }

        return results
    }

    private func loadWorkflow(from fileURL: URL) async throws -> WorkflowDefinition {
        // Use SimpleWorkflowLoader for all JSON files
        return try SimpleWorkflowLoader.load(from: fileURL)
    }

    // MARK: - CRUD Operations

    /// Get a workflow by ID
    func workflow(byID id: UUID) -> LoadedWorkflow? {
        workflowsByID[id]
    }

    /// Get all workflows for a specific source
    func workflows(for source: WorkflowSource) -> [LoadedWorkflow] {
        loadedWorkflows.filter { $0.source == source }
    }

    /// Save a workflow (creates or updates in user/ directory)
    func save(_ workflow: WorkflowDefinition, slug: String? = nil) async throws {
        let effectiveSlug = slug ?? slugify(workflow.name)
        let fileURL = Self.directoryURL(for: .user).appendingPathComponent("\(effectiveSlug).json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(workflow)
        try data.write(to: fileURL, options: .atomic)

        log.info("Saved workflow: \(workflow.name) to \(fileURL.lastPathComponent)")

        // Reload to pick up the change
        await reloadAll()
    }

    /// Delete a workflow (only works for user/ workflows)
    func delete(_ workflow: LoadedWorkflow) async throws {
        guard workflow.source == .user else {
            throw WorkflowFileError.cannotDeleteSystemWorkflow
        }

        try FileManager.default.removeItem(at: workflow.filePath)
        log.info("Deleted workflow: \(workflow.definition.name)")

        await reloadAll()
    }

    /// Duplicate a workflow to user/ directory
    func duplicate(_ workflow: LoadedWorkflow, newName: String? = nil) async throws -> LoadedWorkflow {
        var copy = workflow.definition
        copy = WorkflowDefinition(
            id: UUID(),
            name: newName ?? "\(workflow.definition.name) Copy",
            description: workflow.definition.description,
            icon: workflow.definition.icon,
            color: workflow.definition.color,
            steps: workflow.definition.steps,
            isEnabled: workflow.definition.isEnabled,
            isPinned: false,  // Duplicates start unpinned
            autoRun: false,   // Don't auto-run duplicates
            createdAt: Date(),
            modifiedAt: Date()
        )

        let slug = slugify(copy.name)
        try await save(copy, slug: slug)

        guard let duplicated = workflowsByID[copy.id] else {
            throw WorkflowFileError.workflowNotFound(copy.id)
        }
        return duplicated
    }

    // MARK: - File Watching

    private func startFileWatching() {
        stopFileWatching()

        for source in [WorkflowSource.system, .starter, .user] {
            let dir = Self.directoryURL(for: source)
            watchDirectory(dir)
        }
    }

    private func stopFileWatching() {
        for source in fileWatchSources {
            source.cancel()
        }
        fileWatchSources.removeAll()

        for fd in directoryDescriptors {
            close(fd)
        }
        directoryDescriptors.removeAll()
    }

    private func watchDirectory(_ url: URL) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            log.error("Failed to open \(url.path) for watching")
            return
        }

        directoryDescriptors.append(fd)

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor in
                log.debug("File change detected in \(url.lastPathComponent)")
                await self?.reloadAll()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        fileWatchSources.append(source)
    }

    // MARK: - Helpers

    /// Convert a name to a filesystem-safe slug
    private func slugify(_ name: String) -> String {
        var slug = name.lowercased()

        // Replace spaces with dashes
        slug = slug.replacingOccurrences(of: " ", with: "-")

        // Remove non-alphanumeric except dashes
        slug = slug.components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: "-")).inverted).joined()

        // Collapse multiple dashes
        while slug.contains("--") {
            slug = slug.replacingOccurrences(of: "--", with: "-")
        }

        // Trim dashes from ends
        slug = slug.trimmingCharacters(in: .init(charactersIn: "-"))

        // Ensure not empty
        if slug.isEmpty {
            slug = "workflow-\(UUID().uuidString.prefix(8))"
        }

        return slug
    }

    // Note: No deinit needed - this is a singleton that lives for app lifetime
    // File watching is cleaned up by the OS when the process terminates
}

// MARK: - Errors

enum WorkflowFileError: LocalizedError {
    case cannotDeleteSystemWorkflow
    case workflowNotFound(UUID)
    case invalidJSON(String)

    var errorDescription: String? {
        switch self {
        case .cannotDeleteSystemWorkflow:
            return "Cannot delete system workflows. Duplicate to user folder first."
        case .workflowNotFound(let id):
            return "Workflow not found: \(id)"
        case .invalidJSON(let detail):
            return "Invalid workflow JSON: \(detail)"
        }
    }
}
