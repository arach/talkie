# Talkie Onboarding & New User Experience

## Overview

A progressive onboarding system that introduces Talkie's features through **discovery moments** spread across the first 5-10 sessions. Rather than front-loading tutorials, we celebrate small wins and reveal capabilities when they're most relevant.

**Philosophy:** Every session should have something new to discover. Users feel a sense of progress and mastery, not information overload.

---

## Core Principles

### 1. Progressive Disclosure
Don't show everything at once. Introduce features as the user becomes ready for them.

### 2. Celebrate Small Wins
First memo? First dictation? First workflow? Each milestone deserves recognition.

### 3. Contextual Learning
Show tips when they're actionable, not as abstract documentation.

### 4. Respect User Agency
Tips are dismissible. Progress tracking is optional. Power users can skip ahead.

### 5. Delight Through Discovery
The "aha!" moment of finding a feature yourself is more memorable than being told about it.

---

## Session-by-Session Journey

### Session 1: Welcome & First Recording

**Goals:**
- User successfully creates their first memo
- User understands the core value proposition

**Moments:**
1. **Welcome Modal** (first launch only)
   - Brief (3-4 sentences) explanation of what Talkie does
   - Single CTA: "Record your first memo"
   - Skip option for returning users

2. **First Recording Celebration**
   - Confetti or subtle animation
   - "Your first memo! 🎉 Talkie transcribed X words in Y seconds"
   - Hint: "Next time, try holding ⌥ Option to dictate anywhere"

3. **Home Dashboard (Empty State)**
   - Instead of empty lists, show:
     - "Your memos will appear here"
     - Link to docs: "Learn what Talkie can do →"

---

### Session 2: Live Dictation Discovery

**Goals:**
- User tries live dictation (⌥ hotkey)
- User sees text appear in another app

**Moments:**
1. **Returning User Nudge** (if they haven't tried live dictation)
   - Subtle banner on Home: "Ready to try live dictation? Hold ⌥ anywhere"
   - Dismissible, won't show again after dismissed or after first dictation

2. **First Live Dictation Celebration**
   - "You just dictated directly into [App Name]! ✨"
   - Brief explanation of the interstitial panel
   - Hint: "Try the Command button to give voice instructions"

---

### Session 3: Voice Commands & Polish

**Goals:**
- User discovers AI polish capabilities
- User tries a voice command or quick action

**Moments:**
1. **Interstitial Tooltip** (first time seeing polish buttons)
   - Small tooltip pointing at Command button
   - "Speak an instruction like 'make it professional' or 'fix grammar'"
   - Shows once, then remembered

2. **First Polish Celebration**
   - "Nice! You just refined your text with AI 🪄"
   - Show before/after word count or change summary
   - Hint: "Check your edit history with the clock icon"

---

### Session 4: Workflows Introduction

**Goals:**
- User becomes aware of workflows
- User runs their first workflow (or explores the gallery)

**Moments:**
1. **Workflow Discovery Prompt**
   - After 3+ polishes: "You're getting good at this! Ready to automate?"
   - Points to Workflows in sidebar
   - "Workflows let you save your favorite transformations"

2. **First Workflow Run**
   - "Workflow complete! You just automated [workflow name] 🚀"
   - Hint: "You can create custom workflows too"

---

### Session 5: Stats & Progress

**Goals:**
- User sees their growing stats
- User feels a sense of accomplishment

**Moments:**
1. **Milestone Celebration**
   - "You've transcribed 1,000 words! 📊"
   - Or: "5 memos created!" / "First week streak!"
   - Unlocks: Activity heatmap becomes more meaningful

2. **Stats Discovery**
   - First time visiting Stats: "Here's your voice productivity at a glance"
   - Explain what the metrics mean

---

### Sessions 6-10: Advanced Features

**Feature Unlocks (shown when relevant):**

| Session | Feature | Trigger |
|---------|---------|---------|
| 6 | Quick Open | After 5+ copy-to-clipboard actions |
| 7 | Custom Workflows | After running 3+ built-in workflows |
| 8 | Keyboard Shortcuts | After 10+ recordings |
| 9 | Models & Providers | After 5+ AI polish operations |
| 10 | Power User Mode | Disable all tips, full control |

**Milestone Celebrations:**
- 10 memos: "Double digits! 🎯"
- 50 dictations: "You're a dictation pro! 🎤"
- 7-day streak: "One week of voice productivity! 🔥"
- 10,000 words: "You've transcribed a short story's worth! 📚"

---

## UI Components

### 1. Welcome Modal

```
┌─────────────────────────────────────────────────────┐
│                                                     │
│                    👋 Welcome to Talkie             │
│                                                     │
│   Capture thoughts with your voice, transcribe     │
│   instantly, and polish with AI.                   │
│                                                     │
│   ┌─────────────────────────────────────────────┐  │
│   │          [ Record Your First Memo ]         │  │
│   └─────────────────────────────────────────────┘  │
│                                                     │
│                   Skip for now                      │
│                                                     │
│   ─────────────────────────────────────────────    │
│   📖 Read the docs: talkie.app/docs                │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### 2. Celebration Toast

Appears at top of window, auto-dismisses after 4 seconds:

```
┌─────────────────────────────────────────────────────┐
│ 🎉 Your first memo! Transcribed 47 words in 2.3s   │
│                                                     │
│ Tip: Hold ⌥ anywhere to dictate directly    [ × ]  │
└─────────────────────────────────────────────────────┘
```

### 3. Feature Tooltip

Contextual pointer attached to UI element:

```
                    ┌────────────────────────────────┐
                    │ 🎤 Voice Command               │
                    │                                │
                    │ Speak an instruction like      │
                    │ "make it concise" or           │
                    │ "translate to Spanish"         │
                    │                                │
                    │ [ Got it ]                     │
                    └───────────┬────────────────────┘
                                │
                                ▼
┌──────────────┐
│ 🎤 Command   │
└──────────────┘
```

### 4. Progress Tracker (Optional)

Shown in sidebar or settings, tracks onboarding progress:

```
Getting Started                         4/8 complete
━━━━━━━━━━━━━━━━━━━━━━━━░░░░░░░░░░░░░░

✓ Created first memo
✓ Tried live dictation
✓ Used voice command
✓ Explored workflows
○ Set up Quick Open
○ Customized a workflow
○ Reached 1,000 words
○ Built a 7-day streak
```

### 5. Empty State with Guidance

When Recent Memos is empty:

```
┌─────────────────────────────────────────────────────┐
│ Recent Memos                                        │
│                                                     │
│         📝 No memos yet                            │
│                                                     │
│   Record a thought with ⌘R or click Record above   │
│                                                     │
│   📖 New here? Read the docs →                     │
│                                                     │
└─────────────────────────────────────────────────────┘
```

---

## Data Model

### OnboardingState (persisted in UserDefaults)

```swift
struct OnboardingState: Codable {
    // Completed milestones
    var hasSeenWelcome: Bool = false
    var hasCreatedFirstMemo: Bool = false
    var hasTriedLiveDictation: Bool = false
    var hasUsedVoiceCommand: Bool = false
    var hasRunWorkflow: Bool = false
    var hasSetupQuickOpen: Bool = false

    // Dismissed tips (won't show again)
    var dismissedTips: Set<String> = []

    // Celebration thresholds reached
    var celebratedMilestones: Set<String> = []

    // Session count
    var sessionCount: Int = 0
    var lastSessionDate: Date?

    // Power user mode (disable all tips)
    var powerUserMode: Bool = false
}
```

### Milestone Definitions

```swift
enum Milestone: String, CaseIterable {
    case firstMemo = "first_memo"
    case firstDictation = "first_dictation"
    case firstPolish = "first_polish"
    case firstWorkflow = "first_workflow"
    case tenMemos = "ten_memos"
    case thousandWords = "thousand_words"
    case weekStreak = "week_streak"
    case fiftyDictations = "fifty_dictations"
    case tenThousandWords = "ten_thousand_words"

    var title: String { ... }
    var message: String { ... }
    var emoji: String { ... }
}
```

---

## Implementation Plan

### Phase 1: Foundation
- [ ] Create `OnboardingState` model
- [ ] Create `OnboardingManager` service
- [ ] Add session tracking (increment on app launch)
- [ ] Persist state to UserDefaults

### Phase 2: Welcome Experience
- [ ] Welcome modal (first launch)
- [ ] Empty state improvements (Home dashboard)
- [ ] Docs link in sidebar or empty states

### Phase 3: Celebrations
- [ ] Toast/banner component for celebrations
- [ ] First memo celebration
- [ ] First dictation celebration
- [ ] Milestone celebrations (10 memos, 1000 words, etc.)

### Phase 4: Tooltips
- [ ] Tooltip component (pointer + dismissible)
- [ ] Command button tooltip (first interstitial)
- [ ] Workflow discovery prompt
- [ ] Quick Open discovery prompt

### Phase 5: Progress Tracking
- [ ] Optional progress tracker UI
- [ ] Settings toggle for power user mode
- [ ] "What's New" for returning users after updates

---

## Technical Considerations

### Where to Trigger Celebrations

| Event | Location | Trigger |
|-------|----------|---------|
| First memo | MemoDetailView / after save | `DatabaseManager.memoCount == 1` |
| First dictation | LiveController / after dictation | `OnboardingState.hasTriedLiveDictation == false` |
| First polish | InterstitialManager / after polish | Check state before polish |
| Word milestones | Home dashboard / on appear | Check total word count |

### Avoiding Annoyance

1. **Rate limiting:** Max 1 celebration per session
2. **Dismissal memory:** Once dismissed, a tip never returns
3. **Power user escape:** Single toggle to disable everything
4. **No blocking modals:** Toasts and tooltips, not popups (except welcome)

### Animation & Delight

- Celebrations: Subtle confetti or sparkle animation (like the ✨ in iOS)
- Tooltips: Gentle fade-in, not jarring
- Progress: Smooth fill animations
- Sound: Optional (probably off by default)

---

## Open Questions

1. **Docs URL:** What's the documentation URL to link to?
2. **Celebration frequency:** Is one per session too few? Too many?
3. **Progress tracker visibility:** Always visible? Hidden in settings?
4. **Confetti:** Too playful? Or fits the brand?
5. **Onboarding reset:** Should there be a way to re-trigger onboarding (for testing or re-learning)?

---

## Success Metrics

- **Activation rate:** % of new users who complete first memo in session 1
- **Feature discovery:** % of users who try live dictation by session 3
- **Retention:** Day 7 retention rate
- **Tip engagement:** Click-through rate on tip CTAs
- **Dismissal rate:** How quickly do users dismiss tips (too aggressive?)

---

## References

- [Apple Human Interface Guidelines: Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)
- [Duolingo's gamification patterns](https://www.duolingo.com/)
- [Notion's empty states](https://www.notion.so/)
- Linear's progressive disclosure approach

---

## Next Steps

1. Review and approve this plan
2. Create feature branch: `feature/onboarding-experience`
3. Implement Phase 1 (Foundation)
4. Iterate based on feedback

---

*Document created: 2026-01-22*
*Status: Planning*
