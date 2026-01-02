# Python Pod Architecture

> **Status**: Planned. Escape hatch for ML workloads that don't fit the MLX ecosystem.

## Overview

Execution pods run ML models in isolated subprocesses. The Swift pods (TalkieEnginePod) work great for MLX-native models, but some workloads need access to the broader Python ML ecosystem.

A Python pod would provide:
- Access to PyTorch, Hugging Face transformers, and vanilla Python ML packages
- Same subprocess isolation and memory reclaim benefits as Swift pods
- Flexibility to run models that don't have MLX ports

## Use Cases

- Models with only PyTorch weights (no MLX conversion available)
- Rapid prototyping with new models before committing to MLX integration
- Specialized pipelines (NLP, embeddings, etc.) that live in Python-land
- Testing models from Hugging Face Hub directly

## Architecture

### Pod Protocol

Python pod speaks the same JSON-lines protocol as Swift pods:

```
→ stdin:  {"id":"uuid","action":"process","payload":{"text":"Hello"}}
← stdout: {"id":"uuid","success":true,"result":{"output":"..."}}
```

Lifecycle signals:
```json
{"type":"ready","capability":"llm","backend":"python-transformers","memoryMB":2000,"pid":12345}
{"type":"log","message":"Loading model...","timestamp":"..."}
```

### File Structure

```
macOS/TalkieEnginePodPy/
├── pod.py           # Generic runner, loads capabilities dynamically
├── pyproject.toml   # Minimal core deps, optional extras per capability
├── run-pod.sh       # Bootstraps venv via uv, then exec's pod.py
└── .venv/           # Local environment, created on first run
```

### Dependency Management

Use `uv` for fast, hermetic Python environments:

```bash
# run-pod.sh
uv venv .venv --python 3.11
uv pip install -e ".[capability-name]"
exec .venv/bin/python pod.py "$@"
```

Optional dependencies keep the base small:
```toml
[project.optional-dependencies]
summarization = ["transformers", "torch", "sentencepiece"]
embeddings = ["sentence-transformers", "torch"]
```

### PodManager Integration

Extend PodManager to spawn Python pods:

```swift
enum PodBackend {
    case native      // Swift/MLX (TalkieEnginePod)
    case python      // Python/PyTorch (TalkieEnginePodPy)
}

// Spawn with capability config
try await PodManager.shared.spawn(
    capability: "summarization",
    backend: .python,
    config: ["model": "facebook/bart-large-cnn"]
)
```

## Recipe-Based Capabilities

Instead of hardcoding capabilities, download "recipes" that define:

```json
{
  "name": "whisper-transcription",
  "capability": "transcription",
  "dependencies": ["openai-whisper", "torch"],
  "model": "openai/whisper-large-v3",
  "entry": "transcribe.py"
}
```

Benefits:
- Add capabilities without app updates
- Version-controlled recipes in a GitHub repo
- User can select which capabilities to install

## Memory Characteristics

Python pods will use more memory than MLX equivalents due to PyTorch overhead:

| Stack | Typical Overhead |
|-------|------------------|
| MLX (Swift pod) | Model size only |
| PyTorch (Python pod) | Model + ~500MB runtime |

The subprocess architecture means this memory is reclaimable - kill the pod when not in use.

## Implementation Notes

### Process Naming

Set a friendly name for Activity Monitor:
```python
import setproctitle
setproctitle.setproctitle("Talkie LLM Engine")
```

### Signal Handling

Handle SIGTERM for graceful shutdown:
```python
signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
signal.signal(signal.SIGPIPE, signal.SIG_IGN)
```

### Sandbox Compatibility

Python venv lives in app support directory:
```
~/Library/Application Support/Talkie/pods/python/.venv/
```

No system Python modifications, no sudo required.

## When to Build

This architecture makes sense when:
1. A specific capability needs Python-only packages
2. MLX port doesn't exist or is immature
3. Rapid iteration is more valuable than memory efficiency

For now, MLX-native pods handle our needs. The Python escape hatch is ready when we need it.
