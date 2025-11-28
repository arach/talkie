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

    private init() {
        createModelsDirectoryIfNeeded()
    }

    private func createModelsDirectoryIfNeeded() {
        try? FileManager.default.createDirectory(
            at: modelsDirectory,
            withIntermediateDirectories: true
        )
    }

    func availableModels() -> [LLMModel] {
        // Built-in model catalog
        let catalog: [LLMModel] = [
            // Ultra-fast 1B models - perfect for quick tasks
            LLMModel(
                id: "mlx-community/Llama-3.2-1B-Instruct-4bit",
                name: "Llama-3.2-1B-Instruct-4bit",
                displayName: "Llama 3.2 1B (4-bit) ⚡️",
                size: "1B",
                type: .local,
                provider: "mlx",
                downloadURL: URL(string: "https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit"),
                isInstalled: isModelInstalled(id: "mlx-community/Llama-3.2-1B-Instruct-4bit")
            ),
            LLMModel(
                id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
                name: "Qwen2.5-1.5B-Instruct-4bit",
                displayName: "Qwen 2.5 1.5B (4-bit) ⚡️",
                size: "1.5B",
                type: .local,
                provider: "mlx",
                downloadURL: URL(string: "https://huggingface.co/mlx-community/Qwen2.5-1.5B-Instruct-4bit"),
                isInstalled: isModelInstalled(id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit")
            ),

            // Balanced 3B models - great quality/speed tradeoff
            LLMModel(
                id: "mlx-community/Qwen2.5-3B-Instruct-4bit",
                name: "Qwen2.5-3B-Instruct-4bit",
                displayName: "Qwen 2.5 3B (4-bit)",
                size: "3B",
                type: .local,
                provider: "mlx",
                downloadURL: URL(string: "https://huggingface.co/mlx-community/Qwen2.5-3B-Instruct-4bit"),
                isInstalled: isModelInstalled(id: "mlx-community/Qwen2.5-3B-Instruct-4bit")
            ),
            LLMModel(
                id: "mlx-community/Llama-3.2-3B-Instruct-4bit",
                name: "Llama-3.2-3B-Instruct-4bit",
                displayName: "Llama 3.2 3B (4-bit)",
                size: "3B",
                type: .local,
                provider: "mlx",
                downloadURL: URL(string: "https://huggingface.co/mlx-community/Llama-3.2-3B-Instruct-4bit"),
                isInstalled: isModelInstalled(id: "mlx-community/Llama-3.2-3B-Instruct-4bit")
            ),
            LLMModel(
                id: "mlx-community/Phi-3.5-mini-instruct-4bit",
                name: "Phi-3.5-mini-instruct-4bit",
                displayName: "Phi 3.5 Mini (4-bit)",
                size: "3.8B",
                type: .local,
                provider: "mlx",
                downloadURL: URL(string: "https://huggingface.co/mlx-community/Phi-3.5-mini-instruct-4bit"),
                isInstalled: isModelInstalled(id: "mlx-community/Phi-3.5-mini-instruct-4bit")
            ),

            // Powerful 7B model - best quality
            LLMModel(
                id: "mlx-community/Mistral-7B-Instruct-v0.3-4bit",
                name: "Mistral-7B-Instruct-v0.3-4bit",
                displayName: "Mistral 7B v0.3 (4-bit) 🚀",
                size: "7B",
                type: .local,
                provider: "mlx",
                downloadURL: URL(string: "https://huggingface.co/mlx-community/Mistral-7B-Instruct-v0.3-4bit"),
                isInstalled: isModelInstalled(id: "mlx-community/Mistral-7B-Instruct-v0.3-4bit")
            )
        ]

        return catalog
    }

    func isModelInstalled(id: String) -> Bool {
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
            print("🔄 Unloading previous model...")
            loadedContainer = nil
            loadedModelId = nil
            MLX.GPU.clearCache()
        }

        print("⏳ Loading model: \(id)...")
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
            print("✅ Model loaded in \(String(format: "%.1f", elapsed))s")

            loadedContainer = container
            loadedModelId = id
            isLoading = false
            loadProgress = 1.0

            return container
        } catch {
            isLoading = false
            print("❌ Failed to load model: \(error)")
            throw LLMError.modelNotFound("Failed to load model \(id): \(error.localizedDescription)")
        }
    }

    func downloadModel(id: String, progress: @escaping (Double) -> Void) async throws {
        print("📥 Starting download for model: \(id)")

        // Use MLXLLM's built-in download via loadModelContainer
        // This will download from HuggingFace Hub
        do {
            _ = try await loadModelContainer(id: id) { downloadProgress in
                progress(downloadProgress.fractionCompleted)
            }

            progress(1.0)
            print("✅ Successfully downloaded model: \(id)")
        } catch {
            print("❌ Failed to download model: \(error)")
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

        // Unload if this was the loaded model
        if loadedModelId == id {
            loadedContainer = nil
            loadedModelId = nil
            MLX.GPU.clearCache()
        }

        print("🗑️ Deleted model: \(id)")
    }

    private func modelPath(for id: String) -> URL {
        return modelsDirectory.appendingPathComponent(
            id.replacingOccurrences(of: "/", with: "_")
        )
    }
}

#endif
