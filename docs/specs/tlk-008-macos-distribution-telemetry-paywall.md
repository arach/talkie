# TLK-008 — macOS Distribution, Telemetry, Paywall Gate

**Status**: Draft
**Owner**: TBD

## Summary

This spec defines a direct-distribution macOS app stack with:

- Secure, home-managed auto-updates
- Privacy-forward, batch telemetry with full user transparency
- Remote paywall gate (off by default, toggleable later)

The goal is to ship v1 as free while keeping a clean path to paywall enablement and basic usage insights.

## Goals

- Direct distribution (not Mac App Store)
- Secure auto-updates under our control
- Telemetry that is minimal, transparent, and non-invasive
- Remote paywall gate available in first build, default off

## Non-Goals

- Real-time telemetry or session replay
- Deep user identity tracking or content capture
- Complex paywall experimentation at launch

## Auto-Updates (Sparkle 2, Self-Hosted)

### Requirements
- Use Sparkle 2 for secure updates
- Host appcast and update assets on Talkie infrastructure
- App checks for updates at launch and every 24 hours

### Implementation Notes
- Integrate Sparkle 2 framework
- Sign updates with EdDSA
- Serve an `appcast.xml` from `update.appcastURL`

### Config
- `update.appcastURL` (string)
- `update.channel` (optional: `stable` | `beta`)

### Failure Behavior
- If appcast unreachable, silently skip update

### Acceptance Criteria
- Updates install from a signed appcast
- Invalid signatures are rejected

## Telemetry (Batch, Privacy-Forward)

### Principles
- Batch-only, no real-time reporting
- No content capture (no transcripts, audio, user text)
- Ephemeral install ID with rotation
- User can see exactly what is sent

### Events
- `app_open`
- `session_end` (duration bucket only)
- `feature_used` (feature key only)
- `sync_stats` (counts only)
- `error_count` (category only)

### Identity
- `install_id`: random UUID stored locally
- Rotate every 30 days (new UUID)
- No email, no account ID, no IP storage

### Storage
- Local queue in JSON Lines format:
  `~/Library/Application Support/Talkie/Telemetry/events.jsonl`
- Max 2,000 events (drop oldest on overflow)

### Flush Policy
- Flush once per day (or on app quit)
- POST JSON payload to `telemetry.endpoint`
- Retry next day on failure

### Payload Example
```
{
  "install_id": "UUID",
  "app_version": "x.y.z",
  "os_version": "macOS 14.x",
  "events": [
    {"type": "app_open", "ts": "..."},
    {"type": "feature_used", "feature": "record", "ts": "..."},
    {"type": "session_end", "duration_bucket": "5-30m", "ts": "..."}
  ]
}
```

### Transparency UI
- Settings → Privacy → "Your Data"
- Show last payload (or a readable summary)
- Toggle: "Share anonymous usage stats"

### Acceptance Criteria
- Telemetry OFF means no collection, no sends
- Telemetry ON stores locally and flushes daily
- "Your Data" reflects the real payload

## Remote Paywall Gate (Default Off)

### Requirements
- Paywall gate available in first build
- Remotely toggleable via config
- Default free if config is missing or offline

### Config (remote JSON)
- `paywall_enabled` (bool)
- `paywall_variant` (string)
- `paywall_message` (string)
- `paywall_effective_date` (optional ISO 8601)

### Behavior
- If disabled: no gating
- If enabled: show paywall at defined entry points

### Suggested Entry Points
- App launch (optional)
- Feature usage (export, AI workflows, etc.)

### Acceptance Criteria
- Default experience is free
- Flip remote flag → paywall appears without new build

## Security + Privacy

- All endpoints HTTPS
- Minimal data collection
- Clear privacy policy and in-app disclosure

## Suggested Folder Structure

```
apps/macos/Talkie/Services/
  Updates/
    UpdateManager.swift
  Telemetry/
    TelemetryClient.swift
    TelemetryStore.swift
    TelemetryModels.swift
  RemoteConfig/
    RemoteConfigClient.swift
    RemoteConfigCache.swift
  Paywall/
    PaywallGate.swift
    PaywallView.swift
apps/macos/Talkie/Views/Settings/
  PrivacySettingsView.swift
  UpdatesSettingsView.swift
```

## Proposed Swift APIs (Sketch)

### Telemetry
```swift
enum TelemetryEvent {
    case appOpen
    case sessionEnd(durationBucket: String)
    case featureUsed(name: String)
    case syncStats(count: Int)
    case errorCount(category: String, count: Int)
}

@MainActor
final class TelemetryClient {
    static let shared = TelemetryClient()
    var isEnabled: Bool
    func track(_ event: TelemetryEvent)
    func flushIfNeeded()
    func lastPayloadPreview() -> String
}
```

### Remote Config
```swift
struct RemoteConfig: Codable {
    let paywallEnabled: Bool
    let paywallVariant: String?
    let paywallMessage: String?
    let paywallEffectiveDate: Date?
}

@MainActor
final class RemoteConfigClient {
    static let shared = RemoteConfigClient()
    var current: RemoteConfig
    func refreshIfNeeded()
}
```

### Paywall Gate
```swift
@MainActor
final class PaywallGate {
    static let shared = PaywallGate()
    func shouldShowPaywall(for entryPoint: String) -> Bool
}
```

### Updates (Sparkle)
```swift
@MainActor
final class UpdateManager {
    static let shared = UpdateManager()
    func checkForUpdates()
}
```

## Implementation Phases

1. Updates (Sparkle 2, appcast + signing)
2. Telemetry (local queue + batch sender + "Your Data" UI)
3. Remote config + paywall gate

## Open Questions

- Update hosting location and CDN choice
- Paywall entry points for v1
- Telemetry opt-in default (on vs off)
