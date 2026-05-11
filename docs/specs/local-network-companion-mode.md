# Local Network Companion Mode

## Summary

This spec proposes an opt-in `Companion Mode` that turns an iPhone or iPad into a live secondary control surface for a Mac running Talkie.

The key product constraint is presence, not geography:

- the feature is available only while Talkie is actively running on a Mac
- the iPhone/iPad and Mac are on the same local network
- the user has explicitly opted into Companion Mode
- the devices belong to the same Talkie account and/or trusted pairing relationship

This creates a new surface that is closer to a hardware control deck than a traditional mobile companion app. The iPhone becomes a fast remote. The iPad becomes a richer “AI shortcut keyboard” with larger programmable action tiles, lightweight context, and workflow launch affordances.

An important simplification for V1 is coordinated layout control: when a device is already paired and connected, the Mac can explicitly request that the mobile device enter a companion layout such as `Shortcut Mode`. The mobile device then decides whether to follow that request based on its own preference. That makes the experience deterministic without making the phone or iPad subordinate by default.

## Why This Is Interesting

Talkie already has three strong ingredients:

- a Mac-side workflow engine and live workflow queue
- iPhone-side pairing and “paired Mac” concepts
- iOS keyboard-style configurable shortcut surfaces

Companion Mode combines those into a fourth surface:

- not a memo browser
- not a keyboard extension
- not remote desktop
- a low-latency command deck for “run this now on my Mac”

That is especially compelling for users who are already operating from a desk, couch, kitchen, or meeting room and want fast access to AI-enabled actions without touching the Mac directly.

## Product Principles

### 1. Presence-gated, not location-gated

The app should not infer “home” from geography. The surface appears only when the Mac is actually reachable on the current local network and advertising Companion availability.

### 2. Opt-in and legible

Companion Mode must be explicitly enabled on the Mac and on each apps/ios/iPadOS device. Users should always understand why the surface is visible or unavailable.

For the initial version, the simplest mental model is:

- paired with a Mac
- connected to that Mac
- Mac can request which companion layout should be active right now
- mobile device chooses whether it follows that request

### 3. Fast actions first

The primary job is launching high-value actions with near-zero friction:

- dictate to Mac
- capture context
- run pinned workflows
- trigger AI transformations
- send small structured requests to the Mac

### 4. Remote control, not remote dependency

The Mac remains the executor for desktop-specific capabilities. The phone/tablet is the surface and input device.

### 5. Differentiate iPhone and iPad

- iPhone: quick deck, one-thumb, lock-screen-adjacent mentality
- iPad: expanded command board, more like a programmable shortcut keyboard

## Core User Story

“While my Mac is running Talkie on the same network, I can glance at my iPad or iPhone and see a live deck of actions. I can tap one to capture a screenshot, dictate a thought, or launch an AI workflow on the Mac without digging through menus.”

## Primary Use Cases

### iPhone companion remote

Best for:

- push-to-talk
- “capture screen”
- “run last workflow again”
- “summarize latest memo”
- “create reminder from latest transcript”
- “start/stop ambient mode”

Recommended UI:

- 6 to 8 large action tiles
- one prominent record/dictate control
- compact status strip showing Mac availability

### iPad shortcut keyboard

Best for:

- a larger programmable action grid
- workflow launch pads by theme or context
- context-aware AI shortcuts
- a “mission control” layout for running life/admin flows

Recommended UI:

- 2 to 4 rows of configurable tiles
- sections like `Capture`, `Think`, `Communicate`, `Admin`
- optional side panel for latest result / recent runs / Mac status

### AI-enabled shortcut examples

- `Summarize current Mac context`
- `Capture screenshot + explain what matters`
- `Dictate and turn into email draft`
- `Create reminder from spoken thought`
- `Turn latest memo into tasks`
- `Ask Talkie about the last meeting`
- `Save screenshot + transcript to Notes`
- `Run my "daily reset" workflow`

## Availability Model

The companion surface should appear only when all of the following are true:

1. Companion Mode is enabled on the Mac.
2. Companion Mode is enabled on the iPhone/iPad.
3. Talkie is running on the Mac.
4. The Mac advertises a healthy local companion service.
5. The mobile device discovers that service on the local network.
6. The user identity and trust relationship validate.

If any condition fails, the surface should fall back to an unavailable state instead of showing stale buttons.

## Product Definition

### User-facing name

Working name: `Companion Mode`

Alternative names worth considering:

- `Desk Mode`
- `Talkie Deck`
- `Shortcut Deck`

`Companion Mode` is the clearest umbrella term, while `Deck` can be used inside the UI to describe the actual shortcut surface.

### Mac-side controls

New macOS settings area:

- `Enable Companion Mode`
- `Advertise on local network`
- `Allow iPhone/iPad shortcut control`
- `Require same Talkie account`
- `Require prior pairing approval`
- `Show only pinned actions`
- `Choose actions visible on companion devices`

Mac runtime controls:

- `Activate Shortcut Mode`
- `Return devices to normal mode`
- `Choose active companion layout`
  - `Compact Remote`
  - `Expanded Deck`
  - `Shortcut Mode`
- `Request connected devices follow this layout`

### iPhone/iPad-side controls

New apps/ios/iPadOS settings area:

- `Enable Companion Mode`
- `Discover Macs on local network`
- `Preferred surface`
  - `Compact Remote`
  - `Expanded Deck`
- `Auto-open when Mac is available`
- `Show only trusted Macs`
- `Layout control`
  - `Follow computer requests`
  - `Ask each time`
  - `Keep my own layout`

### Mac-authored active layout

For V1, layout control should be double opt-in.

That means:

- the iPhone/iPad still stores its own default preferences
- the Mac may request a temporary layout change for the live paired session
- the mobile device independently decides whether it follows computer-driven layout requests
- any temporary override ends when the Mac turns it off, disconnects, or Talkie stops running

This supports the workflow you described:

1. Mac is paired with the iPhone/iPad.
2. Mac user toggles `Activate Shortcut Mode`.
3. Mac sends a live request for connected devices to switch layouts.
4. Devices set to `Follow computer requests` switch into the shortcut-oriented layout.
5. Devices set to `Ask each time` can accept or decline.
6. Devices set to `Keep my own layout` ignore the request and stay where they are.
7. When the mode is turned off, compliant devices fall back to their normal layout.

This is better than trying to infer the “right” surface from context because it makes the state explicit, reversible, and user-controlled on both sides.

## UX Flow

### First-time setup

#### On Mac

1. User opens Talkie Settings.
2. User enables `Companion Mode`.
3. Talkie explains that the feature appears only when the app is running and reachable on the local network.
4. User chooses whether to expose pinned actions only or a custom deck.
5. Mac starts advertising a local companion service.
6. Mac can later enable `Shortcut Mode` from a lightweight runtime toggle.

#### On iPhone/iPad

1. User enables `Companion Mode`.
2. App requests Local Network permission with clear language.
3. App discovers eligible Macs.
4. User selects a Mac and confirms trust.
5. App stores the preferred deck layout for that Mac.
6. User chooses whether this device should follow computer-requested layout changes.

### Daily use

1. User opens Talkie on the Mac.
2. Mac advertises Companion availability.
3. iPhone/iPad discovers the Mac and shows a `Talkie Deck Available` state.
4. If the Mac has activated a specific companion layout, the mobile app checks its `Layout control` preference.
5. If allowed, it switches into that layout.
6. The action surface becomes active.
7. Tapping a tile sends a low-latency command to the Mac.
8. The Mac executes locally and streams back progress/result state.

### Unavailable states

The mobile app should clearly distinguish:

- `Talkie not running on Mac`
- `Mac not on this network`
- `Companion Mode disabled on Mac`
- `Trust approval required`
- `Mac busy/offline`

## Surface Model

### Surface A: Compact Remote

Optimized for iPhone portrait.

Suggested layout:

- status strip
- primary action row
- 4 to 6 quick tiles
- recent result chip

Suggested primary actions:

- `Talk`
- `Screen`
- `Latest Memo`
- `Run Workflow`

### Surface B: Expanded Deck

Optimized for iPad landscape and portrait.

Suggested layout:

- persistent Mac status header
- configurable grid of 8 to 20 tiles
- optional recent-run column
- optional floating transcript/result card

Suggested tile groups:

- `Capture`
  - Dictate
  - Screenshot
  - Save note
- `Transform`
  - Summarize
  - Extract tasks
  - Rewrite
- `Route`
  - Reminder
  - Calendar
  - Notes
- `Custom`
  - user-pinned workflows

### Surface C: Shortcut Mode

This is the deterministic, Mac-activated surface for the first version.

It should feel closer to an external command pad than to a general-purpose app screen.

Recommended behavior:

- typically requested from the Mac while the paired session is live
- mirrored on iPhone and iPad with device-specific sizing
- fixed or lightly configurable set of high-value shortcuts
- exits automatically when Mac control ends
- only becomes active on devices that have opted into following computer requests or accepted the prompt

Recommended initial actions:

- `Talk`
- `Screen`
- `Latest Memo`
- `Pinned Workflows`
- `Tasks`
- `Note`

## Action Model

Companion actions should support four classes.

### 1. Immediate Mac actions

Low-latency commands handled directly by the Mac companion service:

- start dictation
- stop dictation
- capture screenshot
- capture active window
- copy latest transcript
- open Talkie view

These should not go through the cloud workflow queue.

### 2. Workflow launch actions

Launch an existing Talkie workflow with optional inputs:

- latest memo
- ad hoc dictated text
- screenshot artifact
- selected template prompt

These can reuse the existing live workflow run concepts, but should prefer a local fast lane when the target Mac is already present.

### 3. Compound AI shortcuts

Predefined action recipes that feel like one button to the user but map to multi-step execution.

Examples:

- `Screenshot + explain`
- `Dictate + extract action items`
- `Capture thought + save to Notes`

These can compile down to either:

- a local command plus a workflow launch
- a dedicated lightweight companion action definition

### 4. Surface-only utilities

Actions that affect presentation rather than execution:

- switch deck
- reorder tiles
- temporarily pin last result
- reveal recent runs

## Recommended Technical Architecture

### Discovery

Use local network discovery on the LAN.

Recommended approach:

- macOS advertises a Bonjour service such as `_talkie-companion._tcp`
- apps/ios/iPadOS uses `Network.framework` browsing to discover available Macs
- discovery payload includes:
  - device name
  - stable device ID
  - app mode/capabilities
  - companion protocol version
  - whether the Mac is currently ready

Why this fits Talkie:

- it satisfies the “same network right now” requirement
- it avoids inferring physical location
- it keeps latency low
- it gives a clean availability signal tied to the running app

For V1, discovery should be subordinate to pairing and connection state, not a separate product concept. In other words, the user experience should feel like:

- “my paired Mac is available”
- not “a random Talkie service appeared on my network”

### Trust and authentication

Reuse existing Talkie trust primitives where possible instead of inventing a separate auth story.

Recommended trust chain:

1. Same Talkie account is required by default.
2. Existing bridge pairing can be used as a bootstrap trust signal when available.
3. First-time local approval on the Mac authorizes a given iPhone/iPad device.
4. The companion session uses a short-lived local session token after trust succeeds.

This allows:

- secure local control
- explicit per-device approval
- low-friction reconnection on later sessions

### Session transport

Recommended transport:

- HTTPS or WebSocket endpoint hosted by the running Mac app or existing bridge server layer
- one request/response channel for actions
- one streaming channel for presence, progress, and results

Suggested direction:

- extend the existing local bridge/server stack instead of creating a second daemon
- add a `companion` router namespace for presence and action execution
- include a layout-request broadcast so the Mac can ask connected devices to enter `Shortcut Mode` or other layouts

Example route families:

- `/companion/health`
- `/companion/deck`
- `/companion/layout`
- `/companion/actions/:id/run`
- `/companion/runs/:id`
- `/companion/presence`

### Execution lanes

Use two execution paths.

#### Lane 1: local direct actions

For low-latency commands like:

- screenshot
- start dictation
- stop dictation
- open a view

These should execute directly in the running Mac session.

#### Lane 2: workflow-backed actions

For richer AI shortcuts:

- create a run from the mobile surface
- route it into the local workflow executor if the discovered Mac is healthy
- optionally mirror into the existing control-plane model for status consistency

This keeps the companion experience fast while staying compatible with current workflow infrastructure.

## Relation To Existing Talkie Architecture

This idea aligns well with current building blocks.

### Existing iOS assets we can reuse

- `BridgeManager` for paired-Mac identity and trust concepts
- `DirectMacRegistry` for “known Macs” modeling
- `TalkieAppConfiguration` for file-backed iPhone settings
- existing keyboard layout and active-layout persistence concepts in `TalkieAppSettings`
- keyboard configurator concepts for tile/slot customization
- cached pinned Mac workflows in `workflows.pinnedMacActions`

### Existing macOS assets we can reuse

- workflow pinning and action-surface metadata in `workflows/config.json`
- workflow control-plane client/service concepts
- screenshot and bridge server infrastructure
- home/shortcut widgets as inspiration for deck presentation

### Important architectural note

The current cloud-backed live workflow queue is good for deferred or cross-network execution. Companion Mode should not depend on that queue for its baseline interaction model because the core promise here is “instant local control while the Mac is present.”

Cloud queueing remains a useful fallback for long-running workflow tracking, but not for the first tap latency.

## Proposed Data Model Additions

This is a spec-only proposal for future implementation.

### iOS app config

Add a new `companion` section to `apps/ios/Talkie iOS/Services/TalkieAppConfiguration.swift`.

Suggested fields:

- `enabled: Bool`
- `autoPresentWhenAvailable: Bool`
- `preferredSurface: String`
- `layoutControlMode: String`
- `trustedMacIDs: [String]`
- `selectedMacID: String`
- `activeRemoteSurface: String?`
- `remoteSurfaceExpiresAt: TimeInterval`
- `deckLayouts: [String: CompanionDeckLayout]`
- `lastSeenMacs: [CompanionMacSnapshot]`

Suggested `layoutControlMode` values:

- `followComputer`
- `askEachTime`
- `localOnly`

### macOS workflow config

Extend `WorkflowConfiguration.WorkflowPreferenceSnapshot` or sibling metadata with optional companion-surface fields:

- `showInCompanion: Bool`
- `companionRank: Int`
- `companionGroup: String`
- `companionRequiresInput: Bool`

This would let the user pin workflows generally while still curating what appears on the mobile deck.

### macOS app settings

Add a `companion` section to the macOS settings config with fields such as:

- `enabled`
- `advertiseOnLocalNetwork`
- `requireSameAccount`
- `requireApprovalForNewDevices`
- `exposedSurfaceMode`
- `allowedDeviceIDs`
- `activeCompanionLayout`
- `requestLayoutChangesForConnectedDevices`

## Companion Deck Configuration

The deck should not just mirror “all pinned workflows.” It needs first-class curation.

Recommended deck item types:

- `systemAction`
- `workflowAction`
- `compoundAction`
- `group`

Each item should support:

- id
- title
- icon
- tint
- placement
- confirmation requirement
- optional input mode
- optional result behavior

## Example Deck

### iPad daily deck

- `Talk`
  - hold to dictate to Mac
- `Screen`
  - capture current screen and analyze
- `Inbox`
  - turn latest thought into tasks
- `Daily Reset`
  - run admin workflow
- `Reply`
  - draft response from latest context
- `Note`
  - save dictated thought to Notes
- `Remind`
  - create reminder from speech
- `Ask`
  - ask Talkie a question about recent memos

### iPhone compact deck

- `Talk`
- `Screen`
- `Latest`
- `Tasks`
- `Note`
- `More`

## Status and Feedback

The mobile surface should feel live.

Recommended feedback states:

- `Ready`
- `Running`
- `Listening`
- `Waiting for Mac`
- `Needs approval`
- `Failed`

Recommended feedback behaviors:

- per-tile progress state
- subtle haptics on successful trigger
- one-line result summaries
- ability to tap into the full workflow run detail when needed

## Security and Privacy

### Requirements

- no passive discoverability unless the user enables Companion Mode
- no action execution from an unapproved device
- all local transport is authenticated
- screen capture actions require explicit consent at setup time
- the user can revoke a device from the Mac

### Privacy posture

The companion should expose presence and actions, not broad ambient browsing by default. A user should have to opt into richer remote context views if they want them.

## Risks

### 1. Too much overlap with Bridge

If Companion Mode feels like “Bridge, but again,” it will create product confusion. We should position it as a presence-based local control surface, not as a generic connection mechanism.

### 2. Too much overlap with keyboard mode

If the iPad deck merely recreates the existing keyboard shortcut grid, it will feel redundant. The differentiator should be live Mac execution and AI workflows, not only text insertion.

### 3. Latency regression

If taps go through cloud pathways or heavyweight workflow startup too often, the feature will feel mushy. Local direct actions need a genuinely fast path.

### 4. Permission complexity

Local network, microphone, screenshots, account auth, and pairing can easily become messy. The setup flow has to explain the value clearly and stage permissions gradually.

## Phased Rollout

### Phase 1: Presence and basic remote deck

Ship:

- Mac advertising on local network
- iPhone/iPad discovery
- opt-in setup
- basic status header
- a small fixed set of direct actions

Actions:

- start/stop dictation
- capture screenshot
- open Talkie

### Phase 2: Pinned workflow deck

Ship:

- show pinned Mac workflows on companion devices
- per-workflow visibility rules for companion mode
- run-status feedback

### Phase 3: Configurable iPad shortcut board

Ship:

- deck editor
- groups/sections
- larger tile grid
- custom icons and placement

### Phase 4: Compound AI shortcuts

Ship:

- “capture + transform + route” one-tap actions
- light parameter prompts
- result cards and recent-run rail

## Recommended MVP

If we want the smallest compelling version, build this:

1. Opt-in Mac/iPhone local companion presence.
2. Double-opt-in layout control:
   - Mac can request `Shortcut Mode`
   - each mobile device chooses whether to follow computer requests
3. A compact shortcut deck on iPhone and a larger shortcut deck on iPad.
4. Three direct actions:
   - `Talk`
   - `Screen`
   - `Run pinned workflow`
5. A live availability model that disappears when Talkie is not running on the Mac.
6. A minimal editor that lets the user choose which pinned workflows appear.

That gives us the distinctive “shortcut keyboard for your life” direction without overcommitting to a huge remote-control surface on day one.

## Proof Of Concept

If we want a very light version that proves the idea without all the bells and whistles, the goal should be:

- preserve the real control model
- avoid premature deck customization
- avoid new cloud dependencies
- prove that the Mac can request a mobile shortcut surface and the mobile app can use it to trigger a real Mac action

### POC product shape

Build only this:

1. One paired Mac.
2. One iPhone or iPad.
3. One Mac toggle: `Shortcut Mode`.
4. One mobile preference: `Follow computer shortcut mode`.
5. One fixed mobile shortcut screen.
6. Two or three real actions that execute on the Mac.

That is enough to validate:

- the double opt-in model
- the local-network presence model
- the feeling of a phone or iPad becoming a temporary command deck

### What the POC should do

#### On Mac

- add a simple toggle in an existing settings/debug surface or menu-bar/dev surface:
  - `Shortcut Mode: On/Off`
- when turned on, the Mac publishes:
  - `companion available`
  - `requested layout = shortcut`

#### On iPhone/iPad

- add a single setting:
  - `Follow computer shortcut mode`
- when enabled and the paired Mac requests shortcut mode:
  - show a fixed `Shortcut Mode` screen
- when disabled:
  - ignore the Mac request and keep the normal mobile UI

#### Shortcut screen

Use a fixed layout, not a configurable deck.

Suggested buttons:

- `Talk`
- `Screen`
- `Pinned`

If we want to go even lighter, start with just:

- `Screen`
- `Pinned`

### Recommended POC actions

Choose actions with the least new infrastructure.

#### Best first action: `Run pinned workflow`

Why:

- iOS already knows about pinned Mac workflows
- Talkie already has workflow execution concepts
- it proves the “AI shortcut” story
- it avoids solving live microphone routing immediately

POC behavior:

- mobile screen shows first 1 to 3 pinned workflows
- tapping one sends a local request to the paired Mac
- Mac executes the workflow locally
- mobile shows a simple `Running` then `Done` state

#### Best second action: `Screen`

Why:

- Mac-side screenshot capability already exists in the bridge/server direction
- it proves device-to-Mac command dispatch
- it feels immediately magical

POC behavior:

- tapping `Screen` triggers a Mac screenshot capture
- Mac returns success only, not a full screenshot viewer
- optional: show a small success label like `Captured on Mac`

#### Defer `Talk`

`Talk` is compelling, but it likely pulls in more complexity around microphone ownership, audio routing, or dictation session semantics. For a POC, it is a good fake button or second-phase action, not the first thing we need to make real.

### What to skip in the POC

Do not build these yet:

- deck editor
- group/section customization
- per-device layout catalogs
- complex result views
- “ask each time” prompts
- companion-specific workflow curation UI
- cross-network support
- multiple simultaneous Macs
- iPad-only bespoke layouts

Keep the structure, but stub the surface area.

### POC control model

To stay aligned with the real product, keep these rules even in the light version:

- Mac can request `Shortcut Mode`
- mobile device must have `Follow computer shortcut mode` enabled
- request only works while the paired Mac is connected and available
- when Mac turns the mode off, mobile leaves shortcut mode

That way the POC is structurally correct, even if visually simple.

### Simplified technical approach

The fastest path is to reuse the existing pairing and bridge concepts rather than building full Bonjour discovery first.

#### POC connectivity

Use:

- existing paired Mac identity from `BridgeManager`
- existing local connection path if available through the current bridge stack
- a tiny new message or endpoint for:
  - current companion availability
  - requested layout
  - action trigger

This means the POC can be:

- pair first
- connect to the paired Mac
- poll or subscribe for `shortcut mode on/off`
- send simple action commands back

That is much lighter than building the full discovery story first.

### Minimal protocol

The POC only needs three concepts:

- `isCompanionAvailable: Bool`
- `requestedSurface: normal | shortcut`
- `runAction(id)`

Example actions:

- `captureScreen`
- `runPinnedWorkflow:<workflow-id>`

### Minimal UI surfaces

#### macOS

One tiny control surface is enough:

- existing settings/debug panel
- or menu bar item
- or live/dev toolbar

Fields:

- `Companion Available`
- `Shortcut Mode` toggle

#### apps/ios/iPadOS

One minimal screen is enough:

- status text:
  - `Following Mac shortcut mode`
  - or `Mac requested shortcut mode, but this device is not following`
- fixed button grid

No editor, no per-layout navigation, no extra onboarding flow beyond one toggle.

### Suggested implementation order

1. Add one mobile preference:
   - `Follow computer shortcut mode`
2. Add one Mac runtime toggle:
   - `Shortcut Mode`
3. Expose a tiny bridge payload for current requested surface.
4. Make apps/ios/iPadOS switch to a fixed shortcut screen when conditions match.
5. Wire one real action:
   - `Run pinned workflow`
6. Optionally wire a second real action:
   - `Screen`

### Smallest believable demo

The smallest believable demo is:

1. Pair iPhone/iPad with Mac.
2. Enable `Follow computer shortcut mode` on mobile.
3. Turn on `Shortcut Mode` on Mac.
4. Mobile app switches to a fixed shortcut layout.
5. Tap `Quick Summary`.
6. Mac runs the pinned workflow.
7. Mobile shows `Done`.

That already demonstrates the core product idea.

### Why this is the right light cut

This version is intentionally narrow, but it does not cheat on the architecture.

It still proves:

- Mac-led but mobile-approved coordination
- a temporary companion surface
- local command dispatch
- AI shortcut execution on the Mac

It just avoids spending time on customization, discovery polish, and multi-surface richness before we know whether the basic interaction feels great.

## Open Questions

- Should Companion Mode require existing bridge pairing, or allow same-account local approval without prior bridge setup?
- Should iPad support a persistent landscape dashboard intended to stay open on a stand?
- Should dictated input originate on the iPhone/iPad microphone or remotely trigger Mac dictation?
- Should screenshot mean:
  - capture on the Mac
  - capture on the mobile device
  - or both as separate actions?
- Should companion-only quick actions be separate from pinned workflows, or a view over the same workflow catalog?

## Recommendation

Pursue this as a dedicated local-network surface, not as a side effect of existing sync or bridge features.

The strongest version of the idea is:

- explicitly enabled
- visible only when the Mac is genuinely present and running Talkie
- centered on fast AI shortcuts
- differentiated by form factor between iPhone and iPad

That gives Talkie a distinctive multi-device interaction model: your Mac does the work, and your phone or iPad becomes the instantly available deck for steering it.
