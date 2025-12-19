# Screen 2: Live Mode Choice

> **NEW SCREEN** - Let users choose their adventure: Core or Core+Live

## What User Sees

**Layout**: Grid background → Icon → Two mode cards → Continue button

**Title**: "Choose Your Mode"

**Subtitle**: "You can always change this later in Settings"

**Icon**: Wand with stars (wand.and.stars) - 80x80, pulsing

**Mode Cards** (two options):

### Option 1: Core Mode (Default)
- **Icon**: Document with waveform (doc.text.fill)
- **Badge**: "RECOMMENDED" (green)
- **Title**: "Core Mode"
- **Tagline**: "Voice transcription & organization"
- **Features**:
  - ✓ Voice transcription with AI
  - ✓ Search and organize memos
  - ✓ AI summaries and workflows
  - ✓ Sync across devices
- **Best for**: "Most users"
- Selected state: Green border, checkmark

### Option 2: Core + Live Mode
- **Icon**: Waveform with cursor (waveform.and.mic)
- **Badge**: "POWER USERS" (purple)
- **Title**: "Core + Live Mode"
- **Tagline**: "Everything in Core, plus global hotkeys"
- **Features**:
  - ✓ Everything in Core mode
  - ✓ Global hotkey (⌥⌘L) works anywhere
  - ✓ Auto-paste transcribed text
  - ✓ Screen context capture
- **Best for**: "Power users who want maximum speed"
- Selected state: Purple border, checkmark

**Buttons**: Continue (enabled when option selected)

**Helper text**: "You can enable or disable Live features anytime in Settings"

---

## Why This Exists

**Purpose**: Give users agency over their experience. Live mode is powerful but requires additional permissions. Let users opt-in rather than overwhelming everyone with features they may not need.

**User Goals**:
- Understand the difference between modes
- Make an informed choice based on their needs
- Feel in control of their experience
- Not feel overwhelmed by features they don't want

**Success Criteria**:
- >70% choose Core mode (simpler default)
- >90% understand difference between modes
- <5% confused about which to pick
- 0% feel forced into Live mode

**Key Messages**:
1. **Choice**: You decide what's right for you
2. **Flexibility**: Can change later in Settings
3. **Recommendation**: Core mode for most users (green badge)
4. **Power**: Live mode for those who want maximum speed

**User Personas**:

*Casual user (70%)*:
- Sees "RECOMMENDED" badge on Core mode
- Reads "Most users" label
- Clicks Core mode, feels confident
- Moves to next step

*Power user (30%)*:
- Reads both cards
- Sees "Global hotkey works anywhere"
- Understands value of auto-paste
- Chooses Live mode deliberately

---

## How to Build

**Target**: `/Users/arach/dev/talkie/macOS/Talkie/Views/Onboarding/LiveModeChoiceView.swift` (NEW FILE)

**State Management** (in OnboardingCoordinator):
```swift
@Published var enableLiveMode: Bool = false  // Default: Core mode
```

**Mode Card Component**:
```swift
struct ModeCard: View {
    let mode: ModeInfo
    @Binding var selectedMode: Bool
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: mode.icon)
                    .font(.system(size: 32))
                    .foregroundColor(mode.color)
                Spacer()
                Text(mode.badge)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(mode.badgeColor.opacity(0.2))
                    .foregroundColor(mode.badgeColor)
                    .cornerRadius(4)
            }

            Text(mode.title)
                .font(.title2)
                .bold()

            Text(mode.tagline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(mode.features, id: \.self) { feature in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text(feature)
                            .font(.system(size: 13))
                    }
                }
            }

            Spacer()

            Text("Best for: \(mode.bestFor)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 280)
        .background(isHovered ? Color(hex: "#1F1F1F") : Color(hex: "#151515"))
        .border(selectedMode ? mode.color : Color(hex: "#2A2A2A"), width: 2)
        .cornerRadius(12)
        .onHover { isHovered = $0 }
        .onTapGesture {
            selectedMode = true
        }
    }
}
```

**Mode Definitions**:
```swift
struct ModeInfo {
    let id: String
    let icon: String
    let badge: String
    let badgeColor: Color
    let title: String
    let tagline: String
    let features: [String]
    let bestFor: String
    let color: Color
}

static let coreMode = ModeInfo(
    id: "core",
    icon: "doc.text.fill",
    badge: "RECOMMENDED",
    badgeColor: .green,
    title: "Core Mode",
    tagline: "Voice transcription & organization",
    features: [
        "Voice transcription with AI",
        "Search and organize memos",
        "AI summaries and workflows",
        "Sync across devices"
    ],
    bestFor: "Most users",
    color: .green
)

static let liveMode = ModeInfo(
    id: "live",
    icon: "waveform.and.mic",
    badge: "POWER USERS",
    badgeColor: .purple,
    title: "Core + Live Mode",
    tagline: "Everything in Core, plus global hotkeys",
    features: [
        "Everything in Core mode",
        "Global hotkey (⌥⌘L) works anywhere",
        "Auto-paste transcribed text",
        "Screen context capture"
    ],
    bestFor: "Power users who want maximum speed",
    color: .purple
)
```

**Layout**:
```swift
OnboardingStepLayout {
    VStack(spacing: 40) {
        // Icon
        Image(systemName: "wand.and.stars")
            .font(.system(size: 80))
            .foregroundColor(.purple)
            .symbolEffect(.pulse)

        // Mode cards
        HStack(spacing: 24) {
            ModeCard(
                mode: .coreMode,
                selectedMode: Binding(
                    get: { !enableLiveMode },
                    set: { if $0 { enableLiveMode = false } }
                )
            )

            ModeCard(
                mode: .liveMode,
                selectedMode: Binding(
                    get: { enableLiveMode },
                    set: { if $0 { enableLiveMode = true } }
                )
            )
        }

        // Helper text
        Text("You can enable or disable Live features anytime in Settings")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}
```

**Validation**:
```swift
var canContinue: Bool {
    // Always true - one of the two cards is always selected (default: Core)
    true
}
```

---

## Impact on Later Screens

**Permissions** (Screen 3):
```swift
var permissionsToShow: [PermissionType] {
    enableLiveMode ? [.microphone, .accessibility, .screenRecording] : [.microphone]
}
```

**Status Check** (Screen 5):
```swift
var servicesToCheck: [ServiceType] {
    enableLiveMode ? [.engine, .live] : [.engine]
}
```

**Complete** (Screen 7):
```swift
// Show interactive pill demo only if Live mode enabled
if enableLiveMode {
    OnboardingPillDemo()  // Interactive demo
    // Listen for first recording to show celebration
} else {
    // Just show keyboard shortcut tips
}
```

---

## Testing

- [ ] Core mode selected by default
- [ ] Only one mode can be selected at a time
- [ ] Cards respond to hover
- [ ] Click selects mode (border changes)
- [ ] Continue button always enabled
- [ ] Choice persists across app restarts
- [ ] Later screens adapt based on choice
- [ ] Can change mode in Settings post-onboarding
