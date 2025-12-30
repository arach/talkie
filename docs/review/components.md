# Components Module

`macOS/Talkie/Components/` - Reusable UI components

**Status: ✅ Reviewed (2024-12-29)**

---

## Files

### TalkieComponents.swift (543 lines) ✅
Core instrumented components: TalkieSection, TalkieButton, TalkieButtonSync, TalkieRow, TalkieList.

**Discussion:**
- Well-documented with convention-based naming examples
- Uses environment propagation for instrumentation context
- os_signpost integration for performance tracking
- ⚠️ Line 114: Uses `Task.sleep(for: .milliseconds(1))` - fragile timing for render marking

---

### FormControls.swift (243 lines) ✅
Form inputs: StyledToggle, StyledDropdown, StyledCheckbox, TabSelector.

**Discussion:**
- Properly uses design system tokens (Spacing, Theme.current, CornerRadius, Opacity)
- Spring animations for pleasant UX
- Consistent hover states

---

### ServiceHealthCard.swift (332 lines) ⚠️
Service status indicator cards for Live and Engine services.

**Discussion:**
- 🔴 **Line 129**: Uses `NSLog` instead of TalkieLogger - violates CLAUDE.md
- ⚠️ **Line 122**: Stale TODO comment `// TODO: Implement TalkieLive launch` but implementation exists below
- Otherwise clean component design with error popover

---

### OnAirIndicator.swift (106 lines) ⚠️
Neon-style "ON AIR" indicator for live recording.

**Discussion:**
- Nice visual effect with glow animation
- ⚠️ Uses hardcoded spacing values (6, 12) instead of `Spacing` tokens

---

### RelativeTimeLabel.swift (22 lines) ✅
"2 minutes ago" display using environment ticker.

**Discussion:**
- Clean, minimal implementation
- Uses @Observable environment pattern correctly

---

### RelativeTimeTicker.swift (33 lines) ✅
Auto-updating relative time singleton with Timer.

**Discussion:**
- Proper @MainActor @Observable singleton
- Timer cleanup in deinit
- 60-second refresh interval

---

### TextPolishEditor.swift (253 lines) ✅
Text editing state with LLM polish, diff preview, and edit history.

**Discussion:**
- Well-structured @Observable state management
- Clean separation of editing vs reviewing states
- Edit history with snapshots for undo
- LLM provider integration with proper fallback

---

## TODO

- [ ] Fix NSLog in ServiceHealthCard.swift:129 → use TalkieLogger
- [ ] Remove stale TODO comment in ServiceHealthCard.swift:122
- [ ] Consider using Spacing tokens in OnAirIndicator.swift

## Done

- [x] Initial review complete
