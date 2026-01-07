//
//  WorkflowFileRepository.swift
//  Talkie macOS
//
//  File-based workflow storage with hot-reload support
//  Workflows are stored in two directories:
//  - system/: Protected workflows (Transcribe, Hey Talkie) - synced from bundle on update
//  - user/: User-created workflows - never touched by app updates
//
//  Templates are loaded directly from the app bundle (not synced to disk)
//

import Foundation
import Observation
import TalkieKit

private let log = Log(.workflow)

// MARK: - Workflow Source

/// Identifies where a workflow came from
enum WorkflowSource: String, Codable {
    case system     // Protected, synced from bundle on update
    case user       // User-created, never touched by app

    var directoryName: String {
        switch self {
        case .system: return "system"
        case .user: return "user"
        }
    }

    var isEditable: Bool {
        self == .user
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

        for source in [WorkflowSource.system, .user] {
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

    /// Track which app version we last synced system workflows from
    private static let syncVersionKey = "WorkflowFileRepository.lastSyncVersion"

    /// Sync bundled system workflows to system/ directory (only on app update or first run)
    private func syncBundledWorkflows() async {
        guard let resourcePath = Bundle.main.resourcePath else { return }

        // Only sync on first run or app update (not every startup)
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let lastSyncVersion = UserDefaults.standard.string(forKey: Self.syncVersionKey)

        guard lastSyncVersion != currentVersion else {
            // Already synced for this version
            return
        }

        log.info("Syncing system workflows (version \(lastSyncVersion ?? "none") → \(currentVersion))")

        // Try both direct path and nested Resources/ path (Xcode folder reference creates nesting)
        let directPath = resourcePath
        let nestedPath = (resourcePath as NSString).appendingPathComponent("Resources")

        // System workflows (always overwrite)
        let systemPaths = [
            (directPath as NSString).appendingPathComponent("SystemWorkflows"),
            (nestedPath as NSString).appendingPathComponent("SystemWorkflows")
        ]

        let fm = FileManager.default
        let destDir = Self.directoryURL(for: .system)
        var synced = 0

        for path in systemPaths {
            if fm.fileExists(atPath: path) {
                do {
                    let files = try fm.contentsOfDirectory(atPath: path)
                    let jsonFiles = files.filter { $0.hasSuffix(".json") }

                    for filename in jsonFiles {
                        let srcURL = URL(fileURLWithPath: path).appendingPathComponent(filename)
                        let destURL = destDir.appendingPathComponent(filename)

                        // Overwrite system workflows from bundle
                        try? fm.removeItem(at: destURL)
                        try fm.copyItem(at: srcURL, to: destURL)
                        synced += 1
                    }
                } catch {
                    log.error("Failed to sync system workflows: \(error)")
                }
                break
            }
        }

        UserDefaults.standard.set(currentVersion, forKey: Self.syncVersionKey)
        log.info("Synced \(synced) system workflows")
    }

    // MARK: - Templates (from bundle, not synced)

    /// Load workflow templates from bundle for the template picker
    /// These are NOT synced to disk - just loaded on demand
    func loadTemplates() -> [WorkflowDefinition] {
        guard let resourcePath = Bundle.main.resourcePath else {
            log.error("No bundle resource path")
            return []
        }

        // Try both direct path and nested Resources/ path
        let directPath = resourcePath
        let nestedPath = (resourcePath as NSString).appendingPathComponent("Resources")
        let templatesPaths = [
            (directPath as NSString).appendingPathComponent("WorkflowTemplates"),
            (nestedPath as NSString).appendingPathComponent("WorkflowTemplates")
        ]

        let fm = FileManager.default
        var templates: [WorkflowDefinition] = []

        for templatesPath in templatesPaths {
            guard fm.fileExists(atPath: templatesPath) else { continue }

            do {
                let files = try fm.contentsOfDirectory(atPath: templatesPath)
                let jsonFiles = files.filter { $0.hasSuffix(".json") }

                for filename in jsonFiles {
                    let fileURL = URL(fileURLWithPath: templatesPath).appendingPathComponent(filename)
                    do {
                        let template = try SimpleWorkflowLoader.load(from: fileURL)
                        templates.append(template)
                    } catch {
                        log.error("Failed to load template \(filename): \(error)")
                    }
                }

                log.debug("Loaded \(templates.count) workflow templates from \(templatesPath)")
                break
            } catch {
                log.error("Failed to read templates directory: \(error)")
            }
        }

        if templates.isEmpty {
            log.warning("No WorkflowTemplates folder found in bundle")
        }

        return templates.sorted { $0.name < $1.name }
    }

    // MARK: - Loading

    /// Reload all workflows from disk
    func reloadAll() async {
        var all: [LoadedWorkflow] = []

        for source in [WorkflowSource.system, .user] {
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
        let data = try Data(contentsOf: fileURL)

        // Try native WorkflowDefinition format first
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let definition = try? decoder.decode(WorkflowDefinition.self, from: data) {
            return definition
        }

        // Fall back to SimpleWorkflowLoader for flat starter workflow format
        // (flat format uses same type names, just different structure)
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

        for source in [WorkflowSource.system, .user] {
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
