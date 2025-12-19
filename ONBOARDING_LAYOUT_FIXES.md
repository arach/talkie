# Onboarding Layout Fixes

Based on storyboard analysis with layout grid overlay.

## Layout Zones (Current)
- **HEADER**: 44px (blue) - Top status/icon area
- **CONTENT**: Middle (green) - Main content area
- **FOOTER**: 40px (orange) - Action button area

Total height: 560px
- Header: 0-44px
- Content: 44-520px (476px)
- Footer: 520-560px (40px)

## Issues Identified

### 1. Button Positioning (CRITICAL)
**Problem**: Action buttons ("Continue", "Next Step", etc.) are at inconsistent Y positions across screens.

**Current State**:
- Buttons float within content area
- No standardized bottom padding
- Different screens = different button heights

**Fix**:
```swift
// In each onboarding view
VStack {
    // Header (44px)
    Color.clear.frame(height: 44)

    // Content (flexible)
    ScrollView {
        contentView
    }
    .frame(maxHeight: .infinity)

    // Footer (40px fixed)
    Button("Continue") { }
        .frame(height: 40)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.xl)
}
```

### 2. Header Icon Consistency
**Problem**: Top icons are at varying Y positions (some at 8px, others at 12px, etc.)

**Fix**:
- Standardize header area as fixed 44px
- Icon should be vertically centered in header (22px from top)
- Use consistent `Spacer()` or `.frame(height: 44)` for header

```swift
// Consistent header pattern
HStack {
    Spacer()
    Image(systemName: "checkmark.circle")
        .font(.system(size: 20))
        .foregroundColor(.green)
    Spacer()
}
.frame(height: 44)
```

### 3. Title Positioning
**Problem**: Main titles start at different Y positions

**Fix**:
- Title should start immediately after 44px header zone
- Add consistent top padding: `Spacing.xl` (24px?)
- Title baseline should be at ~68px for all screens

```swift
VStack(spacing: 0) {
    // Header
    headerView.frame(height: 44)

    // Title area
    Text("SCREEN TITLE")
        .font(.title)
        .padding(.top, Spacing.xl)  // Consistent!

    // Rest of content
    contentView
}
```

### 4. Content Vertical Centering
**Problem**: Content density varies - some screens pack content high, others center it

**Current Examples**:
- Screen 4 (AI Models): 3 cards packed toward top
- Screen 5 (Live Mode): Content nicely centered with equal spacing

**Fix Decision Needed**:

**Option A: Top-Aligned Content** (Recommended for scrollable content)
```swift
VStack(alignment: .leading, spacing: Spacing.md) {
    title
    subtitle
    contentItems
    Spacer()  // Push everything to top
    actionButton
}
```

**Option B: Centered Content** (Recommended for sparse content)
```swift
VStack(spacing: Spacing.md) {
    Spacer()
    title
    subtitle
    contentItems
    Spacer()
    actionButton.padding(.bottom, Spacing.xl)
}
```

**Recommendation**: Use **Option A** (top-aligned) for consistency and to handle varying content amounts.

### 5. Content Padding Consistency
**Problem**: Horizontal padding differs across screens

**Fix**:
- Use consistent horizontal padding: `Spacing.xl` (24px?) on all screens
- Maintain same left/right margins for:
  - Titles
  - Body text
  - Cards
  - Buttons

### 6. Footer Button Styling
**Problem**: Button appears to have different padding/height in different screens

**Fix**:
```swift
Button(action: onNext) {
    Text("Continue")
        .frame(maxWidth: .infinity)
        .frame(height: 40)  // Fixed height
}
.buttonStyle(.borderedProminent)
.padding(.horizontal, Spacing.xl)
.padding(.bottom, Spacing.sm)  // Small bottom padding
```

## Implementation Plan

### Phase 1: Define Standard Layout Constants
In `OnboardingConstants.swift` or `Spacing.swift`:

```swift
struct OnboardingLayout {
    static let headerHeight: CGFloat = 44
    static let footerHeight: CGFloat = 40
    static let buttonHeight: CGFloat = 40
    static let contentTopPadding: CGFloat = 24
    static let horizontalPadding: CGFloat = 24
}
```

### Phase 2: Create Standard Container
In `OnboardingContainer.swift`:

```swift
struct OnboardingContainer<Content: View>: View {
    let headerIcon: String
    let content: Content

    var body: some View {
        VStack(spacing: 0) {
            // Header (44px)
            HStack {
                Spacer()
                Image(systemName: headerIcon)
                    .font(.system(size: 20))
                Spacer()
            }
            .frame(height: OnboardingLayout.headerHeight)

            // Content (flexible)
            ScrollView {
                content
                    .padding(.top, OnboardingLayout.contentTopPadding)
                    .padding(.horizontal, OnboardingLayout.horizontalPadding)
            }
            .frame(maxHeight: .infinity)
        }
    }
}
```

### Phase 3: Update Each Screen

**WelcomeView.swift**:
```swift
OnboardingContainer(headerIcon: "waveform") {
    VStack(spacing: Spacing.lg) {
        Text("VOICE MEMOS\n+ AI")
            .font(.largeTitle)
            .multilineTextAlignment(.center)

        Text("Transform your voice memos...")
            .font(.body)
            .multilineTextAlignment(.center)
            .foregroundColor(.secondary)

        Spacer()

        Button("Get started") { onNext() }
            .frame(height: OnboardingLayout.buttonHeight)
            .frame(maxWidth: .infinity)
    }
}
```

Apply same pattern to:
- PermissionsSetupView
- ModelInstallView
- LLMConfigView
- LiveModePitchView
- StatusCheckView
- CompleteView

### Phase 4: Test & Regenerate Storyboard
1. Build app
2. Run `--debug=onboarding-storyboard`
3. Verify:
   - ✅ All buttons at same Y position
   - ✅ All header icons at same Y position
   - ✅ All titles start at same Y position
   - ✅ Consistent horizontal padding
   - ✅ Grid zones properly utilized

## Success Criteria

After fixes, the storyboard should show:
- All action buttons aligned to **520px baseline** (top of footer zone)
- All header icons vertically centered at **22px** (center of header zone)
- All main titles starting at **68px** (44px header + 24px padding)
- All content using consistent **24px horizontal padding**
- Content properly utilizing the green CONTENT zone without bleeding into HEADER/FOOTER

## Notes

- The layout grid revealed these issues immediately - exactly what we built it for! 🎉
- Focus on **button alignment** first - that's the most noticeable issue
- Consider making OnboardingContainer reusable for future flows
- After fixing, we can adjust zone heights if needed (e.g., make header 48px instead of 44px)
