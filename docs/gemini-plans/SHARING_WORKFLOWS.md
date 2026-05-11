# Sharing Workflows & "Talkie Links"

## Overview

"Talkie" should be a sharable unit of thought. Users should be able to send a voice note + transcript + summary to anyone, even if the recipient doesn't have the app. Additionally, power users should be able to share their Workflow automations.

## 1. Sharing "Talkies" (The Content)

### A. The "Talkie Link" (Web View)
- **Concept**: `talkie.share/v/{uuid}`
- **Content**:
    - Audio player (waveform).
    - Transcript (interactive, click-to-seek).
    - AI Summary/Action Items.
- **Implementation**:
    - **Backend**: Minimal hosting (Vercel/Cloudflare Workers) or CloudKit Public Database.
    - **Data**: Upload audio + JSON to S3/R2/CloudKit.
    - **Security**: Password protection, expiration dates.

### B. "Audiogram" Export (Social)
- **Concept**: Export as video (MP4) for Instagram/TikTok/Twitter.
- **Visual**: Static background + Animated waveform + Scrolling captions.
- **Tech**: `AVFoundation` composition engine or HTML5 Canvas render -> ffmpeg (server-side or WASM).

### C. Native App Clip / Universal Link
- If recipient has Talkie installed: Opens natively.
- If not: Opens App Clip (iOS) or Web View.

## 2. Sharing Workflows (The Logic)

### A. Workflow Definition Sharing (Legacy: .twf)
- *Note: TWF format is currently inactive. Waiting for new workflow schema definition.*
- Workflows were previously JSON (`.twf`).
- **Future Mechanism**: Export new format (SwiftData dump or new JSON schema) via AirDrop/Message.

### B. Workflow Gallery (Community)
- **Repo**: A curated list of workflows (Git-backed or API-backed).
- **In-App**: "Browse Community Workflows".
- **Verification**: Warning for workflows that run shell commands or send data to external URLs.

## 3. Collaborative Folders (Team Mode)
- **Use Case**: "Meeting Notes" folder shared with the team.
- **Tech**: iCloud Shared User Record (CKShare).
- **Behavior**:
    - User A records meeting.
    - Talkie syncs to Shared Database.
    - User B gets notification, can see transcript/summary instantly.

## Implementation Roadmap

### Phase 1: Basic Export
- Share Sheet: "Share Transcript" (Text), "Share Audio" (File).
- "Copy Magic Link" (requires backend setup).

### Phase 2: Workflow Import/Export
- UI for exporting `.twf`.
- Deep link handler `talkie://import-workflow?url=...`

### Phase 3: The Web Player
- Build `talkie-web` project (Next.js).
- CloudKit public share integration.

## Research Questions
- **CloudKit Sharing**: Can we use `CKShare` to generate public web URLs easily? (Apple's public URL solution is limited).
- **Hosting**: Cost of hosting audio files for web sharing.
