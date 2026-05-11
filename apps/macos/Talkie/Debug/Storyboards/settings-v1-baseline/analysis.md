# Settings UI Styling Analysis

**Generated:** 2025-12-22, 1:37 PM
**Pages Analyzed:** 13

---

## Summary

| Page | Fonts | Colors | Spacing | Issues |
|------|-------|--------|---------|--------|
| Appearance | 9 | 17 | 22 | ⚠️ 25 |
| Dictation Capture | 2 | 3 | 5 | ⚠️ 9 |
| Dictation Output | 2 | 3 | 5 | ⚠️ 9 |
| Quick Actions | 6 | 5 | 6 | ⚠️ 11 |
| Quick Open | 9 | 11 | 9 | ⚠️ 28 |
| Auto-Run | 9 | 17 | 8 | ⚠️ 35 |
| AI Providers | 10 | 7 | 11 | ⚠️ 17 |
| Transcription Models | 5 | 0 | 7 | ⚠️ 8 |
| LLM Models | 7 | 0 | 9 | ⚠️ 11 |
| Database | 6 | 5 | 7 | ⚠️ 22 |
| Files | 7 | 14 | 8 | ⚠️ 42 |
| Permissions | 8 | 10 | 13 | ⚠️ 36 |
| Debug Info | 5 | 4 | 5 | ⚠️ 17 |

**Total Issues:** 132 font, 138 color

---

## Appearance
**Category:** Appearance | **Source:** `AppearanceSettings.swift`

### Fonts
- ⚠️ `.font(SettingsManager.shared.fontXS)` ×24
- ✅ `.font(Theme.current.fontXSBold)` ×18
- ⚠️ `.font(SettingsManager.shared.fontSM)` ×6
- ⚠️ `.font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .monospaced))` ×2
- ⚠️ `.font(.system(size: 11, weight: .medium, design: preset.uiFontStyle == .monospace ? .monospaced : (preset.uiFontStyle == .rounded ? .rounded : .default))` ×2
- ⚠️ `.font(.system(size: 11, weight: .semibold, design: .monospaced))` ×2
- ⚠️ `.font(.system(size: 8, weight: .bold, design: .monospaced))` ×2
- ⚠️ `.font(.system(size: 8, weight: isSelected ? .medium : .regular, design: .monospaced))` ×1
- ⚠️ `.font(SettingsManager.shared.fontHeadline)` ×1

### Colors
- ✅ `.accentColor` ×25
- ✅ `Theme.current.fontXSBold` ×18
- ✅ `Theme.current.surface` ×15
- ⚠️ `.foregroundColor(.secondary)` ×8
- ✅ `Color.accentColor.opacity(0.15)` ×6
- ✅ `Theme.current.foregroundMuted` ×4
- ⚠️ `Color.primary.opacity(0.1)` ×4
- ✅ `Theme.current.foregroundSecondary` ×4
- ✅ `Theme.current.divider` ×3
- ⚠️ `.foregroundColor(.primary)` ×3
- ✅ `Color.accentColor.opacity(0.1)` ×2
- ✅ `Theme.current.backgroundTertiary` ×1
- ✅ `.foregroundColor(.accentColor)` ×1
- ⚠️ `.foregroundColor(.white)` ×1
- ✅ `Theme.current.backgroundSecondary` ×1
- ✅ `Color.accentColor.opacity(0.5)` ×1
- ✅ `.background(Color.accentColor)` ×1

### Spacing
- ⚠️ `spacing: 4` ×21
- ⚠️ `spacing: 12` ×14
- ⚠️ `spacing: 8` ×11
- ⚠️ `spacing: 6` ×7
- ⚠️ `spacing: 0` ×6
- ⚠️ `.padding(16)` ×6
- ⚠️ `.padding(10)` ×5
- ⚠️ `spacing: 2` ×4
- ⚠️ `.padding(.horizontal, 8)` ×4
- ⚠️ `.padding(.vertical, 5)` ×2
- ⚠️ `.padding(.vertical, 3)` ×2
- ⚠️ `.padding(.horizontal, 10)` ×2
- ⚠️ `spacing: 10` ×2
- ⚠️ `.padding(8)` ×2
- ⚠️ `.padding(.vertical, 8)` ×1
- ⚠️ `.padding(.horizontal, 6)` ×1
- ⚠️ `.padding(.bottom, 4)` ×1
- ⚠️ `.padding(.top, 4)` ×1
- ⚠️ `.padding(.horizontal, 4)` ×1
- ⚠️ `.padding(.vertical, 4)` ×1
- ⚠️ `.padding(.vertical, 1)` ×1
- ⚠️ `.padding(12)` ×1

### Opacity
- ⚠️ `.opacity(0.8)` ×14
- ⚠️ `.opacity(0.1)` ×7
- ⚠️ `.opacity(0.6)` ×6
- ⚠️ `.opacity(0.15)` ×6
- ⚠️ `.opacity(0.5)` ×3
- ⚠️ `.opacity(0.7)` ×2
- ⚠️ `.opacity(0.3)` ×1

### Issues
- ⚠️ **9** hardcoded font sizes (should use Theme.current)
- ⚠️ **16** non-theme colors (should use Theme.current)

---

## Dictation Capture
**Category:** Dictation | **Source:** `DictationSettings.swift`

### Fonts
- ✅ `.font(Theme.current.fontXSBold)` ×7
- ⚠️ `.font(SettingsManager.shared.fontXS)` ×6

### Colors
- ✅ `Theme.current.fontXSBold` ×7
- ⚠️ `.foregroundColor(.secondary)` ×7
- ⚠️ `.foregroundColor(.primary)` ×2

### Spacing
- ⚠️ `spacing: 12` ×7
- ✅ `Spacing.sm` ×2
- ⚠️ `spacing: 16` ×1
- ⚠️ `spacing: 28` ×1
- ⚠️ `spacing: 24` ×1

### Opacity
- ⚠️ `.opacity(0.8)` ×6

### Issues
- ⚠️ **9** non-theme colors (should use Theme.current)

---

## Dictation Output
**Category:** Dictation | **Source:** `DictationSettings.swift`

### Fonts
- ✅ `.font(Theme.current.fontXSBold)` ×7
- ⚠️ `.font(SettingsManager.shared.fontXS)` ×6

### Colors
- ⚠️ `.foregroundColor(.secondary)` ×7
- ✅ `Theme.current.fontXSBold` ×7
- ⚠️ `.foregroundColor(.primary)` ×2

### Spacing
- ⚠️ `spacing: 12` ×7
- ✅ `Spacing.sm` ×2
- ⚠️ `spacing: 24` ×1
- ⚠️ `spacing: 28` ×1
- ⚠️ `spacing: 16` ×1

### Opacity
- ⚠️ `.opacity(0.8)` ×6

### Issues
- ⚠️ **9** non-theme colors (should use Theme.current)

---

## Quick Actions
**Category:** Memos | **Source:** `QuickActionsSettings.swift`

### Fonts
- ⚠️ `.font(.system(size: 8, weight: .bold, design: .monospaced))` ×4
- ⚠️ `.font(.system(size: 11, weight: .medium, design: .monospaced))` ×2
- ⚠️ `.font(SettingsManager.shared.fontSM)` ×2
- ⚠️ `.font(.system(size: 11, design: .monospaced))` ×2
- ⚠️ `.font(SettingsManager.shared.fontXS)` ×1
- ⚠️ `.font(SettingsManager.shared.fontTitle)` ×1

### Colors
- ✅ `Theme.current.foregroundSecondary` ×5
- ✅ `Theme.current.surface` ×3
- ⚠️ `.foregroundColor(.secondary)` ×2
- ✅ `Theme.current.divider` ×1
- ⚠️ `.foregroundColor(.green)` ×1

### Spacing
- ⚠️ `spacing: 12` ×3
- ⚠️ `.padding(12)` ×2
- ⚠️ `spacing: 4` ×2
- ⚠️ `spacing: 8` ×2
- ⚠️ `spacing: 2` ×1
- ⚠️ `.padding(10)` ×1

### Opacity
- ⚠️ `.opacity(0.15)` ×1

### Issues
- ⚠️ **8** hardcoded font sizes (should use Theme.current)
- ⚠️ **3** non-theme colors (should use Theme.current)

---

## Quick Open
**Category:** Memos | **Source:** `QuickOpenSettings.swift`

### Fonts
- ⚠️ `.font(.system(size: 8, weight: .bold, design: .monospaced))` ×6
- ⚠️ `.font(.system(size: 10, weight: .medium, design: .monospaced))` ×2
- ⚠️ `.font(.system(size: 11, design: .monospaced))` ×2
- ⚠️ `.font(.system(size: 11, weight: .medium, design: .monospaced))` ×2
- ⚠️ `.font(.system(size: 10, design: .monospaced))` ×2
- ⚠️ `.font(.system(size: 8))` ×1
- ⚠️ `.font(.system(size: 10))` ×1
- ⚠️ `.font(.system(size: 9, design: .monospaced))` ×1
- ⚠️ `.font(.system(size: 14))` ×1

### Colors
- ⚠️ `.foregroundColor(.secondary)` ×6
- ✅ `Theme.current.foregroundSecondary` ×6
- ✅ `Theme.current.surface` ×4
- ✅ `Theme.current.divider` ×2
- ✅ `.foregroundColor(.accentColor)` ×1
- ⚠️ `.foregroundColor(.green)` ×1
- ⚠️ `Color.secondary.opacity(0.1)` ×1
- ✅ `Theme.current.surfaceHover` ×1
- ⚠️ `.foregroundColor(.primary)` ×1
- ⚠️ `.background(Color.secondary.opacity(0.1)` ×1
- ✅ `.accentColor` ×1

### Spacing
- ⚠️ `spacing: 8` ×4
- ⚠️ `.padding(12)` ×3
- ⚠️ `spacing: 4` ×3
- ⚠️ `spacing: 12` ×3
- ⚠️ `spacing: 2` ×1
- ⚠️ `spacing: 6` ×1
- ⚠️ `.padding(10)` ×1
- ⚠️ `.padding(.vertical, 4)` ×1
- ⚠️ `.padding(.horizontal, 8)` ×1

### Opacity
- ⚠️ `.opacity(0.1)` ×1

### Issues
- ⚠️ **18** hardcoded font sizes (should use Theme.current)
- ⚠️ **10** non-theme colors (should use Theme.current)

---

## Auto-Run
**Category:** Memos | **Source:** `AutoRunSettings.swift`

### Fonts
- ⚠️ `.font(.system(size: 8, weight: .bold, design: .monospaced))` ×6
- ⚠️ `.font(SettingsManager.shared.fontXS)` ×5
- ✅ `.font(Theme.current.fontSMBold)` ×3
- ⚠️ `.font(.system(size: 10, weight: .bold, design: .monospaced))` ×2
- ⚠️ `.font(.system(size: 8))` ×2
- ⚠️ `.font(.system(size: 14))` ×2
- ✅ `.font(Theme.current.fontXSBold)` ×2
- ✅ `.font(Theme.current.fontXSMedium)` ×1
- ⚠️ `.font(.system(size: 16))` ×1

### Colors
- ⚠️ `.foregroundColor(.secondary)` ×11
- ✅ `Theme.current.surface` ×4
- ✅ `Theme.current.fontSMBold` ×3
- ⚠️ `Color.green.opacity(0.2)` ×2
- ✅ `.accentColor` ×2
- ⚠️ `.background(Color.green.opacity(0.2)` ×2
- ✅ `Theme.current.fontXSBold` ×2
- ⚠️ `.foregroundColor(.green)` ×2
- ✅ `.foregroundColor(.accentColor)` ×1
- ✅ `.background(Color.accentColor.opacity(0.15)` ×1
- ⚠️ `Color.purple.opacity(0.15)` ×1
- ✅ `Theme.current.fontXSMedium` ×1
- ✅ `Color.accentColor.opacity(0.15)` ×1
- ⚠️ `Color.secondary.opacity(0.2)` ×1
- ⚠️ `.background(Color.purple.opacity(0.15)` ×1
- ⚠️ `.background(Color.secondary.opacity(0.2)` ×1
- ⚠️ `.foregroundColor(.purple)` ×1

### Spacing
- ⚠️ `spacing: 12` ×5
- ⚠️ `.padding(12)` ×3
- ⚠️ `spacing: 8` ×3
- ⚠️ `spacing: 4` ×3
- ⚠️ `.padding(.horizontal, 8)` ×3
- ⚠️ `.padding(.vertical, 4)` ×3
- ⚠️ `spacing: 2` ×2
- ⚠️ `.padding(16)` ×1

### Opacity
- ⚠️ `.opacity(0.15)` ×3
- ⚠️ `.opacity(0.2)` ×3

### Issues
- ⚠️ **13** hardcoded font sizes (should use Theme.current)
- ⚠️ **22** non-theme colors (should use Theme.current)

---

## AI Providers
**Category:** AI Models | **Source:** `APISettings.swift`

### Fonts
- ⚠️ `.font(SettingsManager.shared.fontXS)` ×5
- ✅ `.font(Theme.current.fontXSMedium)` ×4
- ⚠️ `.font(.system(size: 8, weight: .bold, design: .monospaced))` ×2
- ⚠️ `.font(.system(size: 11, design: .monospaced))` ×2
- ⚠️ `.font(.system(size: 11, weight: .semibold))` ×2
- ⚠️ `.font(.system(size: 14, weight: .medium))` ×2
- ⚠️ `.font(.system(size: 11, weight: .bold, design: .monospaced))` ×2
- ⚠️ `.font(.system(size: 11))` ×1
- ⚠️ `.font(SettingsManager.shared.fontTitle)` ×1
- ⚠️ `.font(.system(size: 10))` ×1

### Colors
- ✅ `Theme.current.fontXSMedium` ×4
- ⚠️ `.foregroundColor(.secondary)` ×3
- ✅ `Theme.current.surface` ×3
- ✅ `Theme.current.divider` ×2
- ✅ `Theme.current.foregroundMuted` ×2
- ⚠️ `Color.primary.opacity(0.1)` ×1
- ⚠️ `.foregroundColor(.blue)` ×1

### Spacing
- ⚠️ `spacing: 8` ×5
- ⚠️ `spacing: 6` ×3
- ⚠️ `spacing: 12` ×3
- ⚠️ `.padding(.horizontal, 4)` ×1
- ⚠️ `spacing: 16` ×1
- ⚠️ `.padding(.vertical, 8)` ×1
- ⚠️ `.padding(.horizontal, 12)` ×1
- ⚠️ `.padding(16)` ×1
- ⚠️ `.padding(.vertical, 10)` ×1
- ⚠️ `spacing: 4` ×1
- ⚠️ `.padding(10)` ×1

### Opacity
- ⚠️ `.opacity(0.5)` ×1
- ⚠️ `.opacity(0.1)` ×1
- ⚠️ `.opacity(0.8)` ×1

### Issues
- ⚠️ **12** hardcoded font sizes (should use Theme.current)
- ⚠️ **5** non-theme colors (should use Theme.current)

---

## Transcription Models
**Category:** AI Models | **Source:** `TranscriptionModelsSettingsView.swift`

### Fonts
- ⚠️ `.font(.system(size: 10, weight: .medium, design: .monospaced))` ×2
- ⚠️ `.font(.system(size: 11, weight: .bold, design: .monospaced))` ×2
- ⚠️ `.font(.system(size: 18, weight: .bold))` ×2
- ⚠️ `.font(.system(size: 10))` ×1
- ⚠️ `.font(.system(size: 12))` ×1

### Colors

### Spacing
- ⚠️ `spacing: 8` ×4
- ⚠️ `.padding(.horizontal, 24)` ×3
- ⚠️ `spacing: 1` ×1
- ⚠️ `spacing: 6` ×1
- ⚠️ `spacing: 24` ×1
- ⚠️ `.padding(.top, 16)` ×1
- ⚠️ `spacing: 12` ×1

### Issues
- ⚠️ **8** hardcoded font sizes (should use Theme.current)

---

## LLM Models
**Category:** AI Models | **Source:** `ModelLibrarySettings.swift`

### Fonts
- ⚠️ `.font(.system(size: 10, weight: .medium, design: .monospaced))` ×2
- ⚠️ `.font(.system(size: 12, weight: .medium))` ×2
- ⚠️ `.font(.system(size: 11, weight: .medium))` ×2
- ⚠️ `.font(.system(size: 18, weight: .bold))` ×2
- ⚠️ `.font(.system(size: 12))` ×1
- ⚠️ `.font(.system(size: 14))` ×1
- ⚠️ `.font(.system(size: 11))` ×1

### Colors

### Spacing
- ⚠️ `spacing: 12` ×3
- ⚠️ `spacing: 2` ×1
- ⚠️ `spacing: 8` ×1
- ⚠️ `.padding(24)` ×1
- ⚠️ `spacing: 6` ×1
- ⚠️ `spacing: 20` ×1
- ⚠️ `.padding(.vertical, 6)` ×1
- ⚠️ `.padding(.horizontal, 12)` ×1
- ⚠️ `.padding(16)` ×1

### Issues
- ⚠️ **11** hardcoded font sizes (should use Theme.current)

---

## Database
**Category:** Storage | **Source:** `StorageSettings.swift`

### Fonts
- ⚠️ `.font(.system(size: 10, weight: .medium))` ×4
- ✅ `.font(Theme.current.fontXSBold)` ×3
- ⚠️ `.font(SettingsManager.shared.fontXS)` ×3
- ⚠️ `.font(SettingsManager.shared.fontSM)` ×2
- ⚠️ `.font(.system(size: 10))` ×2
- ⚠️ `.font(.system(size: 24))` ×1

### Colors
- ⚠️ `.foregroundColor(.secondary)` ×8
- ✅ `Theme.current.fontXSBold` ×3
- ⚠️ `Color.secondary.opacity(0.1)` ×3
- ⚠️ `.background(Color.secondary.opacity(0.1)` ×3
- ⚠️ `.foregroundColor(.primary)` ×1

### Spacing
- ⚠️ `spacing: 12` ×5
- ⚠️ `.padding(.vertical, 8)` ×2
- ⚠️ `.padding(.horizontal, 12)` ×2
- ⚠️ `spacing: 6` ×2
- ⚠️ `spacing: 4` ×1
- ⚠️ `spacing: 20` ×1
- ⚠️ `spacing: 24` ×1

### Opacity
- ⚠️ `.opacity(0.1)` ×3
- ⚠️ `.opacity(0.8)` ×2

### Issues
- ⚠️ **7** hardcoded font sizes (should use Theme.current)
- ⚠️ **15** non-theme colors (should use Theme.current)

---

## Files
**Category:** Storage | **Source:** `LocalFilesSettings.swift`

### Fonts
- ⚠️ `.font(SettingsManager.shared.fontXS)` ×12
- ⚠️ `.font(SettingsManager.shared.fontSM)` ×7
- ⚠️ `.font(.system(size: 20, weight: .bold, design: .monospaced))` ×6
- ⚠️ `.font(.system(size: 8, weight: .bold, design: .monospaced))` ×4
- ⚠️ `.font(.system(size: 12, weight: .medium, design: .monospaced))` ×4
- ✅ `.font(Theme.current.fontXSBold)` ×3
- ⚠️ `.font(.system(size: 11, design: .monospaced))` ×2

### Colors
- ⚠️ `.foregroundColor(.secondary)` ×10
- ✅ `Theme.current.surface` ×3
- ✅ `Theme.current.fontXSBold` ×3
- ⚠️ `.foregroundColor(.green)` ×3
- ⚠️ `.foregroundColor(.orange)` ×2
- ⚠️ `.foregroundColor(.blue)` ×2
- ⚠️ `.foregroundColor(.purple)` ×2
- ⚠️ `Color.green.opacity(0.2)` ×1
- ⚠️ `Color.green.opacity(0.1)` ×1
- ⚠️ `.background(Color.green.opacity(0.05)` ×1
- ⚠️ `.background(Color.green.opacity(0.1)` ×1
- ⚠️ `Color.green.opacity(0.05)` ×1
- ⚠️ `Color.orange.opacity(0.1)` ×1
- ⚠️ `.background(Color.orange.opacity(0.1)` ×1

### Spacing
- ⚠️ `spacing: 4` ×8
- ⚠️ `spacing: 12` ×5
- ⚠️ `spacing: 6` ×5
- ⚠️ `spacing: 8` ×5
- ⚠️ `.padding(16)` ×4
- ⚠️ `.padding(8)` ×2
- ⚠️ `.padding(.leading, 24)` ×2
- ⚠️ `spacing: 24` ×1

### Opacity
- ⚠️ `.opacity(0.1)` ×2
- ⚠️ `.opacity(0.05)` ×1
- ⚠️ `.opacity(0.2)` ×1

### Issues
- ⚠️ **16** hardcoded font sizes (should use Theme.current)
- ⚠️ **26** non-theme colors (should use Theme.current)

---

## Permissions
**Category:** System | **Source:** `PermissionsSettings.swift`

### Fonts
- ⚠️ `.font(.system(size: 10, weight: .medium, design: .monospaced))` ×6
- ⚠️ `.font(.system(size: 10))` ×6
- ⚠️ `.font(.system(size: 12, weight: .medium))` ×2
- ⚠️ `.font(.system(size: 9, weight: .medium))` ×2
- ⚠️ `.font(.system(size: 9, weight: .bold, design: .monospaced))` ×2
- ⚠️ `.font(.system(size: 16))` ×1
- ⚠️ `.font(.system(size: 9, design: .monospaced))` ×1
- ⚠️ `.font(.system(size: 11))` ×1

### Colors
- ⚠️ `.foregroundColor(.secondary)` ×7
- ⚠️ `.background(Color.secondary.opacity(0.1)` ×2
- ⚠️ `Color.secondary.opacity(0.1)` ×2
- ⚠️ `.background(Color.secondary.opacity(0.05)` ×1
- ⚠️ `Color.secondary.opacity(0.05)` ×1
- ⚠️ `Color.secondary.opacity(0.15)` ×1
- ✅ `.accentColor` ×1
- ⚠️ `.foregroundColor(.primary)` ×1
- ✅ `Theme.current.surfaceHover` ×1
- ✅ `Theme.current.surface` ×1

### Spacing
- ⚠️ `spacing: 6` ×3
- ⚠️ `.padding(.horizontal, 10)` ×3
- ⚠️ `.padding(.vertical, 6)` ×3
- ⚠️ `spacing: 8` ×2
- ⚠️ `spacing: 2` ×2
- ⚠️ `spacing: 16` ×1
- ⚠️ `.padding(.vertical, 8)` ×1
- ⚠️ `spacing: 12` ×1
- ⚠️ `.padding(.horizontal, 8)` ×1
- ⚠️ `.padding(.vertical, 4)` ×1
- ⚠️ `.padding(10)` ×1
- ⚠️ `.padding(12)` ×1
- ⚠️ `spacing: 4` ×1

### Opacity
- ⚠️ `.opacity(0.1)` ×3
- ⚠️ `.opacity(0.15)` ×2
- ⚠️ `.opacity(0.05)` ×1
- ⚠️ `.opacity(0.8)` ×1

### Issues
- ⚠️ **21** hardcoded font sizes (should use Theme.current)
- ⚠️ **15** non-theme colors (should use Theme.current)

---

## Debug Info
**Category:** System | **Source:** `DebugSettings.swift`

### Fonts
- ⚠️ `.font(.system(size: 11, design: .monospaced))` ×4
- ✅ `.font(Theme.current.fontXSBold)` ×3
- ⚠️ `.font(.system(size: 10))` ×2
- ⚠️ `.font(.system(size: 11, weight: .medium, design: .monospaced))` ×2
- ⚠️ `.font(.system(size: 12))` ×1

### Colors
- ⚠️ `.foregroundColor(.secondary)` ×7
- ✅ `Theme.current.surface` ×4
- ✅ `Theme.current.fontXSBold` ×3
- ⚠️ `.foregroundColor(.primary)` ×1

### Spacing
- ⚠️ `spacing: 12` ×5
- ⚠️ `.padding(12)` ×3
- ⚠️ `.padding(.horizontal, 12)` ×1
- ⚠️ `spacing: 8` ×1
- ⚠️ `.padding(.vertical, 8)` ×1

### Issues
- ⚠️ **9** hardcoded font sizes (should use Theme.current)
- ⚠️ **8** non-theme colors (should use Theme.current)

---

