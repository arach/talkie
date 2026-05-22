"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { StudioPage } from "@/components/StudioPage";

/**
 * Scope Audit — agent-driven design read of six canonical mac-* surfaces.
 *
 * Six review agents (one per surface) inspected the studio source + rendered
 * output and returned structured findings across five axes: typography,
 * spacing, hierarchy, semantics, copy. This page synthesizes those findings
 * into a single worksheet with status tracking per item (localStorage).
 *
 * Audit ID: scope-2026-05-21
 */

// ── Types ─────────────────────────────────────────────────────────────

type Grade = "A" | "B" | "C" | "D";
type Severity = "blocker" | "issue" | "polish";
type Axis = "typography" | "spacing" | "hierarchy" | "semantics" | "copy" | "a11y";
type Status = "queued" | "inflight" | "shipped" | "skipped";
type Filter = "all" | "active" | "shipped" | "skipped";
type NoteLevel = "info" | "progress" | "landed" | "blocked" | "proposal" | "question";

interface Note {
  ts: string;
  agent: string;
  level: NoteLevel;
  message: string;
  ref?: string;
}

interface Finding {
  id: string;
  severity: Severity;
  axis: Axis;
  title: string;
  detail: string;
  fix: string;
}

interface SurfaceAudit {
  route: string;
  display: string;
  role: string;
  oneLineRead: string;
  grades: { typography: Grade; spacing: Grade; hierarchy: Grade; semantics: Grade; copy: Grade };
  topThree: string[];
  findings: Finding[];
}

interface Theme {
  id: string;
  title: string;
  hits: string[];
  detail: string;
  fix: string;
}

interface TopItem {
  id: string;
  title: string;
  payoff: string;
}

interface Decision {
  id: string;
  date: string;
  title: string;
  detail: string;
}

// ── Data: cross-cutting themes ────────────────────────────────────────

const THEMES: Theme[] = [
  {
    id: "t-scoperule",
    title: "Hand-rolled hairlines bypass ScopeRule",
    hits: ["/mac-dictation-detail", "/mac-note-detail", "/mac-capture-detail"],
    detail: "Detail surfaces re-declare 0.5px solid borders inline instead of consuming the ScopeRule (.section/.row/.subtle/.action) and scopeCardBorder primitives that already exist.",
    fix: "Migrate all dividers + card edges through ScopeRule / scopeCardBorder. One-pass refactor across three TSX files.",
  },
  {
    id: "t-cool-palette",
    title: "Cool palette not yet committed across substrate",
    hits: ["/mac-note-detail", "/mac-capture-detail"],
    detail: "Eyebrows + footnotes say 'PEARL on FROST · cool' but T tokens render warm cream — direction is cool gray (icy, not blue), tokens haven't moved yet. Cool-blue selection tint #E5EEF3 in LibraryListGutter is also off-canon (blue, not gray).",
    fix: "Apply cool-gray palette per 2026-05-21 decision: canvas #F8F8F7 / pane #F1F1F0 / chrome #E7E7E6 / rail #DCDCDB / ink #232423. Swap blue selection tint to rail gray + ScopeEdge.subtle.",
  },
  {
    id: "t-marketing-copy",
    title: "Marketing copy creeping back in",
    hits: ["/mac-home", "/mac-note-detail", "/mac-skills"],
    detail: "Home Did-you-know serif card titles, Note 'Note as a page in a notebook' eyebrow, Skills footer narration paragraph — all violate the 'let affordances speak' rule.",
    fix: "Delete narrative copy; replace with neutral instrument labels or a single mono datum row.",
  },
  {
    id: "t-equal-cards",
    title: "Equal card weights flatten hierarchy",
    hits: ["/mac-home", "/mac-skills"],
    detail: "Home stacks 4 sections at identical card weight; Skills stacks 5 sibling panes at the same paper-card treatment. No substrate gradient signals primary / secondary / footnote.",
    fix: "Tier substrates: keep primary bands as cards, demote supporting bands to borderless rule-separated rows on canvas.",
  },
  {
    id: "t-amber-rationing",
    title: "Amber rationing broken",
    hits: ["/mac-dictation-detail", "/mac-skills"],
    detail: "Skills uses amber on 6 separate CTAs across one page; Dictation's inline action row stuffs 7 affordances into a single bar. Amber stops meaning 'primary action' when it's everywhere.",
    fix: "One amber per zone. Demote sibling CTAs to INK_FAINT with ScopeEdge.subtle underline. Move secondary affordances to overflow.",
  },
  {
    id: "t-ink-fainter",
    title: "INK_FAINTER (0.32) below WCAG AA",
    hits: ["/mac-note-detail", "/mac-capture-detail", "/mac-skills"],
    detail: "Tool buttons, card codes, timestamps, and meta labels sit at 0.32 alpha on PAPER/CREAM — ~3.0:1 contrast at 9px mono. These are not decorations, they're labels.",
    fix: "Floor secondary metadata at INK_FAINT (0.55). Reserve INK_FAINTER for true decoration (separator dots, dimmed-state mini-chips).",
  },
  {
    id: "t-mono-saturation",
    title: "Mono labels saturated at 9px",
    hits: ["/mac-library", "/mac-skills"],
    detail: "Eyebrows, metas, chips, codes, captions all sit at 8–9px JetBrains Mono with heavy tracking — typographic voice goes monotone and the eye stops differentiating section from caption.",
    fix: "Three-tier ladder: 8px for chrome strips only, 9px for section labels, 10px for content meta.",
  },
];

// ── Data: top of stack ────────────────────────────────────────────────

const TOP_OF_STACK: TopItem[] = [
  {
    id: "tos-scoperule",
    title: "Consume ScopeRule + scopeCardBorder across all detail surfaces",
    payoff: "Fixes hand-rolled hairlines, restores semantic vocabulary, removes per-surface re-invention. Touches 3 TSX files in one pass.",
  },
  {
    id: "tos-cool-palette",
    title: "Commit cool-gray palette tokens across studio",
    payoff: "Resolves the PEARL/FROST inconsistency by extending cool gray everywhere (canon shift 2026-05-21). Single token swap propagated through 6 surfaces + globals.",
  },
  {
    id: "tos-tier-substrates",
    title: "Tier substrate weights on Home + Skills",
    payoff: "Restores hierarchy on the two surfaces with the deepest section stacks. Demote supporting bands to canvas-borderless rows.",
  },
  {
    id: "tos-ink-floor",
    title: "Floor secondary labels at INK_FAINT (0.55)",
    payoff: "WCAG AA across 3 surfaces. Keeps the hush; restores the contrast. Reserve 0.32 for true decoration.",
  },
  {
    id: "tos-amber",
    title: "Ration amber to one primary action per zone",
    payoff: "Restores the scarce-accent semantic Scope depends on. Affects Skills + Dictation most.",
  },
];

// ── Data: decisions log ───────────────────────────────────────────────

const DECISIONS: Decision[] = [
  {
    id: "d-cool-canon",
    date: "2026-05-21",
    title: "Scope substrate pivots cool gray (icy, not blue)",
    detail: "Canon shifts from warm cream (#FBFBFA/#FAF7EF/#F4F1EA/#F2EDDE/#2A2620) to cool neutral gray (#F8F8F7/#F1F1F0/#E7E7E6/#DCDCDB/#232423). Accents stay warm — brass + amber gain contrast against gray, read as instrument metal in a frosted case. Awaiting hex confirmation before tokenizing.",
  },
];

// ── Data: per-surface audits ──────────────────────────────────────────

const AUDITS: SurfaceAudit[] = [
  // ── HOME ────────────────────────────────────────────────────────────
  {
    route: "/mac-home",
    display: "Home",
    role: "Landing surface. Routines · Recent (Voice|Content) · Captures · Agent · today metrics.",
    oneLineRead:
      "Editorial cream substrate reads well; Agent bay leads with confidence, but eyebrow noise, scheme-picker visual weight, and a flat 4-section vertical rhythm dilute hierarchy below the fold.",
    grades: { typography: "B", spacing: "B", hierarchy: "B", semantics: "B", copy: "A" },
    topThree: [
      "Collapse/relocate the scheme picker so the Agent eyebrow leads, not the studio audition chrome.",
      "Differentiate band weight: keep Bay + Recent as cards; demote Routines + Did-you-know to borderless rule-separated rows.",
      "Strip leading '·' from SectionBlock eyebrows and neutralize the Did-you-know serif hooks to remove residual marketing tone.",
    ],
    findings: [
      { id: "h-scheme-picker", severity: "issue", axis: "hierarchy",
        title: "Scheme picker outweighs Agent eyebrow",
        detail: "The Modern/Scope/Reference scheme chips visually dominate the '· Agent' eyebrow, making the picker look like a primary affordance rather than studio chrome.",
        fix: "Treat scheme controls as studio-only — collapse to a single AUDITION toggle, or move to a floating studio dock outside the mac frame." },
      { id: "h-leading-dot", severity: "issue", axis: "typography",
        title: "Leading '·' doubled with row bullets",
        detail: "SectionBlock eyebrows render as '· Agent / · Recent / · Routines' while row glyphs are also dots — the leading dot becomes noise rather than a section mark.",
        fix: "Drop the leading '·' on SectionBlock eyebrows; reserve dot vocabulary for row leadings and PhosphorStatus indicators." },
      { id: "h-equal-cards", severity: "issue", axis: "hierarchy",
        title: "Four sections share identical card weight",
        detail: "Bay, Recent, Routines, Did-you-know all use the same border-studio-edge + bg-white/40 + rounded-md card — page reads as four equally-weighted bands with no descending importance.",
        fix: "Demote Routines + Did-you-know to borderless rows on canvas, so Bay and Recent hold the editorial weight." },
      { id: "h-flat-rhythm", severity: "issue", axis: "spacing",
        title: "gap-9 + identical heights flatten rhythm",
        detail: "36px vertical gap between every section combined with same-height cards leaves no sense of primary vs. secondary band.",
        fix: "Tighten Routines/Did-you-know to gap-6 and lighten their chrome so Recent gets more breathing room above and after." },
      { id: "h-content-tint", severity: "polish", axis: "semantics",
        title: "Voice/Content tints aren't in the palette",
        detail: "VOICE_TINT #9A6A22 is brass (good), but CONTENT_TINT #6B7A75 introduces a slate hue not present in the Scope palette — breaks the warm-cream substrate.",
        fix: "Pair brass with a complementary warm (e.g., ink-faint #7A746C or desaturated amber) so both panes stay within the Scope spectrum." },
      { id: "h-marketing-hooks", severity: "issue", axis: "copy",
        title: "'Did you know' tilts toward marketing",
        detail: "'Talk back to a memo.' / 'Hyper+S, anywhere.' card titles in display serif read promotional, against the no-marketing-copy rule for shipped UI.",
        fix: "Replace serif hooks with neutral instrument labels ('Voice edit during playback' / 'Capture chord · Hyper+S') and let the detail line carry the verb." },
      { id: "h-mono-floor", severity: "polish", axis: "a11y",
        title: "8–9px mono labels below comfortable read",
        detail: "Eyebrows, metas, and PhosphorStatus details at 8–9px JetBrains Mono with faint ink #7A746C are near the contrast floor for body-adjacent labels.",
        fix: "Floor metadata at 10px; reserve 8px exclusively for the system-status rail." },
      { id: "h-bay-header", severity: "polish", axis: "hierarchy",
        title: "Bay date strip header reads weak",
        detail: "'Today' at 15px display sits in the same band as eyebrow ticker + Start memo pill; the page identity rail competes with utility chrome.",
        fix: "Drop 'Today' to a mono eyebrow ('· TODAY · 21 MAY') and let the Bay's serif numerals carry the typographic anchor." },
    ],
  },

  // ── LIBRARY ─────────────────────────────────────────────────────────
  {
    route: "/mac-library",
    display: "Library · List",
    role: "Master list of TalkieObjects with filters, search, kind-tinted rows, inspector swap.",
    oneLineRead:
      "Confident list + instrument-bay composition; the editorial inspector reads beautifully but the list column stays at one uniform density, leaving hierarchy under-resolved.",
    grades: { typography: "B", spacing: "B", hierarchy: "C", semantics: "B", copy: "A" },
    topThree: [
      "Make the selected row read at a glance — kind-tinted left ScopeEdge plus the cream wash, so list↔inspector wiring is obvious.",
      "Quiet the bucket headers down to a hairline + mono label so the list flows as a column instead of card stacks.",
      "Bleed the readout bay to the inspector edges and bump row meta to 10px, so inspector and list read as one continuous instrument.",
    ],
    findings: [
      { id: "lib-selection", severity: "issue", axis: "hierarchy",
        title: "Selected row barely differentiated",
        detail: "Selected row uses #F2EFE6 vs transparent — a 3-point lift on a cream canvas — and only a 500 vs 400 weight bump; among four equal-density candidates the lock-in is almost invisible.",
        fix: "Add a 2px left ScopeEdge in the row's kind tint (brass for dictation/memo) when selected, or pair the cream wash with a ScopeRule.action accent stripe." },
      { id: "lib-bucket-headers", severity: "issue", axis: "hierarchy",
        title: "Bucket headers compete with rows",
        detail: "BucketHeader uses a warmer fill #F8F5EC plus a full ScopeEdge bottom rule, making '· TODAY ·' read at the same loudness as a row title and chopping the list into card blocks rather than a flowing column.",
        fix: "Drop the fill, keep just a hairline ScopeEdge.subtle top rule with the mono label floated left — quieter, more editorial." },
      { id: "lib-mono-legibility", severity: "issue", axis: "typography",
        title: "Mono labels under 9px lose legibility",
        detail: "Filter pill counts, bucket counts, and row meta sit at 8–9px JetBrains Mono with heavy tracking; the row meta line becomes texture rather than readable byline.",
        fix: "Bump row meta to 10px; reserve 8px for chrome strips (footer, readout bay) where it reads as instrument legend." },
      { id: "lib-filter-pills", severity: "issue", axis: "spacing",
        title: "Filter pills crowd the count",
        detail: "6px gap between label/count plus 6px to the active dot creates three visual stops in one pill at 1180; at 820 the row wraps awkwardly against the search field.",
        fix: "Use a single mono cluster 'DICTATIONS · 287' with the active dot as a leading ScopeRule.action mark, not a trailing pip; tighten px-2 py-1 to px-2.5 py-1." },
      { id: "lib-channel-chip", severity: "polish", axis: "semantics",
        title: "Channel-letter chip duplicates meta",
        detail: "The D/M/N/C colored disc encodes the same fact ('Voice', 'iTerm2', 'Hyper+S') already spelled in the meta line — chip is decorative rather than a primitive of the kind ladder.",
        fix: "Either drop the meta-line prefix and let the chip carry kind, or replace the chip with a thin left ScopeEdge in the kind tint." },
      { id: "lib-rec-indicator", severity: "polish", axis: "hierarchy",
        title: "Header 'REC' indicator is unanchored",
        detail: "The amber 'REC' in the top-right of HeaderBand reads like a status pill but sits beside 'NEWEST FIRST' as if it's a sort option; no glyph, no border, no dot anchors it as live state.",
        fix: "Wrap in the same brass dot + ScopeRule.action affordance the FilterPill active state uses." },
      { id: "lib-readout-orphan", severity: "polish", axis: "spacing",
        title: "Inspector readout floats orphaned",
        detail: "The dark phase-plot bay has m-4 margin on a cream pane and a 6px shadow, reading like a popped card on a desk rather than the top register of the inspector instrument.",
        fix: "Bleed the readout to the inspector edges (no m-4); butt the bay's bottom chrome against the masthead's top padding." },
      { id: "lib-middot-aria", severity: "polish", axis: "a11y",
        title: "Decorative middots not screen-reader-hidden",
        detail: "Leading '· ' glyphs are content nodes, so VoiceOver reads 'middle dot today' repeatedly across the surface.",
        fix: "Wrap each leading '· ' in aria-hidden span (or use ::before pseudo) so the dot stays visual but quiet to AT." },
    ],
  },

  // ── DICTATION DETAIL ────────────────────────────────────────────────
  {
    route: "/mac-dictation-detail",
    display: "Dictation · Detail",
    role: "Detail view of a dictation (voice → text). Most common detail surface in the app.",
    oneLineRead:
      "Proposed variant lands the editorial framing, but the inline action row is over-stuffed and the margin rail still under-uses the warm-cream substrate's semantic primitives.",
    grades: { typography: "B", spacing: "B", hierarchy: "B", semantics: "C", copy: "B" },
    topThree: [
      "Route all dividers and card edges through ScopeRule/scopeCardBorder so this surface consumes Scope semantics instead of redefining them.",
      "Trim the inline action row to Copy/Share/Export/Delete (Workflows + Edit → overflow) to honor the recent action-row decision.",
      "Keep the transcript fully in system sans; reserve Cormorant for the headline so the editorial hierarchy doesn't double-up.",
    ],
    findings: [
      { id: "dict-hand-rolled-rules", severity: "issue", axis: "semantics",
        title: "Hand-rolled hairlines bypass ScopeRule",
        detail: "Every divider in both variants is an inline 0.5px solid T.inkRuleS/inkRule border instead of routing through ScopeRule (.section/.row/.subtle/.action) and scopeCardBorder — file re-invents semantics instead of consuming them.",
        fix: "Replace raw borders with ScopeRule.subtle for margin/byline splits and ScopeRule.section for the player-rail top edge; cards (Media, Readout, Scratchpad) should use scopeCardBorder." },
      { id: "dict-action-row", severity: "issue", axis: "hierarchy",
        title: "Inline action row is seven items wide",
        detail: "Copy, Workflows, Share, Export, divider, Edit, Delete, plus trailing overflow puts seven affordances in one row — dilutes the 'Copy primary amber' decision recorded in design notes.",
        fix: "Keep Copy (amber), Share, Export, Delete inline; demote Workflows and Edit into the overflow ⋯ menu." },
      { id: "dict-serif-paragraph", severity: "issue", axis: "typography",
        title: "First paragraph in display serif",
        detail: "Rendering the opening transcript paragraph in Cormorant 16pt mixes display serif with body sans for the same content stream and competes with the serif headline above.",
        fix: "Keep all transcript paragraphs in system sans at 14/1.7; reserve Cormorant for headline + any pull-quote." },
      { id: "dict-rail-crowding", severity: "issue", axis: "spacing",
        title: "Margin rail crowds the body",
        detail: "Body padding-right is 56 and rail padding-left is 28 with a 0.5px hairline between — visually thin gutter while the rail's right padding is 48, asymmetric breathing that pulls the eye outward.",
        fix: "Balance to 64/40/40 (body-right / rail-left / rail-right) or anchor with a ScopeEdge.subtle vertical." },
      { id: "dict-byline-fields", severity: "polish", axis: "copy",
        title: "Byline mono line runs five fields",
        detail: "'0:38 · 47 words · iTerm2 · MacBook Pro · Parakeet v3' stacks provenance, device, and model into the byline AND repeats them in the rail (Provenance/Transcription blocks).",
        fix: "Trim byline to duration + words + source app; let the margin rail own device and model exclusively." },
      { id: "dict-amber-contrast", severity: "polish", axis: "a11y",
        title: "Amber-on-cream contrast for primary action",
        detail: "Copy uses #9A6A22 ink on rgba(196,125,28,0.08) fill — borderline against WCAG AA at 9.5pt mono with 0.14em tracking.",
        fix: "Bump primary label to 10pt and verify against ScopeInk's contrast tokens; consider tightening tracking to 0.12em." },
      { id: "dict-sequence-pill", severity: "polish", axis: "hierarchy",
        title: "Sequence pill lacks brand anchor",
        detail: "'M-0418' is amber-tinted text but reads as a stray mono token next to '· CH-02 · DICTATION', missing the dictation orange-D affordance used in the gutter list.",
        fix: "Wrap the sequence in the same small 'D' disc treatment used in LibraryGutter so the row inherits dictation provenance visually." },
      { id: "dict-derived-title", severity: "polish", axis: "copy",
        title: "Derived title verb is unclear",
        detail: "'No record to talk to — restore from agent' is mid-sentence advice, not a derived title; readers will not parse it as the artifact's name.",
        fix: "Use the first complete sentence ('No record to talk to.') and let the byline carry the rest, per the 'title from transcript first sentence' decision." },
    ],
  },

  // ── NOTE DETAIL ─────────────────────────────────────────────────────
  {
    route: "/mac-note-detail",
    display: "Note · Detail",
    role: "Detail view of an intentional written Note with optional attachments (screenshots, voice snippets).",
    oneLineRead:
      "Readable notebook-page detail, but the cool 'PEARL/FROST' rhetoric in copy disagrees with the warm-cream tokens actually rendered, and the body column drowns in empty whitespace below the prose.",
    grades: { typography: "B", spacing: "C", hierarchy: "B", semantics: "C", copy: "D" },
    topThree: [
      "Commit cool-gray palette tokens (per 2026-05-21 canon shift) so eyebrow copy and rendered substrate agree.",
      "Strip the marketing eyebrows ('Note as a page in a notebook', footnote narration); let eyebrow + serif title + byline carry framing.",
      "Make body uniformly sans 13.5/1.7 at 0.88 opacity per the recent Note decision; close the dead air below the prose.",
    ],
    findings: [
      { id: "note-pearl-frost", severity: "blocker", axis: "semantics",
        title: "PEARL/FROST claim, warm cream rendered",
        detail: "Eyebrows and footnote say 'PEARL on FROST · cool' but the T tokens (#FBFBFA / #FAF7EF / #F4F1EA / #F2EDDE) are the warm Scope cream family; nothing on the pane is cool.",
        fix: "Commit cool gray substrate (canvas #F8F8F7 / pane #F1F1F0 / chrome #E7E7E6 / rail #DCDCDB / ink #232423) per 2026-05-21 canon decision." },
      { id: "note-marketing-eyebrows", severity: "issue", axis: "copy",
        title: "Marketing-style eyebrows in chrome",
        detail: "'Note as a page in a notebook', 'text-first · attachment rail · three widths', and the Footnote all read as marketing narration over UI — violates the no-marketing-copy rule.",
        fix: "Drop the headline + footnote in the live surface; let the eyebrow row (sequence, channel, date) carry the framing." },
      { id: "note-dead-air", severity: "issue", axis: "spacing",
        title: "Body column collapses, dead air below",
        detail: "Three short paragraphs leave ~270px of empty pane between the last line and AttachmentRail, with no marginalia or footer cue — the page feels half-loaded.",
        fix: "Either pull AttachmentRail up under the prose when content is short, add a soft ScopeRule.subtle terminus glyph, or extend the margin rail (Backlinks / Outline) to anchor the foot." },
      { id: "note-serif-lede", severity: "issue", axis: "typography",
        title: "First paragraph still serif",
        detail: "Lede paragraph uses font-display at 15.5pt, contradicting the recent decision that Note body is sans 13.5pt at 0.88 opacity because serif felt too thick.",
        fix: "Drop the i===0 serif branch; render all paragraphs sans 13.5pt/1.7 at ~0.88 ink, or use a one-line eyebrow lede instead of a serif paragraph." },
      { id: "note-toolbar-eyebrow", severity: "issue", axis: "hierarchy",
        title: "Toolbar competes with eyebrow",
        detail: "Sequence + channel appear in BOTH the Toolbar row and the BodyColumn eyebrow ten pixels later, doubling the same metadata.",
        fix: "Keep sequence/channel in the eyebrow (editorial), leave the Toolbar for actions only — or vice versa, not both." },
      { id: "note-toolbutton-contrast", severity: "polish", axis: "a11y",
        title: "ToolButton labels under 0.32 ink",
        detail: "Edit/Star/Pin/Share/Export at 9px mono with INK_FAINTER (0.32 alpha) on T.pane — well below 4.5:1, and they're the surface's primary actions.",
        fix: "Bump to ScopeInk default (0.55+) on hover/rest, or use the established ScopeRule.action treatment." },
      { id: "note-tint-cool", severity: "polish", axis: "semantics",
        title: "noteTint reads cool slate",
        detail: "noteTint #6B7A75 is a desaturated teal-gray that has a slight blue cast — fine direction (cool) but wrong hue (blue, not gray).",
        fix: "Re-tone noteTint toward pure cool gray (e.g. #74746F) — no blue, no warm, matches the new cool-gray canon." },
      { id: "note-row-cool-tint", severity: "polish", axis: "spacing",
        title: "Selected row tint #E5EEF3 reads blue",
        detail: "The selected note row in LibraryListGutter is a pale blue — direction is cool but wrong hue (blue, not gray).",
        fix: "Swap for new rail gray (#DCDCDB) with a 0.5px ScopeEdge.subtle, matching the cool-gray canon." },
    ],
  },

  // ── CAPTURE DETAIL ──────────────────────────────────────────────────
  {
    route: "/mac-capture-detail",
    display: "Capture · Detail",
    role: "Detail view of a Capture — image-first (screenshot/clip) or text-passage (selection). Scope-native.",
    oneLineRead:
      "Solid image-first detail with crisp editorial frame, but the 'PEARL on FROST' comment lies about the warm tokens actually used, and the +ADD CAPTION pill plus derived caption invent ScopeRule-adjacent treatments instead of using Scope primitives.",
    grades: { typography: "B", spacing: "A", hierarchy: "B", semantics: "C", copy: "B" },
    topThree: [
      "Commit cool-gray palette tokens so the eyebrow copy and substrate agree (canon direction is cool, just not yet applied).",
      "Re-rank the hero: serif derived line as headline, filename as mono byline — image-first surface should read editorially, not as a Finder slug.",
      "Replace hand-rolled rules with ScopeRule.* and strip narrating copy ('promotes to a note', footnote prose) so affordances carry meaning.",
    ],
    findings: [
      { id: "cap-pearl-frost-claim", severity: "issue", axis: "semantics",
        title: "Palette comment contradicts tokens",
        detail: "Header/footnote both say 'PEARL on FROST · cool' but T.page/T.pane/T.chrome/T.rail are the warm Scope tokens — surface is cream-on-cream despite cool labels.",
        fix: "Apply cool-gray tokens per 2026-05-21 canon decision and align eyebrow copy ('PEARL on FROST' stays, but as accurate label for the new substrate)." },
      { id: "cap-rule-bypass", severity: "issue", axis: "semantics",
        title: "Rules bypass ScopeRule primitive",
        detail: "Toolbar, margin, and foot rail all hand-roll '0.5px solid T.inkRuleS' instead of declaring ScopeRule.section/.row/.subtle, so the surface diverges from MacNoteDetail's semantic vocabulary.",
        fix: "Replace inline borderColor with ScopeRule tokens (section under toolbar, subtle on margin divider, row inside meta blocks) so the cascade matches sibling surfaces." },
      { id: "cap-filename-vs-derived", severity: "issue", axis: "hierarchy",
        title: "Filename competes with derived caption",
        detail: "Filename is 18px mono-medium ink while the derived editorial line is a tiny 12.5px italic faint — for an image-first surface the human-readable derived line should anchor, not the slug.",
        fix: "Promote derived to a serif 16-17px ScopeInk headline, demote the filename to a mono byline beneath, matching the eyebrow + headline + byline pattern." },
      { id: "cap-promotes-narration", severity: "issue", axis: "copy",
        title: "'promotes to a note' is narration",
        detail: "The italic helper inside the +ADD CAPTION pill explains what the button does — exactly the 'let affordances speak' rule we keep, and the eyebrow/footnote also editorialize.",
        fix: "Drop the inline italic; rely on the ⌘N shortcut + Scope's documented promotion rule. Trim the footnote to '· C-0017 · capture · CH-05'." },
      { id: "cap-toolbutton-contrast", severity: "issue", axis: "a11y",
        title: "Tool buttons sit at 32% ink",
        detail: "ToolButton uses T.inkFainter (rgba 0.32) on T.pane — below WCAG AA for 9px mono labels, and the FootAction Delete at opacity 0.75 over T.rail similarly thins out.",
        fix: "Raise ToolButton to T.inkFaint (0.55) with hover lift to T.ink; remove the blanket opacity 0.75 on FootAction and let tone carry the state." },
      { id: "cap-margin-asymmetric", severity: "polish", axis: "spacing",
        title: "Margin column gutters asymmetric",
        detail: "paddingLeft 20 vs paddingRight 32 on the aside skews the meta block off the left rule; sibling detail surfaces keep symmetric or rule-aligned padding.",
        fix: "Align to a 24/24 or 20/24 pair and pin labels to the inner rule edge for a true margin-rail feel." },
      { id: "cap-tracking-drift", severity: "polish", axis: "typography",
        title: "Tracking values drift across mono labels",
        detail: "0.14em / 0.16em / 0.18em / 0.20em / 0.22em / 0.28em all appear within one surface — mono ladder is noisier than it needs to be.",
        fix: "Collapse to a 3-step ladder (0.16 body / 0.22 eyebrow / 0.28 section header) and reuse via shared constants." },
      { id: "cap-cool-row-tint", severity: "polish", axis: "hierarchy",
        title: "Selected list row uses cool blue tint",
        detail: "LibraryListGutter selection background #E5EEF3 is a cool wash inside an otherwise warm chrome — wrong hue (blue, should be gray).",
        fix: "Swap to new rail gray #DCDCDB (or chiffon/amber tint with brass left-edge) so the gutter speaks the cool-gray canon." },
    ],
  },

  // ── SKILLS ──────────────────────────────────────────────────────────
  {
    route: "/mac-skills",
    display: "Skills",
    role: "Landing for user-authored workflows. Starters · saved skills · where-it-fires · editor bay.",
    oneLineRead:
      "Dense one-page workshop that holds the loop together, but the eyebrow rows and CTA underlines repeat enough to flatten the hierarchy a workshop surface really needs.",
    grades: { typography: "B", spacing: "B", hierarchy: "C", semantics: "B", copy: "C" },
    topThree: [
      "Tier the substrates so Starters / Your Skills / Where-it-fires don't all read as the same paper grid — give the page a workshop → catalog → manifestation gradient.",
      "Ration amber: one primary action per zone (the EDITING pair), demote sibling CTAs to ink — restore the 'scarce accent' the Scope palette depends on.",
      "Delete the footer paragraph and trim the 9pt mono eyebrow repetition; let the artifacts speak instead of narrating them.",
    ],
    findings: [
      { id: "sk-equal-cards", severity: "issue", axis: "hierarchy",
        title: "Five sibling card rows compete",
        detail: "Starters, Your Skills, Where-it-fires, and the editor bay all use the same paper card at the same weight — page reads as one long stack of equal blocks rather than workshop → catalog → manifestation.",
        fix: "Tier the substrates — PAPER for starters, CREAM with ScopeRule.row above each card for Your Skills, quieter ScopeEdge.subtle frame for Where-it-fires." },
      { id: "sk-mono-overuse", severity: "issue", axis: "typography",
        title: "9pt mono eyebrow overused",
        detail: "Every section, pane, chip, card, code, and preview eyebrow uses fontSize 9, uppercase, 0.22–0.32em tracking — typographic 'voice' becomes monotone.",
        fix: "Reserve 9pt mono for section labels; bump pane headers to 10pt; demote card codes (S-0024) to a non-tracked numeral." },
      { id: "sk-editor-bay-coequal", severity: "issue", axis: "hierarchy",
        title: "Editor bay panes feel coequal",
        detail: "Chat and Markup share the same border, radius, height, and eyebrow weight, but Markup is the load-bearing artifact — it's what RUN/SAVE acts on.",
        fix: "Anchor Markup with a slightly heavier scopeCardBorder or a 2px brass left rule; let Chat sit on plain CREAM with just a ScopeRule.subtle divider." },
      { id: "sk-footer-marketing", severity: "issue", axis: "copy",
        title: "Footer paragraph is marketing copy",
        detail: "The closing paragraph ('One tab. The user reads the page top to bottom… Workshop, catalog, and promise on the same surface.') narrates the design instead of letting affordances speak.",
        fix: "Delete the footer paragraph; if a closer is needed, replace with a single ScopeRule.section and a mono datum row ('· 3 starters · 3 saved · 4 invocation surfaces')." },
      { id: "sk-amber-overuse", severity: "issue", axis: "semantics",
        title: "Amber underline CTA repeats six times",
        detail: "USE →, OPEN ABOVE ↑, OPEN IN EDITOR →, APPLY →, ⌘S SAVE, EDITING all share the amber treatment, so amber stops meaning 'primary action' and becomes the page's accent color.",
        fix: "Reserve AMBER for the single active intent (EDITING/RUN pair); demote sibling CTAs to INK_FAINT with ScopeEdge.subtle underline." },
      { id: "sk-pipeline-crowding", severity: "polish", axis: "spacing",
        title: "Card pipeline row crowds the byline",
        detail: "10px gap above the pipeline and 8px under the rule compresses the WHEN/WITH/DO/THEN strip against the italic byline; pipeline tokens read as part of the description.",
        fix: "Increase the gap above the rule to 14px; add 2px line-height to the pipeline row so the four-token strip sits as its own band." },
      { id: "sk-italic-mono-collide", severity: "polish", axis: "typography",
        title: "Byline italic + pipeline mono collide",
        detail: "Cormorant italic at 11.5px next to JetBrains mono at 10px creates a visual stutter — two voices at near-equal volume one line apart.",
        fix: "Drop byline to non-italic 12px or shrink to 11px regular; let the pipeline mono be the only 'instrument' voice in the lower half of the card." },
      { id: "sk-fainter-contrast", severity: "polish", axis: "a11y",
        title: "INK_FAINTER on PAPER hits ~3.0:1",
        detail: "Card codes (S-0024), timestamps, and the '…' mini-chip use INK_FAINTER (0.32 alpha) on PAPER, below WCAG AA for small text.",
        fix: "Lift secondary metadata to INK_FAINT (0.55); reserve INK_FAINTER for true decoration (separator dots, dimmed-state mini-chips)." },
    ],
  },
];

// ── Status constants ──────────────────────────────────────────────────

const STATUS_ORDER: Status[] = ["queued", "inflight", "shipped", "skipped"];
const STATUS_NEXT: Record<Status, Status> = {
  queued: "inflight",
  inflight: "shipped",
  shipped: "skipped",
  skipped: "queued",
};
const STATUS_LABEL: Record<Status, string> = {
  queued: "Queued",
  inflight: "In flight",
  shipped: "Shipped",
  skipped: "Skipped",
};
const STATUS_COLOR: Record<Status, string> = {
  queued: "#A8A39B",
  inflight: "#C47D1C",
  shipped: "#9A6A22",
  skipped: "#6B7A75",
};
const STATUS_GLYPH: Record<Status, string> = {
  queued: "○",
  inflight: "◐",
  shipped: "●",
  skipped: "⊘",
};

const LEVEL_COLOR: Record<NoteLevel, string> = {
  info: "#6B7A75",
  progress: "#C47D1C",
  landed: "#9A6A22",
  blocked: "#C43A1C",
  proposal: "#A87544",
  question: "#7A5BC2",
};

const FILTER_LABEL: Record<Filter, string> = {
  all: "All",
  active: "Active",
  shipped: "Shipped",
  skipped: "Skipped",
};

const SEVERITY_COLOR: Record<Severity, string> = {
  blocker: "#C43A1C",
  issue: "#C47D1C",
  polish: "#9A6A22",
};

const GRADE_COLOR: Record<Grade, string> = {
  A: "#9A6A22",
  B: "#C47D1C",
  C: "#A87544",
  D: "#C43A1C",
};

const AXES: Array<keyof SurfaceAudit["grades"]> = ["typography", "spacing", "hierarchy", "semantics", "copy"];

// ── Status hook (API-backed) ──────────────────────────────────────────
//
// Source of truth is design/studio/data/audit/scope-2026-05-21.json.
// Browser reads via GET /mac-audit/api/status, writes via POST. Agents
// read/write the file directly. Page refetches on focus so changes from
// either side propagate. Protocol doc: data/audit/AGENTS.md.

interface ItemRecord {
  status: Status;
  updatedAt: string;
  updatedBy: string;
  note?: string;
  notes?: Note[];
}

interface StatusFile {
  version: number;
  audit: string;
  updatedAt: string;
  items: Record<string, ItemRecord>;
}

function useAuditStatus() {
  const [data, setData] = useState<StatusFile | null>(null);
  const [hydrated, setHydrated] = useState(false);

  const refetch = async () => {
    try {
      const res = await fetch("/mac-audit/api/status", { cache: "no-store" });
      if (res.ok) setData(await res.json());
    } catch {}
    setHydrated(true);
  };

  useEffect(() => {
    refetch();
    const onFocus = () => refetch();
    window.addEventListener("focus", onFocus);
    return () => window.removeEventListener("focus", onFocus);
  }, []);

  const cycle = async (id: string) => {
    const current = data?.items[id]?.status ?? "queued";
    const next = STATUS_NEXT[current];
    // Optimistic update
    if (data) {
      const optimistic: StatusFile = {
        ...data,
        items: { ...data.items, [id]: { status: next, updatedAt: new Date().toISOString(), updatedBy: "ui" } },
      };
      setData(optimistic);
    }
    try {
      const res = await fetch("/mac-audit/api/status", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ id, status: next, updatedBy: "ui" }),
      });
      if (res.ok) setData(await res.json());
    } catch {}
  };

  const reset = async () => {
    try {
      const res = await fetch("/mac-audit/api/status", { method: "DELETE" });
      if (res.ok) setData(await res.json());
    } catch {}
  };

  const statusOf = (id: string): Status => data?.items[id]?.status ?? "queued";
  const recordOf = (id: string): ItemRecord | undefined => data?.items[id];

  return { data, hydrated, cycle, reset, statusOf, recordOf, refetch };
}

// ── Page ──────────────────────────────────────────────────────────────

export default function MacAuditPage() {
  const status = useAuditStatus();
  const [filter, setFilter] = useState<Filter>("all");

  const allIds = useMemo(() => {
    const ids: string[] = [];
    ids.push(...THEMES.map((t) => t.id));
    ids.push(...TOP_OF_STACK.map((t) => t.id));
    for (const a of AUDITS) ids.push(...a.findings.map((f) => f.id));
    if (status.data?.items) {
      for (const id of Object.keys(status.data.items)) {
        if (!ids.includes(id)) ids.push(id);
      }
    }
    return ids;
  }, [status.data?.items]);

  const counts = useMemo(() => {
    const c: Record<Status, number> = { queued: 0, inflight: 0, shipped: 0, skipped: 0 };
    for (const id of allIds) c[status.statusOf(id)]++;
    return c;
  }, [allIds, status.map]);

  const total = allIds.length;
  const shippedPct = total === 0 ? 0 : Math.round((counts.shipped / total) * 100);

  const matchesFilter = (s: Status): boolean => {
    if (filter === "all") return true;
    if (filter === "active") return s === "queued" || s === "inflight";
    if (filter === "shipped") return s === "shipped";
    if (filter === "skipped") return s === "skipped";
    return true;
  };

  const lastUpdatedAt = status.data?.updatedAt;

  return (
    <StudioPage
      eyebrow="Scope · Audit"
      title="Studio + Swift Worksheet"
      help="agent-driven review · 6 studio surfaces + 6 swift surfaces · click any status pill to cycle · file-backed"
    >
      <div className="px-7 py-8">
        {/* Header / Summary */}
        <div className="mb-8 border-b border-studio-edge pb-7">
          <div className="flex items-baseline gap-6">
            <h1 className="m-0 font-display text-[42px] font-medium leading-none tracking-tight text-studio-ink">
              {counts.shipped}
              <span className="text-studio-ink-faint"> / {total} shipped</span>
            </h1>
            <div className="ml-auto flex items-center gap-3 font-mono text-[9px] uppercase tracking-[0.20em] text-studio-ink-faint">
              {STATUS_ORDER.map((s, i) => (
                <span key={s} className="contents">
                  <SummaryCount status={s} count={counts[s]} />
                  {i < STATUS_ORDER.length - 1 ? <Sep /> : null}
                </span>
              ))}
            </div>
          </div>
          {/* Progress bar */}
          <div className="mt-4 h-1.5 w-full overflow-hidden rounded-sm bg-studio-edge/60">
            <div className="flex h-full">
              <div className="h-full" style={{ width: `${(counts.shipped / total) * 100}%`, background: STATUS_COLOR.shipped }} />
              <div className="h-full" style={{ width: `${(counts.inflight / total) * 100}%`, background: STATUS_COLOR.inflight }} />
              <div className="h-full opacity-60" style={{ width: `${(counts.skipped / total) * 100}%`, background: STATUS_COLOR.skipped }} />
            </div>
          </div>
          <div className="mt-2 flex items-baseline justify-between text-[10px] font-mono uppercase tracking-[0.18em] text-studio-ink-faint">
            <span>
              {shippedPct}% shipped
              {lastUpdatedAt ? <span className="ml-3 normal-case tracking-normal">· file updated {formatRelative(lastUpdatedAt)}</span> : null}
            </span>
            <div className="flex items-center gap-2">
              <button
                onClick={() => status.refetch()}
                className="rounded-sm border border-studio-edge px-2 py-0.5 hover:text-studio-ink"
                title="Re-read status.json (also auto-refetches on focus)"
              >
                Refresh ↻
              </button>
              <button
                onClick={() => {
                  if (confirm("Reset all status to queued? This clears status.json.")) status.reset();
                }}
                className="rounded-sm border border-studio-edge px-2 py-0.5 hover:text-studio-ink"
              >
                Reset ↺
              </button>
            </div>
          </div>
        </div>

        {/* Filter toolbar */}
        <div className="mb-10 flex items-center gap-2">
          {(Object.keys(FILTER_LABEL) as Filter[]).map((f) => (
            <button
              key={f}
              onClick={() => setFilter(f)}
              className={`rounded-sm border px-3 py-1 font-mono text-[9px] uppercase tracking-[0.20em] ${
                filter === f
                  ? "border-studio-ink/30 bg-white text-studio-ink"
                  : "border-studio-edge bg-white/40 text-studio-ink-faint hover:text-studio-ink"
              }`}
            >
              {FILTER_LABEL[f]}
            </button>
          ))}
          <span className="ml-auto text-[9px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint">
            {filter === "all" ? "showing all" : `filtering by ${FILTER_LABEL[filter].toLowerCase()}`}
          </span>
        </div>

        {/* Decisions log */}
        {DECISIONS.length > 0 ? (
          <section className="mb-12">
            <div className="mb-3 flex items-baseline gap-3">
              <h2 className="m-0 font-display text-[20px] font-medium tracking-tight text-studio-ink">
                Decisions
              </h2>
              <span className="text-[9px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint">
                canon shifts captured during the audit
              </span>
            </div>
            <div className="rounded-md border border-studio-edge bg-white/40">
              {DECISIONS.map((d, i) => (
                <div key={d.id} className={`px-4 py-3 ${i > 0 ? "border-t border-studio-edge/60" : ""}`}>
                  <div className="flex items-baseline gap-3">
                    <span className="font-mono text-[9px] uppercase tracking-[0.20em] text-studio-ink-faint">
                      {d.date}
                    </span>
                    <span className="font-display text-[14.5px] font-medium tracking-tight text-studio-ink">
                      {d.title}
                    </span>
                  </div>
                  <div className="mt-1.5 max-w-[760px] text-[11.5px] leading-snug text-studio-ink-faint">
                    {d.detail}
                  </div>
                </div>
              ))}
            </div>
          </section>
        ) : null}

        {/* Grade matrix */}
        <section className="mb-12">
          <div className="mb-3 flex items-baseline gap-3">
            <h2 className="m-0 font-display text-[20px] font-medium tracking-tight text-studio-ink">
              Grade matrix
            </h2>
            <span className="text-[9px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint">
              six surfaces · five axes
            </span>
          </div>
          <GradeMatrix />
        </section>

        {/* Themes */}
        <section className="mb-12">
          <SectionHeader
            title="Cross-cutting themes"
            note="patterns that hit ≥ 2 surfaces · fix once, pay everywhere"
            shipped={THEMES.filter((t) => status.statusOf(t.id) === "shipped").length}
            total={THEMES.length}
          />
          <div className="rounded-md border border-studio-edge bg-white/40">
            {THEMES.filter((t) => matchesFilter(status.statusOf(t.id))).map((t, i) => (
              <ThemeRow
                key={t.id}
                theme={t}
                status={status.statusOf(t.id)}
                notes={status.recordOf(t.id)?.notes}
                onCycle={() => status.cycle(t.id)}
                divided={i > 0}
              />
            ))}
          </div>
        </section>

        {/* Top of stack */}
        <section className="mb-14">
          <SectionHeader
            title="Top of stack"
            note="highest-leverage moves across the audit"
            shipped={TOP_OF_STACK.filter((t) => status.statusOf(t.id) === "shipped").length}
            total={TOP_OF_STACK.length}
          />
          <ol className="m-0 flex list-none flex-col gap-2 p-0">
            {TOP_OF_STACK.filter((t) => matchesFilter(status.statusOf(t.id))).map((row, i) => {
              const st = status.statusOf(row.id);
              const notes = status.recordOf(row.id)?.notes;
              return (
                <li
                  key={row.id}
                  className={`grid grid-cols-[32px_1fr_auto] items-baseline gap-3 border-b border-studio-edge/40 pb-2 ${
                    st === "shipped" ? "opacity-70" : st === "skipped" ? "opacity-50" : ""
                  }`}
                >
                  <span className="font-mono text-[10px] uppercase tracking-[0.20em] text-studio-ink-faint">
                    {String(i + 1).padStart(2, "0")}
                  </span>
                  <div>
                    <div className="font-display text-[15px] font-medium tracking-tight text-studio-ink">
                      {row.title}
                    </div>
                    <div className="mt-1 max-w-[760px] text-[11.5px] leading-snug text-studio-ink-faint">
                      {row.payoff}
                    </div>
                    <NotesBlock notes={notes} />
                  </div>
                  <StatusPill status={st} onClick={() => status.cycle(row.id)} hydrated={status.hydrated} />
                </li>
              );
            })}
          </ol>
        </section>

        {/* Per-surface */}
        <section>
          <div className="mb-4 flex items-baseline gap-3 border-t border-studio-edge pt-7">
            <h2 className="m-0 font-display text-[22px] font-medium tracking-tight text-studio-ink">
              Per-surface · Studio
            </h2>
            <span className="text-[9px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint">
              one-line read · grades · findings · top three fixes
            </span>
          </div>
          <div className="flex flex-col gap-12">
            {AUDITS.map((a) => (
              <SurfaceBlock
                key={a.route}
                audit={a}
                statusOf={status.statusOf}
                recordOf={status.recordOf}
                onCycle={status.cycle}
                filter={filter}
                matchesFilter={matchesFilter}
                hydrated={status.hydrated}
              />
            ))}
          </div>
        </section>

        {/* Per-surface · Swift */}
        <SwiftSection status={status} filter={filter} matchesFilter={matchesFilter} />

        {/* Agent contract */}
        <section className="mt-16 border-t border-studio-edge pt-7">
          <div className="mb-3 flex items-baseline gap-3">
            <h2 className="m-0 font-display text-[20px] font-medium tracking-tight text-studio-ink">
              Agent contract
            </h2>
            <span className="text-[9px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint">
              how to participate as an agent (claude, codex, scout, etc.)
            </span>
          </div>
          <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
            <div className="rounded-md border border-studio-edge bg-white/40 p-4">
              <div className="mb-2 text-[9px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint">
                · Files
              </div>
              <ul className="m-0 flex list-none flex-col gap-1.5 p-0 font-mono text-[11px] text-studio-ink">
                <li>
                  <span className="text-studio-ink-faint">state:</span>{" "}
                  design/studio/data/audit/scope-2026-05-21.json
                </li>
                <li>
                  <span className="text-studio-ink-faint">protocol:</span>{" "}
                  design/studio/data/audit/AGENTS.md
                </li>
                <li>
                  <span className="text-studio-ink-faint">page:</span>{" "}
                  design/studio/app/mac-audit/page.tsx
                </li>
                <li>
                  <span className="text-studio-ink-faint">api:</span>{" "}
                  /mac-audit/api/status (GET · POST · DELETE)
                </li>
              </ul>
            </div>
            <div className="rounded-md border border-studio-edge bg-white/40 p-4">
              <div className="mb-2 text-[9px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint">
                · Schema
              </div>
              <pre className="m-0 overflow-x-auto whitespace-pre font-mono text-[10.5px] leading-relaxed text-studio-ink">
{`{
  "version": 1,
  "audit": "scope-2026-05-21",
  "updatedAt": "<ISO>",
  "items": {
    "<id>": {
      "status": "queued|inflight|shipped|skipped",
      "updatedAt": "<ISO>",
      "updatedBy": "<your handle>",
      "note": "<optional one-liner>",
      "notes": [
        { "ts": "<ISO>", "agent": "<handle>",
          "level": "info|progress|landed|blocked|proposal|question",
          "message": "<1-3 sentences>", "ref": "<commit sha or file:line>" }
      ]
    }
  }
}`}
              </pre>
            </div>
          </div>

          <div className="mt-4 rounded-md border border-studio-edge bg-white/40 p-4">
            <div className="mb-2 text-[9px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint">
              · Protocol
            </div>
            <ol className="m-0 flex list-none flex-col gap-1.5 p-0 text-[11.5px] leading-snug text-studio-ink">
              <li><span className="mr-2 font-mono text-studio-ink-faint">1.</span> Read status.json. Filter for <code className="font-mono text-[10.5px]">status === &quot;queued&quot;</code> to find available work.</li>
              <li><span className="mr-2 font-mono text-studio-ink-faint">2.</span> Pick an item by id. Edit status.json to set <code className="font-mono text-[10.5px]">status: &quot;inflight&quot;</code>, update <code className="font-mono text-[10.5px]">updatedAt</code> (ISO) and <code className="font-mono text-[10.5px]">updatedBy</code> (your name).</li>
              <li><span className="mr-2 font-mono text-studio-ink-faint">3.</span> Grep page.tsx for the id to find the finding&apos;s <code className="font-mono text-[10.5px]">detail</code> + <code className="font-mono text-[10.5px]">fix</code>. Look up the surface in AUDITS to know which file to edit.</li>
              <li><span className="mr-2 font-mono text-studio-ink-faint">4.</span> Apply the fix in the relevant studio (.tsx) or swift file. Verify with curl or build.</li>
              <li><span className="mr-2 font-mono text-studio-ink-faint">5.</span> Edit status.json: set <code className="font-mono text-[10.5px]">status: &quot;shipped&quot;</code> + a short <code className="font-mono text-[10.5px]">note</code> describing what landed.</li>
            </ol>
          </div>

          <details className="mt-4 rounded-md border border-studio-edge bg-white/40 p-4">
            <summary className="cursor-pointer text-[9px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint hover:text-studio-ink">
              · Item ID reference ({allIds.length} ids)
            </summary>
            <ItemIdReference extraIds={allIds} />
          </details>
        </section>

        {/* Footer */}
        <div className="mt-14 border-t border-studio-edge pt-5 text-[10px] font-mono uppercase tracking-[0.18em] text-studio-ink-faint">
          · Agent-validated · 6 reviewers · Audit ID scope-2026-05-21 · state: data/audit/scope-2026-05-21.json · protocol: data/audit/AGENTS.md
        </div>
      </div>
    </StudioPage>
  );
}

// ── Components ────────────────────────────────────────────────────────

function Sep() {
  return <span className="h-3 w-px bg-studio-edge" aria-hidden />;
}

function formatRelative(iso: string): string {
  const then = new Date(iso).getTime();
  if (isNaN(then)) return "";
  const seconds = Math.max(0, Math.floor((Date.now() - then) / 1000));
  if (seconds < 60) return "just now";
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
  return `${Math.floor(seconds / 86400)}d ago`;
}

function SummaryCount({ status, count }: { status: Status; count: number }) {
  return (
    <span className="inline-flex items-center gap-1.5">
      <span
        aria-hidden
        className="inline-flex h-3 w-3 items-center justify-center font-mono text-[11px] leading-none"
        style={{ color: STATUS_COLOR[status] }}
      >
        {STATUS_GLYPH[status]}
      </span>
      <span>{STATUS_LABEL[status]}</span>
      <span className="text-studio-ink">{count}</span>
    </span>
  );
}

function SectionHeader({ title, note, shipped, total }: { title: string; note: string; shipped: number; total: number }) {
  return (
    <div className="mb-3 flex items-baseline gap-3">
      <h2 className="m-0 font-display text-[20px] font-medium tracking-tight text-studio-ink">
        {title}
      </h2>
      <span className="text-[9px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint">
        {note}
      </span>
      <span className="ml-auto rounded-sm border border-studio-edge px-2 py-0.5 font-mono text-[9px] uppercase tracking-[0.18em] text-studio-ink-faint">
        {shipped} / {total} shipped
      </span>
    </div>
  );
}

function StatusPill({ status, onClick, hydrated, compact = false }: {
  status: Status;
  onClick: () => void;
  hydrated: boolean;
  compact?: boolean;
}) {
  // Avoid hydration mismatch — show neutral pill until localStorage read
  const shown: Status = hydrated ? status : "queued";
  const color = STATUS_COLOR[shown];
  const label = STATUS_LABEL[shown];
  const glyph = STATUS_GLYPH[shown];
  return (
    <button
      onClick={onClick}
      title={`${label} — click to cycle`}
      className={`inline-flex items-center gap-1.5 rounded-sm border font-mono uppercase tracking-[0.16em] transition-colors ${
        compact ? "px-1.5 py-0.5 text-[8.5px]" : "px-2 py-0.5 text-[9px]"
      }`}
      style={{
        color: color,
        background: `${color}10`,
        borderColor: `${color}55`,
      }}
    >
      <span aria-hidden style={{ fontSize: compact ? 9 : 10, lineHeight: 1 }}>{glyph}</span>
      <span>{label}</span>
    </button>
  );
}

function GradeMatrix() {
  return (
    <div className="overflow-hidden rounded-md border border-studio-edge bg-white/40">
      <div className="grid grid-cols-[1.3fr_repeat(5,minmax(0,1fr))] items-baseline gap-3 border-b border-studio-edge/80 px-4 py-2.5 text-[9px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint">
        <span>Surface</span>
        {AXES.map((axis) => (
          <span key={axis} className="text-center">{axis}</span>
        ))}
      </div>
      {AUDITS.map((a, i) => (
        <div
          key={a.route}
          className={`grid grid-cols-[1.3fr_repeat(5,minmax(0,1fr))] items-center gap-3 px-4 py-2.5 ${
            i > 0 ? "border-t border-studio-edge/50" : ""
          }`}
        >
          <Link
            href={a.route}
            className="flex min-w-0 flex-col gap-0.5 hover:text-studio-ink"
          >
            <span className="font-display text-[13.5px] font-medium tracking-tight text-studio-ink">
              {a.display}
            </span>
            <span className="text-[9px] font-mono uppercase tracking-[0.18em] text-studio-ink-faint">
              {a.route.replace("/mac-", "")} →
            </span>
          </Link>
          {AXES.map((axis) => (
            <GradeCell key={axis} grade={a.grades[axis]} />
          ))}
        </div>
      ))}
    </div>
  );
}

function GradeCell({ grade }: { grade: Grade }) {
  return (
    <div className="flex items-center justify-center">
      <span
        className="inline-flex h-6 min-w-[24px] items-center justify-center rounded-sm px-2 font-mono text-[11px] font-semibold"
        style={{
          color: GRADE_COLOR[grade],
          background: `${GRADE_COLOR[grade]}10`,
          border: `0.5px solid ${GRADE_COLOR[grade]}40`,
        }}
        title={`Grade ${grade}`}
      >
        {grade}
      </span>
    </div>
  );
}

function ThemeRow({ theme, status, notes, onCycle, divided }: {
  theme: Theme;
  status: Status;
  notes?: Note[];
  onCycle: () => void;
  divided: boolean;
}) {
  const dim = status === "shipped" ? "opacity-70" : status === "skipped" ? "opacity-50" : "";
  return (
    <div className={`grid grid-cols-[1fr_180px_auto] items-start gap-6 px-4 py-3.5 ${divided ? "border-t border-studio-edge/60" : ""} ${dim}`}>
      <div className="min-w-0">
        <div className="font-display text-[14.5px] font-medium tracking-tight text-studio-ink">
          {theme.title}
        </div>
        <div className="mt-1 max-w-[640px] text-[11.5px] leading-snug text-studio-ink-faint">
          {theme.detail}
        </div>
        <div className="mt-2 max-w-[640px] text-[11.5px] leading-snug text-studio-ink">
          <span className="mr-1 font-mono text-[9px] uppercase tracking-[0.20em] text-studio-ink-faint">FIX</span>
          {theme.fix}
        </div>
        <NotesBlock notes={notes} />
      </div>
      <div className="flex flex-wrap items-center justify-end gap-1.5">
        {theme.hits.map((r) => (
          <Link
            key={r}
            href={r}
            className="rounded-sm border border-studio-edge px-1.5 py-0.5 font-mono text-[9px] uppercase tracking-[0.16em] text-studio-ink-faint hover:text-studio-ink"
          >
            {r.replace("/mac-", "")}
          </Link>
        ))}
      </div>
      <StatusPill status={status} onClick={onCycle} hydrated={true} />
    </div>
  );
}

function SurfaceBlock({ audit, statusOf, recordOf, onCycle, filter, matchesFilter, hydrated }: {
  audit: SurfaceAudit;
  statusOf: (id: string) => Status;
  recordOf: (id: string) => ItemRecord | undefined;
  onCycle: (id: string) => void;
  filter: Filter;
  matchesFilter: (s: Status) => boolean;
  hydrated: boolean;
}) {
  const shippedInSurface = audit.findings.filter((f) => statusOf(f.id) === "shipped").length;
  const visible = audit.findings.filter((f) => matchesFilter(statusOf(f.id)));

  return (
    <article className="flex flex-col gap-5">
      {/* Header band */}
      <div className="flex items-baseline gap-3 border-b border-studio-edge pb-3">
        <h3 className="m-0 font-display text-[22px] font-medium tracking-tight text-studio-ink">
          {audit.display}
        </h3>
        <Link
          href={audit.route}
          className="text-[9px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint hover:text-studio-ink"
        >
          STUDIO → {audit.route.replace("/mac-", "")}
        </Link>
        <span className="ml-auto rounded-sm border border-studio-edge px-2 py-0.5 font-mono text-[9px] uppercase tracking-[0.18em] text-studio-ink-faint">
          {shippedInSurface} / {audit.findings.length} shipped
        </span>
        <div className="flex items-center gap-1.5">
          {AXES.map((axis) => (
            <span
              key={axis}
              className="inline-flex items-center gap-1 rounded-sm px-1.5 py-0.5 font-mono text-[9px] uppercase tracking-[0.16em]"
              style={{
                color: GRADE_COLOR[audit.grades[axis]],
                background: `${GRADE_COLOR[audit.grades[axis]]}10`,
              }}
              title={`${axis}: ${audit.grades[axis]}`}
            >
              <span className="text-studio-ink-faint">{axis.slice(0, 3)}</span>
              <span>{audit.grades[axis]}</span>
            </span>
          ))}
        </div>
      </div>

      <div className="grid grid-cols-[160px_1fr] gap-6 text-[11.5px]">
        <div className="font-mono text-[9px] uppercase tracking-[0.20em] text-studio-ink-faint">Role</div>
        <div className="text-studio-ink-faint">{audit.role}</div>
        <div className="font-mono text-[9px] uppercase tracking-[0.20em] text-studio-ink-faint">Read</div>
        <div className="text-studio-ink">{audit.oneLineRead}</div>
      </div>

      {/* Findings */}
      <div className="rounded-md border border-studio-edge bg-white/40">
        <div className="border-b border-studio-edge/80 px-4 py-2 text-[9px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint">
          · {visible.length} of {audit.findings.length} findings {filter !== "all" ? `· ${FILTER_LABEL[filter].toLowerCase()}` : ""}
        </div>
        {visible.length === 0 ? (
          <div className="px-4 py-6 text-center text-[10px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint">
            no findings match this filter
          </div>
        ) : (
          visible.map((f, i) => (
            <FindingRow
              key={f.id}
              finding={f}
              status={statusOf(f.id)}
              notes={recordOf(f.id)?.notes}
              onCycle={() => onCycle(f.id)}
              divided={i > 0}
              hydrated={hydrated}
            />
          ))
        )}
      </div>

      {/* Top three */}
      <div>
        <div className="mb-2 text-[9px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint">
          · Top three fixes
        </div>
        <ol className="m-0 flex list-none flex-col gap-1.5 p-0">
          {audit.topThree.map((row, i) => (
            <li key={i} className="grid grid-cols-[24px_1fr] items-baseline gap-2">
              <span className="font-mono text-[10px] text-studio-ink-faint">{i + 1}.</span>
              <span className="text-[12px] leading-snug text-studio-ink">{row}</span>
            </li>
          ))}
        </ol>
      </div>
    </article>
  );
}

function NotesBlock({ notes }: { notes?: Note[] }) {
  if (!notes || notes.length === 0) return null;
  return (
    <div className="mt-2 border-t border-studio-edge/40 pt-2">
      <div className="mb-1.5 font-mono text-[9px] uppercase tracking-[0.20em] text-studio-ink-faint">
        · {notes.length} note{notes.length === 1 ? "" : "s"}
      </div>
      <ul className="m-0 flex list-none flex-col gap-1.5 p-0">
        {notes.map((n, i) => (
          <li key={i} className="grid grid-cols-[auto_auto_auto_1fr] items-baseline gap-2 text-[11px]">
            <span className="font-mono text-[9px] tracking-[0.04em] text-studio-ink-faint">
              {formatRelative(n.ts)}
            </span>
            <span className="font-mono text-[9px] uppercase tracking-[0.16em] text-studio-ink">
              {n.agent}
            </span>
            <span
              className="rounded-sm px-1.5 py-px font-mono text-[8.5px] uppercase tracking-[0.16em]"
              style={{ color: LEVEL_COLOR[n.level], background: `${LEVEL_COLOR[n.level]}12` }}
            >
              {n.level}
            </span>
            <span className="text-studio-ink-faint">
              {n.message}
              {n.ref ? (
                <span className="ml-2 font-mono text-[10px] text-studio-ink/60">
                  {n.ref}
                </span>
              ) : null}
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}

function ItemIdReference({ extraIds }: { extraIds?: string[] }) {
  const swiftGroups: Array<{ label: string; ids: string[] }> = [];
  if (extraIds && extraIds.length > 0) {
    const bySurface: Record<string, string[]> = {};
    for (const id of extraIds) {
      if (!id.startsWith("sw-")) continue;
      const key = swiftSurfaceFor(id);
      (bySurface[key] ??= []).push(id);
    }
    for (const key of SWIFT_SURFACE_ORDER) {
      const ids = bySurface[key];
      if (ids && ids.length > 0) {
        swiftGroups.push({ label: SWIFT_SURFACE_META[key]?.label ?? key, ids });
      }
    }
  }
  const groups: Array<{ label: string; ids: string[] }> = [
    { label: "Themes", ids: THEMES.map((t) => t.id) },
    { label: "Top of stack", ids: TOP_OF_STACK.map((t) => t.id) },
    ...AUDITS.map((a) => ({ label: a.display, ids: a.findings.map((f) => f.id) })),
    ...swiftGroups,
  ];
  return (
    <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
      {groups.map((g) => (
        <div key={g.label} className="min-w-0">
          <div className="mb-1 text-[9px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint">
            · {g.label}
          </div>
          <ul className="m-0 flex list-none flex-col gap-0.5 p-0 font-mono text-[10.5px] text-studio-ink">
            {g.ids.map((id) => (
              <li key={id}>{id}</li>
            ))}
          </ul>
        </div>
      ))}
    </div>
  );
}

const SWIFT_SURFACE_ORDER = ["sw-design", "sw-dict", "sw-home", "sw-lib", "sw-note", "sw-cap", "sw-sk"] as const;
const SWIFT_SURFACE_META: Record<string, { label: string; role: string; file: string }> = {
  "sw-design": {
    label: "ScopeDesign.swift",
    role: "Canon source · ScopeCanvas / ScopeInk / ScopeBrass / ScopeKind / ScopeRule",
    file: "apps/macos/TalkieKit/Sources/TalkieKit/UI/ScopeDesign.swift",
  },
  "sw-dict": {
    label: "TalkieView.swift",
    role: "Dictation + Memo detail. Owns the visible warm chiffon regression.",
    file: "apps/macos/Talkie/Views/TalkieObject/TalkieView.swift",
  },
  "sw-home": {
    label: "ScopeHomeView.swift",
    role: "Home landing — 40 inline brass hex sites, 6 hand-rolled hairlines.",
    file: "apps/macos/Talkie/Views/Home/ScopeHomeView.swift",
  },
  "sw-lib": {
    label: "ScopeLibraryView.swift",
    role: "List + readout bay. ~400 lines of dead bay scaffolding to delete.",
    file: "apps/macos/Talkie/Views/Library/ScopeLibraryView.swift",
  },
  "sw-note": {
    label: "ScopeNoteDetailView.swift",
    role: "Note detail. NoteToken local enum drifts warm.",
    file: "apps/macos/Talkie/Views/Notes/ScopeNoteDetailView.swift",
  },
  "sw-cap": {
    label: "ScopeCaptureDetailView.swift",
    role: "Capture detail. CapToken local enum + warm matte.",
    file: "apps/macos/Talkie/Views/Notes/ScopeCaptureDetailView.swift",
  },
  "sw-sk": {
    label: "ScopeSkillsLandingView.swift",
    role: "Skills surface. SkillsToken local enum + 12 hand-rolled hairlines.",
    file: "apps/macos/Talkie/Views/Skills/ScopeSkillsLandingView.swift",
  },
};

function swiftSurfaceFor(id: string): string {
  for (const key of SWIFT_SURFACE_ORDER) {
    if (id.startsWith(key + "-")) return key;
  }
  return "sw-other";
}

function SwiftSection({ status, filter, matchesFilter }: {
  status: ReturnType<typeof useAuditStatus>;
  filter: Filter;
  matchesFilter: (s: Status) => boolean;
}) {
  const items = status.data?.items ?? {};
  const swiftIds = Object.keys(items).filter((id) => id.startsWith("sw-"));
  if (swiftIds.length === 0) return null;

  const bySurface: Record<string, string[]> = {};
  for (const id of swiftIds) {
    const key = swiftSurfaceFor(id);
    (bySurface[key] ??= []).push(id);
  }

  const totalSwift = swiftIds.length;
  const shippedSwift = swiftIds.filter((id) => status.statusOf(id) === "shipped").length;
  const inflightSwift = swiftIds.filter((id) => status.statusOf(id) === "inflight").length;

  return (
    <section className="mt-16">
      <div className="mb-4 flex items-baseline gap-3 border-t border-studio-edge pt-7">
        <h2 className="m-0 font-display text-[22px] font-medium tracking-tight text-studio-ink">
          Per-surface · Swift
        </h2>
        <span className="text-[9px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint">
          codex lane · {shippedSwift}/{totalSwift} shipped{inflightSwift > 0 ? ` · ${inflightSwift} inflight` : ""} · live from data/audit
        </span>
      </div>
      <div className="flex flex-col gap-10">
        {SWIFT_SURFACE_ORDER.map((key) => {
          const ids = bySurface[key] ?? [];
          if (ids.length === 0) return null;
          const filtered = ids.filter((id) => matchesFilter(status.statusOf(id)));
          if (filtered.length === 0) return null;
          const shipped = ids.filter((id) => status.statusOf(id) === "shipped").length;
          const inflight = ids.filter((id) => status.statusOf(id) === "inflight").length;
          const meta = SWIFT_SURFACE_META[key];
          if (!meta) return null;

          return (
            <article key={key} className="rounded-md border border-studio-edge bg-white/40 p-5">
              <header className="mb-4 border-b border-studio-edge/60 pb-3">
                <div className="flex items-baseline gap-3">
                  <h3 className="m-0 font-display text-[18px] font-medium tracking-tight text-studio-ink">
                    {meta.label}
                  </h3>
                  <span className="ml-auto font-mono text-[9px] uppercase tracking-[0.20em] text-studio-ink-faint">
                    {shipped}/{ids.length} shipped{inflight > 0 ? ` · ${inflight} inflight` : ""}
                  </span>
                </div>
                <div className="mt-1.5 max-w-[760px] text-[11.5px] leading-snug text-studio-ink-faint">
                  {meta.role}
                </div>
                <div className="mt-1 font-mono text-[9.5px] uppercase tracking-[0.16em] text-studio-ink/40">
                  {meta.file}
                </div>
              </header>
              <ul className="m-0 flex list-none flex-col gap-0 p-0">
                {filtered.map((id, i) => {
                  const item = items[id];
                  const firstNote = item?.notes?.[0];
                  const extraNotes = item?.notes && item.notes.length > 1 ? item.notes.slice(1) : undefined;
                  const st = status.statusOf(id);
                  const severity = (firstNote as Note & { severity?: Severity } | undefined)?.severity;
                  const dim = st === "shipped" ? "opacity-70" : st === "skipped" ? "opacity-50" : "";
                  return (
                    <li
                      key={id}
                      className={`grid grid-cols-[16px_minmax(0,1fr)_auto] items-start gap-3 py-2.5 ${i > 0 ? "border-t border-studio-edge/30" : ""} ${dim}`}
                    >
                      <span
                        aria-hidden
                        className="mt-1.5 inline-block h-1.5 w-1.5 rounded-full"
                        style={{ background: severity ? SEVERITY_COLOR[severity] : "#A0A09E" }}
                        title={severity ?? ""}
                      />
                      <div className="min-w-0">
                        <div className="flex items-baseline gap-2 flex-wrap">
                          <code className="font-mono text-[10px] uppercase tracking-[0.14em] text-studio-ink-faint">{id}</code>
                          {severity ? (
                            <span
                              className="rounded-sm px-1.5 py-px font-mono text-[8.5px] uppercase tracking-[0.16em]"
                              style={{ color: SEVERITY_COLOR[severity], background: `${SEVERITY_COLOR[severity]}12` }}
                            >
                              {severity}
                            </span>
                          ) : null}
                        </div>
                        <div className="mt-1 max-w-[700px] text-[12px] leading-snug text-studio-ink">
                          {firstNote?.message ?? id}
                        </div>
                        {firstNote?.ref ? (
                          <div className="mt-1 font-mono text-[9.5px] tracking-[0.04em] text-studio-ink/55">
                            {firstNote.ref}
                          </div>
                        ) : null}
                        <NotesBlock notes={extraNotes} />
                      </div>
                      <StatusPill status={st} onClick={() => status.cycle(id)} hydrated={status.hydrated} compact />
                    </li>
                  );
                })}
              </ul>
            </article>
          );
        })}
      </div>
    </section>
  );
}

function FindingRow({ finding, status, notes, onCycle, divided, hydrated }: {
  finding: Finding;
  status: Status;
  notes?: Note[];
  onCycle: () => void;
  divided: boolean;
  hydrated: boolean;
}) {
  const dim = status === "shipped" ? "opacity-70" : status === "skipped" ? "opacity-50" : "";
  return (
    <div className={`grid grid-cols-[18px_72px_1fr_auto] items-start gap-3 px-4 py-3 ${divided ? "border-t border-studio-edge/40" : ""} ${dim}`}>
      <span
        aria-hidden
        className="mt-1.5 inline-block h-1.5 w-1.5 rounded-full"
        style={{ background: SEVERITY_COLOR[finding.severity] }}
        title={finding.severity}
      />
      <span className="mt-0.5 font-mono text-[9px] uppercase tracking-[0.18em] text-studio-ink-faint">
        {finding.axis}
      </span>
      <div className="min-w-0">
        <div className="font-display text-[13.5px] font-medium tracking-tight text-studio-ink">
          {finding.title}
        </div>
        <div className="mt-1 max-w-[680px] text-[11.5px] leading-snug text-studio-ink-faint">
          {finding.detail}
        </div>
        <div className="mt-1.5 max-w-[680px] text-[11.5px] leading-snug text-studio-ink">
          <span className="mr-1 font-mono text-[9px] uppercase tracking-[0.20em] text-studio-ink-faint">FIX</span>
          {finding.fix}
        </div>
        <NotesBlock notes={notes} />
      </div>
      <StatusPill status={status} onClick={onCycle} hydrated={hydrated} compact />
    </div>
  );
}
