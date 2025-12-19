# Talkie Onboarding - Quick Reference

> **Full spec**: See `ONBOARDING_SPEC.md` for detailed implementation details

## Flow Overview

**User chooses mode**: Core (transcription only) OR Core + Live (transcription + global hotkeys)

### Core Mode Flow
1. **Welcome** - Animated pill demo
2. **Permissions** - Microphone only
3. **Model Install** - Choose Parakeet or Whisper (non-blocking download)
4. **Status Check** - "Setting things up..." while model downloads
5. **LLM Config** - Optional OpenAI/Anthropic API key
6. **Complete** - Quick tips, get started

### Core + Live Mode Flow
1. **Welcome** - Animated pill demo (same)
2. **Live Mode Choice** - NEW: "Enable Live features?" card
3. **Permissions** - Microphone + Accessibility + Screen Recording (optional)
4. **Model Install** - Choose Parakeet or Whisper (non-blocking download)
5. **Status Check** - "Setting things up..." while model downloads + TalkieLive launches
6. **LLM Config** - Optional OpenAI/Anthropic API key (same)
7. **Complete** - Interactive pill demo + celebration on first recording

---

## Key Principles

### 1. Port, Don't Rebuild
- **Screen 1 (Welcome)**: Copy `PillDemoAnimation` from Live verbatim
- **Screen 7 (Complete)**: Copy `OnboardingPillDemo` + `CelebrationView` from Live verbatim
- Don't reinvent animations - use what works

### 2. Value-Focused Permissions
- **Microphone**: "Capture audio for transcriptions"
- **Accessibility**: "Paste in place to accelerate your actions"
- **Screen Recording**: "Record screen to capture context"

### 3. Conditional Display
- Only show permissions/features relevant to user's choice
- Core mode = simpler, faster onboarding
- Core + Live mode = full feature set

### 4. Apple Keychain Security
- Emphasize "Protected by Apple Keychain encryption" in LLM config
- Make security messaging prominent and trustworthy

### 5. Non-Blocking Downloads
- Model download happens in background
- User can proceed to Status screen while downloading
- Show progress: "Setting things up... Installing AI model..."

---

## Screen Summaries

### Screen 1: Welcome
**Purpose**: Show value proposition through animation
**Key Element**: 7-phase pill demo (port from Live)
**Copy Update**: Change feature columns to Talkie messaging

### Screen 2: Live Mode Choice (Core + Live only)
**Purpose**: Let user choose to enable Live features
**Options**:
- "Core Mode" - Just transcription & organization
- "Core + Live Mode" - Add global hotkeys & auto-paste
**Default**: Core mode (simpler choice for most users)

### Screen 3: Permissions
**Conditional**:
- Core: Microphone only
- Core + Live: Microphone + Accessibility (required), Screen Recording (optional)
**Key**: Value-focused descriptions, conditional display based on choice

### Screen 4: Model Install
**Purpose**: Choose AI model (Parakeet or Whisper)
**Features**: Real download with progress, cancel option, logos, "Learn more" links
**Non-blocking**: Can proceed to next screen while downloading

### Screen 5: Status Check
**Purpose**: Show progress while things happen in background
**Displays**:
- Model download progress (if not complete)
- TalkieLive launch status (Live mode only)
- Engine connection status
**Port from Live**: Use Live's status check screen almost 1:1

### Screen 6: LLM Config
**Purpose**: Optional AI provider setup
**Security**: Prominent "Protected by Apple Keychain encryption" messaging
**Providers**: OpenAI or Anthropic
**Validation**: Format check + connection test

### Screen 7: Complete
**Two-column layout**:
- Left: Keyboard shortcut display (⌥⌘L)
- Right: Interactive pill demo (port from Live)
**Live mode only**: Show celebration with confetti on first recording
**Core mode**: Just show keyboard shortcut + quick tips

---

## Services (Invisible)

Services auto-launch transparently - no user-facing setup:
- **TalkieEngine**: Launches on first transcription
- **TalkieLive** (Live mode only): Launches when user presses hotkey

---

## Implementation Priorities

### Critical (Must Have)
1. Live mode choice screen (NEW)
2. Conditional permissions based on choice
3. Non-blocking model download
4. Status screen with progress indicators
5. Apple Keychain encryption messaging

### High Priority (Port from Live)
1. Welcome screen pill animation
2. Complete screen interactive demo
3. Celebration on first recording (Live mode)
4. Model card enhancements (logos, hover states)

### Medium Priority (Enhancements)
1. Permission row visual polish
2. Real download progress (not simulated)
3. LLM API key validation
4. Status screen polish

---

## Files to Modify

1. **OnboardingCoordinator.swift** - Add Live mode choice state
2. **WelcomeView.swift** - Port pill animation
3. **LiveModeChoiceView.swift** - NEW file
4. **PermissionsSetupView.swift** - Conditional display + value descriptions
5. **ModelInstallView.swift** - Real download + non-blocking
6. **StatusCheckView.swift** - NEW file (port from Live)
7. **LLMConfigView.swift** - Apple Keychain messaging
8. **CompleteView.swift** - Port interactive demo

---

## Testing Checklist

- [ ] Core mode flow works without Live
- [ ] Core + Live mode shows all features
- [ ] Permissions adapt based on choice
- [ ] Model download non-blocking
- [ ] Status screen shows accurate progress
- [ ] Services auto-launch invisibly
- [ ] Apple Keychain stores API keys securely
- [ ] Celebration appears on first recording (Live mode)
- [ ] All animations port correctly from Live

---

## Quick Commands

**Check if Live mode chosen**:
```swift
@Published var enableLiveMode: Bool = false
```

**Determine permissions to show**:
```swift
var permissionsToShow: [PermissionType] {
    enableLiveMode ? [.microphone, .accessibility, .screenRecording] : [.microphone]
}
```

**Launch services based on mode**:
```swift
if enableLiveMode {
    // TalkieLive will auto-launch on first hotkey press
}
// TalkieEngine always auto-launches on first transcription
```

---

**For full implementation details, see**: `ONBOARDING_SPEC.md`
