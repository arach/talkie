# Analysis: Audio Capture Failure with AirPods

## Issue Description
**Symptom**: Audio capture fails with `com.apple.coreaudio.avfaudio error -10868` (`kAudioOutputUnitStartFailed`) when AirPods are connected, even though the intended input device (plugged-in microphone) has not changed.
**Observation**: User suspects a system-wide sample rate drop (down-sampling to 24kHz) due to Bluetooth bandwidth constraints (HFP/A2DP profiles).

## Root Cause Analysis

### 1. The Error Code (`-10868`)
`kAudioOutputUnitStartFailed` indicates that the underlying Core Audio `AudioUnit` could not be started. In the context of `AVAudioEngine`, this almost always signifies a **Format Mismatch** between the Engine's configured format and the Hardware's actual capabilities.

### 2. The "AirPods Effect"
When AirPods connect and the microphone is activated (or the system prepares for telephony), macOS often switches the Bluetooth profile to **HFP (Hands-Free Profile)**.
- **Impact**: This forces the audio bandwidth to 16kHz (mSBC) or 24kHz (AAC-ELD).
- **System Behavior**: To keep audio synchronized, macOS may attempt to lower the sample rate of the **entire Audio Engine** (Input + Output) to match this lowest common denominator (24kHz).

### 3. The Conflict
Your code correctly identifies and sets the input device to the plugged-in microphone:
```swift
// AudioCapture.swift
AudioUnitSetProperty(..., kAudioOutputUnitProperty_CurrentDevice, ..., &deviceID, ...)
```

However, `AVAudioEngine` on macOS creates a "System" graph that typically links Input and Output.
1.  **Output Side**: Connected to AirPods (System Default). Forces Engine to **24kHz**.
2.  **Input Side**: Connected to Plugged-in Mic (via your code).
3.  **The Crash**: The Plugged-in Mic hardware likely **does not support 24kHz natively** (most USB/XLR interfaces support 44.1kHz or 48kHz only).
    - The Engine attempts to initialize the Input Node Audio Unit at the "Engine Rate" (24kHz).
    - The Hardware rejects this format.
    - `AudioOutputUnitStart` fails with `-10868`.

## Current Implementation Gaps (`AudioCapture.swift`)

The current implementation relies on `AVAudioEngine`'s default format negotiation, which is failing in this mixed-rate scenario.

```swift
// AudioCapture.swift
let inputNode = newEngine.inputNode
// ...
// Implicitly accepts engine's sample rate (driven by Output device)
inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil)
try newEngine.start() // Fails here
```

By passing `format: nil` to `installTap`, you are accepting the node's output format. If the Engine has snapped to 24kHz (due to AirPods), the Input Node tries to run at 24kHz.

## Recommended Resolution Strategy

To fix this, we must **decouple** the Input Node's hardware format from the Engine's operating format.

### 1. Enforce Hardware Format
Instead of letting the Engine dictate the rate to the Input Node, query the device's actual native format (e.g., 48kHz) and force the `AVAudioEngine` to mix at that rate, or insert a converter.

### 2. "Voice Processing" Mode (Potential Fix)
Enabling Voice Processing often handles Sample Rate Conversion (SRC) automatically at the system level.
```swift
try? inputNode.setVoiceProcessingEnabled(true)
```

### 3. Manual Format Configuration (Robust Fix)
Explicitly configure the Audio Unit to run at its native rate (48kHz) while letting the Engine handle the conversion.

*This analysis confirms your suspicion: The AirPods are forcing a 24kHz constraints that your high-fidelity microphone cannot physically satisfy, causing the Audio Unit to fail startup.*
