# Screen 6: LLM Config

> Optional API key setup with Apple Keychain security

## What User Sees

**Layout**: Grid background → Lock icon → Security message → API provider cards → Continue button

**Title**: "Connect Your AI (Optional)"

**Subtitle**: "Add an API key to unlock cloud AI features"

**Icon**: Lock with shield (lock.shield) - 80x80, pulsing with green glow

**Security Message** (prominent, above provider cards):
```
┌─────────────────────────────────────────────────┐
│  🔒 Protected by Apple Keychain Encryption      │
│                                                 │
│  Your API key is encrypted using Apple's       │
│  secure storage and never leaves your device   │
└─────────────────────────────────────────────────┘
```
- Background: Dark with subtle green tint
- Border: Green, pulsing softly
- Icon: Lock shield (animated)

**Provider Cards** (three options):

### Option 1: OpenAI
- **Logo**: OpenAI logo
- **Title**: "OpenAI"
- **Models**: "GPT-4, GPT-4 Turbo, GPT-3.5"
- **API Key Field**: Text input with password masking
  - Placeholder: "sk-..."
  - Show/hide toggle (eye icon)
  - Validation indicator (checkmark when valid format)
- **Get API Key**: Link to OpenAI dashboard
- **Pricing**: "Pay as you go - ~$0.01/1K tokens"

### Option 2: Anthropic
- **Logo**: Anthropic logo
- **Title**: "Anthropic"
- **Models**: "Claude 3 Opus, Sonnet, Haiku"
- **API Key Field**: Text input with password masking
  - Placeholder: "sk-ant-..."
  - Show/hide toggle
  - Validation indicator
- **Get API Key**: Link to Anthropic console
- **Pricing**: "Pay as you go - ~$0.015/1K tokens"

### Option 3: Local Only (Default)
- **Icon**: Laptop with checkmark (laptopcomputer.and.checkmark)
- **Title**: "Local Models Only"
- **Description**: "Use downloaded AI models without cloud APIs"
- **Badge**: "PRIVATE & FREE" (green)
- **Features**:
  - ✓ No API key needed
  - ✓ 100% private
  - ✓ Works offline
  - ✓ No usage costs
- Selected by default

**Validation** (when API key entered):
- Format check (starts with "sk-" for OpenAI, "sk-ant-" for Anthropic)
- Optional: Test connection (make test API call)
- Visual feedback: Green checkmark for valid, red X for invalid
- Error message if invalid format

**Helper Text**: "You can always add or change your API key in Settings"

**Buttons**:
- **Continue** (enabled when valid key entered OR "Local Only" selected)
- **Skip for now** (same as selecting "Local Only")

**Info Section** (below cards):
- **Why add an API key?**
  - Access to more powerful cloud models
  - Multi-language support beyond local models
  - Faster processing for some tasks

- **Why skip?**
  - Local models work great for most users
  - Complete privacy (no data leaves device)
  - No usage costs
  - Can add later in Settings

---

## Why This Exists

**Purpose**: Give users the option to connect cloud AI providers while making it crystal clear that:
1. It's completely optional (local works great)
2. Their keys are encrypted with Apple's security
3. They can add/change this later

**User Goals**:
- Understand that API keys are optional
- Feel confident their keys are secure if they add them
- Know they can use local models without any keys
- Make informed choice about privacy vs features tradeoff
- Not feel pressured to enter a key

**Success Criteria**:
- >60% choose "Local Only" (don't enter key during onboarding)
- >90% understand keys are optional
- >95% understand Apple Keychain encryption
- <5% concerned about security
- 0% enter invalid/test keys and proceed

**Key Messages**:
1. **Optional**: Local models work great, cloud is optional
2. **Secure**: Apple Keychain encryption (most prominent message)
3. **Private**: Local models = complete privacy
4. **Reversible**: Can add/change keys anytime in Settings
5. **Informed**: Clear tradeoffs (privacy vs features, free vs paid)

**User Personas**:

*Privacy-conscious user (60%)*:
- Sees "PRIVATE & FREE" badge on Local Only
- Reads "100% private" and "Works offline"
- Doesn't want to share data with cloud
- Selects "Local Only"
- Clicks Continue confidently

*Power user with API key (25%)*:
- Has OpenAI/Anthropic account
- Wants access to GPT-4 or Claude
- Sees prominent Keychain security message
- Enters API key
- Sees green checkmark validation
- Proceeds confidently

*Curious but undecided user (15%)*:
- Reads all three cards
- Sees "You can add later in Settings"
- Chooses "Local Only" for now
- May add key later when they need it

---

## How to Build

**Target**: `/Users/arach/dev/talkie/macOS/Talkie/Views/Onboarding/LLMConfigView.swift`

**State Management** (in OnboardingCoordinator):
```swift
@Published var selectedProvider: LLMProvider = .localOnly  // Default
@Published var openAIKey: String = ""
@Published var anthropicKey: String = ""
@Published var isValidatingKey: Bool = false
@Published var keyValidationState: KeyValidationState = .idle

enum LLMProvider: String, CaseIterable {
    case openai = "OpenAI"
    case anthropic = "Anthropic"
    case localOnly = "Local Only"
}

enum KeyValidationState {
    case idle
    case validating
    case valid
    case invalid(String)  // Error message
}
```

**Security Message Component**:
```swift
struct KeychainSecurityBanner: View {
    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.green)
                    .symbolEffect(.pulse, value: isPulsing)

                Text("Protected by Apple Keychain Encryption")
                    .font(.headline)
                    .foregroundColor(.primary)
            }

            Text("Your API key is encrypted using Apple's secure storage and never leaves your device")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            Color.green.opacity(0.1)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green.opacity(0.3), lineWidth: 2)
                )
        )
        .cornerRadius(12)
        .onAppear {
            isPulsing = true
        }
    }
}
```

**Provider Card Component**:
```swift
struct LLMProviderCard: View {
    let provider: LLMProvider
    @Binding var selectedProvider: LLMProvider
    @Binding var apiKey: String
    @Binding var validationState: KeyValidationState
    @State private var isHovered = false
    @State private var showPassword = false

    var isSelected: Bool {
        selectedProvider == provider
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                if provider == .localOnly {
                    Image(systemName: "laptopcomputer.and.checkmark")
                        .font(.system(size: 32))
                        .foregroundColor(.green)
                } else {
                    Image(provider == .openai ? "OpenAILogo" : "AnthropicLogo")
                        .resizable()
                        .frame(width: 40, height: 40)
                }

                Spacer()

                if provider == .localOnly {
                    Text("PRIVATE & FREE")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                }
            }

            // Title
            Text(provider.rawValue)
                .font(.title2)
                .bold()

            // Content based on provider type
            if provider == .localOnly {
                LocalOnlyCardContent()
            } else {
                CloudProviderCardContent(
                    provider: provider,
                    apiKey: $apiKey,
                    showPassword: $showPassword,
                    validationState: $validationState
                )
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 280)
        .background(isHovered ? Color(hex: "#1F1F1F") : Color(hex: "#151515"))
        .border(isSelected ? Color.green : Color(hex: "#2A2A2A"), width: 2)
        .cornerRadius(12)
        .onHover { isHovered = $0 }
        .onTapGesture {
            withAnimation {
                selectedProvider = provider
            }
        }
    }
}
```

**Local Only Card Content**:
```swift
struct LocalOnlyCardContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Use downloaded AI models without cloud APIs")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                FeatureRow(text: "No API key needed")
                FeatureRow(text: "100% private")
                FeatureRow(text: "Works offline")
                FeatureRow(text: "No usage costs")
            }
        }
    }
}

struct FeatureRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
            Text(text)
                .font(.system(size: 13))
        }
    }
}
```

**Cloud Provider Card Content**:
```swift
struct CloudProviderCardContent: View {
    let provider: LLMProvider
    @Binding var apiKey: String
    @Binding var showPassword: Bool
    @Binding var validationState: KeyValidationState

    var models: String {
        provider == .openai ? "GPT-4, GPT-4 Turbo, GPT-3.5" : "Claude 3 Opus, Sonnet, Haiku"
    }

    var placeholder: String {
        provider == .openai ? "sk-..." : "sk-ant-..."
    }

    var getDashboardURL: URL {
        provider == .openai
            ? URL(string: "https://platform.openai.com/api-keys")!
            : URL(string: "https://console.anthropic.com/settings/keys")!
    }

    var pricing: String {
        provider == .openai ? "~$0.01/1K tokens" : "~$0.015/1K tokens"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Models
            Text("Models: \(models)")
                .font(.caption)
                .foregroundColor(.secondary)

            // API Key field
            HStack {
                if showPassword {
                    TextField(placeholder, text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                } else {
                    SecureField(placeholder, text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                }

                Button(action: { showPassword.toggle() }) {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                // Validation indicator
                Group {
                    switch validationState {
                    case .idle:
                        EmptyView()
                    case .validating:
                        ProgressView()
                            .scaleEffect(0.7)
                    case .valid:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    case .invalid:
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                }
                .frame(width: 20, height: 20)
            }

            // Error message
            if case .invalid(let message) = validationState {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // Get API Key link
            Button(action: {
                NSWorkspace.shared.open(getDashboardURL)
            }) {
                Text("Get API Key →")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)

            Spacer()

            // Pricing
            Text("Pricing: \(pricing)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .onChange(of: apiKey) { oldValue, newValue in
            validateAPIKey(newValue)
        }
    }

    func validateAPIKey(_ key: String) {
        guard !key.isEmpty else {
            validationState = .idle
            return
        }

        // Format validation
        let expectedPrefix = provider == .openai ? "sk-" : "sk-ant-"
        if !key.hasPrefix(expectedPrefix) {
            validationState = .invalid("Invalid key format")
            return
        }

        // Length validation (basic)
        if key.count < 20 {
            validationState = .invalid("Key too short")
            return
        }

        // Optional: Test connection
        // validationState = .validating
        // Task { await testConnection(key) }

        validationState = .valid
    }
}
```

**Save to Keychain** (when user proceeds):
```swift
func saveAPIKeyToKeychain() {
    guard selectedProvider != .localOnly else { return }

    let key = selectedProvider == .openai ? openAIKey : anthropicKey
    guard !key.isEmpty else { return }

    do {
        try KeychainManager.shared.saveAPIKey(
            key,
            for: selectedProvider.rawValue
        )
        print("✅ API key saved securely to Keychain")
    } catch {
        print("❌ Failed to save API key: \(error)")
        showKeychainError(error)
    }
}
```

**Continue Button Logic**:
```swift
var canContinue: Bool {
    switch selectedProvider {
    case .localOnly:
        return true  // Always can proceed with local
    case .openai:
        return !openAIKey.isEmpty && validationState == .valid
    case .anthropic:
        return !anthropicKey.isEmpty && validationState == .valid
    }
}

func handleContinue() {
    // Save to Keychain if cloud provider selected
    if selectedProvider != .localOnly {
        saveAPIKeyToKeychain()
    }

    // Mark LLM config complete
    OnboardingManager.shared.hasConfiguredLLM = true

    // Proceed to Complete screen
    OnboardingManager.shared.currentStep = .complete
}
```

**Layout**:
```swift
OnboardingStepLayout {
    VStack(spacing: 40) {
        // Icon
        Image(systemName: "lock.shield.fill")
            .font(.system(size: 80))
            .foregroundColor(.green)
            .symbolEffect(.pulse)

        // Security banner (PROMINENT)
        KeychainSecurityBanner()

        // Provider cards
        HStack(spacing: 24) {
            LLMProviderCard(
                provider: .localOnly,
                selectedProvider: $selectedProvider,
                apiKey: .constant(""),
                validationState: .constant(.idle)
            )

            LLMProviderCard(
                provider: .openai,
                selectedProvider: $selectedProvider,
                apiKey: $openAIKey,
                validationState: $keyValidationState
            )

            LLMProviderCard(
                provider: .anthropic,
                selectedProvider: $selectedProvider,
                apiKey: $anthropicKey,
                validationState: $keyValidationState
            )
        }

        // Info section
        VStack(spacing: 16) {
            InfoSection(
                title: "Why add an API key?",
                points: [
                    "Access to more powerful cloud models",
                    "Multi-language support beyond local models",
                    "Faster processing for some tasks"
                ]
            )

            InfoSection(
                title: "Why skip?",
                points: [
                    "Local models work great for most users",
                    "Complete privacy (no data leaves device)",
                    "No usage costs",
                    "Can add later in Settings"
                ]
            )
        }
        .font(.caption)
        .foregroundColor(.secondary)

        // Helper text
        Text("You can always add or change your API key in Settings")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}
```

---

## Key Implementation Notes

**⚠️ Security is Paramount**:
```swift
// NEVER store API keys in UserDefaults or plain text files
// ALWAYS use Keychain for sensitive data

class KeychainManager {
    static let shared = KeychainManager()

    func saveAPIKey(_ key: String, for service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecValueData as String: key.data(using: .utf8)!,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        SecItemDelete(query as CFDictionary)  // Delete old if exists
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func getAPIKey(for service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }

        return key
    }
}
```

**Validation Levels**:
1. **Format check** (instant): Verify prefix and length
2. **Optional API test** (async): Make test call to verify key works
   - Pro: Catches invalid keys early
   - Con: Requires network, adds latency
   - Recommendation: Skip during onboarding, validate on first use

**Password Field Behavior**:
- Use `SecureField` by default (masked)
- Toggle to `TextField` when user clicks eye icon
- Clear on provider switch to prevent accidental cross-provider keys

---

## Enhancements from Live

**Keep from Live**:
- Clean provider selection UI
- Clear optional messaging

**Add to Talkie**:
- **Prominent Keychain security banner** (most important!)
- Three providers (Local Only as first-class option)
- "Local Only" selected by default
- Real-time validation feedback
- Info sections explaining tradeoffs
- Direct links to provider dashboards

---

## Testing

- [ ] "Local Only" selected by default
- [ ] Security banner displays prominently at top
- [ ] Lock shield icon pulses
- [ ] Can select OpenAI, Anthropic, or Local Only
- [ ] Only one provider can be selected at a time
- [ ] API key fields mask input by default
- [ ] Eye icon toggles password visibility
- [ ] Format validation works for OpenAI keys (sk-...)
- [ ] Format validation works for Anthropic keys (sk-ant-...)
- [ ] Validation shows green checkmark for valid keys
- [ ] Validation shows red X for invalid keys
- [ ] Continue enabled for Local Only without key
- [ ] Continue disabled for cloud providers without valid key
- [ ] "Get API Key" links open correct URLs
- [ ] Keys save to Keychain (NOT UserDefaults)
- [ ] Can retrieve keys from Keychain in Settings
- [ ] Switching providers clears previous key input
- [ ] No memory leaks with sensitive data
- [ ] Keys are cleared from memory after save
