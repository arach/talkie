# TLK-014 — iOS Keyboard UX

**Status**: Draft
**Owner**: TBD

## Summary

TalkieKeys is a custom iOS keyboard that provides voice dictation within any app. This spec catalogs the end-to-end user experience today, identifies the gaps between current behavior and a cohesive flow, and proposes prioritized improvements.

The primary problems are discovery (users don't know the keyboard exists), setup friction (Full Access permission, manual System Settings navigation), and unclear activation states (gray vs green LED).

## Current state

### Components inventory

| Component | Location | Purpose |
|-----------|----------|---------|
| **KeyboardModeToggle** | VoiceMemoListView toolbar | Enable/disable keyboard mode |
| **KeyboardPlaygroundView** | Long-press toggle | In-app testing environment |
| **KeyboardActivationView** | Deep link handler | Activation flow screen |
| **DictationView** | Full-screen | Recording UI (legacy) |
| **MinimalDictationOverlay** | Invisible overlay | Background recording indicator |
| **HeadlessDictationService** | Background service | Continuous dictation without UI |
| **TalkieKeys extension** | System keyboard | The actual keyboard |

### Current discovery paths

1. **Toolbar toggle** — small toggle in top-right of memo list (easy to miss)
2. **Long-press toggle** — opens Playground (hidden affordance)
3. **Deep links** — `talkie://keyboard/activate` (requires knowing URL)

## User journeys

### First-time user: "I want to dictate in any app"

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

### Returning user: "I want to dictate quickly"

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

## Gaps & opportunities

### 1. No first-run keyboard onboarding

**Gap**: users don't know the keyboard exists or how to set it up.

**Proposal**: add a keyboard onboarding flow — carousel page in main onboarding, or a standalone "Keyboard Setup" entry point from Settings, with step-by-step guide and "Open Settings" button. Explain Full Access permission clearly.

### 2. No feature discovery in main app

**Gap**: the keyboard feature is hidden behind a small toggle.

**Proposal**: discoverable entry points — keyboard card in main view for first-time users, "Try Keyboard" promotional banner (dismissible), Settings section with keyboard setup status.

### 3. No system settings integration

**Gap**: users must manually navigate Settings → Keyboards.

**Proposal**: "Open Keyboard Settings" button that deep links to Settings; show keyboard installation status in-app; detect if TalkieKeys is installed and show appropriate UI.

### 4. Confusing activation states

**Gap**: users don't understand gray vs green LED.

**Proposal**: in-keyboard tooltip on first use ("Tap to connect to Talkie"); status text in LED bar ("Ready" / "Tap to activate" / "Recording"); animated pulse on green LED to indicate active connection.

### 5. No keyboard settings screen

**Gap**: users can't configure keyboard behavior from the Talkie app.

**Proposal**: dedicated Keyboard Settings screen — enable/disable keyboard mode, LED indicators on/off, haptic feedback on/off, auto-capitalize on/off, view setup instructions, "Open System Keyboard Settings" button.

### 6. Playground is hidden

**Gap**: KeyboardPlayground requires long-press to discover.

**Proposal**: add "Keyboard Playground" option in Settings, or convert toggle to segmented control with "Test" mode; show playground link in keyboard setup flow.

## Proposed information architecture

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

## Priority roadmap

### P0 — critical (MVP polish)

- [ ] **Keyboard Settings section** in app Settings — consolidate toggle + preferences; "Open Keyboard Settings" system link
- [ ] **Clear status text** in keyboard LED bar — "Ready" when connected; "Tap to connect" when idle; "Recording…" when active

### P1 — high (first-time experience)

- [ ] **Keyboard Setup Guide** screen — step-by-step with visuals; deep link to system Settings; accessible from Settings and onboarding
- [ ] **Discovery card** in main view — shows once for new users; "Set up voice dictation in any app"; dismiss / don't show again option

### P2 — medium (power users)

- [ ] **Keyboard Playground** accessible from Settings — add explicit menu item alongside long-press
- [ ] **Installation status detection** — check if TalkieKeys is in keyboard list; show "Not installed" vs "Installed" status

### P3 — nice-to-have

- [ ] **Onboarding carousel page** for keyboard
- [ ] **Tutorial overlay** in keyboard on first use
- [ ] **Usage analytics** (recordings via keyboard vs in-app)

## Technical considerations

### System settings deep link

iOS allows opening Settings app but not specific keyboard settings:

```swift
UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
```

For keyboard settings specifically, we can only guide users manually.

### Detecting keyboard installation

iOS doesn't provide an API to check if a specific keyboard extension is installed. We can only track our own state (has user enabled keyboard mode in Talkie).

### Background recording limitations

iOS keyboard extensions cannot access microphone directly. Current architecture (deep link to app → record → return) is the only viable approach. The "continuous mode" with warm recorder minimizes friction.

## Success metrics

1. **Setup completion rate** — % of users who complete keyboard setup
2. **Keyboard activation rate** — % of users who enable keyboard mode
3. **Keyboard usage** — recordings made via keyboard vs in-app
4. **Return rate** — users who use keyboard dictation more than once
5. **Error rate** — failed recordings / timeouts

## Next steps

1. Review this document and prioritize
2. Design mockups for Keyboard Settings section
3. Implement P0 items (settings section, status text)
4. User testing with first-time flow
5. Iterate based on feedback

---

*Last updated: 2025-01-29*
