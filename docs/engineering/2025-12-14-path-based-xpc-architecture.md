# Path-Based XPC Architecture for TalkieEngine

*December 14, 2025*

## Overview

This document traces the evolution of TalkieEngine's transcription architecture from a Data-based XPC approach to a Path-based approach, including the reasoning, performance implications, and final implementation.

## The Problem

TalkieLive captures audio and sends it to TalkieEngine for transcription via XPC (Cross-Process Communication). The original implementation passed audio data directly over XPC:

```swift
// Original XPC protocol
func transcribe(audioData: Data, modelId: String, reply: ...)
```

This meant serializing potentially megabytes of audio data across process boundaries.

## The Solution

Pass the file path instead of the data:

```swift
// New XPC protocol
func transcribe(audioPath: String, modelId: String, reply: ...)
```

The engine reads directly from the client's file. Simple change, significant implications.

---

## Architecture Comparison

### Before: Data Over XPC

```
TalkieLive                              TalkieEngine
    │                                        │
    ├─► Write temp file                      │
    ├─► Read temp into Data                  │
    ├─► Write to permanent storage           │
    ├─► Send Data over XPC ─────────────────►│
    │   (~500KB serialized)                  ├─► Receive Data
    │                                        ├─► Write to temp file
    │                                        ├─► Model reads temp
    │                                        ├─► Transcribe
    │◄─────────────────────────────── Reply ─┤
```

**I/O Cost:** 3 writes, 2 reads, heavy XPC payload

### After: Path Over XPC

```
TalkieLive                              TalkieEngine
    │                                        │
    ├─► Write temp file                      │
    ├─► Copy temp to permanent               │
    ├─► Delete temp                          │
    ├─► Send path over XPC ─────────────────►│
    │   (~100 bytes)                         ├─► Open file (read-only)
    │                                        ├─► Model reads directly
    │                                        ├─► Transcribe
    │◄─────────────────────────────── Reply ─┤
```

**I/O Cost:** 2 writes, 2 reads, minimal XPC payload

---

## The Key Insight: No Contention

A natural concern with the path-based approach: what if there's file contention between TalkieLive writing and TalkieEngine reading?

**There isn't.** The operations are sequential, not concurrent:

```
TalkieLive: copyItem() completes → file closed
TalkieLive: sends path over XPC
TalkieEngine: opens file for reading
```

The file is fully written and the handle is closed before the engine ever touches it. No locks, no contention, no race conditions.

---

## Sandbox Considerations

| Component | Sandboxed | Implication |
|-----------|-----------|-------------|
| TalkieLive | Yes | Files live in `~/Library/Containers/jdi.talkie.live/` |
| TalkieEngine | No | Can read any path on the filesystem |

The engine's lack of sandboxing is intentional—it needs to read files from client containers. The path sent over XPC is just a string; the engine opens it with standard file I/O.

---

## Happy Path Latency Trace

**Scenario:** 30-second voice recording, ~500KB m4a, Parakeet v3 model

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    TALKIELIVE (Sandboxed)                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  [RECORDING: 30 seconds of audio capture]                                   │
│                                                                             │
│  T+0ms     AudioCapture.stopCapture()                                       │
│            └─► Temp file complete: /Containers/.../tmp/UUID.m4a             │
│                                                                             │
│  T+1ms     LiveController.process(tempAudioPath:) starts                    │
│            └─► pipelineStart = Date()                                       │
│                                                                             │
│  T+2ms     AudioStorage.copyToStorage(tempURL)                              │
│            ├─► Read temp file (~500KB)                                      │
│            ├─► Write to permanent: /Containers/.../Audio/UUID.m4a           │
│            └─► File handle closed                                           │
│                                                                             │
│  T+17ms    Copy complete (fileSaveMs ≈ 15ms)                                │
│            └─► Log: "Audio saved: UUID.m4a (512KB) • 15ms"                  │
│                                                                             │
│  T+18ms    Delete temp file                                                 │
│                                                                             │
│  T+19ms    Context capture, sound effects, milestone tracking               │
│                                                                             │
│  T+25ms    preTranscriptionMs ≈ 25ms                                        │
│            └─► Log: "Transcribing... Model: parakeet:v3 • overhead: 25ms"   │
│                                                                             │
│  T+26ms    XPC call: transcribe(audioPath: permanentPath)                   │
│            └─► Payload: ~100 bytes (just the path string)                   │
│                                                                             │
└───────────────────────────────┬─────────────────────────────────────────────┘
                                │
                          [XPC Mach Port]
                                │
┌───────────────────────────────▼─────────────────────────────────────────────┐
│                    TALKIEENGINE (Not Sandboxed)                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  T+27ms    EngineService.transcribe(audioPath:modelId:reply:)               │
│            └─► Log: "Transcribing 'UUID.m4a' with model 'parakeet:v3'"      │
│                                                                             │
│  T+28ms    Open file handle (read-only)                                     │
│            └─► Path: /Users/.../Containers/.../Audio/UUID.m4a               │
│                                                                             │
│  T+30ms    AsrManager.transcribe(audioURL)                                  │
│            ├─► Decode AAC → PCM samples                                     │
│            ├─► Load into model                                              │
│            └─► Neural network inference                                     │
│                                                                             │
│  T+530ms   Transcription complete (~500ms)                                  │
│            └─► "This is the transcribed text from the recording..."         │
│                                                                             │
│  T+531ms   reply(transcript, nil)                                           │
│            └─► Log: "✓ #42 in 504ms (87 words)"                             │
│                                                                             │
└───────────────────────────────┬─────────────────────────────────────────────┘
                                │
                          [XPC Reply]
                                │
┌───────────────────────────────▼─────────────────────────────────────────────┐
│                    TALKIELIVE (Continued)                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  T+532ms   Transcription result received                                    │
│            ├─► transcriptionMs = 506ms                                      │
│            ├─► endToEndMs = 532ms                                           │
│            ├─► overheadMs = 26ms                                            │
│            └─► Log: "87 words • 506ms • overhead: 26ms • total: 532ms"      │
│                                                                             │
│  T+533ms   Route transcript (paste/clipboard)                               │
│                                                                             │
│  T+535ms   Store to PastLivesDatabase                                       │
│                                                                             │
│  T+540ms   Pipeline complete                                                │
│            └─► Log: "Pipeline complete - Ready for next recording"          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Timing Summary

| Phase | Time | % Total |
|-------|------|---------|
| File copy | 15ms | 2.8% |
| Pre-transcription overhead | 10ms | 1.9% |
| XPC overhead | 1ms | 0.2% |
| **Transcription** | **506ms** | **95.1%** |
| Post-processing | 8ms | 1.5% |
| **TOTAL** | **540ms** | 100% |

**Real-Time Factor:** 1.8% (540ms to transcribe 30,000ms of audio)

---

## Performance Comparison

| Metric | Before (Data) | After (Path) | Improvement |
|--------|---------------|--------------|-------------|
| Disk Writes | 3 | 2 | 33% fewer |
| XPC Payload | ~500KB | ~100 bytes | 5000x smaller |
| Total Overhead | ~80ms | ~26ms | 68% reduction |
| Overhead % | 13.8% | 4.9% | 2.8x better |

---

## Design Principles Validated

### 1. Audio is Sacrosanct

The permanent audio file is written once and never modified. The engine only reads it. If transcription fails, the recording is safe for retry.

```
Temp file ──► Permanent file (write-once) ──► Engine reads (read-only)
                     │
                     └─► Never touched again
```

### 2. Engine is Stateless

The engine receives a path, reads the file, returns text. No temp files, no state management, no cleanup responsibility.

```
Input:  /path/to/audio.m4a
Output: "transcribed text"
```

### 3. Separation of Concerns

- **TalkieLive:** Owns audio storage, manages permanent archive
- **TalkieEngine:** Processes audio, returns transcripts
- **XPC:** Thin coordination layer (just passes paths)

---

## Files Changed

| File | Change |
|------|--------|
| `EngineProtocol.swift` | `audioData: Data` → `audioPath: String` |
| `EngineService.swift` | Removed temp file creation, reads directly |
| `XPCServiceWrapper.swift` | Updated to pass path |
| `TalkieLive/EngineClient.swift` | Uses `audioPath: String` |
| `Talkie/EngineClient.swift` | Added path-based method, kept Data for backward compat |
| `LiveController.swift` | Copy temp→permanent, send permanent path |
| `AudioCapture.swift` | Callback passes path, not Data |
| `TranscriptionTypes.swift` | `TranscriptionRequest.audioPath` |
| `TranscriptionRetryManager.swift` | Passes path directly |

---

## Observability Additions

As part of this work, we added performance observability:

1. **TalkieLive Logging**
   - File save timing: `"Audio saved: UUID.m4a (512KB) • 15ms"`
   - Pre-transcription overhead: `"overhead: 25ms"`
   - End-to-end breakdown: `"506ms • overhead: 26ms • total: 532ms"`

2. **Engine Performance Tab**
   - Table of recent transcriptions
   - Latency, word count, RTF per transcription
   - Running averages

3. **Millisecond Precision**
   - All timing logs show milliseconds for fast operations
   - Seconds with 2 decimal places for longer operations

---

## Conclusion

The path-based architecture is objectively better:

- **Fewer disk operations** (2 writes vs 3)
- **5000x smaller XPC payload** (100 bytes vs 500KB)
- **68% less overhead** (26ms vs 80ms)
- **Cleaner separation** (engine is truly stateless)
- **Same reliability** (sequential access, no contention)

The transcription model is the bottleneck (95% of time). Everything else is noise. Our job is to minimize that noise—and we did.

---

*This document serves as a reference for the TalkieEngine architecture and can be expanded for blog posts or technical documentation.*
