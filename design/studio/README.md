# Studio

Visual design exploration for native app treatments. Next.js + React 19
+ Tailwind 3.4 app at `design/studio/`. Each study is a route that
renders one Talkie surface (bay, sheet, list row) faithfully enough to
make palette / material / composition decisions before Swift gets
touched.

## Running

```sh
cd design/studio
bun install         # or: npm install
bun run dev         # or: npm run dev
# → http://localhost:3000
```

The dev server is hot-reload — edit a component or a scheme and the
browser refreshes immediately. No SwiftUI rebuild loop.

## Structure

```
design/studio/
├── app/
│   ├── layout.tsx              # root shell + studio nav
│   ├── page.tsx                # landing — lists studies
│   ├── globals.css             # Tailwind + iOS theme bundles
│   ├── agent-bay/
│   │   ├── page.tsx            # the study (route)
│   │   └── NOTES.md            # decisions log
│   ├── recording-sheet/
│   │   ├── page.tsx
│   │   └── NOTES.md
│   └── iphone-themes/
│       ├── page.tsx
│       └── NOTES.md
├── components/
│   ├── StudioNav.tsx           # cross-study nav strip
│   ├── StudioPage.tsx          # page chrome (header + max-width)
│   ├── ToggleBar.tsx           # treatment / waveform pickers
│   ├── SchemeCard.tsx          # scheme-grid card wrapper
│   └── studies/
│       ├── Bay.tsx             # agent-bay artifact
│       ├── RecordingSheet.tsx  # recording-sheet artifact
│       └── PhoneFrame.tsx      # iphone-themes artifact
└── lib/
    ├── schemes.ts              # 9 material schemes (AMBER → PAPER)
    ├── themes.ts               # 4 iOS themes (Scope / Midnight / Tactical / Ghost)
    └── utils.ts
```

## Two kinds of study

**Scheme grid** (`agent-bay`, `recording-sheet`) — iterate one artifact
across the 9 material schemes simultaneously. Use this to pick the
surviving material for a single surface.

**Theme shell** (`iphone-themes`) — iterate one mock across the 4 iOS
shipping themes simultaneously. Use this to verify a mock survives
across Scope / Midnight / Tactical / Ghost before declaring done.

## Conventions

- **Fonts.** Cormorant Garamond display, system mono chrome, Inter
  body. Loaded from Google Fonts in `app/layout.tsx`.
- **Page canvas.** `studio.canvas` (#FBFBFA). Matches
  `ScopeCanvas.canvas` in
  `apps/macos/TalkieKit/Sources/TalkieKit/UI/ScopeDesign.swift` so the
  studio chrome sits in the same surrounding the artifact will sit in
  once shipped. The studio chrome stays neutral — the *artifact* inside
  is what varies.
- **Scheme tokens.** Semantic var names (`--scheme-bg`,
  `--scheme-accent`, etc.) set by `<SchemeCard>` from `lib/schemes.ts`.
  Artifacts read `var(--scheme-*)` directly. Adding a scheme: add an
  entry to `lib/schemes.ts` and every scheme-grid study picks it up.
- **iOS theme tokens.** `--theme-*` vars remapped by per-theme blocks
  in `app/globals.css`, applied via `<PhoneFrame data-theme="...">`.
- **Decisions log.** Each study has a `NOTES.md` — what's in, what's
  out, *why*. A dropped scheme should leave a one-line trace so future
  studies don't re-learn the lesson.

## Workflow

1. **Open a study** in the browser. Tweak schemes in
   `lib/schemes.ts`, tweak components in
   `components/studies/<artifact>.tsx`. Hot-reload.
2. **Compare variants** in the grid. Drop the ones that read as
   "filtered" / interpolated.
3. **Note the decisions** in the study's `NOTES.md`.
4. **Port the winners** to Swift. The studio is for picking; Swift is
   for shipping. Token names in `lib/schemes.ts` are kept close to
   Swift counterparts where possible (e.g. `--scheme-bg` ↔
   `ScopePanel.bg`) so the port is mechanical.
