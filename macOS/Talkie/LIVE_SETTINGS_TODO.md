# Live Settings - Missing Features from TalkieLive

## Visual Tools & Previews

### ✅ Already Implemented
- [x] Animated particle previews (WavyParticlesPreview)
- [x] Animated waveform previews (WaveformBarsPreview)
- [x] Hotkey recorder with live capture (HotkeyRecorderButton)

### 🔄 In Progress
- [ ] Audio device selector with live level monitoring
  - Dropdown of available microphones
  - Real-time audio level meter next to selected device
  - Visual feedback when mic is working/silent

### ⚠️ Missing from Original Implementation

#### 1. **Overlay Position Preview**
- **What it was**: Small visual preview showing where overlay appears on screen
- **Implementation**: Mini screen representation with overlay position indicator
- **File**: Should be in `OverlayStylePreviews.swift`

#### 2. **Pill Position Preview**
- **What it was**: Visual representation of pill widget placement
- **Implementation**: Mini screen with floating pill at selected position
- **File**: Should be in `OverlayStylePreviews.swift`

#### 3. **Sound Preview Buttons**
- **What it was**: Play button next to each sound dropdown to test the sound
- **Implementation**: Small speaker icon that plays the selected TalkieSound
- **File**: New component `SoundPreviewButton.swift`

#### 4. **Transcription Engine Comparison**
- **What it was**: Table comparing Parakeet models (speed, accuracy, size)
- **Implementation**: Grid showing model specs with download status
- **File**: Should be in transcription settings section

#### 5. **Live Hotkey Conflict Detection**
- **What it was**: Warning when hotkey conflicts with system shortcuts
- **Implementation**: Check against common macOS shortcuts, show warning badge
- **Enhancement to**: `HotkeyRecorder.swift`

#### 6. **Context Capture Privacy Controls**
- **What it was**: Clear explanation of what context is captured + opt-in
- **Implementation**: Toggle with detailed privacy explanation
- **File**: Should be in permissions settings

#### 7. **Storage Usage Display**
- **What it was**: Shows disk space used by recordings with cleanup button
- **Implementation**: Size calculation + "Clean Up Old Recordings" button
- **File**: Should be in storage settings

#### 8. **Microphone Level Meter**
- **What it was**: Real-time audio visualization when selecting microphone
- **Implementation**: Animated bars showing current input level
- **File**: New component `AudioLevelMeter.swift`

#### 9. **Accessibility Permission Helper**
- **What it was**: "Grant Permission" button that opens System Settings to correct pane
- **Implementation**: DeepLink to System Settings > Privacy & Security > Accessibility
- **File**: Should be in permissions settings

#### 10. **PTT vs Toggle Mode Explanation**
- **What it was**: Visual diagram showing difference between modes
- **Implementation**: Two-column comparison with icons
- **File**: Should be in shortcuts settings

## Component Architecture

### Suggested File Structure
```
Views/Live/Components/
├── OverlayStylePreviews.swift ✅ (exists, needs position previews added)
├── HotkeyRecorder.swift ✅ (exists, needs conflict detection)
├── AudioDeviceSelector.swift 🔄 (in progress)
├── AudioLevelMeter.swift ❌ (missing)
├── SoundPreviewButton.swift ❌ (missing)
├── PositionPreviews.swift ❌ (missing)
├── ModelComparisonTable.swift ❌ (missing)
└── PermissionHelpers.swift ❌ (missing)
```

## Instrumentation Requirements

All components should include:
- `os.Logger` for user interactions
- Performance metrics for animations (60fps target)
- Error logging for permission failures
- User preference change logging

## Priority Order

1. **HIGH** - Audio device selector with level meter (core functionality)
2. **HIGH** - Sound preview buttons (immediate user feedback)
3. **MEDIUM** - Position previews (helpful visualization)
4. **MEDIUM** - Permission helpers (reduce support burden)
5. **LOW** - Model comparison table (nice to have)
6. **LOW** - Hotkey conflict detection (edge case)
