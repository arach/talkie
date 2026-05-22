# Studio lib protocol

This directory holds shared modules for the studio. Today: tokens, themes, schemes, utilities.

## Scope canon tokens — `scope-tokens.ts`

**Single source of truth for the macOS Scope substrate.** Anything that's a substrate color, ink shade, rule, edge, accent, or kind tint comes from `SCOPE`.

### Rule

> No inline hexes for Scope substrate colors in any `components/studies/Mac*.tsx` or `app/mac-*/page.tsx` file. Import from `@/lib/scope-tokens`.

```tsx
import { SCOPE } from "@/lib/scope-tokens";

// good
<div style={{ background: SCOPE.pane, color: SCOPE.ink }} />

// good — terse alias for files that have many color sites
const T = SCOPE;
<div style={{ background: T.pane }} />

// bad — inline hex
<div style={{ background: "#F1F1F0" }} />
```

Exception: the `SCOPE_MATS` palette display (named warm/cool tones for comparison) intentionally exposes hex strings — use those when you need a named mat tone.

### When canon shifts

One file edit (`scope-tokens.ts`) propagates everywhere. **Do not** start a search-and-replace sweep across 20+ files — if a file isn't on SCOPE yet, migrate it first, then update the token.

### What's migrated, what's not

Migrated to import from SCOPE (as of 2026-05-21):
- `MacDictationDetail.tsx`
- `MacNoteDetail.tsx`
- `MacCaptureDetail.tsx` (incl. mat-swatch palette → `SCOPE_MATS`)

Still inline (will migrate when touched):
- `MacHome.tsx`, `MacLibrary.tsx`, `MacSkills.tsx`
- `MacMemoDetail.tsx`, `MacCompose.tsx`, `MacLearn.tsx`, `MacTalkieButton.tsx`, `MacNotchSettings.tsx`, `MacSkillForge.tsx`
- `primitives/MacWindowFrame.tsx`, `primitives/IconRail.tsx`
- `app/mac-*/page.tsx` files

These render correctly under current canon — they just won't auto-propagate the next canon shift. Convention: if you touch any of these for another reason, migrate to SCOPE in the same pass.

### What does NOT live in scope-tokens.ts

- **iOS theme bundles** (Scope / Midnight / Tactical / Ghost) → `globals.css` `[data-theme]` blocks. Confusingly shares the "Scope" name; treat as separate.
- **Dark instrument scheme cards** (AMBER, CARBON, PORCELAIN, CHIFFON, etc.) → `lib/schemes.ts`. These are bay material schemes, not substrate colors.
- **Tailwind chrome tokens** (`text-studio-ink`, `border-studio-edge`) → `tailwind.config.ts`. Kept in sync with `SCOPE` by hand; if you change a `SCOPE.*` substrate value, mirror it into tailwind too.

## Related

- Audit worksheet: `design/studio/app/mac-audit/page.tsx` (state in `data/audit/`)
- Parity worksheet: `design/studio/app/parity/page.tsx` (state in `data/parity/`)
- Both use the convention of `data/<surface>/AGENTS.md` for protocol; this file mirrors that for shared lib modules.
