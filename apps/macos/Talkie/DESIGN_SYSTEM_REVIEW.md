# Design System Adherence Review - Live Settings Components

## Issues Found

### 1. OverlayStylePreviews.swift
**Problems:**
- ❌ Corner radius: `cornerRadius: 6` → Should use `CornerRadius.xs`
- ❌ Opacity: `.opacity(0.15)` → Should use `Opacity.medium`
- ❌ Font sizes: `.system(size: 10)`, `.system(size: 7)` → Should use Font tokens
- ❌ Hardcoded color: `Color.black.opacity(0.15)` → Should use Theme colors

**Fixes Needed:**
```swift
// BEFORE:
RoundedRectangle(cornerRadius: 6)
    .fill(Color.black.opacity(0.15))

// AFTER:
RoundedRectangle(cornerRadius: CornerRadius.xs)
    .fill(Color.primary.opacity(Opacity.medium))
```

### 2. HotkeyRecorder.swift
**Problems:**
- ❌ Corner radius: `6`, `4` → Should use `CornerRadius.xs`
- ❌ Font sizes: `.system(size: 14, weight: .semibold, design: .monospaced)` → Should use `Font.bodyMedium`
- ❌ Font sizes: `.system(size: 9, weight: .bold)` → Should use `Font.techLabelSmall`
- ❌ Font sizes: `.system(size: 10, weight: .medium)` → Should use `Font.labelSmall`
- ❌ Hardcoded padding values → Should use `Spacing` enum
- ❌ Hardcoded opacity: `.opacity(0.2)`, `.opacity(0.18)`, `.opacity(0.12)` → Should use `Opacity` enum

**Fixes Needed:**
```swift
// BEFORE:
.font(.system(size: 14, weight: .semibold, design: .monospaced))
.padding(.horizontal, 12)
.padding(.vertical, 8)
RoundedRectangle(cornerRadius: 6)

// AFTER:
.font(.bodyMedium)
.padding(.horizontal, Spacing.sm)
.padding(.vertical, Spacing.xs)
RoundedRectangle(cornerRadius: CornerRadius.xs)
```

### 3. AudioDeviceSelector.swift
**Problems:**
- ❌ Corner radius: `6`, `4` → Should use `CornerRadius.xs`
- ❌ Font sizes: `.system(size: 11)`, `.system(size: 12)`, `.system(size: 9)` → Should use Font tokens
- ❌ Hardcoded padding: `12`, `8` → Should use `Spacing` enum
- ❌ Hardcoded opacity: `.opacity(0.08)`, `.opacity(0.05)`, `.opacity(0.1)` → Should use `Opacity` enum

**Fixes Needed:**
```swift
// BEFORE:
.font(.system(size: 12))
.padding(.horizontal, 12)
.padding(.vertical, 8)
RoundedRectangle(cornerRadius: 6)
    .fill(Color.primary.opacity(0.05))

// AFTER:
.font(.labelMedium)
.padding(.horizontal, Spacing.sm)
.padding(.vertical, Spacing.xs)
RoundedRectangle(cornerRadius: CornerRadius.xs)
    .fill(Color.primary.opacity(Opacity.subtle))
```

### 4. SoundPicker.swift
**Problems:**
- ❌ Corner radius: `8`, `6` → Should use `CornerRadius.sm`, `CornerRadius.xs`
- ❌ Font sizes: Multiple `.system(size:)` calls → Should use Font tokens
- ❌ Hardcoded padding: `12`, `8`, `6` → Should use `Spacing` enum
- ❌ Hardcoded opacity: `.opacity(0.15)`, `.opacity(0.05)`, `.opacity(0.03)`, etc. → Should use `Opacity` enum

**Fixes Needed:**
```swift
// BEFORE:
.font(.system(size: 20, weight: .medium))
.padding(.vertical, 12)
RoundedRectangle(cornerRadius: 8)
    .fill(Color.primary.opacity(0.03))

// AFTER:
.font(.headlineMedium)
.padding(.vertical, Spacing.sm)
RoundedRectangle(cornerRadius: CornerRadius.sm)
    .fill(Color.primary.opacity(Opacity.subtle))
```

## Font Mapping Guide

| Old | New | Use Case |
|-----|-----|----------|
| `.system(size: 7)` | `.techLabelSmall` or custom | Tiny metadata |
| `.system(size: 9, weight: .bold)` | `.techLabelSmall` | Status indicators |
| `.system(size: 10, weight: .medium)` | `.labelSmall` | Small labels |
| `.system(size: 10)` | `.labelSmall` | Standard small text |
| `.system(size: 11, weight: .medium)` | `.labelMedium` | Standard labels |
| `.system(size: 11)` | `.labelMedium` | UI chrome text |
| `.system(size: 12)` | `.bodySmall` or `.monoSmall` | Body/technical text |
| `.system(size: 14, weight: .semibold, design: .monospaced)` | `.bodyMedium` | Mono body text |
| `.system(size: 20, weight: .medium)` | `.headlineMedium` | Icons/headers |

## Spacing Mapping Guide

| Old Value | New Token | Use Case |
|-----------|-----------|----------|
| `2` | `Spacing.xxs` | Micro spacing |
| `4` | Custom or `Spacing.xxs * 2` | Between xxs and xs |
| `6` | `Spacing.xs` | Extra small |
| `8` | `Spacing.xs + 2` or `Spacing.sm - 2` | Between xs and sm |
| `10` | `Spacing.sm` | Small spacing |
| `12` | `Spacing.sm + 2` or `Spacing.md - 2` | Between sm and md |
| `14` | `Spacing.md` | Medium spacing |
| `20` | `Spacing.lg` | Large spacing |
| `24` | `Spacing.lg + 4` or `Spacing.xl - 4` | Between lg and xl |

## Corner Radius Mapping Guide

| Old Value | New Token |
|-----------|-----------|
| `1`, `1.5` | Custom (too small for tokens) |
| `4` | `CornerRadius.xs` |
| `6` | `CornerRadius.xs + 2` or `CornerRadius.sm - 2` |
| `8` | `CornerRadius.sm` |
| `12` | `CornerRadius.md` |

## Opacity Mapping Guide

| Old Value | New Token |
|-----------|-----------|
| `0.03` | `Opacity.subtle` |
| `0.05` | Between `subtle` and `light` |
| `0.08` | `Opacity.light` |
| `0.1` | Between `light` and `medium` |
| `0.12`, `0.15` | `Opacity.medium` |
| `0.18`, `0.2` | Between `medium` and `strong` |
| `0.25` | Between `medium` and `strong` |
| `0.3` | `Opacity.strong` |
| `0.5` | `Opacity.half` |
| `0.6` | Between `half` and `prominent` |
| `0.7` | `Opacity.prominent` |
| `0.8` | Between `prominent` and full |

## Priority

1. **HIGH**: Fix corner radius and font usage (most visible inconsistencies)
2. **MEDIUM**: Fix opacity values (subtle but important for consistency)
3. **LOW**: Fix spacing (mostly correct, minor tweaks needed)

## Notes

- Some hardcoded values like `1.5` for very small corner radius may not have exact tokens
- Preview components (WavyParticlesPreview, WaveformBarsPreview) may need custom values for animation precision
- Focus on user-facing UI components first, animation internals can stay as-is if needed
