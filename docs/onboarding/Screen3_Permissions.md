# Screen 3: Permissions

> Request necessary permissions with value-focused messaging

## What User Sees

**Layout**: Grid background → Pulsing shield icon → Permission rows → Continue button

**Title**: "Grant Permissions"

**Subtitle**: "Let's enable the features you chose"

**Icon**: Shield with checkmark - pulsing animation with rings

**Permission Rows** (conditional based on mode choice):

### Core Mode: 1 Permission

1. **Microphone** (Required)
   - Icon: Mic icon (mic.fill) - red circle
   - Title: "Microphone Access"
   - Description: **"Capture audio for transcriptions"**
   - Button: "Grant Access" → System dialog
   - Badge: "REQUIRED" (red)

### Core + Live Mode: 3 Permissions

1. **Microphone** (Required)
   - Same as above

2. **Accessibility** (Required)
   - Icon: Command key (command) - blue circle
   - Title: "Accessibility Access"
   - Description: **"Paste in place to accelerate your actions"**
   - Button: "Open Settings" → System Preferences
   - Badge: "REQUIRED" (red)

3. **Screen Recording** (Optional)
   - Icon: Display (display) - purple circle
   - Title: "Screen Recording"
   - Description: **"Record screen to capture context"**
   - Button: "Grant Access" → System dialog
   - Badge: "OPTIONAL" (gray)

**Helper Text**: "All processing happens on your Mac - your data never leaves your device"

**Buttons**:
- Continue (enabled when required permissions granted)
- Skip (shows warning if required permissions not granted)

---

## Why This Exists

**Purpose**: Transparently request permissions while explaining **value** (what you get) not **mechanism** (how it works). Adapt based on user's mode choice.

**Key Messages**:
1. **Value First**: Frame by what permissions unlock
   - "Capture audio" not "access microphone"
   - "Paste in place" not "enable accessibility"
   - "Record screen" not "capture display"
2. **Conditional**: Only show what's needed for chosen mode
3. **Privacy**: "All processing on your Mac"

**Success Criteria**:
- **Core Mode**: >95% grant microphone
- **Core + Live Mode**: >95% mic, >80% accessibility, >40% screen recording
- <5% abandon at this step

---

## How to Build

**Target**: `/Users/arach/dev/talkie/macOS/Talkie/Views/Onboarding/PermissionsSetupView.swift`

**Conditional Display**:
```swift
var permissionsToShow: [PermissionType] {
    OnboardingManager.shared.enableLiveMode
        ? [.microphone, .accessibility, .screenRecording]
        : [.microphone]
}
```

**Permission Descriptions** (value-focused):
```swift
enum PermissionType {
    case microphone
    case accessibility
    case screenRecording

    var description: String {
        switch self {
        case .microphone:
            return "Capture audio for transcriptions"
        case .accessibility:
            return "Paste in place to accelerate your actions"
        case .screenRecording:
            return "Record screen to capture context"
        }
    }

    var isRequired: Bool {
        switch self {
        case .microphone, .accessibility:
            return true  // accessibility required only if Live mode
        case .screenRecording:
            return false
        }
    }
}
```

**Accessibility Permission Polling**:
```swift
func startAccessibilityPolling() {
    accessibilityCheckTimer?.invalidate()
    accessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
        Task { @MainActor in
            self?.checkAccessibilityPermission()
            if self?.hasAccessibilityPermission == true {
                self?.stopAccessibilityPolling()
            }
        }
    }
}

// ⚠️ Add cleanup
deinit {
    stopAccessibilityPolling()
}
```

**Validation**:
```swift
var canContinue: Bool {
    if OnboardingManager.shared.enableLiveMode {
        // Live mode: require mic + accessibility
        return hasMicrophonePermission && hasAccessibilityPermission
    } else {
        // Core mode: require mic only
        return hasMicrophonePermission
    }
}
```

---

## Enhancements from Live

**Port from TalkieLive**:
- Pulsing shield icon with animated rings
- Checkmark bounce animation
- Color-coded permission icons

**Already in Talkie** (keep):
- Permission polling for accessibility
- State persistence across app restarts

**Add**:
- Conditional display based on mode
- Value-focused descriptions
- Better visual polish

---

## Testing

- [ ] Core mode: Shows mic only
- [ ] Live mode: Shows all 3 permissions
- [ ] Shield icon pulses continuously
- [ ] Checkmarks appear with bounce
- [ ] Accessibility polling detects grant within 1s
- [ ] Continue enabled only when required permissions granted
- [ ] Skip shows warning if required permissions missing
- [ ] Permission state persists across restarts
