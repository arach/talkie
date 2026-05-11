# Talkie macOS Design Evaluation Guide

Based on [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines) and macOS best practices.

## Apple HIG Core Principles

### 1. Clarity
- Interface should be legible and easy to understand
- Clear text, sharp icons, strong visual hierarchy
- Focus on the most important elements
- Nothing should be ambiguous or confusing

### 2. Deference
- UI should step back and let user content take center stage
- Fluid animations and translucent/subtle UI elements
- Minimize visual clutter

### 3. Depth
- Help users understand where they are and how they got there
- Visual layering, smooth transitions, logical hierarchy
- Create sense of spatial depth and intuitive navigation

### 4. Consistency
- Learned actions in one part should transfer to another
- Predictable layouts - controls where users expect them
- Behavior and function remain same even as appearance adapts

---

## macOS-Specific Guidelines

### Window Sizing

| Metric | Guideline |
|--------|-----------|
| **Minimum window** | 400-500px width for usable content |
| **System Settings reference** | ~710×470 points |
| **Sidebar width** | 180-220 points (System Settings: 215pt) |
| **Sidebar min/max** | 180-300 points with draggable divider |

### Navigation Patterns

**Standard macOS Layout:**
```
┌─────────────────────────────────────────────────────────┐
│ Toolbar                                                 │
├───────────┬─────────────────────────────────────────────┤
│           │                                             │
│  Sidebar  │              Content / Detail               │
│  (List)   │                                             │
│           │                                             │
└───────────┴─────────────────────────────────────────────┘
```

**NavigationSplitView Options:**
- Two-column: sidebar + detail (most common)
- Three-column: sidebar + content + detail (for complex hierarchies)
- `balanced` style: detail shrinks as sidebar shows
- `prominentDetail` style: detail maintains size

### Typography (SF Pro)

| Level | Size | Weight | Use |
|-------|------|--------|-----|
| Large Title | 26pt | Bold | Screen headers |
| Title 1 | 22pt | Regular | Section headers |
| Title 2 | 17pt | Regular | Subsection headers |
| Title 3 | 15pt | Regular | Card titles |
| Body | 13pt | Regular | Primary content |
| Callout | 12pt | Regular | Secondary info |
| Footnote | 10pt | Regular | Timestamps, metadata |
| Caption | 10pt | Medium | Labels, badges |

### Spacing Scale

| Token | Value | Use |
|-------|-------|-----|
| xxs | 2pt | Tight inline spacing |
| xs | 4pt | Related element groups |
| sm | 8pt | Standard element spacing |
| md | 12pt | Section padding |
| lg | 16pt | Card padding |
| xl | 20pt | Screen margins |
| xxl | 24pt | Large section gaps |

### Color Guidelines

- Use semantic colors that adapt to light/dark mode
- `NSColor.labelColor` for primary text
- `NSColor.secondaryLabelColor` for secondary text
- `NSColor.tertiaryLabelColor` for muted text
- `NSColor.separatorColor` for dividers
- Accent color for interactive elements
- Avoid hardcoded white/black except for shadows

### Control Sizing

| Control | Height | Notes |
|---------|--------|-------|
| Standard button | 22pt | Default for most actions |
| Small button | 19pt | Inline, dense layouts |
| Large button | 26pt | Primary CTAs |
| Toggle | 22pt | Standard checkbox/switch |
| Text field | 22pt | Single line input |

---

## Evaluation Checklist

### Layout & Structure
- [ ] Uses NavigationSplitView or equivalent sidebar pattern
- [ ] Sidebar width is 180-220pt with draggable divider
- [ ] Minimum window size is usable (≥400pt wide)
- [ ] Content reflows gracefully at different sizes
- [ ] Proper spacing hierarchy (consistent use of spacing scale)

### Visual Design
- [ ] Uses SF Pro or system font
- [ ] Typography follows size/weight hierarchy
- [ ] Colors adapt to light/dark mode (semantic colors)
- [ ] No hardcoded Color.white or Color.black in views
- [ ] Accent color used consistently for interactive elements
- [ ] Glass/material effects use `.ultraThinMaterial` appropriately

### Navigation
- [ ] Clear visual hierarchy showing current location
- [ ] Sidebar shows selected state clearly
- [ ] Breadcrumbs or back navigation where appropriate
- [ ] Keyboard navigation works (Tab, Arrow keys)
- [ ] Escape dismisses modals/popovers

### Interaction
- [ ] Hover states on interactive elements
- [ ] Focus rings for keyboard navigation
- [ ] Appropriate cursor changes (pointer, resize, etc.)
- [ ] Drag and drop where expected
- [ ] Context menus on relevant items

### Accessibility
- [ ] All interactive elements have accessibility labels
- [ ] Color is not the only indicator of state
- [ ] Text meets contrast requirements
- [ ] VoiceOver can navigate the interface
- [ ] Dynamic Type respected (if applicable)

### Performance & Polish
- [ ] Smooth animations (60fps)
- [ ] No layout jumps on state changes
- [ ] Loading states for async operations
- [ ] Appropriate empty states
- [ ] Error states are clear and actionable

---

## Screen-by-Screen Evaluation Template

### Screen: [Name]

**Purpose:** [Brief description]

**Layout Compliance:**
- Pattern: [Sidebar+Detail / Single Column / Dashboard]
- Responsive: [Yes/No - describe behavior]
- Issues: [List any problems]

**Visual Design:**
- Typography: [Correct hierarchy / Issues]
- Colors: [Theme-compliant / Hardcoded issues]
- Spacing: [Consistent / Issues]

**Navigation:**
- [How user gets here]
- [How user navigates within]
- [How user exits]

**Interactions:**
- Hover states: [Present / Missing]
- Keyboard nav: [Works / Issues]
- Focus indicators: [Present / Missing]

**Score:** [1-5] with notes

---

---

## Evaluation Results (January 2026)

### Summary Scores

| Screen | Score | Status |
|--------|-------|--------|
| **HomeScreen** | 4.0/5 | Good - minor typography/focus issues |
| **MemosScreen** | 3.5/5 | Good - focus ring inconsistencies |
| **MemoDetail** | 3.5/5 | Good - navigation/accessibility gaps |
| **AppNavigation** | 4.3/5 | Excellent - Settings placement non-standard |

**Overall: 3.8/5** - Strong foundation, needs focus state and accessibility polish.

---

### HomeScreen (4.0/5)

**Strengths:**
- Excellent design system foundation (8pt grid, semantic colors, Theme tokens)
- Liquid Glass integration throughout
- Proper hover states with smooth animations
- Smart empty state patterns
- Responsive HStack/VStack composition

**Critical Issues:**
1. Missing keyboard focus indicators on interactive rows
2. Hardcoded activity heatmap color (`Color(red: 0.2, green: 0.8, blue: 0.7)`)
3. Typography sizes hardcoded instead of Theme tokens (lines 174, 518, 1010)
4. No selection state distinction (only hover)

**Priority Fixes:**
- [ ] Add focus ring to all interactive rows
- [ ] Move heatmap color to Theme system
- [ ] Replace `.system(size: 24)` with `Theme.current.fontDisplay`

---

### MemosScreen (3.5/5)

**Strengths:**
- Responsive layout (split view at 700pt, sheet below)
- Comprehensive keyboard navigation (arrows, Shift-select, Cmd+A, Tab)
- Semantic theming throughout
- Multi-select with Command/Shift-click
- Dual view modes (preview cards vs table)

**Critical Issues:**
1. Focus ring inconsistency between MemoRowEnhanced and MemoRowPreview
2. Table header columns lack keyboard focus ring
3. Column resize has no visual drag feedback
4. Page Up/Down uses fixed 10-item jump (should be viewport-aware)

**Priority Fixes:**
- [ ] Unify focus ring implementation across row types
- [ ] Add focus ring to sortable column headers
- [ ] Improve column resize visual feedback
- [ ] Calculate Page Up/Down based on visible rows

---

### MemoDetail (3.5/5)

**Strengths:**
- Glass material design with proper layering
- Clear section organization with spacing hierarchy
- Keyboard shortcuts (Cmd+E edit, Cmd+Return done, Escape cancel)
- Audio playback with waveform visualization
- Context menus for transcript actions

**Critical Issues:**
1. **No back button in inspector mode** - user trapped without exit path
2. **No unsaved changes indicator** - user may lose edits
3. UPPERCASE section headers reduce readability
4. Status indicators are color-only (accessibility issue)

**Priority Fixes:**
- [ ] Add back navigation when `showHeader=false`
- [ ] Add dirty state indicator on Edit button
- [ ] Change headers to sentence case with font weight
- [ ] Add text labels to status indicators for colorblind users

---

### AppNavigation (4.3/5)

**Strengths:**
- Native NavigationSplitView (explicit comments against reimplementation)
- Proper 2/3-column layout selection
- Left accent bar on selection with animation
- Icons switch to filled variants on selection
- Comprehensive notification-based deep linking
- Audio drop zone with multi-stage progress

**Issues:**
1. Settings at bottom of sidebar (macOS convention is top)
2. Some icons missing `.fill` mappings (waveform.badge.mic, chart.line.uptrend.xyaxis)
3. Sidebar toggle shortcut undocumented
4. No visual separator between Activity and Tools sections

**Priority Fixes:**
- [ ] Consider moving Settings to top of sidebar
- [ ] Complete icon fill mappings for all sidebar items
- [ ] Add Divider() between major sidebar sections

---

## Top Priority Action Items

### Critical (Fix This Week)
1. **Add focus rings** to all interactive rows in HomeScreen and MemosScreen
2. **Add back button** in MemoDetail inspector mode
3. **Add unsaved changes indicator** in MemoDetail edit mode

### High (Fix This Sprint)
4. Unify focus ring implementation in MemosScreen row types
5. Change MemoDetail section headers to sentence case
6. Add accessibility labels to status indicators
7. Replace hardcoded colors with Theme tokens

### Medium (Fix Next Sprint)
8. Complete icon fill mappings in AppNavigation sidebar
9. Standardize animation durations across app
10. Add visual separators between sidebar sections
11. Document keyboard shortcuts

---

## References

- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines)
- [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)
- [NavigationSplitView Documentation](https://developer.apple.com/documentation/swiftui/navigationsplitview)
- [SwiftUI for Mac 2024](https://troz.net/post/2024/swiftui-mac-2024/)
