//
//  MLXProvider.swift
//  Talkie
//
//  MLX-based local LLM provider for Apple Silicon using mlx-swift-lm
//

import Foundation
import MLXLMCommon
import MLX
import MLXLLM
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "LLM")
#if arch(arm64)

class MLXProvider: LLMProvider {
    let id = "mlx"
    let name = "MLX (Local)"

    @MainActor
    private var modelManager: MLXModelManager {
        MLXModelManager.shared
    }

    var isAvailable: Bool {
        get async {
            #if arch(arm64)
            return true
            #else
            return false
            #endif
        }
    }

    var models: [LLMModel] {
        get async throws {
            return await modelManager.availableModels()
        }
    }

    func generate(
        prompt: String,
        model: String,
        options: GenerationOptions
    ) async throws -> String {
        // Validate model is installed before attempting to load
        let isInstalled = await modelManager.isModelInstalled(id: model)
        if !isInstalled {
            throw LLMError.modelNotFound("MLX model '\(model)' is not installed. Please download it first in Settings > Models.")
        }

        // Load model if not already loaded
        let container = try await modelManager.loadModel(id: model)

        // Create a ChatSession for generation
        let session = ChatSession(
            container,
            generateParameters: GenerateParameters(
                maxTokens: options.maxTokens,
                temperature: Float(options.temperature),
                topP: 0.9
            )
        )

        // Generate response
        return try await session.respond(to: prompt)
    }

    func streamGenerate(
        prompt: String,
        model: String,
        options: GenerationOptions
    ) async throws -> AsyncThrowingStream<String, Error> {
        let container = try await modelManager.loadModel(id: model)

        let session = ChatSession(
            container,
            generateParameters: GenerateParameters(
                maxTokens: options.maxTokens,
                temperature: Float(options.temperature),
                topP: 0.9
            )
        )

        return session.streamResponse(to: prompt)
    }
}

// MARK: - MLX Model Manager

@MainActor
class MLXModelManager: ObservableObject {
    static let shared = MLXModelManager()

    @Published var loadedModelId: String?
    @Published var isLoading: Bool = false
    @Published var loadProgress: Double = 0

    /// Cached set of installed model IDs - updated on download/delete
    @Published private(set) var installedModelIds: Set<String> = []

    private var loadedContainer: ModelContainer?

    private let modelsDirectory: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return appSupport
            .appendingPathComponent("Talkie")
            .appendingPathComponent("Models")
            .appendingPathComponent("MLX")
    }()

    /// All model IDs from the centralized catalog
    private var catalogModelIds: [String] {
        MLXModelCatalog.allIds
    }

    private init() {
        createModelsDirectoryIfNeeded()
        refreshInstalledModels()
    }

    /// Refresh the cached installed models state
    func refreshInstalledModels() {
        installedModelIds = Set(catalogModelIds.filter { checkModelExists(id: $0) })
        logger.debug("[MLX] Refreshed installed models: \(self.installedModelIds)")
    }

    private func createModelsDirectoryIfNeeded() {
        try? FileManager.default.createDirectory(
            at: modelsDirectory,
            withIntermediateDirectories: true
        )
    }

    func availableModels() -> [LLMModel] {
        // Build from centralized catalog
        return MLXModelCatalog.models.map { def in
            LLMModel(
                id: def.id,
                name: def.name,
                displayName: def.displayName,
                size: def.size,
                type: .local,
                provider: "mlx",
                downloadURL: def.huggingFaceURL,
                isInstalled: isModelInstalled(id: def.id)
            )
        }
    }

    /// Check if a model is installed (uses cached state)
    func isModelInstalled(id: String) -> Bool {
        installedModelIds.contains(id)
    }

    /// Actually check filesystem for model existence (used internally)
    private func checkModelExists(id: String) -> Bool {
        // Check our local models directory first
        let localPath = modelsDirectory.appendingPathComponent(id.replacingOccurrences(of: "/", with: "_"))
        if FileManager.default.fileExists(atPath: localPath.path) {
            return true
        }

        // Check the MLX library's default cache location: ~/Library/Caches/models/{org}/{model-name}
        // This works correctly with App Sandbox (redirects to container)
        if let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            // MLX stores models as: Caches/models/mlx-community/Llama-3.2-1B-Instruct-4bit
            let mlxPath = cacheDir.appendingPathComponent("models/\(id)")
            if FileManager.default.fileExists(atPath: mlxPath.path) {
                return true
            }

            // Also check legacy HubApi cache directory (for backwards compatibility)
            let hubPath = cacheDir.appendingPathComponent("huggingface/hub/models--\(id.replacingOccurrences(of: "/", with: "--"))")
            if FileManager.default.fileExists(atPath: hubPath.path) {
                return true
            }
        }

        return false
    }

    func loadModel(id: String) async throws -> ModelContainer {
        // Check if already loaded
        if loadedModelId == id, let container = loadedContainer {
            return container
        }

        // Unload previous model to free memory
        if loadedContainer != nil {
            logger.debug("🔄 Unloading previous model...")
            loadedContainer = nil
            loadedModelId = nil
            MLX.GPU.clearCache()
        }

        logger.debug("⏳ Loading model: \(id)...")
        let startTime = Date()

        isLoading = true
        loadProgress = 0

        do {
            // Use the mlx-swift-lm loadModelContainer function
            // It will download from HuggingFace if not cached
            let container = try await loadModelContainer(id: id) { [weak self] progress in
                Task { @MainActor in
                    self?.loadProgress = progress.fractionCompleted
                }
            }

            let elapsed = Date().timeIntervalSince(startTime)
            logger.debug("✅ Model loaded in \(String(format: "%.1f", elapsed))s")
            loadedContainer = container
            loadedModelId = id
            isLoading = false
            loadProgress = 1.0

            return container
        } catch {
            isLoading = false
            logger.debug("❌ Failed to load model: \(error)")
            throw LLMError.modelNotFound("Failed to load model \(id): \(error.localizedDescription)")
        }
    }

    func downloadModel(id: String, progress: @escaping (Double) -> Void) async throws {
        logger.debug("📥 Starting download for model: \(id)")
        // Use MLXLLM's built-in download via loadModelContainer
        // This will download from HuggingFace Hub
        do {
            _ = try await loadModelContainer(id: id) { downloadProgress in
                progress(downloadProgress.fractionCompleted)
            }

            progress(1.0)
            installedModelIds.insert(id) // Update cached state
            logger.debug("✅ Successfully downloaded model: \(id)")
        } catch {
            logger.debug("❌ Failed to download model: \(error)")
            throw error
        }
    }

    func deleteModel(id: String) throws {
        // Delete from our local directory
        let localPath = modelsDirectory.appendingPathComponent(id.replacingOccurrences(of: "/", with: "_"))
        if FileManager.default.fileExists(atPath: localPath.path) {
            try FileManager.default.removeItem(at: localPath)
        }

        if let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            // Delete from MLX library's cache location: ~/Library/Caches/models/{org}/{model-name}
            let mlxPath = cacheDir.appendingPathComponent("models/\(id)")
            if FileManager.default.fileExists(atPath: mlxPath.path) {
                try FileManager.default.removeItem(at: mlxPath)
            }

            // Also try to delete from legacy HubApi cache
            let hubPath = cacheDir.appendingPathComponent("huggingface/hub/models--\(id.replacingOccurrences(of: "/", with: "--"))")
            if FileManager.default.fileExists(atPath: hubPath.path) {
                try FileManager.default.removeItem(at: hubPath)
            }
        }

        // Update cached state
        installedModelIds.remove(id)

        // Unload if this was the loaded model
        if loadedModelId == id {
            loadedContainer = nil
            loadedModelId = nil
            MLX.GPU.clearCache()
        }

        logger.debug("🗑️ Deleted model: \(id)")
    }

    private func modelPath(for id: String) -> URL {
        return modelsDirectory.appendingPathComponent(
            id.replacingOccurrences(of: "/", with: "_")
        )
    }
}

#else

// MARK: - Intel Stub (MLX not available on x86_64)

/// Stub MLXModelManager for Intel Macs where MLX is not available
@MainActor
class MLXModelManager: ObservableObject {
    static let shared = MLXModelManager()

    @Published var loadedModelId: String?
    @Published var isLoading: Bool = false
    @Published var loadProgress: Double = 0
    @Published private(set) var installedModelIds: Set<String> = []

    private init() {}

    func availableModels() -> [LLMModel] {
        return []
    }

    func isModelInstalled(id: String) -> Bool {
        return false
    }
}

#endif
