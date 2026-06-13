# TLK-030 Review Notes — Skeptical Architecture Review

**Reviewer**: talkie-arch-review (Scout relay worker)
**Date**: 2026-06-13
**Subject**: `docs/specs/tlk-030-modular-build-architecture.md`
**Stance**: skeptical / risk-first (not agreement)

## Runtime / model assumptions (disclosure)

Invoked via Scout as "claude, model opus, reasoning-effort high, permission-profile
review." Actual runtime: I am Claude Opus (`claude-opus-4-8`) in the Claude Code
harness. I cannot introspect or verify the Scout launch flags — "reasoning-effort
high" and "permission-profile review" are not values I can confirm from inside the
session. In practice this task was **read-only**: I inspected the repo and modified no
source. The only file I wrote is this review document.

---

## 1. Findings (ordered by severity)

### F1 — CRITICAL: the "pure overlay" first-slice premise is false; the listed files depend *upward* on app-target singletons

The spec (§"First Extraction Candidate") asserts the clean first step is "pure overlay
UI, hit-testing, markup session types" that "only depends on AppKit, ScreenCaptureKit,
and shared capture contracts." The code contradicts this for most of the listed files:

| File | App-target singletons it calls |
|---|---|
| `Services/Capture/CaptureBarController.swift` | `FeatureFlags.shared`, `SelectionTray.shared` |
| `Services/Capture/CaptureHUDController.swift` | `FeatureFlags.shared`, `SelectionTray.shared`, `SettingsManager.shared` |
| `Services/Capture/CaptureHUDPanel.swift` | `SettingsManager.shared` |
| `Services/Capture/WallpaperLuminanceSampler.swift` | `ScreenshotCaptureService.shared` |
| `Services/Screenshots/ScreenCaptureOverlay.swift` | `FeatureFlags.shared` |
| `Services/Screenshots/CaptureMarkupPanelChrome.swift` | `EphemeralTranscriber.shared`, `LLMConfig.shared`, `LLMProviderRegistry.shared` |

Every one of these singletons is defined in the **app target**, not TalkieKit:
- `Talkie/Services/FeatureFlags.swift:18`
- `Talkie/Services/Tray/Data/SelectionTray.swift:43`
- `Talkie/Services/SettingsManager.swift:965`
- `Talkie/Services/EphemeralTranscriber.swift:72`
- `Talkie/Services/LLM/LLMConfig.swift:15` (app-only; no TalkieKit equivalent)
- `Talkie/Services/LLM/LLMProvider.swift:238` (`LLMProviderRegistry`)

Consequence: extracting these into a *lower* module (`TalkieCaptureKit`) is impossible
without one of two things the operator explicitly wants to avoid:
(a) dragging app-state singletons (`FeatureFlags`, `SelectionTray`, `SettingsManager`,
`EphemeralTranscriber`, LLM config) down into the "stable lower" module — which inflates
the lower module with app state and defeats the granularity goal; or
(b) inverting every dependency through injected protocols — net-new indirection on a
latency-sensitive capture path, exactly the "dependency indirection / runtime
complexity" the review was asked to guard against.

`CaptureMarkupPanelChrome.swift` (46 KB) pulls the LLM stack and the transcriber. It is
not a leaf and should not be in any "clean first step."

### F2 — HIGH: name-collision causes a *silent semantic swap* on move

`ScreenshotCaptureService` and `LLMProviderRegistry` already exist as **two distinct
classes** in two modules:
- `Talkie/Services/ScreenshotCaptureService.swift:80` — `@MainActor final class`, own `static let shared`
- `TalkieKit/Sources/TalkieKit/Capture/ScreenshotCaptureService.swift:15` — `public final class`
- `Talkie/Services/LLM/LLMProvider.swift:238` (app) vs `TalkieKit/Sources/TalkieKit/LLM/LLMProvider.swift:173`

Today, files like `WallpaperLuminanceSampler.swift` `import TalkieKit` yet `.shared`
resolves to the **app** class (same-module wins over imported). The moment that file is
moved into `TalkieCaptureKit` (which can see TalkieKit but not the app module),
`ScreenshotCaptureService.shared` silently rebinds to the *TalkieKit* class — a
different type with potentially different behavior. This is a runtime bug introduced
purely by relocation, invisible at the diff level because the call site is unchanged.
The duplicate classes are a pre-existing latent hazard and are a bigger risk than build
time. **They must be reconciled to a single canonical type before any capture file
moves.**

### F3 — MEDIUM-HIGH: resource relocation hazard is understated

Capture markup loads bundled web assets from `Bundle.main`:
- `Services/Screenshots/CaptureMarkupWebSession.swift:286` — `Bundle.main.resourceURL?.appendingPathComponent("Resources/CaptureMarkup")`
- `Services/ScreenRecording/LiveCaptureMarkupOverlayController.swift:159` — same pattern

These reference `overlay.html/css/js`, which were **just added to the app bundle** (still
untracked: `apps/macos/Talkie/Resources/CaptureMarkup/overlay.{html,css,js}`). Phase 4
moves the overlay controller into a package, which requires (a) relocating those
resources into the package, (b) declaring them in `Package.swift` (`.copy`/`.process`),
and (c) rewriting every `Bundle.main` lookup to `Bundle.module`. The existing multi-path
fallback search already signals that resource location is fragile. The spec's Risks
section mentions "resource and localization assumptions" but does not flag that the
chosen first slice (WebKit + bundled JS/HTML/CSS) is precisely the resource-heavy case.

### F4 — MEDIUM: the build win is conditional and weakest for *actively changing* code

Xcode/SPM cross-module incremental builds only skip recompiling importers when the
upstream module's **public interface** is unchanged (implementation-only edits are free
to downstream). The spec's justification for choosing capture is that it "is actively
changing." But actively changing public overlay APIs will recompile the app composition
layer on every signature edit anyway — you pay a module-boundary tax (edit module, widen
public API, recompile both sides) for little incremental-build gain. The reliable win is
the opposite: extract **stable** code with a narrow, frozen interface. Starting with the
file you edit most is the lowest-ROI choice for incremental builds.

### F5 — MEDIUM: overlay/WebView latency is unmeasured

Capture markup runs a `WKWebView` (`CaptureMarkupWebSession` imports WebKit) on a path
where the overlay must appear immediately on capture. Wrapping session setup behind a
module with injected dependencies adds an init/wiring layer to a UX-latency-sensitive
flow. The spec measures only build time, never overlay-show latency or first-WebView-
ready time, so a regression here would be invisible to its success metric.

### F6 — LOW-MEDIUM: the 6-module graph is a large upfront bet against the spec's own risk

The proposed graph (`TalkieCore`, `TalkieDataKit`, `TalkieDesignKit`, `TalkieCaptureKit`,
`TalkieWorkflowKit`, `TalkieFeatureModules` + a `TalkieKit` facade) is drawn before a
single extraction has proven value. The spec itself lists "too many tiny modules" as a
risk. Don't commit to the whole graph; prove one stable extraction first.

### F7 — LOW (positive): signing/embedding is correctly de-risked

Build Rule 5 (static targets first; dynamic frameworks only if link time stays painful)
is the right call — static library targets add no embed/sign/`dlopen` cost. `run.sh`
already does a post-build `codesign --force --deep` + `--verify --deep --strict`
(`run.sh:340-359`), so it would tolerate embedded frameworks if they ever appear. No new
signing cost for the static-target plan. Keep it static.

---

## 2. TLK-030 recommendations that increase runtime risk or build fragility

- **"Phase 4: Move Capture Overlay UI" / the capture-first slice (lines 124-148, 197-202).**
  As written it moves files that depend on six app singletons (F1) and on `Bundle.main`
  resources (F3), and it risks the silent class-swap (F2). Highest-risk, lowest-ROI
  starting point.
- **"Move pure capture markup models/rendering first" is fine; pairing it with overlay
  controllers in the same "clean first step" is not** — the section conflates a genuinely
  safe move (models already in TalkieKit) with an unsafe one (singleton-coupled
  controllers).
- **The full first-level graph (lines 45-79).** Committing to 6 modules + facade before
  measuring contradicts the spec's own "too many tiny modules" risk.
- **Implicit assumption that module split reduces incremental cost for churning code (F4).**
  True only for interface-stable modules.

---

## 3. Safest first extraction path + what stays app-side

**Reorder the spec: do Phase 3 first, and consider stopping there until measured.**

Safe first slice (in order):
1. **Reconcile the duplicate classes** (`ScreenshotCaptureService`, `LLMProviderRegistry`)
   to one canonical definition. Non-negotiable prerequisite (F2).
2. **Consolidate the capture-markup model/document/rendering types that already live in
   TalkieKit** (`CaptureMarkup/CaptureMarkupDocument.swift`, `CaptureMarkupRenderer.swift`,
   `CaptureMarkupStorage.swift`, `RecordingVisualContext.swift`) into a dedicated target
   (`TalkieDataKit` or `TalkieCaptureKit`). These have no app-singleton dependencies and
   are already package-resident — near-zero risk, and they exercise the multi-target
   `Package.swift` pattern.
3. **Optionally** extract the pure luminance math out of `WallpaperLuminanceSampler`
   (AppKit + CoreImage only), leaving the `ScreenshotCaptureService.shared` call app-side.

Must explicitly **stay app-side** (do not move, do not invert into a lower module yet):
- `FeatureFlags`, `SelectionTray`, `SettingsManager`, `EphemeralTranscriber`, `LLMConfig`,
  `LLMProviderRegistry` — app config/state singletons.
- `ScreenRecordingController.shared` and anything writing app repositories / tray.
- The capture **controllers** (`CaptureBarController`, `CaptureHUDController`) that
  orchestrate those singletons. Only pure SwiftUI view bodies / hit-testing / DTOs may
  move down, fed by app-owned state as **plain value inputs**, never via protocols that
  call back into the app.
- The `Bundle.main` overlay resources stay until a deliberate `Bundle.module` migration
  with the resources relocated (F3).

The guiding rule the spec already states ("the app calls into the module, not the module
calling back into the app") is correct — but the chosen files violate it. Pick files that
already satisfy it.

---

## 4. Measurement to prove it helps (before *and* after)

The spec's Phase 1 list is good but build-only. Establish a baseline **now**, before any
split:

Build:
- Clean build time; warm no-op build time (control = existing `./run.sh Talkie --no-launch`).
- Edit-leaf-file recompile: **count of recompiled files**, not just wallclock — the spec's
  real metric ("touch one overlay file"). Pull it from the build log's
  `CompileSwiftSources` count or `xcodebuild -showBuildTimingSummary`.
- Four scenarios: edit a leaf-module impl file; edit a leaf-module **public** API (worst
  case, F4); edit an app composition file; edit a low/stable-module file.

Runtime (to prove no UX/quality regression — this is what answers the operator's concern):
- Overlay show latency: capture trigger → overlay visible (add `os_signpost`).
- First markup `WKWebView` ready time.
- App cold-launch time and `.app` bundle size before/after (catches accidental dynamic
  frameworks; static libs should barely move these).

Gate: proceed past the model/rendering extraction only if leaf-edit recompile count drops
materially (target ≥5× fewer files) **and** overlay latency / launch time are unchanged.

---

## 5. Verdict: is the split overkill, and is the first slice wrong?

- **Not overkill in principle.** ~485 Swift files in one app target (per spec §Current
  Shape) is a real incremental-build tax; module boundaries are the standard remedy.
- **The first slice as written is wrong.** Capture overlay controllers are the most
  app-coupled (F1), the most actively churning (F4), and the most resource/WebView-bearing
  (F3, F5) code in the candidate set — maximizing inversion work, collision risk (F2), and
  recompile-on-interface-change. Worst ROI, highest bug surface.
- **Invert the order:** reconcile the duplicate classes, extract the already-package-
  resident markup models/rendering, measure, and only then revisit overlay UI once its
  singleton coupling is untangled. Don't draw the full 6-module graph up front; earn each
  module with a measurement.

---

## 6. Second-reviewer corroboration (Claude Opus 4.8, high effort — 2026-06-13)

Independent pass via the OpenScout relay. I reach the **same verdict** (sound direction,
wrong first slice, ordering is the real threat — not runtime cost) and **verified the two
most load-bearing claims against the code**:

- **F2 confirmed (the severe one).** `ScreenshotCaptureService` is defined twice —
  `Talkie/Services/ScreenshotCaptureService.swift:80` (app, internal `final class`) **and**
  `TalkieKit/.../Capture/ScreenshotCaptureService.swift:15` (`public final class`), each with
  `static let shared`. `LLMProviderRegistry` likewise: `Talkie/Services/LLM/LLMProvider.swift:238`
  vs `TalkieKit/.../LLM/LLMProvider.swift:173`. So a file that `import TalkieKit` but calls
  `ScreenshotCaptureService.shared` binds to the **app** type today (same-module wins); moving it
  into a module that can't see the app type silently rebinds to the *TalkieKit* type — same call
  site, different class, no compile error. This is the headline "makes it worse" risk and it
  gates everything: **reconcile to one canonical type before any capture file moves.**

- **F3 confirmed + sharpened.** `CaptureMarkupWebSession.swift:286-287` resolves markup web
  assets via `Bundle.main.resourceURL + "Resources/CaptureMarkup"` (copying `index.html` /
  `markup.css` / `markup.js`); assets live in the app bundle at `Talkie/Resources/CaptureMarkup/`
  (incl. the still-untracked `overlay.*`). Moving this file (the spec's "clean first step",
  `spec:135,145-148`) without a `Bundle.main`→`Bundle.module` rewrite **and** relocating the
  resources into the target's `resources:` produces a **silent runtime break** (lookup returns
  nil, falls through). Precedent for doing it right already exists: TalkieKit ships resources via
  `Bundle.module` (`TalkieKit/.../TalkieContextRoots.swift:25`, `TalkieKitFonts.swift:33`;
  `TalkieKit/Package.swift:26-29`).

**Deltas I'd add to the above:**
- **Signing/embedding is zero today and must stay an invariant, not a "consider."** Confirmed no
  Embed-Frameworks phase (`project.pbxproj:3059-3087`, all `XCSwiftPackageProductDependency`) and
  no `.dynamic` in any local `Package.swift`. The post-build `codesign --force --deep` +
  `--verify --deep --strict` (`run.sh:351-357`) means **if** anyone ever adds a dynamic framework,
  that step signs+verifies each one every build *and* you pay dyld load at launch. The dynamic-
  framework escape hatch (`spec:117-118,216-217`) is the **only** path that demonstrably worsens
  runtime/build — make it a hard no-by-default, not a "consider."
- **Coupling tally for the named 9-file slice** (corroborates F1): across them, app singletons
  referenced are `FeatureFlags.shared`×3, `SettingsManager.shared`×2, `SelectionTray.shared`×2,
  `LLMProviderRegistry.shared`×2, `EphemeralTranscriber.shared`×2, `ScreenshotCaptureService.shared`,
  `LLMConfig.shared`. Three (`LLMProviderRegistry`/`LLMConfig`/`EphemeralTranscriber`) are
  LLM/transcription, not capture — they cannot descend with capture and force protocol inversion.
- **Measurement:** add **recompiled-file count** (not just wall-clock) via `xclogparser` on the
  `.xcactivitylog`, and a hard revert-gate per phase. Agreed with §4's runtime signposts — overlay-
  show latency is the metric that actually answers "did we make the app worse."

Net: ship TLK-030, but reorder to *reconcile duplicates → extract package-resident markup
models → measure → only then overlay UI*, hold static as an invariant, and move WKWebView assets
with their code. **Next owner:** the engineer implementing TLK-030 — fold F2/F3/static-invariant
into the spec's Build Rules and Phased Plan before Phase 2.
