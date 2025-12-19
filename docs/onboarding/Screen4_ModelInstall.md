# Screen 4: Model Install

> Choose AI model and start non-blocking download

## What User Sees

**Layout**: Grid background → Icon → Model choice cards → Continue button

**Title**: "Choose Your AI Model"

**Subtitle**: "Select the model that best fits your needs"

**Icon**: Brain with circuit (brain.head.profile) - 80x80, pulsing

**Model Cards** (two options):

### Option 1: Parakeet v3 (Recommended)
- **Logo**: Parakeet logo image (colorful bird icon)
- **Badge**: "RECOMMENDED" (green)
- **Title**: "Parakeet v3"
- **Tagline**: "Fast, accurate, optimized for macOS"
- **Size**: "~450 MB"
- **Features**:
  - ✓ Optimized for Apple Silicon
  - ✓ Low memory usage
  - ✓ Excellent accuracy
  - ✓ Fast processing
- **Best for**: "Most users - balanced performance"
- **Learn more**: Link to Parakeet info page
- Selected state: Green border, checkmark

### Option 2: Whisper large-v3
- **Logo**: OpenAI Whisper logo
- **Badge**: "ADVANCED" (blue)
- **Title**: "Whisper large-v3"
- **Tagline**: "Maximum accuracy, larger size"
- **Size**: "~1.5 GB"
- **Features**:
  - ✓ State-of-the-art accuracy
  - ✓ Multi-language support
  - ✓ Technical terminology
  - ✓ Longer audio clips
- **Best for**: "Power users - need maximum accuracy"
- **Learn more**: Link to Whisper info page
- Selected state: Blue border, checkmark

**Download Status** (appears after selection):
- Progress bar with percentage (e.g., "Downloading... 23%")
- Download speed (e.g., "4.2 MB/s")
- Time remaining estimate (e.g., "~2 minutes remaining")
- Can be minimized/dismissed

**Buttons**:
- **Continue** (enabled immediately after selection, doesn't wait for download)
- **Skip for now** (subtle link - can choose model later in Settings)

**Helper text**: "Download happens in background - you can continue setup"

**Skip behavior**: If user clicks Continue before download starts, download begins and continues in background while user proceeds to next screen.

---

## Why This Exists

**Purpose**: Let users choose the AI model that fits their needs while not blocking onboarding flow on download time. Download starts immediately but user can proceed - status will be checked on Screen 5.

**User Goals**:
- Understand difference between models (speed vs accuracy tradeoff)
- Make informed choice based on their needs
- See download progress (reassurance something is happening)
- Not waste time waiting for download
- Feel confident they chose the right model

**Success Criteria**:
- >75% choose Parakeet (recommended default)
- >90% understand model differences
- <10% wait for download to complete before clicking Continue
- Download completes within 5 minutes (typical network)
- 0% confusion about which model to pick

**Key Messages**:
1. **Choice**: Pick what's right for you (most → Parakeet)
2. **Non-blocking**: Don't wait - continue setup
3. **Informed**: Clear tradeoffs (size vs accuracy)
4. **Reversible**: Can change in Settings later

**User Personas**:

*Typical user (75%)*:
- Sees "RECOMMENDED" badge on Parakeet
- Reads "Most users" label
- Clicks Parakeet, sees download start
- Clicks Continue immediately
- Moves to Status screen while download continues

*Power user (25%)*:
- Reads both cards
- Sees Whisper has "Maximum accuracy"
- Understands larger download tradeoff
- Chooses Whisper deliberately
- May wait to see download progress, or proceeds

---

## How to Build

**Target**: `/Users/arach/dev/talkie/macOS/Talkie/Views/Onboarding/ModelInstallView.swift`

**State Management** (in OnboardingCoordinator):
```swift
@Published var selectedModel: AIModel = .parakeet  // Default
@Published var modelDownloadProgress: Double = 0.0  // 0.0 to 1.0
@Published var downloadSpeed: String = ""
@Published var isDownloading: Bool = false
@Published var isModelInstalled: Bool = false
```

**Model Enum**:
```swift
enum AIModel: String, CaseIterable {
    case parakeet = "Parakeet v3"
    case whisper = "Whisper large-v3"

    var size: String {
        switch self {
        case .parakeet: return "~450 MB"
        case .whisper: return "~1.5 GB"
        }
    }

    var tagline: String {
        switch self {
        case .parakeet: return "Fast, accurate, optimized for macOS"
        case .whisper: return "Maximum accuracy, larger size"
        }
    }

    var badge: String {
        switch self {
        case .parakeet: return "RECOMMENDED"
        case .whisper: return "ADVANCED"
        }
    }

    var badgeColor: Color {
        switch self {
        case .parakeet: return .green
        case .whisper: return .blue
        }
    }

    var features: [String] {
        switch self {
        case .parakeet:
            return [
                "Optimized for Apple Silicon",
                "Low memory usage",
                "Excellent accuracy",
                "Fast processing"
            ]
        case .whisper:
            return [
                "State-of-the-art accuracy",
                "Multi-language support",
                "Technical terminology",
                "Longer audio clips"
            ]
        }
    }

    var bestFor: String {
        switch self {
        case .parakeet: return "Most users - balanced performance"
        case .whisper: return "Power users - need maximum accuracy"
        }
    }
}
```

**Model Card Component**:
```swift
struct ModelCard: View {
    let model: AIModel
    @Binding var selectedModel: AIModel
    @State private var isHovered = false

    var isSelected: Bool {
        selectedModel == model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with logo and badge
            HStack {
                Image(model == .parakeet ? "ParakeetLogo" : "WhisperLogo")
                    .resizable()
                    .frame(width: 40, height: 40)

                Spacer()

                Text(model.badge)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(model.badgeColor.opacity(0.2))
                    .foregroundColor(model.badgeColor)
                    .cornerRadius(4)
            }

            // Title and tagline
            VStack(alignment: .leading, spacing: 4) {
                Text(model.rawValue)
                    .font(.title2)
                    .bold()

                Text(model.tagline)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Size
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle")
                    .font(.caption)
                Text(model.size)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Features
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.features, id: \.self) { feature in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text(feature)
                            .font(.system(size: 13))
                    }
                }
            }

            Spacer()

            // Best for + Learn more
            VStack(alignment: .leading, spacing: 8) {
                Text("Best for: \(model.bestFor)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(action: {
                    // Open info URL
                    NSWorkspace.shared.open(model.learnMoreURL)
                }) {
                    Text("Learn more →")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 340)
        .background(isHovered ? Color(hex: "#1F1F1F") : Color(hex: "#151515"))
        .border(isSelected ? model.badgeColor : Color(hex: "#2A2A2A"), width: 2)
        .cornerRadius(12)
        .onHover { isHovered = $0 }
        .onTapGesture {
            withAnimation {
                selectedModel = model
                // Start download immediately on selection
                startModelDownload(model: model)
            }
        }
    }
}
```

**Download Progress Component**:
```swift
struct DownloadProgressView: View {
    @Binding var progress: Double  // 0.0 to 1.0
    @Binding var speed: String
    @Binding var isDownloading: Bool

    var timeRemaining: String {
        // Calculate based on progress and speed
        // Return formatted string like "~2 minutes remaining"
    }

    var body: some View {
        VStack(spacing: 12) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    Rectangle()
                        .fill(Color(hex: "#2A2A2A"))
                        .frame(height: 6)
                        .cornerRadius(3)

                    // Progress
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: geometry.size.width * progress, height: 6)
                        .cornerRadius(3)
                        .animation(.linear(duration: 0.3), value: progress)
                }
            }
            .frame(height: 6)

            // Status text
            HStack {
                Text("Downloading... \(Int(progress * 100))%")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                Spacer()

                if !speed.isEmpty {
                    Text(speed)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            if !timeRemaining.isEmpty {
                Text(timeRemaining)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(hex: "#151515"))
        .cornerRadius(8)
    }
}
```

**Download Logic**:
```swift
func startModelDownload(model: AIModel) async {
    // Check if already installed
    if await ModelManager.shared.isModelInstalled(model) {
        await MainActor.run {
            isModelInstalled = true
            modelDownloadProgress = 1.0
        }
        return
    }

    await MainActor.run {
        isDownloading = true
        modelDownloadProgress = 0.0
    }

    do {
        // Real download with progress monitoring
        for await update in ModelManager.shared.downloadModel(model) {
            await MainActor.run {
                modelDownloadProgress = update.progress
                downloadSpeed = update.speedFormatted  // e.g., "4.2 MB/s"
            }
        }

        await MainActor.run {
            isDownloading = false
            isModelInstalled = true
            modelDownloadProgress = 1.0
        }
    } catch {
        await MainActor.run {
            isDownloading = false
            // Show error alert
            showDownloadError(error)
        }
    }
}
```

**Continue Button Logic**:
```swift
var canContinue: Bool {
    // Can continue immediately after model selection
    // Don't need to wait for download
    true
}

func handleContinue() {
    // If download hasn't started, start it now
    if !isDownloading && !isModelInstalled {
        Task {
            await startModelDownload(model: selectedModel)
        }
    }

    // Proceed to next screen (Status Check)
    // Download will continue in background
    OnboardingManager.shared.currentStep = .statusCheck
}
```

**Layout**:
```swift
OnboardingStepLayout {
    VStack(spacing: 40) {
        // Icon
        Image(systemName: "brain.head.profile")
            .font(.system(size: 80))
            .foregroundColor(.purple)
            .symbolEffect(.pulse)

        // Model cards
        HStack(spacing: 24) {
            ModelCard(model: .parakeet, selectedModel: $selectedModel)
            ModelCard(model: .whisper, selectedModel: $selectedModel)
        }

        // Download progress (if downloading)
        if isDownloading {
            DownloadProgressView(
                progress: $modelDownloadProgress,
                speed: $downloadSpeed,
                isDownloading: $isDownloading
            )
            .transition(.opacity)
        }

        // Helper text
        Text("Download happens in background - you can continue setup")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}
```

**Skip Logic**:
```swift
// If user clicks Skip, they can choose model later in Settings
// TalkieEngine will use a fallback/default until model is selected
func handleSkip() {
    OnboardingManager.shared.currentStep = .statusCheck
    // No model selected - will be prompted later or use default
}
```

---

## Key Implementation Notes

**⚠️ Real Download, Not Simulated**:
- Use actual `URLSession` download tasks with progress monitoring
- Don't fake progress with timers (previous code review found this issue)
- Handle network errors gracefully with retry option

**Non-Blocking is Critical**:
- User should be able to click Continue immediately
- Download continues in background
- Status Check screen (Screen 5) will monitor completion
- Don't disable Continue button while downloading

**Model Selection Persistence**:
```swift
// Save to UserDefaults immediately on selection
UserDefaults.standard.set(selectedModel.rawValue, forKey: "selectedAIModel")

// Or better: use OnboardingManager state that persists
OnboardingManager.shared.selectedModel = selectedModel
```

**Already Installed Detection**:
```swift
// Check if model files already exist before downloading
if ModelManager.shared.isModelInstalled(selectedModel) {
    // Skip download, mark as complete
    modelDownloadProgress = 1.0
    isModelInstalled = true
    // Show "Already installed ✓" instead of download progress
}
```

---

## Enhancements from Live

**Keep from Live**:
- Model choice cards with clear visual distinction
- Progress bar with speed indicators
- Non-blocking flow (don't wait for download)

**Add to Talkie**:
- Two-model choice (Live only had one)
- Learn more links for each model
- Better badge distinction (RECOMMENDED vs ADVANCED)
- Download speed and time remaining estimates
- "Already installed" detection and skip

---

## Testing

- [ ] Can select Parakeet or Whisper model
- [ ] Only one model can be selected at a time
- [ ] Cards respond to hover
- [ ] Click selects model and starts download immediately
- [ ] Continue button enabled immediately (doesn't wait for download)
- [ ] Download progress updates smoothly in real-time
- [ ] Download speed shows accurate measurements
- [ ] Time remaining estimates are reasonable
- [ ] Can proceed to next screen while download continues
- [ ] Download continues in background after leaving screen
- [ ] Handles network errors gracefully with retry
- [ ] Detects "already installed" and skips download
- [ ] Learn more links open correct URLs
- [ ] Model selection persists across app restarts
- [ ] No memory leaks during long downloads
