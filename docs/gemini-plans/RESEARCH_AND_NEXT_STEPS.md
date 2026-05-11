1# Research & Next Steps: Ambient, Interactive, Social Talkie

## Executive Summary
This folder contains planning documents for three major strategic expansions of the Talkie platform:
1.  **Ambient Voice Mode**: Transforming from "tool" to "presence" (Always-listening/VAD).
2.  **Computer Talks Back**: Bi-directional conversation and proactive assistance.
3.  **Sharing**: Viral loops and team collaboration.

## Consolidated Research Questions

### 1. Audio & AI (Ambient/Interactive)
- [ ] **Wake Word**: Benchmark `OpenWakeWord` vs `Porcupine` (apps/ios/macOS).
    - *Goal*: < 1% CPU usage on idle.
- [ ] **VAD Quality**: Test `Silero VAD` or WebRTC VAD on macOS audio tap.
- **Latency**: Measure "End-to-End" latency for a conversational turn:
    - VAD End -> Transcribe -> LLM -> TTS -> Audio Start.
    - *Target*: < 1000ms for natural feel.

### 2. Platform Integration
- [ ] **Live Activities**: Can we update a Live Activity from a background audio process continuously?
- [ ] **Background Audio**: Verify iOS entitlements for "Always on" audio (very strict review guidelines).
- [ ] **CloudKit Sharing**: Prototype a `CKShare` flow for a single `VoiceMemo`.

### 3. Sharing Infrastructure
- [ ] **Web Player**: Determine hosting strategy for "Talkie Links".
    - *Option A*: CloudKit Public DB (Native, cheap/free).
    - *Option B*: S3 + Custom Backend (Flexible, costs money).

## Immediate "To Dos" (Next 2 Weeks)

### A. Prototyping "Talk Back"
1.  Implement `TTSManager` (as per `docs/specs/text-to-speech.md`).
2.  Add a "Listen" button to the Memo Detail view.
3.  Test OpenAI TTS vs macOS System TTS latency.

### B. Prototyping "Ambient"
1.  Create a standalone "WakeWordTest" macOS app (outside main repo or as a tool).
2.  Test getting an audio stream from `TalkieAgent`'s existing recorder without triggering a full "Recording" state.

### C. Workflow Schema Update
1.  Draft the schema changes for `Speak Text` and `Ask for Input` steps in TWF format.

## Long-term Vision
A user speaks into the air: *"Talkie, send the meeting notes to the team."*
Talkie (Ambient) wakes, records, transcribes.
Talkie (Workflow) extracts tasks, summarizes.
Talkie (Sharing) creates a web link and emails it to the team.
Talkie (TTS) responds: *"Sent. You also have a follow-up task assigned to yourself."*
