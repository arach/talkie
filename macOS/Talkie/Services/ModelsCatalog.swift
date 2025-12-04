//
//  ModelsCatalog.swift
//  Talkie
//
//  Central catalog of all model definitions and metadata
//

import Foundation

// MARK: - MLX Local Models Catalog

struct MLXModelDefinition {
    let id: String
    let name: String
    let displayName: String
    let family: String       // "Llama", "Qwen", "Phi", "Mistral"
    let size: String         // "1B", "3B", "7B"
    let quantization: String // "4bit", "8bit"
    let diskSize: String     // "700MB", "2.0GB"
    let huggingFaceURL: URL?
    let paperURL: URL?
}

enum MLXModelCatalog {
    static let models: [MLXModelDefinition] = [
        // Llama Family
        MLXModelDefinition(
            id: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            name: "Llama-3.2-1B-Instruct-4bit",
            displayName: "Llama 3.2 1B (4-bit)",
            family: "Llama",
            size: "1B",
            quantization: "4-bit",
            diskSize: "700MB",
            huggingFaceURL: URL(string: "https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit"),
            paperURL: URL(string: "https://arxiv.org/abs/2407.21783")
        ),
        MLXModelDefinition(
            id: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            name: "Llama-3.2-3B-Instruct-4bit",
            displayName: "Llama 3.2 3B (4-bit)",
            family: "Llama",
            size: "3B",
            quantization: "4-bit",
            diskSize: "2.0GB",
            huggingFaceURL: URL(string: "https://huggingface.co/mlx-community/Llama-3.2-3B-Instruct-4bit"),
            paperURL: URL(string: "https://arxiv.org/abs/2407.21783")
        ),

        // Qwen Family
        MLXModelDefinition(
            id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
            name: "Qwen2.5-1.5B-Instruct-4bit",
            displayName: "Qwen 2.5 1.5B (4-bit)",
            family: "Qwen",
            size: "1.5B",
            quantization: "4-bit",
            diskSize: "1.0GB",
            huggingFaceURL: URL(string: "https://huggingface.co/mlx-community/Qwen2.5-1.5B-Instruct-4bit"),
            paperURL: URL(string: "https://arxiv.org/abs/2309.16609")
        ),
        MLXModelDefinition(
            id: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            name: "Qwen2.5-3B-Instruct-4bit",
            displayName: "Qwen 2.5 3B (4-bit)",
            family: "Qwen",
            size: "3B",
            quantization: "4-bit",
            diskSize: "2.0GB",
            huggingFaceURL: URL(string: "https://huggingface.co/mlx-community/Qwen2.5-3B-Instruct-4bit"),
            paperURL: URL(string: "https://arxiv.org/abs/2309.16609")
        ),

        // Phi Family
        MLXModelDefinition(
            id: "mlx-community/Phi-3.5-mini-instruct-4bit",
            name: "Phi-3.5-mini-instruct-4bit",
            displayName: "Phi 3.5 Mini (4-bit)",
            family: "Phi",
            size: "3.5B",
            quantization: "4-bit",
            diskSize: "2.0GB",
            huggingFaceURL: URL(string: "https://huggingface.co/mlx-community/Phi-3.5-mini-instruct-4bit"),
            paperURL: URL(string: "https://arxiv.org/abs/2404.14219")
        ),

        // Mistral Family
        MLXModelDefinition(
            id: "mlx-community/Mistral-7B-Instruct-v0.3-4bit",
            name: "Mistral-7B-Instruct-v0.3-4bit",
            displayName: "Mistral 7B v0.3 (4-bit)",
            family: "Mistral",
            size: "7B",
            quantization: "4-bit",
            diskSize: "4.0GB",
            huggingFaceURL: URL(string: "https://huggingface.co/mlx-community/Mistral-7B-Instruct-v0.3-4bit"),
            paperURL: URL(string: "https://arxiv.org/abs/2310.06825")
        )
    ]

    static var allIds: [String] {
        models.map { $0.id }
    }

    static var families: [String] {
        Array(Set(models.map { $0.family })).sorted()
    }

    static func models(for family: String) -> [MLXModelDefinition] {
        models.filter { $0.family == family }
    }

    static func model(byId id: String) -> MLXModelDefinition? {
        models.first { $0.id == id }
    }
}

// MARK: - Whisper STT Models Metadata

struct WhisperModelMetadata {
    let model: WhisperModel
    let displayName: String
    let sizeMB: Int
    let accuracy: Int          // Word error rate improvement %
    let rtf: Double            // Real-time factor
    let description: String
}

enum WhisperModelCatalog {
    static let repoURL = URL(string: "https://github.com/argmaxinc/WhisperKit")!
    static let paperURL = URL(string: "https://arxiv.org/abs/2212.04356")!

    static let metadata: [WhisperModelMetadata] = [
        WhisperModelMetadata(
            model: .tiny,
            displayName: "Tiny",
            sizeMB: 39,
            accuracy: 72,
            rtf: 0.07,
            description: "Fastest, basic quality"
        ),
        WhisperModelMetadata(
            model: .base,
            displayName: "Base",
            sizeMB: 74,
            accuracy: 81,
            rtf: 0.10,
            description: "Fast, good quality"
        ),
        WhisperModelMetadata(
            model: .small,
            displayName: "Small",
            sizeMB: 244,
            accuracy: 88,
            rtf: 0.17,
            description: "Balanced speed/quality"
        ),
        WhisperModelMetadata(
            model: .distilLargeV3,
            displayName: "Large",
            sizeMB: 756,
            accuracy: 95,
            rtf: 0.33,
            description: "Best quality, slower"
        )
    ]

    static func metadata(for model: WhisperModel) -> WhisperModelMetadata? {
        metadata.first { $0.model == model }
    }
}

// MARK: - Parakeet STT Models Metadata

struct ParakeetModelMetadata {
    let model: ParakeetModel
    let displayName: String
    let languages: Int
    let languagesBadge: String // "EN" or "ML" (multilingual)
    let sizeMB: Int
    let rtf: Double
    let description: String
}

enum ParakeetModelCatalog {
    static let repoURL = URL(string: "https://github.com/FluidInference/FluidAudio")!
    static let paperURL = URL(string: "https://arxiv.org/abs/2409.17143")!

    static let metadata: [ParakeetModelMetadata] = [
        ParakeetModelMetadata(
            model: .v2,
            displayName: "V2",
            languages: 1,
            languagesBadge: "EN",
            sizeMB: 600,
            rtf: 0.05,
            description: "English only, highest accuracy"
        ),
        ParakeetModelMetadata(
            model: .v3,
            displayName: "V3",
            languages: 25,
            languagesBadge: "25L",
            sizeMB: 600,
            rtf: 0.05,
            description: "25 languages, fast"
        )
    ]

    static func metadata(for model: ParakeetModel) -> ParakeetModelMetadata? {
        metadata.first { $0.model == model }
    }
}

// MARK: - Cloud Provider Metadata (UI enrichment for LLMConfig)
// Note: Cloud model definitions live in LLMConfig.json - this provides UI-only metadata

enum CloudProviderMetadata {
    struct Info {
        let tagline: String
        let docsURL: URL?
        let pricingURL: URL?
    }

    static let providers: [String: Info] = [
        "openai": Info(
            tagline: "Industry standard for reasoning and vision",
            docsURL: URL(string: "https://platform.openai.com/docs"),
            pricingURL: URL(string: "https://openai.com/pricing")
        ),
        "anthropic": Info(
            tagline: "Extended thinking and nuanced understanding",
            docsURL: URL(string: "https://docs.anthropic.com"),
            pricingURL: URL(string: "https://anthropic.com/pricing")
        ),
        "gemini": Info(
            tagline: "Multimodal powerhouse with massive context",
            docsURL: URL(string: "https://ai.google.dev/docs"),
            pricingURL: URL(string: "https://ai.google.dev/pricing")
        ),
        "groq": Info(
            tagline: "Ultra-fast inference at scale",
            docsURL: URL(string: "https://console.groq.com/docs"),
            pricingURL: URL(string: "https://groq.com/pricing")
        )
    ]

    static func info(for providerId: String) -> Info? {
        providers[providerId]
    }
}
