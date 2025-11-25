# MLX Integration Guide

## Overview

Talkie now supports local LLM inference using **MLX** (Apple's ML framework optimized for Apple Silicon) alongside cloud providers like Gemini.

## Architecture

```
┌─────────────────────────────────────┐
│      LLMProvider Protocol           │
│    (Provider abstraction layer)     │
├──────────────┬──────────────────────┤
│ MLXProvider  │  GeminiProvider      │
│ (Local M1+)  │  (Cloud API)         │
└──────────────┴──────────────────────┘
```

### Key Components

1. **LLMProvider.swift** - Protocol defining common interface for all LLM providers
2. **MLXProvider.swift** - Local inference using MLX on Apple Silicon
3. **GeminiProvider.swift** - Cloud-based Gemini API provider (refactored)
4. **LLMProviderRegistry.swift** - Manages all providers and models

## MLX Provider

### Supported Models

Pre-configured 4-bit quantized models from `mlx-community`:

- **Qwen 2.5 3B** (1.5GB) - Excellent instruction following, fast
- **Llama 3.2 3B** (1.5GB) - Meta's latest, strong general purpose
- **Mistral 7B** (3.5GB) - Powerful reasoning and generation
- **Phi 3.5 Mini** (2GB) - Microsoft's efficient model

### Model Storage

Models are stored in:
```
~/Library/Application Support/Talkie/Models/MLX/
```

### Implementation Status

✅ **Completed:**
- Protocol architecture
- Provider abstraction
- Model catalog
- Model management (download, storage, loading)
- Gemini provider refactor

🚧 **Next Steps:**
1. Add MLX Swift package via SPM
2. Implement actual MLX inference (currently placeholder)
3. Implement streaming inference
4. Build download UI with progress
5. Add model selection in workflows

## Adding MLX Dependencies

### Option 1: Swift Package Manager (Recommended)

Add to Xcode project:
1. File → Add Package Dependencies
2. Enter: `https://github.com/ml-explore/mlx-swift`
3. Version: 0.18.0 or later
4. Add to Talkie (macOS) target

### Option 2: Manual Package.swift

A `Package.swift` has been created in `/iOS/` directory with MLX dependencies pre-configured.

## Usage

### Basic Generation

```swift
let registry = LLMProviderRegistry.shared

// Get MLX provider
guard let mlxProvider = registry.provider(for: "mlx") else {
    print("MLX not available")
    return
}

// Generate text
let result = try await mlxProvider.generate(
    prompt: "Summarize this: ...",
    model: "mlx-community/Qwen2.5-3B-Instruct-4bit",
    options: .default
)
```

### Streaming Generation

```swift
for try await token in mlxProvider.streamGenerate(
    prompt: prompt,
    model: modelId,
    options: options
) {
    print(token, terminator: "")
}
```

### Model Management

```swift
let manager = MLXModelManager.shared

// Download model
try await manager.downloadModel(id: modelId) { progress in
    print("Download progress: \(progress * 100)%")
}

// Check if installed
if manager.isModelInstalled(id: modelId) {
    let model = try await manager.loadModel(id: modelId)
}

// Delete model
try manager.deleteModel(id: modelId)
```

## Next Implementation Steps

### 1. Add MLX Inference

Replace placeholders in `MLXProvider.swift`:

```swift
import MLX
import MLXNN
import MLXOptimizers

// In MLXModel class
func generate(prompt: String, maxTokens: Int, temperature: Double) async throws -> String {
    // 1. Load model weights
    let weights = try MLX.load(url: path.appendingPathComponent("weights.safetensors"))

    // 2. Load tokenizer
    let tokenizer = try Tokenizer(path: path.appendingPathComponent("tokenizer.json"))

    // 3. Encode prompt
    let tokens = tokenizer.encode(prompt)

    // 4. Run inference
    var generated = tokens
    for _ in 0..<maxTokens {
        let logits = model(generated)
        let nextToken = sample(logits, temperature: temperature)
        generated.append(nextToken)

        if nextToken == tokenizer.eosToken {
            break
        }
    }

    // 5. Decode output
    return tokenizer.decode(generated)
}
```

### 2. Model Download Implementation

Use HuggingFace Hub API:

```swift
func downloadModel(id: String, progress: @escaping (Double) -> Void) async throws {
    let baseURL = "https://huggingface.co/\(id)/resolve/main"

    // Files to download for MLX models
    let files = [
        "config.json",
        "tokenizer.json",
        "tokenizer_config.json",
        "weights.safetensors"
    ]

    let modelPath = modelsDirectory.appendingPathComponent(
        id.replacingOccurrences(of: "/", with: "_")
    )
    try FileManager.default.createDirectory(at: modelPath, withIntermediateDirectories: true)

    for (index, file) in files.enumerated() {
        let url = URL(string: "\(baseURL)/\(file)")!
        let destination = modelPath.appendingPathComponent(file)

        // Download file
        try await downloadFile(from: url, to: destination) { fileProgress in
            let totalProgress = (Double(index) + fileProgress) / Double(files.count)
            progress(totalProgress)
        }
    }
}
```

### 3. Update UI

Models content view should show:
- Cloud providers (Gemini) with API key status
- Local providers (MLX) with:
  - Available models catalog
  - Installed models
  - Download button with progress
  - Storage usage
  - Delete option

## Performance Notes

- **4-bit quantization** reduces model size by ~75%
- **3B models** run at ~20-30 tokens/sec on M1 Pro
- **7B models** run at ~10-15 tokens/sec on M1 Pro
- **Unified memory** on Apple Silicon allows larger context windows
- **Metal acceleration** provides near-optimal performance

## Rust Integration (Future)

When adding Rust/Candle later:
1. Create `talkie-inference` Rust crate
2. Build as `cdylib` for Swift FFI
3. Add as `CandleProvider` conforming to `LLMProvider`
4. Provides Intel Mac support
5. Can also run on Apple Silicon as alternative

This keeps architecture clean - just another provider!

## Resources

- [MLX Swift GitHub](https://github.com/ml-explore/mlx-swift)
- [MLX Community Models](https://huggingface.co/mlx-community)
- [MLX Documentation](https://ml-explore.github.io/mlx/build/html/index.html)
