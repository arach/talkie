# Screen 1: Welcome

> First impression - show value proposition through animation

## What User Sees

**Layout**: Grid background → Animated pill demo → Feature columns → Continue button

**Title**: "Welcome to Talkie"

**Animated Demo** (center):
- 7-phase pill animation showing recording workflow
- Cursor approaches, clicks, pill records, processes, completes
- Waveform visualization during recording
- Keyboard shortcut (⌥⌘L) fades in/out
- Click ripple effects
- Loops continuously

**Feature Columns** (below demo):
1. **Record** - "Press hotkey in any app"
2. **Auto-paste** - "Text appears instantly"
3. **On-device** - "Private, fast, no internet"

**Buttons**: Continue (pulsing green), Skip Onboarding (subtle)

---

## Why This Exists

**Purpose**: Immediately demonstrate value through engaging animation rather than static text. This is the first impression - it must be memorable.

**User Goals**:
- Understand what Talkie does in <10 seconds
- See the actual workflow (not just read about it)
- Learn the keyboard shortcut (⌥⌘L)
- Feel excited to try it

**Success Criteria**:
- >80% watch full animation loop before continuing
- User understands hotkey concept
- Feels confident about next steps

---

## How to Build

### ⚠️ CRITICAL: DO NOT REBUILD - PORT DIRECTLY

The animation in TalkieLive is perfect. **Copy and integrate**, don't rebuild.

**Files to Port from Live**:
- `PillDemoAnimation.swift` - Copy entire file
- `WaveformDemoView.swift` - Copy entire component
- `KeyboardShortcutView.swift` - Copy entire component
- `ClickRippleEffect.swift` - Copy helper
- Any supporting types these depend on

**Target**: `/Users/arach/dev/talkie/macOS/Talkie/Views/Onboarding/WelcomeView.swift`

**Integration**:
```swift
OnboardingStepLayout {
    VStack(spacing: 40) {
        // DROP IN THE EXISTING COMPONENT
        PillDemoAnimation()  // ← From Live
            .frame(height: 200)

        // Update copy for feature columns
        HStack(spacing: 60) {
            FeatureColumn(icon: "mic.fill", title: "Press hotkey in any app", ...)
            FeatureColumn(icon: "text.cursor", title: "Text appears instantly", ...)
            FeatureColumn(icon: "cpu", title: "Private, fast, no internet", ...)
        }
    }
}
```

**What NOT to Do**:
- ❌ Don't rewrite the animation
- ❌ Don't change timing or phases
- ❌ Don't "improve" the curves

**What TO Do**:
- ✅ Copy verbatim from Live
- ✅ Update only feature column text
- ✅ Test that it loops perfectly

**Reference**: TalkieLive's OnboardingView.swift (lines ~300-800)

---

## Testing

- [ ] Animation loops smoothly (no stutter)
- [ ] All 7 phases transition cleanly
- [ ] Cursor movement natural
- [ ] Ripple effects appear on clicks
- [ ] Keys fade in/out at correct times
- [ ] Waveform animates only during recording
- [ ] Works in light/dark mode
- [ ] No memory leaks after 10+ loops
