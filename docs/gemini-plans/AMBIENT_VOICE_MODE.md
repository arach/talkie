# Ambient Voice Mode Integration Plan

## Overview

Current state: Talkie is primarily "Push-to-Talk" (global hotkey or UI button) or "Tap-to-Record".
Goal: Enable "Ambient Mode" where Talkie listens passively for a wake word or voice activity to trigger recording/processing without manual intervention.

## Core Concepts

### 1. The "Always-Listening" Ring Buffer
To support a wake word or instant VAD catch-up, `TalkieAgent` needs a circular audio buffer (e.g., 3-5 seconds).
- **Privacy**: This buffer stays in RAM, never written to disk unless a trigger event occurs.
- **Resource Usage**: Must be extremely lightweight.

### 2. Trigger Mechanisms

#### A. Wake Word ("Hey Talkie")
- **Technology**: OpenWakeWord (Python/ONNX) or a lightweight CoreML keyword spotter.
- **Pros**: Clear intent, hands-free.
- **Cons**: "Always on" microphone privacy implications, battery drain (on apps/ios/MacBooks), false positives.

#### B. Voice Activity Detection (VAD) Gating
- **Mechanism**: Detect speech energy. If > threshold for > N seconds, start "Tentative Recording".
- **Confirmation**:
    - **Gaze-based**: (Future, Vision Pro/webcam)
    - **Keyboard**: "Hold Shift to confirm ambient capture"
    - **Post-hoc**: Record everything, but only "commit" if specific keywords/intents are detected.

#### C. "Sidecar" Mode (iOS -> Mac)
- Use iPhone as the ambient microphone (on desk/MagSafe stand) streaming to Mac.
- Leverages iPhone's efficient neural engine for wake word detection to save Mac battery.

## Architecture Updates

### TalkieAgent (macOS)
`TalkieAgent` is the ideal host for this. It already runs independently.

1.  **Audio Engine Update**:
    - Implement `RingBuffer` audio tap.
    - Feed `VAD` analyzer continuously.
2.  **Inference Pipeline**:
    - Add `WakeWordDetector` service (separate from `TalkieEngine` to avoid spinning up heavy models constantly).
    - Can we use `Speech` framework (SFSpeechRecognizer) for low-power keyword spotting?
3.  **UI Feedback**:
    - Menu bar icon needs a distinct "Listening" state (e.g., pulsing dot).
    - Optional "Visualizer" overlay on desktop (Siri-style orb) when active.

### Talkie iOS
- **Live Activities**: Show "Listening" status on Lock Screen/Dynamic Island.
- **Background Audio**: Apple restricts background recording. "Ambient Mode" might only work while app is foreground/charging or via specific "Live Audio" entitlement (Inter-App Audio/CarPlay).

## User Workflows

1.  **The "Shower Thought" Catcher**:
    - User toggles "Ambient Mode" while cooking/driving.
    - Says "Talkie, remind me to buy milk."
    - Talkie detects wake word -> records "remind me to buy milk" -> Workflow "Extract Tasks" -> Reminders.app.

2.  **Meeting Scribe**:
    - User toggles "Meeting Mode".
    - Talkie VAD records chunks of speech.
    - Diarization (who is speaking) becomes critical here.
    - *Challenge*: Distinguishing user vs. others.

## Privacy & Trust
- **Visual Indicators**: **Must** have a clear "Microphone On" indicator (system does this, but app should too).
- **Local-Only**: Emphasize that wake-word detection happens on-device.
- **Retention**: Configurable "Forget buffer immediately" settings.

## Research Questions
- **Wake Word Model**: Is there a good Swift-native port of OpenWakeWord or Porcupine (free tier)?
- **Energy Impact**: What is the CPU % of continuous audio analysis on M-series chips?
- **False Positives**: How to minimize accidental recordings?
