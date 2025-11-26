//
//  MLXProvider.swift
//  Talkie
//
//  MLX-based local LLM provider for Apple Silicon
//

import Foundation

#if arch(arm64)
// TODO: Add MLX packages via Xcode: File → Add Package Dependencies → https://github.com/ml-explore/mlx-swift
// import MLX
// import MLXRandom
// import MLXNN
// import MLXOptimizers

class MLXProvider: LLMProvider {
    let id = "mlx"
    let name = "MLX (Local)"

    @MainActor
    private var modelManager: MLXModelManager {
        MLXModelManager.shared
    }

    var isAvailable: Bool {
        get async {
            // Check if running on Apple Silicon
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
        let mlxModel = try await modelManager.loadModel(id: model)

        // Generate text
        return try await mlxModel.generate(
            prompt: prompt,
            maxTokens: options.maxTokens,
            temperature: options.temperature
        )
    }

    func streamGenerate(
        prompt: String,
        model: String,
        options: GenerationOptions
    ) async throws -> AsyncThrowingStream<String, Error> {
        let mlxModel = try await modelManager.loadModel(id: model)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await token in try await mlxModel.generateStream(
                        prompt: prompt,
                        maxTokens: options.maxTokens,
                        temperature: options.temperature
                    ) {
                        continuation.yield(token)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - MLX Model Manager

@MainActor
class MLXModelManager {
    static let shared = MLXModelManager()

    private var loadedModels: [String: MLXModel] = [:]

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
        let modelPath = modelsDirectory.appendingPathComponent(id.replacingOccurrences(of: "/", with: "_"))
        return FileManager.default.fileExists(atPath: modelPath.path)
    }

    func loadModel(id: String) async throws -> MLXModel {
        // Check if already loaded
        if let loaded = loadedModels[id] {
            return loaded
        }

        // Check if model is installed
        guard isModelInstalled(id: id) else {
            throw LLMError.modelNotFound(id)
        }

        // Load model (placeholder - actual MLX implementation will go here)
        let model = MLXModel(id: id, path: modelPath(for: id))
        loadedModels[id] = model

        print("✅ Loaded MLX model: \(id)")
        return model
    }

    func downloadModel(id: String, progress: @escaping (Double) -> Void) async throws {
        print("📥 Starting download for model: \(id)")

        let baseURL = "https://huggingface.co/\(id)/resolve/main"
        let modelPath = self.modelPath(for: id)

        // Create model directory
        try FileManager.default.createDirectory(
            at: modelPath,
            withIntermediateDirectories: true
        )

        // Essential files for MLX models
        let files: [(name: String, optional: Bool)] = [
            ("config.json", false),
            ("tokenizer.json", false),
            ("tokenizer_config.json", false),
            ("model.safetensors", false),
            ("tokenizer.model", true)
        ]

        // First, get the total size of all files by checking their Content-Length headers
        print("  Calculating total download size...")
        var fileSizes: [String: Int64] = [:]
        var totalBytes: Int64 = 0

        for file in files {
            guard let fileURL = URL(string: "\(baseURL)/\(file.name)") else { continue }

            do {
                var request = URLRequest(url: fileURL)
                request.httpMethod = "HEAD"
                let (_, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse,
                   (200...299).contains(httpResponse.statusCode) {
                    let size = httpResponse.expectedContentLength
                    fileSizes[file.name] = size
                    totalBytes += size
                    print("    \(file.name): \(size / 1_000_000)MB")
                }
            } catch {
                if !file.optional {
                    print("    ⚠️ Could not get size for \(file.name)")
                }
            }
        }

        print("  Total download size: \(totalBytes / 1_000_000)MB")

        // Now download each file with accurate byte-based progress
        var downloadedBytes: Int64 = 0

        for file in files {
            guard let fileURL = URL(string: "\(baseURL)/\(file.name)") else {
                continue
            }

            let destination = modelPath.appendingPathComponent(file.name)
            let fileSize = fileSizes[file.name] ?? 0

            do {
                print("  Downloading \(file.name)...")

                // Update progress immediately before starting download
                progress(Double(downloadedBytes) / Double(totalBytes))

                let startBytes = downloadedBytes
                try await downloadFileWithProgress(
                    from: fileURL,
                    to: destination,
                    totalBytes: totalBytes,
                    startBytes: startBytes,
                    progress: progress
                )
                downloadedBytes += fileSize

                // Update progress immediately after completing download
                progress(Double(downloadedBytes) / Double(totalBytes))

            } catch let error as LLMError {
                if file.optional {
                    // Silently skip optional files (like tokenizer.model which often doesn't exist)
                    print("  ⚠️ Skipping optional file: \(file.name)")
                    continue
                }
                throw error
            } catch {
                if file.optional {
                    print("  ⚠️ Skipping optional file: \(file.name)")
                    continue
                }
                throw error
            }
        }

        // Final 100% update
        progress(1.0)

        print("✅ Successfully downloaded model: \(id)")
    }

    private func downloadFileWithProgress(
        from url: URL,
        to destination: URL,
        totalBytes: Int64,
        startBytes: Int64,
        progress: @escaping (Double) -> Void
    ) async throws {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 3600

        let session = URLSession(configuration: configuration)
        defer {
            session.finishTasksAndInvalidate()
        }

        // Track the download task reference
        var downloadTask: URLSessionDownloadTask?

        let taskResult: (URL, URLResponse) = try await withCheckedThrowingContinuation { continuation in
            var resumed = false

            let task = session.downloadTask(with: url) { location, response, error in
                if !resumed {
                    resumed = true
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let location = location, let response = response {
                        continuation.resume(returning: (location, response))
                    } else {
                        continuation.resume(throwing: LLMError.generationFailed("No response"))
                    }
                }
            }

            downloadTask = task
            task.resume()

            // Poll progress in background
            Task {
                var lastReported: Int64 = 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))

                    guard let task = downloadTask, task.state == .running else { break }

                    let downloaded = task.countOfBytesReceived

                    if downloaded > lastReported && totalBytes > 0 {
                        let currentTotal = startBytes + downloaded
                        let overallProgress = Double(currentTotal) / Double(totalBytes)
                        let mbDownloaded = currentTotal / 1_000_000
                        let mbTotal = totalBytes / 1_000_000
                        let percentage = Int(overallProgress * 100)

                        // Log every 5MB change
                        if (mbDownloaded - lastReported / 1_000_000) >= 5 {
                            print("    \(percentage)% - \(mbDownloaded)MB / \(mbTotal)MB")
                            lastReported = downloaded
                        }

                        await MainActor.run {
                            progress(min(overallProgress, 1.0))
                        }
                    }
                }
            }
        }

        let (tempURL, response) = taskResult

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if statusCode != 404 {
                print("  ❌ Download error for \(url.lastPathComponent): HTTP \(statusCode)")
            }
            throw LLMError.generationFailed("Failed to download \(url.lastPathComponent) - HTTP \(statusCode)")
        }

        // Remove existing file if it exists
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }

        // Move temp file to destination
        try FileManager.default.moveItem(at: tempURL, to: destination)

        let fileSize = try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64 ?? 0
        print("  ✅ Downloaded \(url.lastPathComponent) (\(fileSize / 1_000_000)MB)")
    }
}

// MARK: - Download Delegate for Progress Tracking

class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let totalBytes: Int64       // Total bytes across all files
    let startBytes: Int64        // Bytes already downloaded before this file
    let progressCallback: (Double) -> Void

    init(totalBytes: Int64, startBytes: Int64, progressCallback: @escaping (Double) -> Void) {
        self.totalBytes = totalBytes
        self.startBytes = startBytes
        self.progressCallback = progressCallback
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytes > 0 else {
            print("    [DEBUG] Delegate called but totalBytes is 0")
            return
        }

        // Calculate overall progress across all files
        let currentTotalBytes = startBytes + totalBytesWritten
        let overallProgress = Double(currentTotalBytes) / Double(totalBytes)

        // Update progress on main thread
        Task { @MainActor in
            self.progressCallback(min(overallProgress, 1.0))
        }

        // Log progress frequently for debugging
        let mbDownloaded = currentTotalBytes / 1_000_000
        let mbTotal = self.totalBytes / 1_000_000
        let percentage = Int(overallProgress * 100)

        // Log every 10MB for better visibility
        if totalBytesWritten % (10 * 1024 * 1024) < bytesWritten {
            print("    \(percentage)% - \(mbDownloaded)MB / \(mbTotal)MB (file: \(totalBytesWritten / 1_000_000)MB)")
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // File is at temporary location - will be moved by caller
    }
}

// MARK: - MLX Model Manager (continued)

extension MLXModelManager {
    func deleteModel(id: String) throws {
        let path = modelPath(for: id)
        try FileManager.default.removeItem(at: path)
        loadedModels.removeValue(forKey: id)
        print("🗑️ Deleted model: \(id)")
    }

    private func modelPath(for id: String) -> URL {
        return modelsDirectory.appendingPathComponent(
            id.replacingOccurrences(of: "/", with: "_")
        )
    }
}

// MARK: - MLX Model Wrapper

class MLXModel {
    let id: String
    let path: URL
    private var modelWeights: [String: Any]? // MLXArray when MLX is imported
    private var tokenizer: MLXTokenizer?

    init(id: String, path: URL) {
        self.id = id
        self.path = path
    }

    private func loadIfNeeded() async throws {
        guard modelWeights == nil else { return }

        print("🔄 Loading model from \(path.path)")

        // Load model configuration
        let configPath = path.appendingPathComponent("config.json")
        let configData = try Data(contentsOf: configPath)
        let config = try JSONDecoder().decode(ModelConfig.self, from: configData)

        print("  Model type: \(config.modelType ?? "unknown")")
        print("  Vocab size: \(config.vocabSize ?? 0)")

        // Load tokenizer
        tokenizer = try MLXTokenizer(path: path)
        print("  ✅ Tokenizer loaded")

        // Load model weights
        let weightsPath = path.appendingPathComponent("model.safetensors")
        guard FileManager.default.fileExists(atPath: weightsPath.path) else {
            throw LLMError.modelNotFound("Model weights not found at \(weightsPath.path)")
        }

        // For now, we'll use a simplified loading approach
        // In production, you'd load the actual safetensors file
        print("  ⚠️ Model weights loading not yet fully implemented")
        print("  ⚠️ Using placeholder inference for now")

        modelWeights = [:]
    }

    func generate(
        prompt: String,
        maxTokens: Int,
        temperature: Double
    ) async throws -> String {
        try await loadIfNeeded()

        guard let tokenizer = tokenizer else {
            throw LLMError.generationFailed("Tokenizer not loaded")
        }

        // Encode prompt
        let tokens = try tokenizer.encode(prompt)
        print("🔤 Encoded prompt to \(tokens.count) tokens")

        // Note: Actual inference would use the loaded model weights
        // This is a placeholder until we implement the full inference loop
        let response = """
        [MLX Model Response - Inference Placeholder]

        Your prompt: \(prompt.prefix(100))...

        Note: Full MLX inference with model.safetensors loading is not yet implemented.
        This requires:
        1. Loading safetensors weights into MLXArray
        2. Building model architecture (transformer layers)
        3. Running forward pass with prompt tokens
        4. Sampling tokens with temperature
        5. Decoding back to text

        Model: \(id)
        Model path: \(path.path)
        """

        return response
    }

    func generateStream(
        prompt: String,
        maxTokens: Int,
        temperature: Double
    ) async throws -> AsyncStream<String> {
        return AsyncStream { continuation in
            Task {
                try? await self.loadIfNeeded()

                // Placeholder streaming
                if let response = try? await self.generate(
                    prompt: prompt,
                    maxTokens: maxTokens,
                    temperature: temperature
                ) {
                    // Stream word by word
                    let words = response.split(separator: " ")
                    for word in words {
                        continuation.yield(String(word) + " ")
                        try? await Task.sleep(for: .milliseconds(50))
                    }
                }

                continuation.finish()
            }
        }
    }
}

// MARK: - MLX Tokenizer

class MLXTokenizer {
    private let vocabPath: URL
    private let configPath: URL

    init(path: URL) throws {
        self.vocabPath = path.appendingPathComponent("tokenizer.json")
        self.configPath = path.appendingPathComponent("tokenizer_config.json")

        guard FileManager.default.fileExists(atPath: vocabPath.path) else {
            throw LLMError.generationFailed("Tokenizer vocab not found")
        }
    }

    func encode(_ text: String) throws -> [Int] {
        // Simplified tokenization
        // In production, parse tokenizer.json and implement proper BPE/WordPiece
        let tokens = text.split(separator: " ").map { _ in Int.random(in: 0..<50000) }
        return tokens
    }

    func decode(_ tokens: [Int]) throws -> String {
        // Simplified detokenization
        return tokens.map { String($0) }.joined(separator: " ")
    }
}

// MARK: - Model Configuration

struct ModelConfig: Codable {
    let modelType: String?
    let vocabSize: Int?
    let hiddenSize: Int?
    let numHiddenLayers: Int?
    let numAttentionHeads: Int?

    enum CodingKeys: String, CodingKey {
        case modelType = "model_type"
        case vocabSize = "vocab_size"
        case hiddenSize = "hidden_size"
        case numHiddenLayers = "num_hidden_layers"
        case numAttentionHeads = "num_attention_heads"
    }
}

#endif
