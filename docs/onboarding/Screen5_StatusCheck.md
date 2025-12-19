# Screen 5: Status Check

> **Port from Live** - Show progress while things happen in background

## What User Sees

**Layout**: Grid background → App icon → Status card → Auto-advances when ready

**Title**: "Setting Things Up"

**Subtitle**: "This will only take a moment..."

**Icon**: Talkie app icon - 100x100

**Status Card** (4 rows with real-time updates):

### All Modes:
1. **Model Selection**
   - Label: "Model Selection"
   - Value: "Parakeet v3" or "Whisper large-v3"
   - Icon: Checkmark (green) when confirmed

2. **File Download**
   - Label: "AI Model Download"
   - Value: "45%" or "Complete" or "Already installed ✓"
   - Icon: Spinner while downloading, checkmark when done
   - Shows progress percentage while downloading

3. **Engine Connection**
   - Label: "Engine Connection"
   - Value: "Connecting..." → "Connected ✓"
   - Icon: Spinner then checkmark

4. **Engine Status**
   - Label: "Engine Ready"
   - Value: "Warming up..." → "Ready ✓"
   - Icon: Spinner then checkmark

### Core + Live Mode Only (5th row):
5. **TalkieLive Service**
   - Label: "Live Service"
   - Value: "Starting..." → "Running ✓"
   - Icon: Spinner then checkmark

**Helper Text**: "Your system is being optimized for best performance"

**Auto-advance**: When all checks pass, automatically proceeds to next step (no button needed)

**Error State**: If anything fails, shows "Retry" button

---

## Why This Exists

**Purpose**: Allow non-blocking model download and service launch. User doesn't wait on Model Install screen - they proceed here while things happen in background. Creates perception of speed.

**User Goals**:
- Know something is happening (not stuck)
- See progress (not just spinning wheel)
- Feel confident system is being set up correctly
- Not waste time waiting

**Success Criteria**:
- User sees progress within 1 second
- All checks complete within 30 seconds (typical)
- <5% encounter errors
- >95% feel system is "fast"

**Key Messages**:
1. **Progress**: Real-time status updates
2. **Speed**: Non-blocking = appears faster
3. **Reliability**: Checks ensure everything works
4. **Automation**: Just works, no user action needed

---

## How to Build

### ⚠️ Port from TalkieLive's Engine Warmup Screen

**Source**: TalkieLive's `EngineWarmupStepView.swift`

**Target**: `/Users/arach/dev/talkie/macOS/Talkie/Views/Onboarding/StatusCheckView.swift` (NEW FILE)

**Port Almost 1:1**:
- Copy the status check row component
- Copy the auto-advance logic
- Copy the visual styling
- Adapt for Talkie's conditional checks (engine always, Live only if enabled)

**Status Checks**:
```swift
enum StatusCheck: String, CaseIterable {
    case modelSelection = "Model Selection"
    case fileDownload = "AI Model Download"
    case engineConnection = "Engine Connection"
    case engineReady = "Engine Ready"
    case liveService = "Live Service"  // Conditional

    var isRequired: Bool {
        // Live service only required if Live mode enabled
        if self == .liveService {
            return OnboardingManager.shared.enableLiveMode
        }
        return true
    }
}

enum CheckStatus {
    case pending
    case inProgress(String)  // e.g., "45%", "Connecting..."
    case complete
    case error(String)

    var icon: String {
        switch self {
        case .pending: return "circle"
        case .inProgress: return "spinner"  // Use ProgressView
        case .complete: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .pending: return .gray
        case .inProgress: return .blue
        case .complete: return .green
        case .error: return .red
        }
    }
}
```

**Status Check Logic**:
```swift
func performStatusChecks() async {
    // 1. Model Selection (instant)
    await updateCheck(.modelSelection, status: .complete)

    // 2. File Download (monitor existing download or skip if installed)
    if isModelAlreadyInstalled() {
        await updateCheck(.fileDownload, status: .inProgress("Already installed ✓"))
        try? await Task.sleep(for: .milliseconds(500))
        await updateCheck(.fileDownload, status: .complete)
    } else {
        // Monitor ongoing download
        for await progress in modelDownloadProgress {
            let percentage = Int(progress * 100)
            await updateCheck(.fileDownload, status: .inProgress("\(percentage)%"))
        }
        await updateCheck(.fileDownload, status: .complete)
    }

    // 3. Engine Connection
    await updateCheck(.engineConnection, status: .inProgress("Connecting..."))
    do {
        try await connectToEngine()
        await updateCheck(.engineConnection, status: .complete)
    } catch {
        await updateCheck(.engineConnection, status: .error(error.localizedDescription))
        return
    }

    // 4. Engine Ready
    await updateCheck(.engineReady, status: .inProgress("Warming up..."))
    do {
        try await waitForEngineReady()
        await updateCheck(.engineReady, status: .complete)
    } catch {
        await updateCheck(.engineReady, status: .error(error.localizedDescription))
        return
    }

    // 5. Live Service (conditional)
    if OnboardingManager.shared.enableLiveMode {
        await updateCheck(.liveService, status: .inProgress("Starting..."))
        do {
            try await launchLiveService()
            await updateCheck(.liveService, status: .complete)
        } catch {
            await updateCheck(.liveService, status: .error(error.localizedDescription))
            return
        }
    }

    // All checks passed - auto-advance
    try? await Task.sleep(for: .seconds(1))  // Brief pause to show success
    await advanceToNextScreen()
}
```

**Status Row Component** (port from Live):
```swift
struct StatusCheckRow: View {
    let check: StatusCheck
    let status: CheckStatus

    var body: some View {
        HStack(spacing: 12) {
            // Label (left)
            Text(check.rawValue)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 140, alignment: .leading)

            Spacer()

            // Value + Icon (right)
            HStack(spacing: 8) {
                // Status value
                if case .inProgress(let message) = status {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                // Icon
                Group {
                    if case .inProgress = status {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: status.icon)
                            .foregroundColor(status.color)
                    }
                }
                .frame(width: 20, height: 20)
            }
        }
        .padding(.vertical, 8)
    }
}
```

**Layout**:
```swift
OnboardingStepLayout {
    VStack(spacing: 40) {
        // App icon
        Image("AppIcon")
            .resizable()
            .frame(width: 100, height: 100)
            .cornerRadius(20)

        // Status card
        VStack(spacing: 0) {
            ForEach(visibleChecks, id: \.self) { check in
                StatusCheckRow(
                    check: check,
                    status: checkStatuses[check] ?? .pending
                )

                if check != visibleChecks.last {
                    Divider()
                }
            }
        }
        .padding()
        .background(Color(hex: "#151515"))
        .cornerRadius(12)

        // Helper text
        Text("Your system is being optimized for best performance")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}
.onAppear {
    Task {
        await performStatusChecks()
    }
}
```

**Auto-advance Logic**:
```swift
func advanceToNextScreen() async {
    await MainActor.run {
        // Mark status checks complete
        OnboardingManager.shared.hasCompletedStatusChecks = true

        // Auto-advance to LLM Config
        OnboardingManager.shared.currentStep = .llmConfig
    }
}
```

---

## Key Differences from Live

**Live's Screen**:
- Always shows engine checks
- Fixed 4 checks
- Always required

**Talkie's Screen**:
- Conditional 5th check (Live service)
- Model download may already be complete
- Adapts based on mode choice

**Keep from Live**:
- Visual design (status rows, icons, spacing)
- Auto-advance behavior
- Error handling with retry
- Progress indicators

---

## Testing

- [ ] Auto-starts checks on appear
- [ ] Shows real-time progress updates
- [ ] Model download percentage updates smoothly
- [ ] Live service check only shows if Live mode enabled
- [ ] Auto-advances when all checks pass
- [ ] Shows retry button on error
- [ ] Retry button actually retries failed check
- [ ] All checks complete within 30s (typical)
- [ ] Handles "already installed" model gracefully
- [ ] No stuck states (always progresses or errors)
