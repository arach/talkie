# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

Talkie ships two first-class native apps that each follow their own OS design language: a macOS app plus companion agent (`apps/macos/Talkie/`, `apps/macos/TalkieAgent/`) and an iOS app with widget, share, keyboard, and watch targets (`apps/ios/`). Neither is a wrapper around the other or around a website. Supporting web services exist (`services/talkie.to`, `services/talkie-admin`) but are not design surfaces under this record.

## Users

**Primary (beachhead): developer and agent-driven power users.** People who live inside terminals, editors, browsers, and coding agents, switching context many times an hour. They are keyboard-first, expect global availability, and are capturing thoughts *while* doing something else — mid-task, mid-session, hands already on the keyboard. The ambient-context work (`docs/product/ambient-context-vision.md`) describes this user concretely: dictations that land against a Claude Code session, a git branch, a specific window.

**Adjacent (kept open, not yet designed for): knowledge workers broadly** — anyone who needs to externalize a thought fast without breaking flow (`docs/product/positioning.md`). Design decisions serve the power-user core today; they must not foreclose this path, but they also must not be diluted toward a hypothetical general audience.

The job, in both cases: *get the thought out of my head in the cheapest possible way right now, and let me recover it later with its context intact.*

## Product Purpose

Talkie is a multi-modal capture system with one memory behind it. Speech, typing, screen, and camera are entry points; a single searchable, transformable body of captured work is the product.

The promise is not "record audio" or "dictate anywhere." It is:

> capture the thought in the cheapest possible way now, then recover, search, transform, and act on it later.

Success means a user externalizes a thought without breaking flow, and later finds it — with the surrounding context (app, window, URL, moment) still attached — without having filed, tagged, or organized anything.

## Positioning

**Talkie is a multi-modal capture system, framed that way externally as well as internally.** One capture system with several entry points, not a voice memo app that grew features. This resolves the open question in `docs/product/positioning.md`: the product is *not* to be led with as "voice-first" externally, even though voice is the simplest door in.

What a neighboring product cannot truthfully copy:

1. **Context-aware capture.** Every capture carries its environment — source app, window title, browser URL when available, device and capture surface. That context is what makes later retrieval and routing smart, and it is captured for free at the moment of capture, not reconstructed after.
2. **Desktop-native, not browser-native.** Global hotkey capture, menu-bar/utility behavior, app-aware context, screenshots and window capture. Talkie sits next to the OS, not inside a tab.
3. **Local-first personal infrastructure.** Captures and context live on-device (SQLite). There is no server receiving ambient context. The user is the only audience for their own data — not aggregated, not anonymized-and-shipped, not training anything.
4. **AI as amplifier, not as the product.** Transcription, summarization, search, workflow routing, structured outputs. The product starts at capture and memory, not at a prompt box.

Language to prefer: *capture in whatever mode is fastest · externalize thoughts without breaking flow · pick it up later with context intact · one system for memos, dictation, notes, and workflows · a personal memory layer for active work.* An internal shorthand that has proven useful: *a selfie for your thoughts.*

Language to avoid: reducing Talkie to "voice memo app," "dictation app," or "workflow tool." Each is true and none is the product.

## Operating Context

- **Capture happens mid-task.** The user is inside another app when they capture. Talkie's surfaces appear over, beside, or behind that work — recording HUD/overlay, tray, camera bubble, command palette, quick-open — and must not demand the foreground or steal focus.
- **The dictation hotkey is a sacred interaction.** Press, speak, release, sub-second latency, zero friction. Nothing may be added to that path — no confirmation, no context gathering, no dialog. Heavier work (context accumulation, transformation) happens *between* captures, asynchronously.
- **Multi-device and multi-process.** The Mac app, the companion agent, an on-device engine, a local Bun bridge/server, an iOS app, and a CLI all participate. Devices pair over Tailscale by default; local mode binds to loopback with a short-lived bearer token.
- **The CLI is a real usage surface.** `talkie` with structured JSON output is how the user and their agents query captures — it is composable, scriptable, and the query layer for agent workflows, not a debugging afterthought.
- **Retrospective, not real-time.** Reconstruction ("what did I work on?", "what's ready to ship?") is something the user asks for after the fact. Talkie is not a live dashboard or an analytics feed.

## Capabilities and Constraints

**Confirmed capabilities**

- Voice memos, push-to-talk dictation, typed notes and scratchpad, transcripts, and readouts (spoken playback of captured or transformed content) — one object model behind all of them (`TalkieObject`; the GRDB table is still `recordings`).
- On-device transcription (Whisper and Parakeet engines), with model install handled in onboarding.
- Capture-time context metadata: source app and bundle ID, window title, browser URL via accessibility, capture surface, duration, word count, engine timing.
- Screen, window, and camera capture surfaces alongside audio.
- Workflows and AI-assisted transforms against transcripts and live context; optional provider keys (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `GROQ_API_KEY`).
- Sync across devices (CloudKit plus a local bridge/gateway); an agent home for Claude-driven work under Application Support.
- iOS widget, share extension, custom keyboard, and watch targets.
- `talkie` CLI (`packages/npm/cli/`) and TypeScript SDK (`packages/npm/sdk/`).

**Durable constraints**

- **Local-first, no exfiltration.** Ambient context never leaves the machine. Any future server work must not become a path for it. This is architectural, not a preference.
- **Capture follows user intent.** Passive context attaches to an intentional capture; it does not run continuously or independently. Talkie is not surveillance and must never read as such.
- **Permissions are real and staged.** Microphone always; accessibility and screen recording only when the agent/Live features are installed. Onboarding adapts to which mode is present, and services (agent, engine) launch invisibly — the user never sees a "starting services" step.
- **Two OS design languages.** macOS (Tahoe-era SwiftUI, menu-bar/utility behavior, signing and notarization) and iOS 26; shared logic lives in Swift packages, but presentation follows each platform's native expectations.
- Source-available under PolyForm Noncommercial 1.0.0. Commercial use, resale, hosted services, or App Store redistribution by others requires a separate license.

**Terminology (use these words, in the product and in design work)**

memo · dictation · note · scratchpad · transcript · readout · capture · context · workflow · agent. A `TalkieObject` is the unified content primitive; its type determines presentation emphasis, not a separate product.

**Explicitly undecided**

- Whether "readouts" is the durable user-facing name for listen-back/spoken output.
- Whether the broader knowledge-worker audience gets its own surfaces, or is served by the same ones.

## Brand Commitments

- Name: **Talkie**. Existing icon and identity assets live in `assets/brand/`, `assets/logo-primitives*/`, and `assets/icon-assets/`.
- Voice: direct, technical, unhyped. The product is personal infrastructure and should sound like it — no growth-marketing register, no anthropomorphized assistant persona.
- A design system with tokens and automated audit tooling already exists (`docs/engineering/milestone-design-system-v1.md`); the shipped apps have a real incumbent visual world. New work reckons with it rather than assuming a blank slate.

## Evidence on Hand

- Product docs: `docs/product/positioning.md`, `docs/product/ambient-context-vision.md`, `docs/product/onboarding-spec.md`.
- Engineering/architecture: `docs/engineering/ARCHITECTURE.md`, `topology.md`, `context-capture-architecture.md`, `PERFORMANCE.md`, `milestone-design-system-v1.md`.
- Real product screenshots: `assets/talkie-home.png`, `talkie-memos*.png`, `talkie-capture.png`, `talkie-settings*.png`, `screenshot.png`.
- A visual exploration studio for native treatments: `design/studio/` (Next.js/Tailwind studies used to iterate on palette, material, and composition before porting to SwiftUI), plus `design/reviews/` and `design/screenshots/`.
- A live prototype session demonstrated full workday reconstruction from dictation metadata + git/PR state across four repos (`docs/product/ambient-context-vision.md`). This is a real demonstration, not a projection.

**Absences future work must not fabricate:** there are no published testimonials, named customers, user counts, benchmark results, pricing, awards, or press. Do not invent them, and do not imply a customer base the product does not have.

## Product Principles

1. **Never tax the capture moment.** Latency and friction at capture outrank every other consideration. Anything expensive happens between captures.
2. **Context is captured, never reconstructed.** The environment around a thought is recorded for free at capture time — that is the moat and the reason retrieval works.
3. **The user is the only audience for their data.** Every design decision must read as personal infrastructure, not as a service watching them.
4. **Capture in the cheapest mode available.** Voice, typing, screen, or camera — the system adapts to whichever is fastest right now; no mode is the "real" one.
5. **AI amplifies captured thought; it does not replace it.** Transforms, summaries, and agents act on the user's own material and stay subordinate to it.
6. **Native, keyboard-first, always available.** Talkie behaves like part of the operating system, not like an app the user must go visit.

## Accessibility & Inclusion

No accessibility standard has been committed to as a product requirement. The current state is partial: both apps use `accessibilityLabel` in places (more consistently on iOS than macOS), with no systematic VoiceOver, keyboard-navigation, reduced-motion, or contrast audit behind it. This is an open decision, not a settled bar — future work should either establish the standard deliberately or avoid claiming compliance.
