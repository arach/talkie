# Navigation Perceived-Performance Tricks — Brainstorm

**Author:** arach + claude (session) · **Date:** 2026-05-14 · **Status:** Brainstorm, seeking review

## Context

While instrumenting Talkie macOS with an FPS HUD + structured log stream, two distinct nav-perf problems surfaced:

1. **Multi-second main-thread freezes during section transitions.** Worst observed: `Context → Home: 6847ms`. Common: 500ms–1500ms. User clicks a sidebar icon, app stops responding for a second or more, then jumps to destination.
2. **2–3s of post-transition "warm-up"** with `hottest=AppNavigation:30/s` body invalidations and `maxMs=60-100ms` frame intervals before settling to a clean 60fps. Visually a flat 60fps, so users don't notice — but it indicates SwiftUI is still doing real work after the nav appears done.

The first is the actual UX problem. The second is mostly diagnostic noise.

Rather than fixing underlying work (slow GRDB queries, heavy view-tree construction, NavigationSplitView internals — all hard), this doc proposes **perceived-perf tricks** that make navigations *feel* instant regardless of the real cost. Many of these compound.

---

## Idea 1 — Eager visual feedback on click

**Premise:** the user clicks a rail icon. Right now we likely run: click → sidebar selection animates → content tears down → new content view inits → `.task` runs → data loads → render. All sequential, mostly on main. Perceived: 1-second freeze.

**Idea:** on the same frame as the click, fire the *cheap* visual acknowledgements: rail icon highlights, accent bar slides, sidebar selection state updates, detail column shows the destination's chrome (header bar, title bar, empty body). The async data load kicks off in the background. User sees acknowledgement in <16ms even if total time-to-loaded is 1s.

**Why it's high-impact:** the user's complaint isn't usually "loading is slow" — it's "did my click register?" Splitting the visual ack from the content swap removes that anxiety entirely.

> **Codex:** Strong agree, but split the state more deliberately than “update `selectedSection` faster.” In current `AppNavigation`, `selectedSection` drives both the sidebar highlight and the big `mainContentView` switch, so acknowledging the click also tears down/builds the destination in the same transaction. I'd introduce an immediate visual selection / pending destination state for the rail + chrome, then commit the expensive content section on the next turn or when a cheap shell is ready. Watch deep links/commands too: `NavigationState` currently expects one canonical selected section, so any split-state model needs a small sync rule to avoid highlight/content drift.

---

## Idea 2 — Skeleton screens (never spinners)

**Premise:** when a section is loading its real content, show greyed-out placeholder shapes matching the eventual layout — header bar, ~5 list-row rectangles, etc. Replace each shape as real data lands.

**Why:** spinners signal "wait." Skeletons signal "this is what you'll see, almost there." Industry-standard. Tiny memory footprint per skeleton (just rendered geometry, no data dependency).

**Discussion point with arach:** keep skeletons in memory **forever** — they're cheap and ubiquitous, no need to cull.

> **Codex:** Agree on skeletons, especially for Library/Context/Screenshots/Console. The gotcha is that skeletons must be static, cheap layout placeholders — no live lists, no geometry-heavy row math, no per-row shimmer that itself becomes the new FPS culprit. “Keep them forever” should mean keep reusable skeleton view definitions / lightweight states around, not keep one mounted skeleton tree per section indefinitely. For Talkie’s Scope theme, the skeleton should probably preserve the top band + rail/list/detail proportions rather than a generic grey card.

---

## Idea 3 — In-session view cache with TTL

**Premise:** today we likely tear down and rebuild a detail view on every section change. Two trips to Library means two full view tree constructions.

**Idea:** keep the last N visited section views *alive* in memory, keyed by section. Subsequent visits to a cached section paint in one frame. After some idle TTL (e.g. 5 minutes since last access), release the cached view so Talkie doesn't accumulate memory over a multi-day session.

**Tunables:** TTL duration, cache cap (e.g. 5 sections), eviction policy (LRU).

**Critical constraint from arach:** NOT forever. The whole point is to balance fast back-and-forth against bounded memory. Short in-session TTL, not permanent.

> **Codex:** I would not cache SwiftUI `View` values as the primary mechanism. SwiftUI views are cheap value descriptions and can capture stale bindings/environment; keeping subtrees mounted also keeps `.task`, observations, timers, and selection state alive unless carefully suspended. Cache data snapshots, view models, and per-section UI state first. If we still need mounted-view caching, make it explicit (`ZStack` with the last 2-3 sections hidden) and audit cancellables/observers. Also note `RecordingsViewModel.shared` already persists across these library sections, so repeated observation restarts may cost more than view construction.

---

## Idea 4 — Pre-warm common sections on launch

**Premise:** after the app's first frame paints (so launch isn't slowed), kick off a low-priority background task to *construct* the view tree for high-traffic sections (Home, Library, Notes). Don't load data yet — just build the views into the cache from idea 3.

**Result:** by the time the user clicks their first sidebar icon, the destination view tree is already in memory. Only the data fetch remains, and we have ideas for that too.

> **Codex:** Disagree with “construct the view tree” as the useful warm-up. Unmounted SwiftUI view construction usually buys little, and mounting offscreen risks firing `.task` / `ValueObservation` work at the wrong time. Pre-warm repositories, database queries, thumbnails, counts, and section data snapshots after first frame instead. For Home/Library/Notes, “already have the data” is likely the win; a built-but-empty view tree still freezes if its first observation starts synchronously.

---

## Idea 5 — Debounced data fetch

**Premise:** if a user is *passing through* a section on their way somewhere else (click Home, then immediately click Library), there's no reason to kick off Home's GRDB query. The fetch only matters if they actually land and stay.

**Idea:** when a section becomes visible, start a 150-200ms timer. If the section is still active when the timer fires, start the fetch. If the user navigates away before then, cancel.

**Compounding effect:** combined with pre-warming (idea 4) and the cache (idea 3), most navigations either hit a cached fully-loaded view (instant) or skip the fetch entirely (passing through).

> **Codex:** Good for pass-through navigation, but only debounce optional refresh work. If cached/stale data exists, show it immediately and debounce the refresh; if no data exists, show the skeleton immediately and start the fetch after a short cancellable delay. 150-200ms may make a deliberate single click feel slower, so I’d either use a shorter delay (~75-125ms) or only apply the longer delay once a rapid nav sequence is detected. Make cancellation generation-based so late results can’t update a section the user has left.

---

## Idea 6 — Move data fetch fully off main

**Premise:** `.task { await loadX() }` on view appear is async, but the GRDB query underneath may still hop to main or block via `try await dbReader.read { ... }` ordering. If the query itself takes 500ms, that's where the freeze comes from.

**Idea:** explicitly `Task.detached(priority: .userInitiated)` for the fetch, hop to MainActor *only* for the final state update. Profile each section's data path to confirm.

**Bonus thought from arach:** "or maybe we should already have the data" — i.e. a background sync layer that keeps the per-section data warm independent of nav. Worth scoping separately if the simpler off-main path isn't enough.

> **Codex:** Mostly agree, but the concrete suspect in current code is `RecordingsViewModel.startObservation()`: it is on the main actor and starts a GRDB `ValueObservation` with `scheduling: .immediate`. That can make the initial fetch happen synchronously enough to block the click path. I would fix the DB/observation layer rather than scatter `Task.detached` from views: start/read on a background scheduler or repository actor, then publish only the final array/count on MainActor. Add timing around `selectedSection → first shell → first data` and around observation startup before assuming the heavy work is generic SwiftUI construction.

---

## Idea 7 — Crossfade vs. column-swap

**Premise:** NavigationSplitView's default content-swap behavior might do more under the hood than a plain opacity transition. If we wrapped the detail column in a manual `.transition(.identity)` or `.transition(.opacity)` with a tight duration, the swap might be cheaper.

**Risk:** unclear how much SwiftUI/NavigationSplitView internals we'd be fighting. Worth a quick experiment.

> **Codex:** Premise needs updating for the current branch: the outer sidebar/content split is now `SidebarColumns` (plain `HStack`), not `NavigationSplitView`; `NavigationSplitView` remains for the inner workflows/settings 3-column flows. So for normal two-column nav, the cost is more likely the `mainContentView` switch plus destination `.task`/observations than AppKit split internals. A tight identity/opacity transition may hide a visual tear, but it won’t fix a synchronous destination load. Still worth a small experiment on the content host once the data path is instrumented.

---

## Idea 8 — Drag-time layout freeze: stop the propagation (Approach A)

**Premise:** during a sidebar resize drag, we saw `hottest=AppNavigation:480/s` — the root view re-evaluating hundreds of times per second. SwiftUI is propagating every drag tick down through the entire view tree because the binding (`expandedLabelWidth`) lives on the root.

**Idea:** during drag, write the proposed width to *local* state on the handle/sidebar component only. Don't update the root-level `@State` until drag-end. The sidebar component still resizes visibly (it reads from its own local state). The detail column doesn't see a width change, so it doesn't re-layout.

**We did this partially** — removed the live preview-write on compact drag. Need to extend to expanded-drag.

> **Codex:** Strong agree and this is the clearest low-risk drag fix. The code already says compact preview writes were removed because root binding writes invalidated `AppNavigation`; expanded mode still calls `onResize(proposed)` every tick, which writes `expandedLabelWidth` at the root and passes it through `Sidebar`. Move the live width into `SidebarEdgeHandle`/sidebar-local state, render the sidebar from that during drag, and only commit `expandedLabelWidth` + `@AppStorage` on end. If detail width visually needs to stay fixed during drag, make that explicit instead of letting the whole root relayout on every tick.

---

## Idea 9 — Drag-time visual snapshot: rasterize-during-interaction (Approach B)

**Premise from arach:** "freeze the underlying. Take a screenshot, freeze that, only redraw when the user stops dragging." Industry-standard technique — UIKit calls it `shouldRasterize`, AppKit has `cacheDisplay(in:to:)`, web has `will-change: transform`.

**Idea:** when drag begins, take an `ImageRenderer` snapshot of the detail column. Show that bitmap as an overlay over the live detail view, hide the live one. During drag, only the handle moves visually. Detail column's view tree is dormant — no body evaluations, no relayout, no SwiftUI cost regardless of what NavigationSplitView wants to do. On drag-end, hide snapshot, re-show live detail with new geometry.

**Why this is the nuclear option:** works even when SwiftUI/AppKit force recalculation we can't control. Acknowledges arach's intuition that "Maybe macOS forces the recalculation and we don't have a choice."

**Cost:** ~16ms one-time snapshot render at drag-start; GPU compositing during drag (effectively free). Memory: one bitmap the size of the detail column.

> **Codex:** Agree as a fallback, but it’s more expensive/risky on macOS SwiftUI than the paragraph implies. `ImageRenderer` may not faithfully capture materials, AppKit-backed subviews, scroll state, video, or focus rings, and taking the snapshot can itself hitch if done at drag start. An AppKit/layer snapshot (`cacheDisplay` / bitmap rep) of the detail host may be more reliable. I’d do Approach A first, then only rasterize if the remaining jank is unavoidable. If we do snapshot, define hit-testing, accessibility, window-resize, and dark/material changes during the frozen interval.

---

## Idea 10 — Unified theory: rasterize during *all* transits

**Observation:** ideas 8/9 (drag-time freeze) and ideas 1/2/7 (nav-time tricks) are the same pattern in different guises. Both say: "during a moment of visual transit, the underlying view tree should be DORMANT. Show pixels, not live views. Reactivate when the transit ends."

**Generalized application:** during a section nav, snapshot the OLD detail column at click-time, overlay it briefly while skeletons crossfade in, then reveal the new live view as it loads. User never sees an empty frame. Works the same for sidebar drag *and* section change.

**Open question:** is this overengineering? The simpler tricks (1, 2, 3, 5) might be enough on their own. The snapshot approach adds complexity. Worth it only if simpler approaches still leave perceptible jank.

> **Codex:** Directionally right, but I would not make “show pixels, not live views” the default architecture for all nav. For drag, pixels are great because the user is manipulating layout and expects content to stay visually stable. For nav, showing the old detail too long can feel like the click did not work unless the rail/header/skeleton changes immediately. The more general rule is: acknowledge intent immediately, keep old/cached content only until the new shell is ready, then swap to a cheap live shell and let data fill in. Reserve snapshots for very short crossfades or genuinely unfixable transition jank.

---

## Proposed order of work

Lowest-risk-first, with compounding effects:

1. **Skeleton-screen base** (idea 2) — define a `SectionSkeleton` per section, swap-in real content as `.task` completes. Trial on Library first.
2. **Eager visual feedback** (idea 1) — split selection-animation from content-swap.
3. **Debounced fetch** (idea 5) — 150-200ms delay before kicking off the GRDB query.
4. **View cache with TTL** (idea 3) — keep last 5 sections, 5-min idle TTL.
5. **Pre-warm common sections** (idea 4) — after first frame, async-construct Home/Library/Notes.
6. **Drag-time approach A** (idea 8) — local state during drag.
7. **Drag-time approach B** (idea 9) — visual snapshot if A is insufficient.

Most apps that feel snappy stop at 1–3. We measure between steps and decide if we keep going.

---

## Codex take (overall)

My bigger-picture take: the framing is useful, but the likely first-order bottleneck is not “SwiftUI view tree construction” in the abstract. In this branch, two concrete things stand out: root state is still mutated on every expanded sidebar drag tick, and library-style destinations start GRDB observations from a main-actor view model with `.immediate` scheduling. Those are more actionable than broad view caching.

I’d reorder the work as:

1. Add phase timing around navigation (`click/selection ack`, `shell visible`, `data visible`) plus query/observation startup timing. The FPS HUD tells us the symptom; we still need the boundary where the click path blocks.
2. Fix expanded-drag propagation (idea 8) before snapshotting. It is already half-proven by the compact-drag change.
3. Split visual selection/chrome from expensive content commit (idea 1), then add static skeleton shells (idea 2).
4. Fix the data path for Library/Notes/Dictations: background observation/read setup, stale-data-first rendering, cancellable refresh. This is idea 6 plus the “already have the data” thought, and I’d do it before view caches/pre-warm.
5. Add debounce only for refresh/pass-through work, not as a blanket delay.
6. Treat mounted view caching and pre-constructing views as later experiments; cache data/state first.
7. Use snapshots for drag or very short crossfades only if the above still leaves visible jank.

Also, the `NavigationSplitView` theory is partly stale for the current sidebar work: the outer sidebar split has already been replaced by `SidebarColumns`, so normal sidebar section transitions should be investigated as destination-switch/data-load work. `NavigationSplitView` may still matter inside workflows/settings, but it probably is not the main two-column nav freeze.

---

## Claude take (after digesting Codex's review)

Codex's pushback is mostly right and I'd update the plan to match. Capturing where I land after digesting their notes, so future-me can pick this up after a context clear without re-deriving:

**Things I now think we got wrong in the original brainstorm:**

- **NavigationSplitView framing (Idea 7).** Stale on this branch — `SidebarColumns` is the outer host now. Idea 7 was aimed at the wrong layer. Drop it; the real win is destination-switch + data-load.
- **View caching of `View` values (Idea 3).** Codex is right — caching SwiftUI `View`s is a SwiftUI anti-pattern. The cache should be at the **view-model / data snapshot** level. Subsequent visits to a section see "stale data shown instantly, refresh kicks off in background." That's better than mounting a view subtree with stale observations.
- **Pre-warm by constructing views (Idea 4).** Replace "construct view tree" with "pre-load data." After first frame, kick off the queries for Home/Library/Notes; cache the results in the per-section view model. The view itself can re-construct on demand — what matters is that its data is already in memory.
- **"Show pixels not live views" as nav default (Idea 10).** Codex right — for nav, showing the OLD detail too long reads as "click didn't register." Snapshot-during-nav is wrong as the default. The right rule: acknowledge click immediately (chrome + selection), reveal cheap live shell, fill data. Snapshots reserved for drag and genuinely unfixable transitions.

**Things where I'd add nuance to Codex's pushback:**

- On **Idea 3 / view caching:** if data-path fixes alone (Codex's step 4) don't fully solve back-and-forth nav cost, there's still a case for keeping *layout state* (scroll offsets, expanded/collapsed UI bits, search query) cached at the view-model level. Not mounted views — just `@Published` on a per-section ViewModel that survives across nav. Worth revisiting only if step 4 leaves visible cost.
- On **Idea 5 / debounce:** Codex's "shorter delay (75-125ms) or only after detecting rapid nav" is better than my flat 150-200ms. The 200ms number was a guess; the actual right number is "shorter than the user's typical deliberate-click reaction time, longer than their typical pass-through transit time." Should be measured, not hardcoded.

**The new priority order I agree with (Codex's, slightly re-annotated):**

1. **Phase-timing instrumentation first.** Add `os_signpost` markers around: `selectedSection.onChange`, `mainContentView` construction, each section's `.task`, `RecordingsViewModel.startObservation()`. Without this, every subsequent fix is a guess. Also: the FPS HUD should track time-from-click-to-first-paint as a published metric, so we can see improvement in the existing log stream.
2. **Expanded-drag root-state propagation fix** (Idea 8). Real, identified, half-fixed already (compact-mode). Should be quick.
3. **Data-path fix for Library/Notes/Dictations** (Idea 6 + the "have the data already" thought). Background `ValueObservation` setup, stale-data-first render, cancellable refresh. Codex named `RecordingsViewModel.startObservation()` as the specific suspect — `scheduling: .immediate` on main actor is plausibly the click-path blocker.
4. **Eager visual feedback + skeleton shells** (Ideas 1+2). Tuned together. Probably better done with claude+arach iteration loop (FPS HUD live, fast feedback) than via async codex delegation.
5. **Debounced refresh** (revised Idea 5). Only for refresh of stale data, not blanket nav delay. Tunable parameter.
6. **Mounted view cache, pre-construct views, snapshot tricks** — keep on the bench. Only revisit if 1-5 leave perceptible jank.

**Scope split for who does what:**

- **Codex executes (deterministic, code-grounded fixes):** steps 1, 2, 3 above. They have the code context and the kind of focused-quiet-work that suits these. Each as its own commit on a feature branch.
- **Claude + arach iterate (perceived-perf, tuning, judgment):** steps 4, 5. UX feel needs the FPS HUD + real-time iteration loop.
- **Deferred:** step 6. Don't even spec yet.

The doc above is now the definitive plan, not the original brainstorm. The codex-annotated ideas remain as design history.
