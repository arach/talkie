iOS Keyboard UX Design

## Executive Summary

TalkieKeys is a custom iOS keyboard that provides voice dictation within any app. This document outlines the end-to-end user experience, identifies gaps, and proposes improvements to create a cohesive, delightful experience.

---

## Current State

### Components Inventory

| Component | Location | Purpose |
|-----------|----------|---------|
| **KeyboardModeToggle** | VoiceMemoListView toolbar | Enable/disable keyboard mode |
| **KeyboardPlaygroundView** | Long-press toggle | In-app testing environment |
| **KeyboardActivationView** | Deep link handler | Activation flow screen |
| **DictationView** | Full-screen | Recording UI (legacy) |
| **MinimalDictationOverlay** | Invisible overlay | Background recording indicator |
| **HeadlessDictationService** | Background service | Continuous dictation without UI |
| **TalkieKeys extension** | System keyboard | The actual keyboard |

### Current Discovery Paths

1. **Toolbar toggle** - Small toggle in top-right of memo list (easy to miss)
2. **Long-press toggle** - Opens Playground (hidden affordance)
3. **Deep links** - `talkie://keyboard/activate` (requires knowing URL)

---

## User Journeys

### First-Time User: "I want to dictate in any app"

**Current experience:**

```
1. User hears about TalkieKeys somehow
2. Opens Talkie app
3. Notices small toggle in corner (maybe)
4. Taps toggle → Nothing visible happens
5. Goes to Settings → Keyboards → Add New Keyboard → TalkieKeys
6. Enables "Full Access" (scary permission)
7. Opens any app, switches keyboard, taps record
8. Talkie opens, user is confused
9. Eventually figures out the flow
```

**Problems:**
- No in-app discovery of the keyboard feature
- No guidance on system settings setup
- "Full Access" permission is scary without explanation
- First recording requires app switch (confusing)
- No success confirmation

### Returning User: "I want to dictate quickly"

**Current experience (after setup):**

```
1. Open any app (Safari, Notes, etc.)
2. Switch to TalkieKeys keyboard
3. Tap record → LED green? Start recording
4. LED gray? Tap LED → Opens Talkie → Toggle on → Back to app
5. Try again
```

**Problems:**
- Unclear when keyboard mode is active
- Requires context switching to activate
- State isn't persistent across app restarts

---

## Gaps & Opportunities

### 1. **No First-Run Keyboard Onboarding**

**Gap:** Users don't know the keyboard exists or how to set it up.

**Proposal:** Add keyboard onboarding flow:
- Carousel page in main onboarding highlighting keyboard
- OR standalone "Keyboard Setup" entry point from Settings
- Step-by-step guide with "Open Settings" button
- Explain Full Access permission clearly

### 2. **No Feature Discovery in Main App**

**Gap:** The keyboard feature is hidden behind a small toggle.

**Proposal:** Add discoverable entry points:
- **Keyboard card** in main view (first-time users)
- **"Try Keyboard"** promotional banner (dismissible)
- **Settings section** with keyboard setup status

### 3. **No System Settings Integration**

**Gap:** Users must manually navigate Settings → Keyboards.

**Proposal:**
- "Open Keyboard Settings" button that deep links to Settings
- Show keyboard installation status in-app
- Detect if TalkieKeys is installed and show appropriate UI

### 4. **Confusing Activation States**

**Gap:** Users don't understand gray vs green LED.

**Proposal:**
- **In-keyboard tooltip** on first use: "Tap to connect to Talkie"
- **Status text** in LED bar: "Ready" / "Tap to activate" / "Recording"
- **Animated pulse** on green LED to indicate active connection

### 5. **No Keyboard Settings Screen**

**Gap:** Users can't configure keyboard behavior from Talkie app.

**Proposal:** Dedicated Keyboard Settings screen:
- Enable/disable keyboard mode (current toggle)
- LED indicators on/off
- Haptic feedback on/off
- Auto-capitalize on/off
- View setup instructions
- "Open System Keyboard Settings" button

### 6. **Playground is Hidden**

**Gap:** KeyboardPlayground requires long-press to discover.

**Proposal:**
- Add "Keyboard Playground" option in Settings
- Or: Convert toggle to segmented control with "Test" mode
- Show playground link in keyboard setup flow

---

## Proposed Information Architecture

```
Talkie App
├── Main View (VoiceMemoListView)
│   ├── [NEW] Keyboard promo card (first-time)
│   └── Toolbar
│       └── Keyboard toggle (existing)
│
├── Settings
│   ├── ...existing settings...
│   └── [NEW] Keyboard
│       ├── Enable Keyboard Mode (toggle)
│       ├── Setup Instructions (expand/collapse)
│       │   ├── Step 1: Add keyboard
│       │   ├── Step 2: Enable Full Access
│       │   └── [Open Settings] button
│       ├── Keyboard Playground (link)
│       └── Preferences
│           ├── LED Indicators
│           ├── Haptic Feedback
│           └── Auto-Capitalize
│
└── [NEW] Keyboard Setup Flow (deep-linkable)
    ├── Welcome screen
    ├── Permission explanation
    ├── Setup steps with system link
    └── Success / Test it out
```

---

## Priority Roadmap

### P0: Critical (MVP Polish)

- [ ] **Keyboard Settings section** in app Settings
  - Consolidate toggle + preferences
  - "Open Keyboard Settings" system link

- [ ] **Clear status text** in keyboard LED bar
  - "Ready" when connected
  - "Tap to connect" when idle
  - "Recording..." when active

### P1: High (First-Time Experience)

- [ ] **Keyboard Setup Guide** screen
  - Step-by-step with visuals
  - Deep link to system Settings
  - Accessible from Settings and onboarding

- [ ] **Discovery card** in main view
  - Shows once for new users
  - "Set up voice dictation in any app"
  - Dismiss/don't show again option

### P2: Medium (Power Users)

- [ ] **Keyboard Playground** accessible from Settings
  - Currently long-press only
  - Add explicit menu item

- [ ] **Installation status detection**
  - Check if TalkieKeys is in keyboard list
  - Show "Not installed" vs "Installed" status

### P3: Nice-to-Have

- [ ] **Onboarding carousel page** for keyboard
- [ ] **Tutorial overlay** in keyboard on first use
- [ ] **Usage analytics** (recordings via keyboard vs in-app)

---

## Technical Considerations

### System Settings Deep Link

iOS allows opening Settings app but not specific keyboard settings:
```swift
UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
```

For keyboard settings specifically, we can only guide users manually.

### Detecting Keyboard Installation

Unfortunately, iOS doesn't provide an API to check if a specific keyboard extension is installed. We can only track our own state (has user enabled keyboard mode in Talkie).

### Background Recording Limitations

iOS keyboard extensions cannot access microphone directly. Current architecture (deep link to app → record → return) is the only viable approach. The "continuous mode" with warm recorder minimizes friction.

---

## Success Metrics

1. **Setup completion rate** - % of users who complete keyboard setup
2. **Keyboard activation rate** - % of users who enable keyboard mode
3. **Keyboard usage** - Recordings made via keyboard vs in-app
4. **Return rate** - Users who use keyboard dictation more than once
5. **Error rate** - Failed recordings / timeouts

---

## Next Steps

1. Review this document and prioritize
2. Design mockups for Keyboard Settings section
3. Implement P0 items (settings section, status text)
4. User testing with first-time flow
5. Iterate based on feedback

---

*Last updated: 2025-01-29*
