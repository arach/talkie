# Talkie UI Design Guide

## Overview

The Talkie app features a minimal, clean design with subtle gradients and shadows for depth. The color scheme emphasizes clarity and functionality.

## Design System

### Colors

**Primary Actions (Recording)**
- Red gradient: `Color.red` → `Color.red.opacity(0.8)`
- Used for: Record buttons, destructive actions
- Shadow: `Color.red.opacity(0.3)`, radius 8

**Secondary Actions (Playback)**
- Blue gradient: `Color.blue` → `Color.blue.opacity(0.7)`
- Used for: Play/pause buttons, primary actions
- Shadow: `Color.blue.opacity(0.3)`, radius 8

**Neutral Elements**
- Gray with opacity for disabled states
- Secondary text: `.foregroundColor(.secondary)`
- Success indicators: `.green`

### Typography

- **Titles**: `.title2`, `.semibold` weight
- **Headlines**: `.headline` for memo titles
- **Body**: `.body` for descriptions
- **Captions**: `.caption` for metadata (date, duration)
- **Monospaced**: `.system(.title, design: .monospaced)` for timer

### Gradients

All gradients use a consistent pattern:
```swift
LinearGradient(
    colors: [baseColor, baseColor.opacity(0.7-0.8)],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)
```

### Shadows

Standard shadow for elevated elements:
```swift
.shadow(color: baseColor.opacity(0.3), radius: 8, x: 0, y: 4)
```

## Screens

### 1. Empty State (Zero State)

**When Shown**: When user has no voice memos

**Components**:
- Centered gradient circle background (120x120)
- Waveform icon (size 50)
- Title: "No Voice Memos Yet"
- Subtitle: "Tap the button below to record your first voice memo"
- CTA Button: "Start Recording" (full width, max 280px)

**Visual Hierarchy**:
```
[Spacer]
    [Gradient Circle with Icon]
    [Title]
    [Subtitle]
[Spacer]
    [CTA Button]
    [Bottom padding: 60]
```

### 2. Voice Memo List

**When Shown**: When user has 1+ voice memos

**Components**:
- Navigation title: "Voice Memos"
- List with `.insetGrouped` style
- Floating record button (bottom right)

**Each Memo Row**:
- Play/pause button (40pt, gradient blue)
- Title (headline weight)
- Created date (medium style)
- Duration (M:SS format)
- Waveform visualization (height 40)
- Transcription preview (2 lines max)
- Swipe-to-delete action

**Floating Record Button**:
- Size: 70x70 circle
- Red gradient fill
- Mic icon
- Shadow for depth
- Bottom-right corner with padding

### 3. Recording View

**States**:

**Initial State** (not recording):
- Large waveform icon (80pt, gray)
- Text: "Tap to start recording"
- Record button: Red gradient circle (60pt)
- Border ring (80pt, gray)

**Recording State**:
- Live waveform visualization
- "Recording..." text (red)
- Duration timer (monospaced)
- Record button becomes stop square (30pt)
- Red border ring (80pt)

**Completed State**:
- Green checkmark icon (60pt)
- "Recording Saved" text
- Title input field
- "Save & Close" button (blue gradient)

### 4. Detail View

**Components**:
- Editable title (title2, bold)
- Metadata (date, duration)
- Large waveform (height 80)
- Playback progress slider
- Time indicators (current / total)
- Play/pause button (60pt, blue gradient)
- Transcription section (scrollable)

**Toolbar**:
- Leading: "Done" button
- Trailing: "Edit" / "Save" button

## Animations

### Waveform Animation
```swift
.animation(.easeInOut(duration: 0.3), value: isPlaying)
```
- Waveform changes color when playing (blue to blue.opacity(0.3))
- Smooth 0.3s ease-in-out transition

### State Transitions
- All state changes wrapped in `withAnimation`
- List insertions/deletions animated
- Sheet presentations use default slide animation

## Interactions

### Gestures
- **Tap**: Open detail view
- **Swipe left**: Show delete action
- **Long press**: (Future) Share or more options

### Buttons
- Record button: Toggle recording
- Play button: Toggle playback for memo
- Save button: Save and dismiss

## Accessibility

- All buttons have clear labels
- System colors for semantic meaning
- SF Symbols for icons
- VoiceOver friendly structure
- Dynamic Type support (system fonts)

## Future Enhancements

Potential improvements:
- Dark mode optimization
- Custom app icon
- Haptic feedback on interactions
- Pull-to-refresh
- Search functionality
- Folder/tag organization
- Share sheet integration
- Widget support
