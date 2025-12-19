# Talkie Onboarding Documentation

> Spec for porting TalkieLive's delightful onboarding to Talkie's superior architecture

## Quick Links

- **[Summary](SUMMARY.md)** - Quick reference guide
- **[Screen 1: Welcome](Screen1_Welcome.md)** - Animated pill demo
- **[Screen 2: Live Mode Choice](Screen2_LiveChoice.md)** - Core vs Core+Live (NEW)
- **[Screen 3: Permissions](Screen3_Permissions.md)** - Conditional permissions
- **[Screen 4: Model Install](Screen4_ModelInstall.md)** - Non-blocking download
- **[Screen 5: Status Check](Screen5_StatusCheck.md)** - Background progress (NEW)
- **[Screen 6: LLM Config](Screen6_LLMConfig.md)** - Optional API key
- **[Screen 7: Complete](Screen7_Complete.md)** - Interactive demo + celebration

---

## Core Principle: Work Without Live, Enable Anytime

**Talkie MUST work perfectly without Live mode enabled**

- **Default**: Core mode (just works, no decision needed)
- **Live mode**: Optional enhancement, can be enabled:
  - During onboarding (subtle opt-in)
  - Post-onboarding in Settings (retroactive)
  - As an upsell/paid feature

**Don't force a big decision** - users shouldn't feel pressure to choose during onboarding

---

## Onboarding Flow (Unified)

**Flow**: Welcome → Permissions (adaptive) → Model Install → Status → LLM Config → Complete

1. **Welcome** - Show value (same for all users)
2. **Permissions** - Request only what's needed (mic by default, more if Live enabled)
3. **Model Install** - Choose AI model (same for all)
4. **Status Check** - Verify setup (adaptive based on what's enabled)
5. **LLM Config** - Optional API key (same for all)
6. **Complete** - Tips + optional Live promo

**Live mode toggle**: Small checkbox during onboarding (Permissions or Complete screen)
- Label: "Enable Live features? (Global hotkey, auto-paste)"
- Subtext: "You can enable this anytime in Settings"
- Default: OFF (Core mode)

---

## Key Principles

1. **Port, Don't Rebuild** - Use existing Live animations verbatim
2. **User Choice** - Let users choose their adventure (Core vs Live)
3. **Value-Focused** - Explain what permissions unlock, not how they work
4. **Non-Blocking** - Model downloads in background, user continues
5. **Invisible Services** - TalkieLive and TalkieEngine auto-launch transparently
6. **Security First** - Emphasize Apple Keychain encryption for API keys

---

## Screen Overview

| # | Screen | Core | Core+Live | Key Element |
|---|--------|------|-----------|-------------|
| 1 | Welcome | ✅ | ✅ | Pill animation (port from Live) |
| 2 | Live Choice | ✅ | ✅ | NEW: Choose mode card |
| 3 | Permissions | Mic only | All 3 | Conditional display |
| 4 | Model Install | ✅ | ✅ | Non-blocking download |
| 5 | Status Check | Engine only | Engine + Live | Port from Live |
| 6 | LLM Config | ✅ | ✅ | Apple Keychain emphasis |
| 7 | Complete | Tips only | + Interactive demo | Celebration (Live mode) |

---

## Services (Invisible)

**No onboarding step for services** - they auto-launch transparently:

- **TalkieEngine** (both modes)
  - Launches: On first transcription
  - Purpose: AI model inference

- **TalkieLive** (Live mode only)
  - Launches: When user presses ⌥⌘L first time
  - Purpose: Global hotkey listener, auto-paste

---

## Implementation Files

```
macOS/Talkie/Views/Onboarding/
├── OnboardingCoordinator.swift       [MODIFY] Add enableLiveMode state
├── OnboardingView.swift              [MODIFY] Add Live choice step
├── WelcomeView.swift                 [MODIFY] Port pill animation
├── LiveModeChoiceView.swift          [CREATE] NEW screen
├── PermissionsSetupView.swift        [MODIFY] Conditional permissions
├── ModelInstallView.swift            [MODIFY] Real download + non-blocking
├── StatusCheckView.swift             [CREATE] NEW screen (port from Live)
├── LLMConfigView.swift               [MODIFY] Apple Keychain messaging
├── CompleteView.swift                [MODIFY] Port interactive demo
└── OnboardingUI.swift                [KEEP] Shared components
```

---

## Status: Draft

This spec is being finalized. Each screen document contains:
- 📺 **Screenwriter View** - What the user sees
- 🎯 **Product Manager View** - Why it exists, user goals, success metrics
- 🔧 **Engineer View** - How to build it, files to port, implementation details

---

**Last Updated**: 2024-12-18
