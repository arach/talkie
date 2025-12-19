# Onboarding Implementation Plan

> Breaking implementation into manageable 2-screen subtasks with transition validation

## Implementation Strategy

Each subtask focuses on **2 screens at a time** to ensure:
1. Screen implementations are complete
2. Transitions between screens work smoothly
3. State management flows correctly
4. Visual consistency maintained

After all subtasks complete, **end-to-end validation** ensures the full flow works seamlessly.

---

## Pre-Implementation: Screen 2 Deprecation

**Status**: Screen2_LiveChoice.md is **OBSOLETE** based on user feedback.

**Why**: User specified that Live mode should be:
- A subtle checkbox/toggle (not a big choice screen)
- Default OFF
- Can be enabled during onboarding OR retroactively in Settings
- Potentially an upsell feature
- Talkie MUST work without Live mode enabled

**Action**: Remove Screen 2 from flow. Live mode toggle will be integrated into:
- **Option A**: Permissions screen (Screen 3) - checkbox at bottom
- **Option B**: Complete screen (Screen 7) - as optional promo
- **Recommended**: Both places (opt-in during Permissions, promo at Complete if not enabled)

**Updated Flow**:
1. Welcome
2. ~~Live Choice~~ ← REMOVED
3. Permissions (+ Live mode checkbox)
4. Model Install
5. Status Check
6. LLM Config
7. Complete

---

## Subtask Breakdown

### Subtask 1: Welcome + Permissions (with Live Toggle)
**Screens**: 1-2 in final flow
**Complexity**: Medium
**Key Focus**: Animation port + conditional permissions

**Files to Create/Modify**:
```
macOS/Talkie/Views/Onboarding/
├── WelcomeView.swift              [MODIFY]
│   └── Port pill animation from Live
├── PermissionsSetupView.swift     [MODIFY]
│   ├── Add Live mode toggle checkbox
│   ├── Conditional permission display
│   └── Value-focused descriptions
└── Components/
    ├── PillDemoAnimation.swift    [PORT from Live]
    ├── WaveformDemoView.swift     [PORT from Live]
    └── KeyboardShortcutView.swift [PORT from Live]
```

**State to Add** (OnboardingCoordinator):
```swift
@Published var enableLiveMode: Bool = false  // Default OFF

var permissionsToShow: [PermissionType] {
    enableLiveMode ? [.microphone, .accessibility, .screenRecording] : [.microphone]
}
```

**Transition Validation**:
- [ ] Welcome → Permissions transition smooth
- [ ] Live toggle on Permissions screen updates state
- [ ] Permission list adapts instantly when toggle changes
- [ ] Pill animation plays correctly on Welcome
- [ ] Continue button enables only when required permissions granted

---

### Subtask 2: Model Install + Status Check
**Screens**: 3-4 in final flow
**Complexity**: High
**Key Focus**: Non-blocking download + background status monitoring

**Files to Create/Modify**:
```
macOS/Talkie/Views/Onboarding/
├── ModelInstallView.swift         [MODIFY]
│   ├── Two-model choice cards
│   ├── Real download progress
│   └── Non-blocking Continue
├── StatusCheckView.swift          [CREATE]
│   ├── Port from Live's EngineWarmupStepView
│   ├── Conditional Live service check
│   └── Auto-advance logic
└── Managers/
    └── ModelDownloadManager.swift [CREATE/MODIFY]
        ├── Real URLSession downloads
        ├── Progress monitoring
        └── Background continuation
```

**State to Add**:
```swift
@Published var selectedModel: AIModel = .parakeet
@Published var modelDownloadProgress: Double = 0.0
@Published var isDownloading: Bool = false
@Published var isModelInstalled: Bool = false

// Status check states
@Published var checkStatuses: [StatusCheck: CheckStatus] = [:]
```

**Transition Validation**:
- [ ] Permissions → Model Install transition smooth
- [ ] Model selection starts download immediately
- [ ] Can click Continue before download completes
- [ ] Model Install → Status Check transition while download continues
- [ ] Status Check monitors ongoing download progress
- [ ] Status Check shows conditional Live service check (only if enabled)
- [ ] Auto-advances when all checks pass
- [ ] Download continues in background throughout

**Critical**: Fix fake model download simulation (code review todo #4)

---

### Subtask 3: LLM Config + Complete
**Screens**: 5-6 in final flow
**Complexity**: High
**Key Focus**: Keychain security + conditional celebration

**Files to Create/Modify**:
```
macOS/Talkie/Views/Onboarding/
├── LLMConfigView.swift            [MODIFY]
│   ├── Prominent Keychain security banner
│   ├── Three provider cards (Local/OpenAI/Anthropic)
│   └── Real-time validation
├── CompleteView.swift             [MODIFY]
│   ├── Conditional content (Core vs Live)
│   ├── Port interactive demo from Live
│   └── First recording detection
└── Components/
    ├── InteractivePillDemo.swift  [PORT from Live]
    ├── ConfettiManager.swift      [PORT from Live]
    └── KeychainSecurityBanner.swift [CREATE]
```

**State to Add**:
```swift
@Published var selectedProvider: LLMProvider = .localOnly
@Published var openAIKey: String = ""
@Published var anthropicKey: String = ""
@Published var keyValidationState: KeyValidationState = .idle

@Published var hasCompletedFirstRecording: Bool = false
```

**Services Integration**:
```swift
// Use KeychainManager (not UserDefaults!)
class KeychainManager {
    func saveAPIKey(_ key: String, for service: String) throws
    func getAPIKey(for service: String) -> String?
}
```

**Transition Validation**:
- [ ] Status Check → LLM Config transition smooth
- [ ] Keychain security banner displays prominently
- [ ] API key validation works for OpenAI/Anthropic formats
- [ ] Keys save to Keychain (NOT UserDefaults)
- [ ] LLM Config → Complete transition smooth
- [ ] Complete shows Core content if Live disabled
- [ ] Complete shows Live demo if Live enabled
- [ ] Interactive demo uses real mic input
- [ ] Confetti triggers on first recording (Live mode)
- [ ] "Get Started" completes onboarding and opens main app

**Critical**: Implement API key storage using KeychainManager (code review todo #3)

---

### Subtask 4: End-to-End Validation + Polish
**Scope**: Full flow testing + edge cases
**Complexity**: Medium
**Key Focus**: Smooth transitions, state persistence, error handling

**Validation Checklist**:

**Full Flow (Core Mode)**:
- [ ] Welcome → Permissions → Model Install → Status Check → LLM Config → Complete
- [ ] Only shows microphone permission
- [ ] Downloads model in background
- [ ] Status check doesn't include Live service
- [ ] Complete shows tips (not interactive demo)
- [ ] All transitions smooth (no flicker or lag)

**Full Flow (Live Mode)**:
- [ ] Welcome → Permissions (with Live enabled) → Model Install → Status Check → LLM Config → Complete
- [ ] Shows all 3 permissions (mic, accessibility, screen recording)
- [ ] Downloads model in background
- [ ] Status check includes Live service check
- [ ] Complete shows interactive demo
- [ ] First recording triggers celebration
- [ ] All transitions smooth

**State Persistence**:
- [ ] Can quit app mid-onboarding and resume at same screen
- [ ] Live mode choice persists
- [ ] Model selection persists
- [ ] Permission grants persist
- [ ] API keys persist in Keychain (not lost on restart)

**Error Handling**:
- [ ] Network error during model download shows retry
- [ ] Invalid API key shows clear error message
- [ ] Permission denial shows guidance to System Settings
- [ ] Service launch failure shows retry option
- [ ] All errors recoverable (no stuck states)

**Performance**:
- [ ] Animations run at 60fps
- [ ] No memory leaks (profile with Instruments)
- [ ] Model download doesn't block UI
- [ ] No timer leaks (cleanup in deinit)
- [ ] Background tasks cancel properly on screen exit

**Visual Consistency**:
- [ ] All screens use same grid background
- [ ] Icons consistent size and style
- [ ] Color scheme matches across screens
- [ ] Typography consistent
- [ ] Spacing/padding uniform

**Accessibility**:
- [ ] VoiceOver reads all content correctly
- [ ] Tab navigation works through all controls
- [ ] All buttons have clear labels
- [ ] Keyboard shortcuts work

---

## Implementation Order

**Week 1**: Subtask 1 (Welcome + Permissions)
- Port animations from Live
- Implement Live mode toggle
- Test transitions

**Week 2**: Subtask 2 (Model Install + Status Check)
- Real download implementation
- Status monitoring
- Background continuation

**Week 3**: Subtask 3 (LLM Config + Complete)
- Keychain integration
- Interactive demo port
- Celebration animations

**Week 4**: Subtask 4 (End-to-End + Polish)
- Full flow testing
- Bug fixes
- Performance optimization

---

## Dependencies & Blockers

**External Dependencies**:
- TalkieLive codebase access (for porting animations)
- TalkieEngine service integration
- TalkieLive service integration
- Model download URLs and authentication

**Internal Dependencies**:
- `OnboardingCoordinator` state management
- `KeychainManager` implementation
- `ModelDownloadManager` implementation
- Permission helpers (AVAudioApplication, AXIsProcessTrusted, etc.)

**Code Review Todos to Address**:
- [ ] #3: Implement API key storage using KeychainManager (Subtask 3)
- [ ] #4: Replace fake model download with real implementation (Subtask 2)
- [ ] #9: Add deinit timer cleanup in OnboardingCoordinator (Subtask 1)

---

## Success Criteria

**Onboarding Complete When**:
1. All 6 screens (Welcome → Complete) implemented
2. All transitions smooth (< 100ms delay)
3. State persists across app restarts
4. Both Core and Live modes work end-to-end
5. No critical bugs or crashes
6. Performance acceptable (60fps animations, < 5s model download start)
7. Passes all accessibility checks
8. User can complete onboarding in < 2 minutes (typical case)

---

## Risk Mitigation

**High Risk Items**:
1. **Animation port complexity** → Start with Subtask 1 early to validate approach
2. **Non-blocking download** → Extensive testing in Subtask 2
3. **Keychain security** → Security review in Subtask 3
4. **Service integration** → Mock services first, real integration later

**Rollback Plan**:
- Keep existing onboarding as fallback
- Feature flag new onboarding (`useNewOnboarding`)
- A/B test with 10% of users first
- Monitor crash rates and completion rates

---

## Next Steps

1. **Assign Subtask 1** to engineer (Welcome + Permissions)
2. **Assign Subtask 2** to engineer (Model Install + Status Check)
3. **Assign Subtask 3** to engineer (LLM Config + Complete)
4. **Assign Subtask 4** to engineer (End-to-End Validation)

Each engineer should:
- Read the relevant screen docs thoroughly
- Port from Live where specified (don't rebuild)
- Test transitions between their 2 screens
- Document any blockers or questions
- Submit PR with clear testing instructions

---

**Last Updated**: 2024-12-18
