# Talkie Reporter

Experimental Cloudflare Worker for receiving error reports from Talkie apps.

This service is not part of the core Apple app build and should be treated as maintainer-owned infrastructure. It is kept in the repo for historical context and future service work, but public contributors do not need it for local app development.

## Setup

1. Install dependencies:
   ```bash
   bun install
   ```

2. Create R2 bucket:
   ```bash
   wrangler r2 bucket create talkie-reports
   ```

3. Deploy:
   ```bash
   bun run deploy
   ```

## Development

```bash
bun run dev
```

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/` | Health check |
| POST | `/report` | Submit a new report |
| GET | `/report/:id` | Retrieve a report |
| GET | `/reports` | List recent reports |

## Report Structure

```json
{
  "id": "ABC12345",
  "timestamp": "2024-01-25T10:30:00Z",
  "system": {
    "os": "macOS",
    "osVersion": "14.2.0",
    "chip": "Apple M1",
    "memory": "16 GB",
    "locale": "en_US"
  },
  "apps": {
    "talkie": { "running": true, "pid": 1234, "version": "2.0.13" },
    "live": { "running": true, "pid": 5678, "version": "2.0.13" },
    "engine": { "running": false, "pid": null, "version": null }
  },
  "context": {
    "source": "live",
    "connectionState": "error",
    "lastError": "Engine not reachable",
    "userDescription": "Tried to record but nothing happened"
  },
  "logs": [
    "[10:29:55] [XPC] Engine not reachable...",
    "..."
  ],
  "performance": {
    "lastTranscriptionMs": "450"
  }
}
```

## Client Usage (Swift)

```swift
import TalkieKit

// Register providers at app startup
TalkieReporter.shared.registerAppInfo(for: .live) {
    ReportAppInfo(
        running: true,
        pid: ProcessInfo.processInfo.processIdentifier,
        version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    )
}

// Submit a report
Task {
    do {
        let response = try await TalkieReporter.shared.submit(
            source: .live,
            userDescription: "Recording failed"
        )
        print("Report submitted: \(response.id ?? "unknown")")
    } catch {
        print("Failed to submit: \(error)")
    }
}

// Or copy to clipboard
let json = TalkieReporter.shared.copyToClipboard(source: .live)
```
