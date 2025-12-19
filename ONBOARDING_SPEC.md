# Talkie Onboarding Flow Specification

**Purpose**: Port TalkieLive's delightful onboarding animations and interactions into Talkie's superior modular architecture.

**Architecture**: Keep Talkie's existing structure (OnboardingCoordinator + individual view files). Port only visual components and animations from Live.

## Installation Modes

The onboarding adapts based on what's being installed:

### **Core Mode**
- Just Talkie app (transcription + organization)
- **Flow**: Welcome → Permissions (mic only) → Model Install → LLM Config → Complete
- **Skips**: Accessibility/Screen Recording permissions, Live-specific features (pill demo)
- **Services**: TalkieEngine auto-launches in background when needed (no onboarding step)

### **Core + Live Mode**
- Talkie + TalkieLive integration
- **Flow**: Welcome → Permissions (all 3) → Model Install → LLM Config → Complete
- **Includes**: All permissions (mic + accessibility + screen recording), interactive pill demo in Complete screen
- **Services**: Both TalkieLive and TalkieEngine auto-launch in background when needed (no onboarding step)

**Determining Mode:**
Check if TalkieLive.app exists in /Applications or is being installed alongside Talkie. If yes, use Core + Live mode. If no, use Core mode.

**⚠️ IMPORTANT: Services Are Invisible**
There is **no** Service Setup onboarding step. Services (TalkieLive, TalkieEngine) auto-launch transparently in the background when needed. The user never sees a "launching services" screen - it just works.

---

## Screen 1: Welcome

### 📺 Screenwriter View (What the User Sees)

**Layout:**
- Top: Grid pattern background (tactical dark theme)
- Center: Large animated demo showing the recording workflow
- Bottom: Three feature columns with icons and descriptions
- Footer: "Continue" button (pulsing, green accent)

**Title:** "Welcome to Talkie"

**Subtitle:** "Capture, transcribe, and organize your thoughts with AI"

**Animated Demo (Center):**
- Shows a pill-shaped button in resting state
- Cursor approaches from left, pill expands on hover
- Cursor clicks pill, it turns red with "REC" text
- Waveform animation appears inside pill showing audio visualization
- Timer counts up (0:01, 0:02, 0:03...)
- Cursor clicks again to stop, pill shows "Processing..."
- Pill turns green with checkmark
- Keyboard shortcut keys (⌥⌘L) fade in and out above pill
- Animation loops continuously with 7 distinct phases
- Click ripple effects emanate from cursor click points

**Feature Columns (Below Demo):**
1. **Record**
   - Icon: mic.fill (green)
   - Title: "Press hotkey in any app"
   - Description: "Capture your thoughts instantly with a global keyboard shortcut"

2. **Auto-paste**
   - Icon: text.cursor (green)
   - Title: "Text appears instantly"
   - Description: "Transcribed text automatically pastes where you need it"

3. **On-device**
   - Icon: cpu (green)
   - Title: "Private, fast, no internet"
   - Description: "AI runs locally on your Mac for maximum privacy and speed"

**Buttons:**
- "Continue" - Large, pulsing green button (bottom right)
- "Skip Onboarding" - Small text button (top right, subtle)

**Visual Style:**
- Dark background (#0A0A0A)
- Green accent color (#22C55E)
- Grid pattern overlay (subtle)
- Spring animations (response: 0.3, dampingFraction: 0.7)

---

### 🎯 Product Manager View (Why This Exists)

**Purpose:**
Immediately demonstrate Talkie's value proposition through an engaging, interactive demo rather than static text. This is the user's first impression - it must be memorable and clearly show what the app does.

**User Goals:**
- Understand what Talkie does in under 10 seconds
- See the actual workflow (not just read about it)
- Feel excitement about the product
- Understand the keyboard shortcut before using the app

**Success Criteria:**
- User watches at least one full animation cycle (7 seconds)
- User understands the hotkey concept (⌥⌘L)
- User feels confident about what happens next
- Engagement rate: >80% watch full loop before continuing

**Key Messages:**
1. **Simple**: One hotkey does everything
2. **Fast**: Instant capture and transcription
3. **Private**: No data leaves your Mac
4. **Magical**: Watch the workflow happen in real-time

**Competitive Differentiation:**
Unlike other transcription apps that require opening an app or website, Talkie works from anywhere via a global hotkey. The animation makes this "works anywhere" concept tangible.

**User Journey:**
1. User launches Talkie for the first time
2. Sees animated demo and immediately "gets it"
3. Watches keyboard shortcut appear and thinks "I can remember ⌥⌘L"
4. Reads feature columns to understand benefits
5. Feels eager to set it up and try it
6. Clicks "Continue" with confidence

**Risks to Mitigate:**
- Animation too long → User gets bored (Solution: 7-second loop, snappy timing)
- Animation too fast → User doesn't understand (Solution: Deliberate pacing with pauses)
- User skips without watching → Doesn't understand product (Solution: Autoplay, pulsing CTA)

---

### 🔧 Engineer View (How to Build This)

**⚠️ IMPORTANT: DO NOT REBUILD - PORT DIRECTLY**

The animation in TalkieLive is already perfect. Your job is to **copy and integrate** the existing components, not rebuild them from scratch.

**Source Files to Port from TalkieLive:**
- `PillDemoAnimation.swift` - **Copy entire file as-is**
- `WaveformDemoView.swift` - **Copy entire component**
- `KeyboardShortcutView.swift` - **Copy entire component**
- `ClickRippleEffect.swift` - **Copy entire helper**
- Any supporting types, enums, or helpers these components use

**Target File:**
- `/Users/arach/dev/talkie/macOS/Talkie/Views/Onboarding/WelcomeView.swift`

**Implementation Steps:**

1. **Copy Components**: Locate all animation files in TalkieLive's onboarding and copy them to Talkie's project
2. **Add to Xcode Project**: Ensure all copied files are added to the Talkie target
3. **Update Imports**: Change any TalkieLive-specific imports to Talkie equivalents if needed
4. **Drop into WelcomeView**: Replace the current static content with the `PillDemoAnimation` component
5. **Update Feature Copy**: Change the three feature column text to match the spec above
6. **Test**: Run and verify the animation works exactly as it does in TalkieLive

**Integration Pattern:**
```swift
// In WelcomeView.swift
OnboardingStepLayout {
    VStack(spacing: 40) {
        // Animation area - DROP IN THE EXISTING COMPONENT
        PillDemoAnimation()  // ← This is the entire animated demo from Live
            .frame(height: 200)

        // Feature columns (update copy only)
        HStack(spacing: 60) {
            FeatureColumn(
                icon: "mic.fill",
                title: "Press hotkey in any app",
                description: "Capture your thoughts instantly with a global keyboard shortcut"
            )
            FeatureColumn(
                icon: "text.cursor",
                title: "Text appears instantly",
                description: "Transcribed text automatically pastes where you need it"
            )
            FeatureColumn(
                icon: "cpu",
                title: "Private, fast, no internet",
                description: "AI runs locally on your Mac for maximum privacy and speed"
            )
        }
    }
}
```

**What NOT to Do:**
- ❌ Don't rewrite the animation from scratch
- ❌ Don't try to "improve" the timing or phases
- ❌ Don't rebuild components with different state management
- ❌ Don't change animation curves or durations

**What TO Do:**
- ✅ Copy existing components verbatim
- ✅ Update only the feature column text
- ✅ Ensure it integrates with `OnboardingStepLayout` wrapper
- ✅ Test that animation loops perfectly like in Live

**Reference Implementation:**
The animation already exists at:
`/Users/arach/dev/talkie/macOS/TalkieLive/TalkieLive/Views/OnboardingView.swift` (lines ~300-800 for the animation logic)

**For Context Only - Animation Details (already implemented in Live):**

1. **CursorView**:
   - Size: 24x24
   - Color: White with subtle shadow
   - Animated position with easeInOut
   - Opacity changes (0 → 1 → 0)

2. **PillButton**:
   - Resting: 120x40, gray (#1F1F1F)
   - Hovered: 160x48, lighter gray (#2A2A2A)
   - Recording: 180x52, red (#EF4444), "REC" text
   - Processing: 200x52, yellow (#F59E0B), "Processing..."
   - Complete: 180x52, green (#22C55E), checkmark icon

3. **WaveformView**:
   - 8-12 vertical bars
   - Random heights (20-40px)
   - Animate with repeatForever, speed: 0.3s
   - Only visible during recording phase

4. **RecordingTimer**:
   - Format: "0:01", "0:02", etc.
   - Font: .monospacedDigit, size: 14, weight: .medium
   - Color: White
   - Position: Inside pill, left of waveform

5. **KeyboardShortcutView**:
   - Three keys: ⌥ ⌘ L
   - Each key: 32x32 rounded rect
   - Background: #1F1F1F with border
   - Fade in at phase 5, fade out at phase 7
   - Position: Above pill, centered

6. **ClickRippleEffect**:
   - Circle expanding from cursor position
   - Start: 0px, End: 60px
   - Opacity: 0.4 → 0
   - Duration: 0.6s
   - Color: Green (#22C55E)

**Layout Structure:**
```
VStack {
  Spacer() // Push content down

  // Animation Area
  ZStack {
    GridPatternView() // Background

    VStack(spacing: 40) {
      // Animated demo
      PillDemoAnimation()
        .frame(height: 200)

      // Feature columns
      HStack(spacing: 60) {
        FeatureColumn(icon:, title:, description:)
        FeatureColumn(icon:, title:, description:)
        FeatureColumn(icon:, title:, description:)
      }
    }
  }

  Spacer()

  // CTA Button
  OnboardingCTAButton("Continue") { ... }
}
```

**Performance Considerations:**
- Use `.drawingGroup()` on waveform for 60fps animation
- Limit timer updates to 10 Hz (not every frame)
- Use `GeometryReader` sparingly (only for cursor positioning)
- Preload sound effects if adding audio feedback

**Accessibility:**
- Add `.accessibilityLabel("Recording workflow demonstration")` to animation
- Provide `.accessibilityHint("Shows how to use keyboard shortcut to record")`
- Allow VO users to skip animation with standard navigation

**Testing Checklist:**
- [ ] Animation loops smoothly without stuttering
- [ ] Cursor movement is natural (easeInOut curves)
- [ ] Ripple effects appear on clicks
- [ ] Keys fade in/out at correct times
- [ ] Waveform animates only during recording phase
- [ ] Timer counts accurately
- [ ] All 7 phases transition smoothly
- [ ] Animation restarts after completion
- [ ] Works in light mode and dark mode
- [ ] No memory leaks after 10+ loops

**Migration Notes:**
- Talkie uses `OnboardingStepLayout` wrapper - keep this
- Update feature column copy from Live's version
- Ensure green accent color matches Talkie theme (#22C55E)
- Keep existing "Skip Onboarding" button functionality

---

## Screen 2: Permissions

### 📺 Screenwriter View (What the User Sees)

**Layout:**
- Top: Grid pattern background
- Center: Large pulsing shield icon with animated rings
- Middle: Three permission rows with status indicators
- Bottom: Continue/Skip buttons

**Title:** "Grant Permissions"

**Subtitle:** "Talkie needs a few permissions to work its magic"

**Icon:**
- Shield with checkmark (shield.checkmark.fill)
- Size: 80x80
- Color: Green when all granted, yellow when partial, gray when none
- Pulsing animation with expanding rings (3 concentric circles)
- Rings pulse outward every 2 seconds, fade from 0.3 → 0 opacity

**Permission Rows (Conditional based on mode):**

**Core Mode (Always shown):**

1. **Microphone** (Required)
   - Left: Microphone icon (mic.fill) in circle - red background
   - Center:
     - Title: "Microphone Access"
     - Description: "Capture audio for transcriptions"
   - Right:
     - Status: Checkmark (green) if granted, "Grant Access" button if not
     - "REQUIRED" badge in red

**Core + Live Mode (Only if TalkieLive is being installed):**

2. **Accessibility** (Required for Live)
   - Left: Command key icon (command) in circle - blue background
   - Center:
     - Title: "Accessibility Access"
     - Description: "Paste in place to accelerate your actions"
   - Right:
     - Status: Checkmark (green) if granted, "Open Settings" button if not
     - "REQUIRED" badge in red

3. **Screen Recording** (Optional for Live)
   - Left: Display icon (display) in circle - purple background
   - Center:
     - Title: "Screen Recording"
     - Description: "Record screen to capture context"
   - Right:
     - Status: Checkmark (green) if granted, "Grant Access" button if not
     - "OPTIONAL" badge in gray

**Note:** If not installing TalkieLive, only show Microphone permission. Accessibility and Screen Recording are Live-specific features.

**Helper Text (Below rows):**
"Don't worry - we take privacy seriously. All processing happens on your Mac, and your data never leaves your device."

**Buttons:**
- "Continue" - Enabled only when required permissions granted, pulsing when enabled
- "Skip for now" - Small text button, shows warning if required permissions not granted

**Visual Feedback:**
- Each permission row has hover state (slight background highlight)
- Checkmarks appear with bounce animation when permission granted
- Shield icon pulses faster when all permissions granted (celebration)

---

### 🎯 Product Manager View (Why This Exists)

**Purpose:**
Transparently request necessary permissions while educating users on **why** each is needed (value-focused, not technical). Adapt permissions based on installation mode to avoid overwhelming users with irrelevant requests.

**User Goals:**
- Understand what value each permission unlocks
- Know the purpose (not the mechanism) of each permission
- Feel confident that privacy is respected
- Grant permissions with minimal friction
- Only see permissions relevant to their installation

**Success Criteria:**
- **Core Mode**: >95% grant microphone permission
- **Core + Live Mode**: >95% grant microphone, >80% grant accessibility, >40% grant screen recording
- <5% abandon onboarding at this step
- Average time on screen: <45 seconds (Core), <60 seconds (Core + Live)

**Key Messages:**
1. **Value First**: Frame permissions by what they enable, not how they work
   - Microphone → "Capture audio for transcriptions"
   - Accessibility → "Paste in place to accelerate your actions"
   - Screen Recording → "Record screen to capture context"
2. **Conditional**: Only show permissions needed for the user's installation
3. **Privacy**: "All processing happens on your Mac"
4. **Ease**: Direct links to System Settings

**User Journey (Core Mode):**
1. User sees shield icon
2. Reads microphone permission: "Capture audio for transcriptions"
3. Understands the value, clicks "Grant Access"
4. System dialog appears, grants permission
5. Checkmark appears with bounce
6. Clicks "Continue" immediately (only 1 permission needed)

**User Journey (Core + Live Mode):**
1. User sees shield icon
2. Reads three permissions, each with clear value proposition
3. Clicks "Grant Access" for microphone → system dialog → granted
4. Clicks "Open Settings" for accessibility
5. Enables Talkie in Accessibility settings
6. Returns to app, checkmark appears (auto-detected via polling)
7. Reads screen recording ("Record screen to capture context")
8. Either grants it or skips (optional)
9. Clicks "Continue"

**Risks to Mitigate:**
- User confused why different permissions in different modes → Clear descriptions explain what unlocks each feature
- User denies microphone → Show warning that app won't work
- User abandons because "too many permissions" → Only show relevant permissions based on mode
- User doesn't understand Live features → Value descriptions make it clear

**Edge Cases:**
- User previously granted some permissions → Show checkmarks immediately
- User denies permission → Can click button again to retry
- User quits during permission granting → Resume at same state on relaunch
- Accessibility permission granted while on another step → Polling detects it
- Core mode user later installs Live → Can re-run onboarding or grant in Settings

---

### 🔧 Engineer View (How to Build This)

**Source Files to Port from TalkieLive:**
- Shield icon animation (pulsing rings) - port from `PermissionsStepView.swift`
- Permission row component - adapt from `PermissionRowView`
- Checkmark bounce animation

**Target File:**
- `/Users/arach/dev/talkie/macOS/Talkie/Views/Onboarding/PermissionsSetupView.swift` (already exists, enhance)

**Current State:**
Talkie already has this step implemented. Enhancements needed:

1. **Add pulsing ring animation to shield icon**
2. **Improve permission row visual design with value-focused descriptions**
3. **Add bounce animation to checkmarks**
4. **Add color-coded icons per permission**
5. **Add conditional display based on installation mode**

**⚠️ CRITICAL: Conditional Permission Display**

Permissions shown must adapt based on installation mode:

**Core Mode** (TalkieLive not installed):
- Show ONLY Microphone permission
- Required badge on microphone
- Can continue after microphone granted

**Core + Live Mode** (TalkieLive installed/being installed):
- Show all three permissions (Microphone, Accessibility, Screen Recording)
- Required badges on microphone + accessibility
- Optional badge on screen recording
- Can continue after microphone + accessibility granted

**Determining Mode:**
```swift
var isLiveMode: Bool {
    // Check if TalkieLive.app exists
    let liveAppPath = "/Applications/TalkieLive.app"
    return FileManager.default.fileExists(atPath: liveAppPath)
}

var permissionsToShow: [PermissionType] {
    if isLiveMode {
        return [.microphone, .accessibility, .screenRecording]
    } else {
        return [.microphone]
    }
}
```

**Components to Enhance:**

1. **PulsingShieldIcon**:
   ```
   State: @State private var pulseScale: CGFloat = 1.0

   Visual:
   - Base shield: 80x80, current state color
   - Ring 1: 100x100, opacity 0.3 → 0
   - Ring 2: 120x120, opacity 0.3 → 0, delayed 0.3s
   - Ring 3: 140x140, opacity 0.3 → 0, delayed 0.6s

   Animation:
   - Duration: 2 seconds
   - Repeat forever
   - Trigger faster pulse (1s) when all granted
   ```

2. **PermissionRow** (enhanced):
   ```
   Components:
   - Leading: Icon in colored circle (40x40)
   - Center: VStack(title + description)
   - Trailing: Status (checkmark or button) + badge

   Icon colors:
   - Microphone: Red (#EF4444)
   - Accessibility: Blue (#3B82F6)
   - Screen Recording: Purple (#A855F7)

   Hover state:
   - Background: #151515 → #1F1F1F
   - Transition: 0.15s ease
   ```

3. **CheckmarkAnimation**:
   ```
   Animation sequence:
   1. Checkmark appears at scale 0
   2. Bounces to scale 1.2 (0.2s, spring)
   3. Settles to scale 1.0 (0.1s, ease)
   4. Green glow appears around checkmark

   Trigger: When permission state changes to granted
   ```

4. **StatusBadge**:
   ```
   Required:
   - Background: Red (#EF4444)
   - Text: "REQUIRED"
   - Font: 9pt, bold, all caps

   Optional:
   - Background: Gray (#6B7280)
   - Text: "OPTIONAL"
   - Font: 9pt, bold, all caps

   Dimensions: Height 18px, horizontal padding 8px, corner radius 4px
   ```

**Permission Handling:**

1. **Microphone**:
   ```swift
   func requestMicrophonePermission() async {
       await AVAudioApplication.requestRecordPermission { granted in
           await MainActor.run {
               self.hasMicrophonePermission = granted
               if granted {
                   self.showCheckmarkAnimation = true
               }
           }
       }
   }
   ```

2. **Accessibility**:
   ```swift
   func requestAccessibilityPermission() {
       // Open System Settings
       NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)

       // Start polling (existing implementation in Talkie is good)
       startAccessibilityPolling()
   }
   ```

3. **Screen Recording**:
   ```swift
   func requestScreenRecordingPermission() {
       if #available(macOS 10.15, *) {
           CGRequestScreenCaptureAccess()

           // Poll for status (system dialog doesn't callback)
           Task {
               for _ in 0..<5 {
                   try? await Task.sleep(for: .seconds(1))
                   checkScreenRecordingPermission()
                   if hasScreenRecordingPermission { break }
               }
           }
       }
   }
   ```

**Layout Structure:**
```
OnboardingStepLayout {
    VStack(spacing: 40) {
        // Pulsing shield icon
        PulsingShieldIcon(state: permissionState)
            .frame(height: 100)

        // Permission rows
        VStack(spacing: 16) {
            PermissionRow(
                icon: "mic.fill",
                iconColor: .red,
                title: "Microphone Access",
                description: "Required to capture your voice",
                isRequired: true,
                isGranted: hasMicrophonePermission,
                action: { await requestMicrophonePermission() }
            )

            PermissionRow(...)
            PermissionRow(...)
        }

        // Privacy message
        Text("Don't worry - we take privacy seriously...")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
    }
}
```

**State Management:**
```swift
// Use existing OnboardingManager properties:
@Published var hasMicrophonePermission: Bool
@Published var hasAccessibilityPermission: Bool
@Published var hasScreenRecordingPermission: Bool

// Add for animations:
@State private var showMicCheckmark = false
@State private var showAccessibilityCheckmark = false
@State private var showScreenCheckmark = false
```

**Validation Logic:**
```swift
var canContinue: Bool {
    hasMicrophonePermission && hasAccessibilityPermission
}

var permissionState: PermissionState {
    if hasMicrophonePermission && hasAccessibilityPermission {
        return .allGranted
    } else if hasMicrophonePermission || hasAccessibilityPermission {
        return .partialGranted
    } else {
        return .noneGranted
    }
}
```

**Testing Checklist:**
- [ ] Shield icon pulses continuously
- [ ] Shield icon pulses faster when all granted
- [ ] Microphone button triggers system dialog
- [ ] Accessibility button opens System Settings to correct pane
- [ ] Screen recording button triggers system dialog
- [ ] Checkmarks appear with bounce animation
- [ ] Polling detects accessibility permission within 1 second
- [ ] Continue button disabled until required permissions granted
- [ ] Skip button shows warning if trying to skip required permissions
- [ ] Permission state persists across app restarts
- [ ] Hover states work on all permission rows

**Migration Notes:**
- Keep existing OnboardingManager integration
- Keep existing polling mechanism for accessibility
- Add visual enhancements only (animations, colors, badges)
- Don't change permission request logic (already working)

---

## Screen 3: ~~Service Setup~~ (REMOVED)

**⚠️ THIS SCREEN HAS BEEN REMOVED**

Services (TalkieLive and TalkieEngine) now auto-launch transparently in the background. There is no user-facing "Service Setup" step in the onboarding flow.

**Rationale:**
- Services are infrastructure, not something users need to think about
- Auto-launching provides a better user experience (just works™)
- Reduces onboarding friction and complexity

**Implementation:**
Services auto-launch on first use:
- **TalkieEngine**: Launches when user starts first transcription
- **TalkieLive**: Launches when user presses hotkey (Core + Live mode only)

No onboarding UI needed.

---

## Screen 4: Model Install

### 📺 Screenwriter View (What the User Sees)

**Layout:**
- Top: Grid pattern background
- Center: Large CPU icon with pulsing background
- Middle: Two model selection cards
- Bottom: Download progress (if downloading) + Continue button

**Title:** "Choose AI Model"

**Subtitle:** "Select the transcription model that fits your needs"

**Icon:**
- CPU icon (cpu)
- Size: 80x80
- Background: Green glow (pulsing)
- Pulsing animation during download

**Model Selection Cards (2):**

1. **Parakeet v3** (Recommended)
   - Layout: Card with hover state
   - Top right: "RECOMMENDED" badge (green)
   - Logo: Nvidia logo (green/black)
   - Title: "Parakeet v3"
   - Subtitle: "Ultra-fast, English only"
   - Specs table:
     - Size: ~200 MB
     - Speed: Ultra-fast
     - Languages: English
   - Version (on hover): "v3"
   - Learn more (on hover): External link icon → nvidia.com/parakeet
   - Selected state: Green border, checkmark in corner

2. **Whisper large-v3**
   - Layout: Card with hover state
   - Top right: "MULTILINGUAL" badge (blue)
   - Logo: OpenAI logo (black/white)
   - Title: "Whisper large-v3"
   - Subtitle: "Fast, 99+ languages"
   - Specs table:
     - Size: ~1.5 GB
     - Speed: Fast
     - Languages: 99+
   - Version (on hover): "large-v3-turbo"
   - Learn more (on hover): External link icon → openai.com/whisper
   - Selected state: Green border, checkmark in corner

**Card Interaction:**
- Default: Gray border (#2A2A2A)
- Hover: Lighter background, "Learn more" link appears, version shows
- Click: Select model (only one can be selected)
- Selected: Green border, checkmark, slightly elevated

**Download Progress (Bottom):**
When downloading:
- Progress bar (0-100%)
- Text: "Downloading Parakeet v3... 45%"
- Size downloaded: "92 MB of 200 MB"
- Time remaining: "~30 seconds remaining"
- Cancel button (small, right of progress bar)

**Helper Text:**
"Models are downloaded once and run locally on your Mac. Your recordings never leave your device."

**Buttons:**
- "Download & Continue" - Triggers download of selected model
- If model already installed: "Continue" (skip download)
- "Back" - Return to previous step

---

### 🎯 Product Manager View (Why This Exists)

**Purpose:**
Let users choose between speed-optimized (Parakeet) and multilingual (Whisper) models. Educate on trade-offs while providing clear recommendation for most users.

**User Goals:**
- Understand model differences (speed vs. multilingual)
- Make informed choice based on their needs
- See download progress and time remaining
- Feel confident model is reputable (logo branding)
- Understand privacy (local processing)

**Success Criteria:**
- >70% choose recommended Parakeet model
- >90% complete download without canceling
- <5% click "Learn more" (card UI is self-explanatory)
- Average time on screen: 90 seconds (60s reading + 30s downloading)

**Key Messages:**
1. **Choice**: Two good options, pick what fits your needs
2. **Recommendation**: Parakeet for most users (faster, smaller)
3. **Trust**: Nvidia and OpenAI branding builds confidence
4. **Privacy**: "Models run locally on your Mac"
5. **Transparency**: Clear size, speed, and language specs

**User Personas:**

*English-only user (70% of users):*
- Sees "RECOMMENDED" badge on Parakeet
- Reads "Ultra-fast" and "200 MB"
- Clicks Parakeet card → border turns green
- Clicks "Download & Continue"
- Waits 20-40 seconds for download
- Continues to next step

*Multilingual user (25% of users):*
- Reads both cards
- Sees "99+ languages" on Whisper
- Understands 1.5 GB is larger but worth it
- Clicks Whisper card → border turns green
- Clicks "Download & Continue"
- Waits 2-4 minutes for download
- Continues to next step

*Technical user (5% of users):*
- Hovers over cards to see versions
- Clicks "Learn more" to read about models
- Compares specs carefully
- Makes informed choice
- Continues with confidence

**User Journey (Happy Path):**
1. User arrives at screen
2. Sees two cards, reads "RECOMMENDED" on Parakeet
3. Hovers over Parakeet card → sees Nvidia logo, reads specs
4. Clicks Parakeet → green border appears
5. Clicks "Download & Continue"
6. Progress bar appears, shows "Downloading..."
7. Download completes in 30 seconds
8. Auto-advances to next step (or enables Continue button)

**User Journey (Cancel Path):**
1. User starts downloading Whisper (1.5 GB)
2. Realizes it's taking too long (slow connection)
3. Clicks "Cancel" on progress bar
4. Download stops, returns to selection state
5. Switches to Parakeet (smaller, faster)
6. Downloads successfully

**Risks to Mitigate:**
- Download fails mid-way → Resume capability
- Slow internet connection → Show time remaining, allow cancel
- Model already installed → Skip download, show "Already installed ✓"
- Confusion about differences → Clear specs table, badges, descriptions
- Distrust of AI models → Show logos, link to official docs

**Business Metrics:**
- Parakeet adoption: Target 70%
- Whisper adoption: Target 25%
- Skip/abandon: Target <5%
- Download completion rate: Target >90%

---

### 🔧 Engineer View (How to Build This)

**Source Files to Port from TalkieLive:**
- `ModelSelectionCardView.swift` - Card component with hover states
- `DownloadProgressButton.swift` - Progress bar with cancel
- Model logos (Nvidia, OpenAI) - Asset files

**Target File:**
- `/Users/arach/dev/talkie/macOS/Talkie/Views/Onboarding/ModelInstallView.swift` (already exists, enhance heavily)

**Current State:**
Talkie has basic card UI but missing:
1. Logos (Nvidia, OpenAI)
2. "Learn more" links with external URLs
3. Version display on hover
4. Real download progress (currently simulated)
5. Cancel download functionality
6. Resume capability

**Assets to Add:**
```
/Assets/
  NvidiaLogo.png (2x, 3x)
  OpenAILogo.png (2x, 3x)
```

**Components to Build/Enhance:**

1. **ModelSelectionCard**:
   ```
   State:
   @State private var isHovered = false
   @Binding var selectedModel: String?
   let model: ModelInfo

   Visual Structure:
   VStack {
     HStack {
       // Logo
       Image(model.logoAsset)
         .resizable()
         .frame(width: 40, height: 40)

       Spacer()

       // Badge
       Text(model.badge)
         .badge(color: model.badgeColor)
     }

     // Title
     Text(model.name)
       .font(.title2)
       .bold()

     // Subtitle
     Text(model.tagline)
       .foregroundColor(.secondary)

     // Specs table
     VStack(alignment: .leading, spacing: 8) {
       SpecRow(label: "Size", value: model.size)
       SpecRow(label: "Speed", value: model.speed)
       SpecRow(label: "Languages", value: model.languages)
     }

     // Hover-only elements
     if isHovered {
       HStack {
         Text("Version: \(model.version)")
           .font(.caption)
         Spacer()
         Button("Learn more") {
           NSWorkspace.shared.open(model.learnMoreURL)
         }
       }
       .transition(.opacity)
     }

     // Selected checkmark
     if selectedModel == model.id {
       Image(systemName: "checkmark.circle.fill")
         .foregroundColor(.green)
         .position(top right)
     }
   }
   .padding()
   .background(backgroundColor)
   .border(borderColor, width: 2)
   .cornerRadius(12)
   .onHover { isHovered = $0 }
   .onTapGesture {
     selectedModel = model.id
   }

   Computed Properties:
   var backgroundColor: Color {
     if isHovered {
       return Color(hex: "#1F1F1F")
     } else {
       return Color(hex: "#151515")
     }
   }

   var borderColor: Color {
     if selectedModel == model.id {
       return .green
     } else if isHovered {
       return Color(hex: "#2A2A2A")
     } else {
       return Color(hex: "#1A1A1A")
     }
   }
   ```

2. **ModelInfo Struct**:
   ```swift
   struct ModelInfo {
       let id: String
       let name: String
       let tagline: String
       let logoAsset: String
       let badge: String
       let badgeColor: Color
       let size: String
       let speed: String
       let languages: String
       let version: String
       let learnMoreURL: URL
   }

   static let parakeet = ModelInfo(
       id: "parakeet:v3",
       name: "Parakeet v3",
       tagline: "Ultra-fast, English only",
       logoAsset: "NvidiaLogo",
       badge: "RECOMMENDED",
       badgeColor: .green,
       size: "~200 MB",
       speed: "Ultra-fast",
       languages: "English",
       version: "v3",
       learnMoreURL: URL(string: "https://huggingface.co/nvidia/parakeet-tdt-1.1b")!
   )

   static let whisper = ModelInfo(
       id: "whisper:large-v3-turbo",
       name: "Whisper large-v3",
       tagline: "Fast, 99+ languages",
       logoAsset: "OpenAILogo",
       badge: "MULTILINGUAL",
       badgeColor: .blue,
       size: "~1.5 GB",
       speed: "Fast",
       languages: "99+",
       version: "large-v3-turbo",
       learnMoreURL: URL(string: "https://openai.com/research/whisper")!
   )
   ```

3. **DownloadProgressView**:
   ```
   State:
   @ObservedObject var downloadManager: DownloadManager

   Visual:
   VStack(spacing: 12) {
     // Status text
     HStack {
       Text("Downloading \(modelName)...")
       Spacer()
       Text("\(Int(progress * 100))%")
     }
     .font(.system(size: 14, weight: .medium))

     // Progress bar
     GeometryReader { geometry in
       ZStack(alignment: .leading) {
         // Background
         RoundedRectangle(cornerRadius: 4)
           .fill(Color.gray.opacity(0.2))

         // Filled portion
         RoundedRectangle(cornerRadius: 4)
           .fill(Color.green)
           .frame(width: geometry.size.width * progress)
       }
     }
     .frame(height: 8)

     // Details
     HStack {
       Text("\(downloadedMB) MB of \(totalMB) MB")
       Spacer()
       Text("~\(timeRemaining) remaining")
       Spacer()
       Button("Cancel") {
         downloadManager.cancel()
       }
       .foregroundColor(.secondary)
     }
     .font(.system(size: 12))
     .foregroundColor(.secondary)
   }
   ```

4. **Real Download Integration**:

   **CRITICAL: Replace simulated download**

   Current (lines 246-262 in OnboardingCoordinator.swift):
   ```swift
   // ❌ SIMULATED - REPLACE THIS
   func downloadModel() async {
       for i in 0...100 {
           downloadProgress = Double(i) / 100.0
           try? await Task.sleep(for: .milliseconds(50))
       }
   }
   ```

   Replace with:
   ```swift
   func downloadModel() async throws {
       isDownloadingModel = true
       downloadStatus = "Connecting to TalkieEngine..."

       do {
           // Connect to TalkieEngine download API
           let engineClient = TalkieEngineClient.shared

           // Start download with progress streaming
           let progressStream = try await engineClient.downloadModel(
               modelId: selectedModelId,
               onProgress: { progress in
                   Task { @MainActor in
                       self.downloadProgress = progress.fractionCompleted
                       self.downloadStatus = "Downloading... \(Int(progress.fractionCompleted * 100))%"
                   }
               }
           )

           // Wait for completion
           for try await progress in progressStream {
               await MainActor.run {
                   downloadProgress = progress.fractionCompleted
               }
           }

           isModelDownloaded = true
           downloadStatus = "Model ready!"

       } catch {
           errorMessage = "Download failed: \(error.localizedDescription)"
           isModelDownloaded = false
       }

       isDownloadingModel = false
   }

   func cancelDownload() {
       downloadTask?.cancel()
       isDownloadingModel = false
       downloadProgress = 0
       downloadStatus = ""
   }
   ```

**Layout Structure:**
```
OnboardingStepLayout {
    VStack(spacing: 40) {
        // CPU icon with pulsing glow
        ZStack {
            // Glow effect
            Circle()
                .fill(Color.green.opacity(0.2))
                .frame(width: 120, height: 120)
                .scaleEffect(pulseScale)

            // CPU icon
            Image(systemName: "cpu")
                .font(.system(size: 60))
                .foregroundColor(.green)
        }
        .frame(height: 100)

        // Model cards
        HStack(spacing: 20) {
            ModelSelectionCard(
                model: .parakeet,
                selectedModel: $selectedModelType
            )

            ModelSelectionCard(
                model: .whisper,
                selectedModel: $selectedModelType
            )
        }

        // Download progress
        if isDownloadingModel {
            DownloadProgressView(
                progress: downloadProgress,
                modelName: selectedModelDisplayName,
                onCancel: { cancelDownload() }
            )
            .transition(.opacity)
        }

        // Privacy message
        Text("Models are downloaded once and run locally...")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
    }
}
```

**State Management:**
```swift
// Use OnboardingManager properties:
@Published var selectedModelType: String = "parakeet"
@Published var isModelDownloaded: Bool = false
@Published var isDownloadingModel: Bool = false
@Published var downloadProgress: Double = 0
@Published var downloadStatus: String = ""

var selectedModelId: String {
    selectedModelType == "parakeet" ? "parakeet:v3" : "whisper:large-v3-turbo"
}

var selectedModelDisplayName: String {
    selectedModelType == "parakeet" ? "Parakeet v3" : "Whisper large-v3"
}
```

**Validation Logic:**
```swift
var canContinue: Bool {
    isModelDownloaded && !isDownloadingModel
}

// Check if model already installed
func checkModelInstalled() async {
    let engineClient = TalkieEngineClient.shared
    let status = try? await engineClient.getStatus()

    if status?.loadedModel == selectedModelId {
        isModelDownloaded = true
        downloadStatus = "Already installed ✓"
    }
}
```

**Testing Checklist:**
- [ ] Both model cards render correctly with logos
- [ ] Hover shows version and "Learn more" link
- [ ] Click selects model (green border, checkmark)
- [ ] Only one model can be selected at a time
- [ ] "Learn more" opens external URL in browser
- [ ] CPU icon pulses during download
- [ ] Download progress bar updates in real-time
- [ ] Percentage and MB downloaded update correctly
- [ ] Time remaining estimate is reasonable
- [ ] Cancel button stops download immediately
- [ ] Can switch models after canceling
- [ ] Skip download works (if already installed)
- [ ] Continue button enabled only after download completes
- [ ] Error message shows if download fails
- [ ] Resume works if download interrupted

**Migration Notes:**
- ❌ Remove simulated download loop (lines 246-262)
- ✅ Add TalkieEngineClient integration
- ✅ Add model logos to Assets
- ✅ Port ModelSelectionCard from Live
- ✅ Port DownloadProgressView from Live
- ⚠️ Add #warning if real integration not complete

---

## Screen 5: LLM Configuration

### 📺 Screenwriter View (What the User Sees)

**Layout:**
- Top: Grid pattern background
- Center: Sparkles icon (animated)
- Middle: Provider selection OR API key input (two states)
- Bottom: Continue / Skip buttons

**Title:** "Connect Your AI" (optional step)

**Subtitle:** "Enable AI-powered workflows and summaries"

**Icon:**
- Sparkles icon (sparkles)
- Size: 80x80
- Color: Purple gradient when selected, gray when not
- Pulsing animation when provider selected
- Rotating sparkle effect

**State 1: Provider Selection**

Two provider cards:

1. **OpenAI**
   - Layout: Card with hover state
   - Icon: CPU icon in circle - green background
   - Title: "OpenAI"
   - Description: "GPT-4o, GPT-4, GPT-3.5 models"
   - Tag: "Most popular"
   - Selected state: Purple border, checkmark

2. **Anthropic**
   - Layout: Card with hover state
   - Icon: Sparkles icon in circle - purple background
   - Title: "Anthropic"
   - Description: "Claude 3.5 Sonnet, Claude 3 Opus models"
   - Tag: "Latest AI"
   - Selected state: Purple border, checkmark

**Card Interaction:**
- Default: Gray border, white text
- Hover: Lighter background, subtle scale up
- Click: Select provider → transition to API key input
- Selected: Purple border, checkmark in corner

**State 2: API Key Input**

After selecting provider:

- Provider logo/icon at top (OpenAI or Anthropic)
- Title: "Enter your [Provider] API Key"
- Description: "Get your API key from [provider].com/api-keys"
- Link: "Don't have an API key? Sign up →" (opens website)

**API Key Input:**
- Secure text field (password-style, can reveal)
- Placeholder: "sk-..." or "sk-ant-..."
- Eye icon to toggle visibility
- Validation indicator:
  - Gray border while typing
  - Red border if invalid format
  - Green border if valid format
- **Security message (prominent):**
  - Icon: Lock with shield (lock.shield)
  - Text: "Protected by Apple Keychain encryption"
  - Subtext: "Your API key is encrypted using Apple's secure storage and never leaves your device"

**Error States:**
- Empty field: "API key cannot be empty"
- Invalid format: "API key should start with sk- for OpenAI or sk-ant- for Anthropic"
- Connection test failed: "Unable to verify API key. Check your key and internet connection."

**Back Button:**
- "← Choose different provider" - Returns to provider selection

**Buttons:**
- "Continue" - Tests API key, then advances (enabled only with valid format)
- "Skip for now" - Large, clear option
- Helper text under skip: "You can add this later in Settings"

---

### 🎯 Product Manager View (Why This Exists)

**Purpose:**
Allow users to optionally configure AI integrations for advanced features (summaries, smart actions, workflows). Must be clearly optional to avoid onboarding abandonment.

**User Goals:**
- Understand what LLM integration enables
- Choose their preferred AI provider
- Securely configure API key
- Skip easily if not interested now
- Feel confident key is stored securely

**Success Criteria:**
- >40% configure LLM during onboarding
- <5% abandon onboarding at this step
- >95% of those who start configuration complete it
- 0 API keys logged or leaked

**Key Messages:**
1. **Optional**: "Skip for now" is prominent and encouraged
2. **Value**: Unlock AI-powered summaries and workflows
3. **Choice**: Support both major providers (OpenAI, Anthropic)
4. **Security**: "Stored securely in macOS Keychain"
5. **Deferred**: "You can add this later in Settings"

**User Personas:**

*Power user (40%):*
- Already has OpenAI/Anthropic account
- Sees value in AI features immediately
- Selects provider → enters API key
- Continues confidently

*Curious user (30%):*
- Interested in AI features but doesn't have API key
- Clicks "Sign up" link → opens provider website
- Realizes signup required, decides to skip for now
- Plans to configure later

*Basic user (30%):*
- Just wants voice transcription, doesn't care about AI
- Sees "Skip for now" is clear and prominent
- Clicks skip immediately
- Continues without guilt

**User Journey (Configuration Path):**
1. User arrives at screen
2. Reads "Enable AI-powered workflows" and is interested
3. Sees two provider cards
4. Recognizes OpenAI, clicks card
5. Card transitions to API key input
6. Goes to OpenAI website to get API key
7. Copies key, pastes into field
8. Border turns green (valid format detected)
9. Clicks "Continue"
10. App tests connection briefly (1-2 seconds)
11. Success → advances to next step

**User Journey (Skip Path):**
1. User arrives at screen
2. Reads title, not interested in AI features yet
3. Sees large "Skip for now" button
4. Clicks skip immediately
5. Advances to next step (no guilt, no friction)

**Risks to Mitigate:**
- User feels forced to configure → Make skip option very clear
- User abandons because they don't have key → "Skip for now" + can configure later
- API key leaks → Store in Keychain, never log
- User enters invalid key → Validate format before testing
- Connection test takes too long → 5-second timeout
- User confused about which provider → Show clear descriptions

**Feature Enablement:**
With LLM configured, users can:
- Auto-generate summaries of voice memos
- Create smart workflows (e.g., "Email me summary of meetings")
- Ask questions about their memo archive
- Generate titles automatically
- Tag and categorize memos with AI

**Business Metrics:**
- LLM configuration rate: Target 40%
- OpenAI vs Anthropic split: Track for partnership decisions
- Skip rate: Target <60% (want configurators, but skip is okay)
- Post-onboarding configuration: Track how many add later

---

### 🔧 Engineer View (How to Build This)

**Source Files to Reference:**
- No direct equivalent in TalkieLive (this is Talkie-specific)
- Reference provider card pattern from ModelInstallView
- Reference secure input from macOS keychain examples

**Target File:**
- `/Users/arach/dev/talkie/macOS/Talkie/Views/Onboarding/LLMConfigView.swift` (already exists, enhance)

**Current State:**
Talkie has basic implementation but missing:
1. API key format validation
2. Connection testing
3. Keychain integration (TODO in coordinator)
4. Better visual design
5. "Don't have key?" signup links

**Components to Build/Enhance:**

1. **ProviderCard**:
   ```
   State:
   @State private var isHovered = false
   @Binding var selectedProvider: String?
   let provider: ProviderInfo

   Visual Structure:
   VStack(spacing: 16) {
     // Icon
     Image(systemName: provider.icon)
       .font(.system(size: 40))
       .foregroundColor(provider.color)
       .frame(width: 60, height: 60)
       .background(provider.color.opacity(0.2))
       .clipShape(Circle())

     // Title
     Text(provider.name)
       .font(.title2)
       .bold()

     // Description
     Text(provider.description)
       .font(.body)
       .foregroundColor(.secondary)
       .multilineTextAlignment(.center)

     // Tag
     Text(provider.tag)
       .font(.caption)
       .foregroundColor(provider.tagColor)
       .padding(.horizontal, 8)
       .padding(.vertical, 4)
       .background(provider.tagColor.opacity(0.2))
       .cornerRadius(4)

     // Selected checkmark
     if selectedProvider == provider.id {
       Image(systemName: "checkmark.circle.fill")
         .foregroundColor(.purple)
     }
   }
   .padding()
   .frame(maxWidth: .infinity)
   .background(backgroundColor)
   .border(borderColor, width: 2)
   .cornerRadius(12)
   .scaleEffect(isHovered ? 1.02 : 1.0)
   .onHover { isHovered = $0 }
   .onTapGesture {
     withAnimation {
       selectedProvider = provider.id
     }
   }
   ```

2. **ProviderInfo Struct**:
   ```swift
   struct ProviderInfo {
       let id: String
       let name: String
       let description: String
       let tag: String
       let tagColor: Color
       let icon: String
       let color: Color
       let apiKeyPrefix: String
       let signupURL: URL
   }

   static let openai = ProviderInfo(
       id: "openai",
       name: "OpenAI",
       description: "GPT-4o, GPT-4, GPT-3.5 models",
       tag: "Most popular",
       tagColor: .green,
       icon: "cpu",
       color: .green,
       apiKeyPrefix: "sk-",
       signupURL: URL(string: "https://platform.openai.com/api-keys")!
   )

   static let anthropic = ProviderInfo(
       id: "anthropic",
       name: "Anthropic",
       description: "Claude 3.5 Sonnet, Claude 3 Opus models",
       tag: "Latest AI",
       tagColor: .purple,
       icon: "sparkles",
       color: .purple,
       apiKeyPrefix: "sk-ant-",
       signupURL: URL(string: "https://console.anthropic.com/settings/keys")!
   )
   ```

3. **SecureAPIKeyInput**:
   ```
   State:
   @Binding var apiKey: String
   @State private var isSecured = true
   @State private var validationState: ValidationState = .none
   let provider: ProviderInfo

   Visual:
   VStack(alignment: .leading, spacing: 12) {
     // Label
     Text("API Key")
       .font(.system(size: 14, weight: .medium))

     // Input field
     HStack {
       if isSecured {
         SecureField("sk-...", text: $apiKey)
           .textFieldStyle(.plain)
       } else {
         TextField("sk-...", text: $apiKey)
           .textFieldStyle(.plain)
       }

       // Toggle visibility button
       Button {
         isSecured.toggle()
       } label: {
         Image(systemName: isSecured ? "eye" : "eye.slash")
           .foregroundColor(.secondary)
       }
       .buttonStyle(.plain)
     }
     .padding()
     .background(Color(hex: "#1A1A1A"))
     .border(borderColor, width: 2)
     .cornerRadius(8)

     // Validation message
     if case .invalid(let message) = validationState {
       Text(message)
         .font(.caption)
         .foregroundColor(.red)
     }

     // Security message
     HStack(spacing: 4) {
       Image(systemName: "lock.shield")
         .font(.system(size: 10))
       Text("Stored securely in macOS Keychain")
         .font(.caption)
     }
     .foregroundColor(.secondary)

     // Signup link
     Button {
       NSWorkspace.shared.open(provider.signupURL)
     } label: {
       HStack(spacing: 4) {
         Text("Don't have an API key?")
         Text("Sign up →")
           .foregroundColor(.purple)
       }
       .font(.caption)
     }
     .buttonStyle(.plain)
   }
   .onChange(of: apiKey) { _, newValue in
       validateAPIKey(newValue)
   }

   var borderColor: Color {
       switch validationState {
       case .none: return Color(hex: "#2A2A2A")
       case .valid: return .green
       case .invalid: return .red
       }
   }

   enum ValidationState {
       case none
       case valid
       case invalid(String)
   }
   ```

4. **API Key Validation**:
   ```swift
   func validateAPIKey(_ key: String) {
       guard !key.isEmpty else {
           validationState = .none
           return
       }

       // Format validation
       let expectedPrefix = selectedProvider == "openai" ? "sk-" : "sk-ant-"

       if !key.hasPrefix(expectedPrefix) {
           validationState = .invalid("API key should start with \(expectedPrefix)")
           return
       }

       // Length validation
       if key.count < 20 {
           validationState = .invalid("API key is too short")
           return
       }

       validationState = .valid
   }
   ```

5. **Connection Testing** (when Continue clicked):
   ```swift
   func testConnection() async -> Bool {
       guard case .valid = validationState else {
           return false
       }

       isTesting = true

       do {
           // Test API key with minimal request
           if selectedProvider == "openai" {
               let client = OpenAIClient(apiKey: apiKey)
               _ = try await client.testConnection() // GET /v1/models endpoint
           } else {
               let client = AnthropicClient(apiKey: apiKey)
               _ = try await client.testConnection() // GET /v1/messages endpoint
           }

           // Store in keychain
           try await KeychainManager.shared.storeAPIKey(
               provider: selectedProvider!,
               key: apiKey
           )

           hasConfiguredLLM = true
           isTesting = false
           return true

       } catch {
           errorMessage = "Unable to verify API key: \(error.localizedDescription)"
           isTesting = false
           return false
       }
   }
   ```

6. **KeychainManager Integration**:
   ```swift
   // Replace TODO in OnboardingCoordinator.swift:266-273
   func configureLLM(provider: String, apiKey: String) async throws {
       // Validate format first
       guard validateAPIKeyFormat(provider: provider, key: apiKey) else {
           throw LLMConfigError.invalidFormat
       }

       // Test connection
       guard await testConnection(provider: provider, key: apiKey) else {
           throw LLMConfigError.connectionFailed
       }

       // Store in keychain
       try KeychainManager.shared.store(
           key: apiKey,
           service: "com.talkie.llm.\(provider)",
           account: provider
       )

       // Update state
       self.llmProvider = provider
       self.hasConfiguredLLM = true
   }
   ```

**Layout Structure:**
```
OnboardingStepLayout {
    VStack(spacing: 40) {
        // Sparkles icon
        SparklesIcon(isActive: llmProvider != nil)
            .frame(height: 100)

        if selectedProvider == nil {
            // Provider selection state
            VStack(spacing: 24) {
                Text("Choose your AI provider")
                    .font(.headline)

                HStack(spacing: 20) {
                    ProviderCard(
                        provider: .openai,
                        selectedProvider: $selectedProvider
                    )

                    ProviderCard(
                        provider: .anthropic,
                        selectedProvider: $selectedProvider
                    )
                }
            }
            .transition(.opacity)

        } else {
            // API key input state
            VStack(spacing: 24) {
                // Back button
                Button {
                    withAnimation {
                        selectedProvider = nil
                        apiKey = ""
                    }
                } label: {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Choose different provider")
                    }
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)

                // API key input
                SecureAPIKeyInput(
                    apiKey: $apiKey,
                    provider: selectedProviderInfo
                )
                .frame(maxWidth: 400)

                // Testing indicator
                if isTesting {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Verifying API key...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .transition(.opacity)
        }
    }
}
```

**State Management:**
```swift
// Use OnboardingManager properties:
@Published var llmProvider: String? = nil
@Published var hasConfiguredLLM: Bool = false

// Add to view state:
@State private var selectedProvider: String? = nil
@State private var apiKey: String = ""
@State private var validationState: ValidationState = .none
@State private var isTesting: Bool = false
@State private var errorMessage: String? = nil

var selectedProviderInfo: ProviderInfo {
    selectedProvider == "openai" ? .openai : .anthropic
}
```

**Validation Logic:**
```swift
var canContinue: Bool {
    if selectedProvider == nil {
        // On provider selection screen
        return false // Must select provider first
    } else {
        // On API key input screen
        return case .valid = validationState && !isTesting
    }
}
```

**Testing Checklist:**
- [ ] Both provider cards render correctly
- [ ] Click selects provider and transitions to input
- [ ] Back button returns to provider selection
- [ ] API key input shows/hides with eye icon
- [ ] Validation shows red border for invalid format
- [ ] Validation shows green border for valid format
- [ ] Signup link opens provider website
- [ ] Connection test runs on Continue click
- [ ] Success stores key in Keychain
- [ ] Failure shows error message
- [ ] Skip button always available and clear
- [ ] "Configure later" message under skip
- [ ] No API keys logged to console
- [ ] Keychain storage encrypted
- [ ] API key cleared from memory after storage

**Security Checklist:**
- [ ] API key stored in Keychain (not UserDefaults)
- [ ] API key never logged (even in debug mode)
- [ ] Secure text field used (password-style)
- [ ] Key cleared from memory after use
- [ ] HTTPS only for connection tests
- [ ] No key in error messages
- [ ] No key in crash reports

**Migration Notes:**
- ✅ Keep existing two-step UI (provider → key)
- ❌ Remove basic non-empty validation (too weak)
- ✅ Add format validation (prefix checking)
- ✅ Add connection testing on Continue
- ⚠️ Must implement KeychainManager before shipping
- ⚠️ Add #warning if keychain integration not complete

---

## Screen 6: Complete

### 📺 Screenwriter View (What the User Sees)

**Layout:**
- Top: Grid pattern background
- Center: Large checkmark icon (animated entrance)
- Middle: Two-column layout (keyboard shortcut + pill demo)
- Bottom: Quick tips + Get Started button

**Title:** "You're All Set!"

**Subtitle:** "Start recording with these methods"

**Icon:**
- Checkmark in circle (checkmark.circle.fill)
- Size: 80x80
- Color: Green
- Entrance animation: Bounce effect (scale 0 → 1.2 → 1.0)
- Subtle pulsing glow

**Recording Methods (Two Columns):**

**Left Column: Keyboard Shortcut**
- Title: "Keyboard Shortcut"
- Large visual: Three keys (⌥ ⌘ L) in rounded rectangles
- Keys specs:
  - Size: 48x48 each
  - Background: Dark gray (#1A1A1A)
  - Border: Light gray (#2A2A2A)
  - Text: White, SF Symbols
  - Spacing: 8px between keys
- Description: "Press ⌥⌘L from anywhere to start/stop recording"
- Sublabel: "Works in any app"

**Right Column: Always-On Pill**
- Title: "Always-On Pill"
- Interactive demo pill at bottom center of screen
- Pill specs:
  - Size: 120x40 (resting), expands on hover
  - Position: Bottom center, 20px from bottom edge
  - Behavior: Same as Welcome screen demo
  - Tooltip on hover: "This is just a demo! Real pill is below ↓"
- Description: "Click the pill at the bottom of your screen"
- Sublabel: "Always visible, one click away"

**Interactive Demo Pill:**
- Resting: Gray, small (120x40)
- Hover: Expands, shows tooltip
- Click: Starts demo recording (not real)
  - Shows timer counting
  - Waveform animation
  - REC indicator pulsing
- Click again: Stops demo
- Tooltip appears: "Nice! Now try with the real pill below"

**Quick Tips (Below methods):**
Chip-style tips in horizontal row:

1. **Hotkey tip**
   - Icon: keyboard
   - Text: "Press ⌥⌘L to start/stop recording from anywhere"

2. **Search tip**
   - Icon: magnifyingglass
   - Text: "Use Search (⌘F) to find your memos quickly"

3. **Settings tip**
   - Icon: gear
   - Text: "Customize settings and workflows anytime"

**First Recording Celebration:**
When user makes their first real recording (detected via notification):
- Pill demo disappears
- Large celebration overlay appears:
  - Party popper animation (🎉)
  - Text: "NICE! Your first recording!"
  - Confetti animation
  - Auto-dismisses after 2 seconds
  - Onboarding auto-closes, switches to Recent view

**Buttons:**
- "Get Started" - Large, pulsing green button
- Closes onboarding, opens main app to Home/Recent view

---

### 🎯 Product Manager View (Why This Exists)

**Purpose:**
Congratulate user on completing onboarding, reinforce the two primary interaction methods, and encourage immediate first use with interactive demo.

**User Goals:**
- Feel accomplished and ready to use the app
- Remember the keyboard shortcut (⌥⌘L)
- Understand the always-on pill option
- Try their first recording with confidence
- Access quick reference tips

**Success Criteria:**
- >80% interact with demo pill before clicking "Get Started"
- >60% make first recording within 2 minutes of completing onboarding
- >90% remember keyboard shortcut after 1 day (measured by usage)
- <5% confusion about how to start recording post-onboarding

**Key Messages:**
1. **Success**: "You're all set!" - positive reinforcement
2. **Two methods**: Keyboard shortcut OR pill - user chooses
3. **Practice**: Interactive demo encourages trying it
4. **Celebration**: First recording is celebrated (delight)
5. **Reference**: Quick tips for common actions

**User Journey (Interactive Path - Preferred):**
1. User arrives at screen
2. Sees checkmark bounce in with green glow
3. Reads "You're all set!" and feels accomplished
4. Sees two recording methods side-by-side
5. Notices interactive pill demo in right column
6. Hovers over demo pill → tooltip appears
7. Clicks demo pill → starts "recording"
8. Sees timer count, waveform animate
9. Clicks again to stop
10. Tooltip: "Nice! Now try with the real pill below"
11. Looks at bottom of screen, sees real pill
12. Feels confident about how it works
13. Clicks "Get Started"
14. Onboarding closes, main app opens
15. (Later) Presses ⌥⌘L to make first real recording
16. Celebration overlay appears with confetti
17. Onboarding completes, switches to Recent view

**User Journey (Quick Path):**
1. User arrives at screen
2. Reads content quickly
3. Clicks "Get Started" immediately
4. (Later) Tries recording, succeeds
5. Celebration appears

**Risks to Mitigate:**
- User forgets keyboard shortcut → Large visual reminder
- User doesn't know where pill is → Demo shows exact location
- User confused by demo vs. real pill → Clear tooltip distinction
- User never tries recording → Demo encourages practice
- User doesn't see celebration → Make it prominent and auto-trigger

**Feature Education:**
This screen reinforces:
- **Primary**: Keyboard shortcut (⌥⌘L) for power users
- **Secondary**: Pill button for mouse users
- **Tertiary**: Search, settings, workflows (quick tips)

**Success Metrics:**
- Demo interaction rate: Target >80%
- First recording within 2 minutes: Target >60%
- First recording within 1 hour: Target >90%
- Keyboard shortcut usage (vs. pill): Target >70% after 1 week
- Return to app after onboarding: Target >95%

---

### 🔧 Engineer View (How to Build This)

**⚠️ IMPORTANT: PORT EXISTING COMPONENTS - DON'T REBUILD**

The interactive pill demo and celebration animations already exist in TalkieLive and are polished. Your job is to **copy and integrate** them into Talkie's CompleteView, not rebuild from scratch.

**Source Files to Port from TalkieLive:**
- `OnboardingPillDemo.swift` - **Copy entire interactive demo component**
- `CelebrationView.swift` - **Copy entire celebration with confetti**
- Keyboard shortcut display components (if separate file)
- Any supporting views, animations, or helpers these depend on

**Target File:**
- `/Users/arach/dev/talkie/macOS/Talkie/Views/Onboarding/CompleteView.swift` (already exists, major enhancements needed)

**Current State:**
Talkie has basic completion screen with:
- Checkmark icon with bounce ✅ (keep this)
- Three tips in simple list ✅ (keep this)
- "Get Started" button ✅ (keep this)

Missing:
- Two-column layout (keyboard + pill demo)
- Interactive pill demo from Live
- Celebration on first recording from Live
- Notification integration
- Auto-dismiss and switch to Recent view

**Implementation Steps:**

1. **Copy Interactive Components**: Locate `OnboardingPillDemo` and `CelebrationView` in TalkieLive and copy to Talkie
2. **Add to Xcode Project**: Ensure all copied files are added to the Talkie target
3. **Update Imports**: Change any TalkieLive-specific imports to Talkie equivalents
4. **Integrate into CompleteView**: Add two-column layout with keyboard shortcut + pill demo
5. **Add Notification Listeners**: Set up `.onReceive` for first recording detection
6. **Add Celebration Overlay**: Show celebration when first recording completes
7. **Test**: Verify demo works and celebration appears on first recording

**Integration Pattern:**
```swift
// In CompleteView.swift
OnboardingStepLayout {
    VStack(spacing: 40) {
        // Checkmark (keep existing)
        CheckmarkIcon()

        // Two-column recording methods
        HStack(spacing: 24) {
            // Keyboard shortcut display (build new, simple)
            KeyboardShortcutDisplay()

            // Interactive pill demo (PORT FROM LIVE)
            OnboardingPillDemo()  // ← Copy this entire component from Live
        }

        // Quick tips (keep existing, update copy)
        QuickTips()
    }
}
.overlay {
    if showCelebration {
        CelebrationView()  // ← Copy this entire component from Live
            .transition(.opacity)
    }
}
.onReceive(NotificationCenter.default.publisher(for: .recordingDidStart)) { _ in
    if !hasSeenCelebration {
        hasSeenCelebration = true
        showCelebration = true
    }
}
```

**What NOT to Do:**
- ❌ Don't rebuild the pill demo from scratch
- ❌ Don't rebuild the celebration animation
- ❌ Don't change confetti physics or timing
- ❌ Don't simplify or remove delightful details

**What TO Do:**
- ✅ Copy `OnboardingPillDemo` component verbatim
- ✅ Copy `CelebrationView` component verbatim
- ✅ Build simple keyboard shortcut display (just 3 keys in boxes)
- ✅ Add notification integration for first recording
- ✅ Test celebration appears and auto-dismisses

**Reference Implementation:**
The components already exist in TalkieLive's onboarding (search for "OnboardingPillDemo" and "CelebrationView")

**For Context Only - Component Details (already implemented in Live):**

1. **CheckmarkIcon** (enhanced):
   ```
   State:
   @State private var scale: CGFloat = 0
   @State private var glowOpacity: Double = 0

   Visual:
   ZStack {
     // Glow effect
     Circle()
       .fill(Color.green.opacity(glowOpacity))
       .frame(width: 120, height: 120)
       .blur(radius: 20)

     // Checkmark
     Image(systemName: "checkmark.circle.fill")
       .font(.system(size: 80))
       .foregroundColor(.green)
       .scaleEffect(scale)
   }
   .onAppear {
     // Bounce entrance
     withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
       scale = 1.0
     }

     // Glow pulse
     withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
       glowOpacity = 0.3
     }
   }
   ```

2. **KeyboardShortcutDisplay**:
   ```
   Visual:
   VStack(spacing: 16) {
     Text("Keyboard Shortcut")
       .font(.headline)

     // Keys
     HStack(spacing: 8) {
       KeyView(symbol: "⌥")
       KeyView(symbol: "⌘")
       KeyView(symbol: "L")
     }

     Text("Press ⌥⌘L from anywhere to start/stop recording")
       .font(.body)
       .foregroundColor(.secondary)
       .multilineTextAlignment(.center)

     Text("Works in any app")
       .font(.caption)
       .foregroundColor(.secondary)
   }
   .frame(maxWidth: .infinity)
   .padding()
   .background(Color(hex: "#151515"))
   .cornerRadius(12)
   ```

3. **KeyView**:
   ```
   let symbol: String

   Visual:
   Text(symbol)
     .font(.system(size: 24, weight: .medium))
     .foregroundColor(.white)
     .frame(width: 48, height: 48)
     .background(Color(hex: "#1A1A1A"))
     .overlay(
       RoundedRectangle(cornerRadius: 8)
         .stroke(Color(hex: "#2A2A2A"), lineWidth: 1)
     )
     .cornerRadius(8)
   ```

4. **PillDemoDisplay**:
   ```
   State:
   @State private var isRecording = false
   @State private var recordingDuration: TimeInterval = 0
   @State private var showTooltip = false
   @State private var hasInteracted = false

   Visual:
   VStack(spacing: 16) {
     Text("Always-On Pill")
       .font(.headline)

     // Demo pill (interactive)
     OnboardingPillDemo(
       isRecording: $isRecording,
       duration: $recordingDuration,
       showTooltip: $showTooltip,
       onInteraction: {
         hasInteracted = true
       }
     )
     .frame(height: 60)

     Text("Click the pill at the bottom of your screen")
       .font(.body)
       .foregroundColor(.secondary)
       .multilineTextAlignment(.center)

     Text("Always visible, one click away")
       .font(.caption)
       .foregroundColor(.secondary)
   }
   .frame(maxWidth: .infinity)
   .padding()
   .background(Color(hex: "#151515"))
   .cornerRadius(12)
   ```

5. **OnboardingPillDemo** (port from Live):
   ```
   @Binding var isRecording: Bool
   @Binding var duration: TimeInterval
   @Binding var showTooltip: Bool
   var onInteraction: () -> Void

   State:
   @State private var isHovered = false
   @State private var timer: Timer?

   Visual:
   ZStack {
     // Pill button
     HStack(spacing: 8) {
       if isRecording {
         // Recording state
         Circle()
           .fill(Color.red)
           .frame(width: 8, height: 8)
         Text("REC")
           .font(.system(size: 12, weight: .bold))
         WaveformView()
         Text(formatDuration(duration))
           .font(.system(size: 12, .monospacedDigit))
       } else {
         // Resting state
         Image(systemName: "waveform")
         Text("Click to try")
           .font(.system(size: 12))
       }
     }
     .padding(.horizontal, 16)
     .padding(.vertical, 8)
     .background(isRecording ? Color.red.opacity(0.2) : Color(hex: "#1F1F1F"))
     .cornerRadius(20)
     .scaleEffect(isHovered ? 1.1 : 1.0)
     .onHover { isHovered = $0 }
     .onTapGesture {
       toggleRecording()
       onInteraction()
     }

     // Tooltip
     if showTooltip && isHovered {
       VStack {
         Text(hasInteracted ? "Nice! Now try with the real pill below ↓" : "This is just a demo! Real pill is below ↓")
           .font(.caption)
           .padding(8)
           .background(Color.black.opacity(0.8))
           .cornerRadius(8)
         Spacer()
       }
       .offset(y: -50)
       .transition(.opacity)
     }
   }

   func toggleRecording() {
     isRecording.toggle()

     if isRecording {
       // Start timer
       duration = 0
       timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
         duration += 0.1
       }
     } else {
       // Stop timer
       timer?.invalidate()
       timer = nil
       duration = 0
     }
   }
   ```

6. **QuickTips**:
   ```
   Visual:
   VStack(alignment: .leading, spacing: 12) {
     Text("Quick Tips")
       .font(.headline)

     VStack(alignment: .leading, spacing: 8) {
       TipRow(
         icon: "keyboard",
         text: "Press ⌥⌘L to start/stop recording from anywhere"
       )
       TipRow(
         icon: "magnifyingglass",
         text: "Use Search (⌘F) to find your memos quickly"
       )
       TipRow(
         icon: "gear",
         text: "Customize settings and workflows anytime"
       )
     }
   }

   struct TipRow: View {
       let icon: String
       let text: String

       var body: some View {
           HStack(spacing: 12) {
               Image(systemName: icon)
                   .font(.system(size: 16))
                   .foregroundColor(.green)
                   .frame(width: 24)

               Text(text)
                   .font(.system(size: 13))
                   .foregroundColor(.secondary)
           }
       }
   }
   ```

7. **CelebrationView** (first recording):
   ```
   State:
   @State private var confettiPieces: [ConfettiPiece] = []
   @State private var showPartyPopper = false

   Visual:
   ZStack {
     // Dark overlay
     Color.black.opacity(0.6)
       .ignoresSafeArea()

     VStack(spacing: 24) {
       // Party popper
       Text("🎉")
         .font(.system(size: 100))
         .scaleEffect(showPartyPopper ? 1.0 : 0)
         .rotationEffect(.degrees(showPartyPopper ? 0 : -45))

       // Message
       Text("NICE!")
         .font(.system(size: 48, weight: .bold))
         .foregroundColor(.green)

       Text("Your first recording!")
         .font(.title2)
         .foregroundColor(.white)
     }

     // Confetti animation
     ForEach(confettiPieces) { piece in
       ConfettiPieceView(piece: piece)
     }
   }
   .onAppear {
     withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
       showPartyPopper = true
     }

     // Spawn confetti
     for _ in 0..<50 {
       confettiPieces.append(ConfettiPiece())
     }

     // Auto-dismiss after 2 seconds
     DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
       // Close onboarding
       OnboardingManager.shared.completeOnboarding()
       // Switch to Recent view
       NotificationCenter.default.post(name: .switchToRecent, object: nil)
     }
   }

   struct ConfettiPiece: Identifiable {
       let id = UUID()
       let color: Color = [.red, .green, .blue, .yellow, .purple].randomElement()!
       let x: CGFloat = CGFloat.random(in: -200...200)
       let y: CGFloat = CGFloat.random(in: -400...0)
       let rotation: Double = Double.random(in: 0...360)
   }
   ```

8. **Notification Integration**:
   ```swift
   // Listen for first recording
   .onReceive(NotificationCenter.default.publisher(for: .recordingDidStart)) { _ in
       if !hasSeenCelebration {
           hasSeenCelebration = true
           showCelebration = true
       }
   }

   // Define notification
   extension Notification.Name {
       static let recordingDidStart = Notification.Name("recordingDidStart")
       static let switchToRecent = Notification.Name("switchToRecent")
   }
   ```

**Layout Structure:**
```
OnboardingStepLayout {
    VStack(spacing: 40) {
        // Checkmark icon
        CheckmarkIcon()
            .frame(height: 100)

        // Title
        VStack(spacing: 8) {
            Text("You're All Set!")
                .font(.system(size: 32, weight: .bold))
            Text("Start recording with these methods")
                .font(.body)
                .foregroundColor(.secondary)
        }

        // Two-column recording methods
        HStack(spacing: 24) {
            KeyboardShortcutDisplay()
            PillDemoDisplay()
        }
        .padding(.vertical)

        // Quick tips
        QuickTips()
            .frame(maxWidth: 500)
    }
}
.overlay {
    if showCelebration {
        CelebrationView()
            .transition(.opacity)
    }
}
```

**State Management:**
```swift
// Use OnboardingManager:
@Published var hasCompletedOnboarding: Bool

// View state:
@State private var showCelebration = false
@State private var hasSeenCelebration = false
@State private var demoIsRecording = false
@State private var demoDuration: TimeInterval = 0
```

**Testing Checklist:**
- [ ] Checkmark bounces in on appear
- [ ] Checkmark has pulsing glow
- [ ] Keyboard keys render correctly
- [ ] Demo pill responds to hover
- [ ] Demo pill toggles recording on click
- [ ] Demo pill shows timer when recording
- [ ] Demo pill shows waveform when recording
- [ ] Tooltip appears on hover
- [ ] Tooltip changes after interaction
- [ ] Quick tips render correctly
- [ ] "Get Started" closes onboarding
- [ ] Notification listener fires on first recording
- [ ] Celebration appears with confetti
- [ ] Celebration auto-dismisses after 2s
- [ ] App switches to Recent view after celebration
- [ ] OnboardingManager marks completion

**Migration Notes:**
- ✅ Keep existing completion layout as base
- ✅ Add two-column recording methods
- ✅ Port interactive pill demo from Live
- ✅ Port celebration view from Live
- ✅ Add notification listeners
- ⚠️ Ensure .recordingDidStart is posted by TalkieLive
- ⚠️ Test auto-switch to Recent view

---

## Implementation Summary

### Files to Create:
None - all exist already

### Files to Modify:
1. `WelcomeView.swift` - Add pill animation demo
2. `PermissionsSetupView.swift` - Add pulsing shield, colored icons
3. `ServiceSetupView.swift` - Add rotating gears, auto-launch
4. `ModelInstallView.swift` - Add logos, hover states, real download
5. `LLMConfigView.swift` - Add validation, connection test, keychain
6. `CompleteView.swift` - Add two-column layout, pill demo, celebration

### Assets to Add:
- NvidiaLogo.png (2x, 3x)
- OpenAILogo.png (2x, 3x)

### Components to Port from TalkieLive:
- PillDemoAnimation
- WaveformDemoView
- KeyboardShortcutView
- ClickRippleEffect
- OnboardingPillDemo
- CelebrationView
- ConfettiAnimation

### Critical Integrations Required:
1. TalkieEngineClient.downloadModel() - Real model download
2. KeychainManager.store() - Secure API key storage
3. NotificationCenter .recordingDidStart - First recording detection
4. Auto-switch to Recent view - Post-onboarding navigation

### Estimated Complexity:
- Screen 1 (Welcome): High - Complex animation
- Screen 2 (Permissions): Low - Minor enhancements
- Screen 3 (Service Setup): Medium - Auto-launch logic
- Screen 4 (Model Install): High - Real download integration
- Screen 5 (LLM Config): Medium - Validation + keychain
- Screen 6 (Complete): High - Interactive demo + celebration

### Testing Priority:
1. Real model download (critical path)
2. API key security (privacy/security)
3. First recording celebration (UX delight)
4. All animations smooth at 60fps
5. No memory leaks in polling/timers
