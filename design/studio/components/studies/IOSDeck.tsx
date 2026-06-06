"use client";

/**
 * IOSDeck — cleanup pass on DeckMirrorNext.swift, pushed toward a
 * Teenage-Engineering register.
 *
 * Design thesis (aspirational TE / Braun-Rams lineage):
 *   • FULL BLEED — the deck IS the app, not a gadget embedded in one.
 *     The chassis runs corner to corner; there is no framing canvas and
 *     no bounded plate. The bottom is a recessed key WELL that bleeds to
 *     the edges, with the keybed filling it edge to edge.
 *   • Flat matte keytops, raised in the recessed well. Physicality comes
 *     from precision — crisp chamfered edges + a thin recess gap — NOT
 *     from glossy domes, and never floating on a flat sheet.
 *   • Color is information. The accent appears only where something IS
 *     a state: the dictation key, the live pill, a fired key. Chassis
 *     stays monochrome.
 *   • Silkscreen discipline. Tiny all-caps mono legends + a per-key
 *     index (01–16) read as a designed system, not decoration.
 *
 * Named parts (mirrored in DeckMirrorNext.swift + the marginalia on the
 * route): Chassis · Masthead · Accent Chip · Device Row · Display ·
 * Control Strip · Silkscreen · Key Well · Keybed · Keytop · Recess Gap ·
 * Empty Well · Index · Active Key.
 *
 * Top-left keybed slot is the dictation slot. State-aware:
 *   • idle       → mic glyph, label "DICTATE"   (tap to start)
 *   • dictating  → enter glyph, label "FINISH"   (tap to commit)
 *     while dictating, the Display shows the live transcript.
 */

import { createContext, useContext, type CSSProperties, type ReactNode } from "react";

import { StatusBar } from "./primitives/StatusBar";

export type DeckState = "idle" | "dictating";

type Tile = { icon: keyof typeof TILE_ICONS; label: string };

// Toggle the per-key index legends (01–16). A TE signature; flip off
// here if it ever reads as noise rather than system.
const SHOW_INDEX = true;

// ── Treatments ──────────────────────────────────────────────────
// Material skins. LAYOUT + PROPORTIONS are frozen across all of them;
// a treatment only changes texture — the chassis metal, the key well,
// and how the keycaps catch light (gradient + lift + optional glassy
// sheen overlay). Swap them live in the studio to compare.
//
// The two the brief settled on (glass/polished/brushed kept dormant in
// the registry but no longer surfaced — easy to resurrect):
//   milled    matte aluminium, flat caps, recessed well — clean + honest
//   relief    satin caps with pronounced LIFT off a flat face (figure/ground)

export type TreatmentKey =
  | "milled"
  | "brushed"
  | "glass"
  | "polished"
  | "relief";

interface SheenSpec {
  height: string;
  gradient: string;
}

export interface Treatment {
  key: TreatmentKey;
  name: string;
  blurb: string;
  chassis: CSSProperties; // the full-bleed metal face (root background)
  well: CSSProperties; // the lower key-well container
  emptyWell: CSSProperties; // an unbound slot
  keytop: CSSProperties; // a resting keycap
  active: CSSProperties; // an armed / fired keycap
  sheen: SheenSpec | null; // glassy reflection overlay on each cap
}

const ACTIVE_GLOW = "0 0 16px -3px var(--theme-amber-glow)";

export const TREATMENTS: Record<TreatmentKey, Treatment> = {
  milled: {
    key: "milled",
    name: "Milled",
    blurb:
      "Baseline — matte aluminium carved from one block. Flat keytops, deep recessed well. The 'too carved / one texture' starting point.",
    chassis: {
      background:
        "repeating-linear-gradient(100deg, rgba(255,255,255,0.018) 0 1px, transparent 1px 3px), linear-gradient(180deg, rgba(255,255,255,0.05), rgba(255,255,255,0) 12%, rgba(0,0,0,0.05) 100%), var(--theme-canvas-alt)",
    },
    well: {
      background:
        "repeating-linear-gradient(100deg, rgba(255,255,255,0.018) 0 1px, transparent 1px 3px), color-mix(in srgb, var(--theme-canvas-alt) 88%, #000)",
      boxShadow: "inset 0 3px 8px -2px rgba(0,0,0,0.40)",
    },
    emptyWell: {
      background: "rgba(0,0,0,0.14)",
      boxShadow: "inset 0 1px 2px rgba(0,0,0,0.30)",
    },
    keytop: {
      background: "var(--theme-paper)",
      // Lift: tight contact + a soft ambient so the cap stands off its
      // pocket (was nearly flat). Still seats lower than Relief.
      boxShadow:
        "0 1px 2px rgba(0,0,0,0.24), 0 4px 9px -3px rgba(0,0,0,0.26), inset 0 1px 0 rgba(255,255,255,0.16), inset 0 -1px 0 rgba(0,0,0,0.12)",
    },
    active: {
      background:
        "color-mix(in srgb, var(--theme-amber) 16%, var(--theme-paper))",
      boxShadow: `0 0 0 1px var(--theme-amber), ${ACTIVE_GLOW}, inset 0 1px 0 rgba(255,255,255,0.12)`,
    },
    sheen: null,
  },

  brushed: {
    key: "brushed",
    name: "Brushed",
    blurb:
      "Anodised aluminium — fine vertical brushing on the chassis, satin keycaps floated on a soft shadow. Restrained, MacBook-deck.",
    chassis: {
      background:
        "repeating-linear-gradient(90deg, rgba(255,255,255,0.015) 0 2px, rgba(0,0,0,0.015) 2px 4px), linear-gradient(180deg, rgba(255,255,255,0.10), rgba(255,255,255,0.02) 10%, rgba(0,0,0,0.04) 60%, rgba(0,0,0,0.07)), var(--theme-canvas-alt)",
    },
    well: {
      background: "linear-gradient(180deg, rgba(0,0,0,0.02), rgba(0,0,0,0.05))",
      boxShadow: "inset 0 1px 0 rgba(255,255,255,0.06)",
    },
    emptyWell: {
      background: "rgba(0,0,0,0.06)",
      boxShadow: "inset 0 1px 2px rgba(0,0,0,0.18)",
    },
    keytop: {
      backgroundImage:
        "linear-gradient(180deg, color-mix(in srgb, var(--theme-paper) 80%, #fff), var(--theme-paper) 60%, color-mix(in srgb, var(--theme-paper) 92%, #000))",
      boxShadow:
        "0 1.5px 2px rgba(0,0,0,0.25), 0 4px 8px -3px rgba(0,0,0,0.22), inset 0 1px 0 rgba(255,255,255,0.45), inset 0 -1px 1px rgba(0,0,0,0.10)",
    },
    active: {
      backgroundImage:
        "linear-gradient(180deg, color-mix(in srgb, var(--theme-amber) 28%, var(--theme-paper)), color-mix(in srgb, var(--theme-amber) 18%, var(--theme-paper)) 60%, color-mix(in srgb, var(--theme-amber) 22%, #000))",
      boxShadow: `0 1.5px 2px rgba(0,0,0,0.25), 0 4px 8px -3px rgba(0,0,0,0.24), ${ACTIVE_GLOW}, 0 0 0 1px var(--theme-amber), inset 0 1px 0 rgba(255,255,255,0.40)`,
    },
    sheen: null,
  },

  glass: {
    key: "glass",
    name: "Glass",
    blurb:
      "Glass keycaps on a darker metal deck — bright top rim + a specular reflection in the upper half. Premium, glassy lift.",
    chassis: {
      background:
        "linear-gradient(180deg, rgba(255,255,255,0.06), rgba(0,0,0,0.06) 70%, rgba(0,0,0,0.10)), color-mix(in srgb, var(--theme-canvas-alt) 92%, #000)",
    },
    well: {
      background: "linear-gradient(180deg, rgba(0,0,0,0.04), rgba(0,0,0,0.08))",
      boxShadow:
        "inset 0 2px 5px -1px rgba(0,0,0,0.30), inset 0 1px 0 rgba(255,255,255,0.04)",
    },
    emptyWell: {
      background: "rgba(0,0,0,0.12)",
      boxShadow: "inset 0 1px 3px rgba(0,0,0,0.34)",
    },
    keytop: {
      backgroundImage:
        "linear-gradient(180deg, color-mix(in srgb, var(--theme-paper) 65%, #fff), var(--theme-paper) 48%, color-mix(in srgb, var(--theme-paper) 88%, #000))",
      boxShadow:
        "0 1px 1px rgba(0,0,0,0.28), 0 3px 8px -2px rgba(0,0,0,0.30), inset 0 1px 0 rgba(255,255,255,0.65), inset 0 -1px 1px rgba(0,0,0,0.14)",
    },
    active: {
      backgroundImage:
        "linear-gradient(180deg, color-mix(in srgb, var(--theme-amber) 34%, var(--theme-paper)), color-mix(in srgb, var(--theme-amber) 20%, var(--theme-paper)) 48%, color-mix(in srgb, var(--theme-amber) 26%, #000))",
      boxShadow: `0 1px 1px rgba(0,0,0,0.28), 0 3px 9px -2px rgba(0,0,0,0.32), ${ACTIVE_GLOW}, 0 0 0 1px var(--theme-amber), inset 0 1px 0 rgba(255,255,255,0.55)`,
    },
    sheen: {
      height: "46%",
      gradient:
        "linear-gradient(180deg, rgba(255,255,255,0.34), rgba(255,255,255,0.06) 55%, transparent)",
    },
  },

  polished: {
    key: "polished",
    name: "Polished",
    blurb:
      "High-gloss liquid metal — a hard shine line across the top half of every key, mirror-bright. The most dramatic, most reflective.",
    chassis: {
      background:
        "linear-gradient(180deg, rgba(255,255,255,0.14), rgba(255,255,255,0.02) 18%, rgba(0,0,0,0.05) 70%, rgba(0,0,0,0.10)), var(--theme-canvas-alt)",
    },
    well: {
      background: "linear-gradient(180deg, rgba(0,0,0,0.02), rgba(0,0,0,0.06))",
      boxShadow: "inset 0 1px 0 rgba(255,255,255,0.08)",
    },
    emptyWell: {
      background: "rgba(0,0,0,0.08)",
      boxShadow: "inset 0 1px 2px rgba(0,0,0,0.22)",
    },
    keytop: {
      backgroundImage:
        "linear-gradient(180deg, color-mix(in srgb, var(--theme-paper) 55%, #fff), color-mix(in srgb, var(--theme-paper) 80%, #fff) 48%, var(--theme-paper) 50%, color-mix(in srgb, var(--theme-paper) 85%, #000))",
      boxShadow:
        "0 1px 1px rgba(0,0,0,0.30), 0 4px 9px -3px rgba(0,0,0,0.30), inset 0 1px 0 rgba(255,255,255,0.70), inset 0 -2px 2px rgba(0,0,0,0.14)",
    },
    active: {
      backgroundImage:
        "linear-gradient(180deg, color-mix(in srgb, var(--theme-amber) 40%, #fff), color-mix(in srgb, var(--theme-amber) 30%, var(--theme-paper)) 48%, color-mix(in srgb, var(--theme-amber) 22%, var(--theme-paper)) 50%, color-mix(in srgb, var(--theme-amber) 28%, #000))",
      boxShadow: `0 1px 1px rgba(0,0,0,0.30), 0 4px 10px -3px rgba(0,0,0,0.32), ${ACTIVE_GLOW}, 0 0 0 1px var(--theme-amber), inset 0 1px 0 rgba(255,255,255,0.70)`,
    },
    sheen: {
      height: "50%",
      gradient:
        "linear-gradient(180deg, rgba(255,255,255,0.45), rgba(255,255,255,0.12) 46%, transparent 52%)",
    },
  },

  relief: {
    key: "relief",
    name: "Relief",
    blurb:
      "Lift-forward — satin keys, low gloss, but a pronounced drop shadow so the caps clearly stand off a flat metal face. Figure/ground.",
    chassis: {
      background:
        "repeating-linear-gradient(100deg, rgba(255,255,255,0.018) 0 1px, transparent 1px 3px), linear-gradient(180deg, rgba(255,255,255,0.04), rgba(0,0,0,0.03)), var(--theme-canvas-alt)",
    },
    well: {
      background: "transparent",
      boxShadow: "none",
    },
    emptyWell: {
      background: "transparent",
      boxShadow: "inset 0 0 0 1px rgba(0,0,0,0.10)",
    },
    keytop: {
      backgroundImage:
        "linear-gradient(180deg, color-mix(in srgb, var(--theme-paper) 86%, #fff), var(--theme-paper))",
      // Lift, harder: a deeper/farther ambient throw + brighter top edge so
      // the cap clearly floats off the flush face. Figure/ground.
      boxShadow:
        "0 2px 4px rgba(0,0,0,0.28), 0 9px 18px -4px rgba(0,0,0,0.34), inset 0 1px 0 rgba(255,255,255,0.45)",
    },
    active: {
      backgroundImage:
        "linear-gradient(180deg, color-mix(in srgb, var(--theme-amber) 26%, var(--theme-paper)), color-mix(in srgb, var(--theme-amber) 18%, var(--theme-paper)))",
      boxShadow: `0 2px 3px rgba(0,0,0,0.22), 0 6px 16px -4px rgba(0,0,0,0.30), ${ACTIVE_GLOW}, 0 0 0 1px var(--theme-amber), inset 0 1px 0 rgba(255,255,255,0.35)`,
    },
    sheen: null,
  },
};

// Only the two finalists are surfaced in the studio + the picker. The
// other three definitions stay in TREATMENTS, dormant.
const TREATMENT_ORDER: TreatmentKey[] = ["milled", "relief"];

export const TREATMENT_LIST: { key: TreatmentKey; name: string; blurb: string }[] =
  TREATMENT_ORDER.map((k) => ({
    key: k,
    name: TREATMENTS[k].name,
    blurb: TREATMENTS[k].blurb,
  }));

const TreatmentContext = createContext<Treatment>(TREATMENTS.relief);
const useTreatment = () => useContext(TreatmentContext);

// Slot 0 is the dictation slot — its icon + label morph by state.
// The remaining 15 slots are deck bindings (Mac/Safari sample here).
const TILES: (Tile | null)[] = [
  { icon: "mic", label: "Dictate" },
  { icon: "tab-x", label: "Close Tab" },
  { icon: "reload", label: "Reload" },
  null,
  { icon: "arrow-left", label: "Back" },
  { icon: "arrow-right", label: "Forward" },
  { icon: "find", label: "Find" },
  null,
  { icon: "bookmark", label: "Bookmark" },
  null,
  null,
  null,
  { icon: "window", label: "Window" },
  null,
  null,
  null,
];

const SAMPLE_TRANSCRIPT =
  "Open a new tab and search for the wireframe references Alex sent over yesterday afternoon — the ones about cockpit chassis depth.";

export function IOSDeck({
  state = "idle",
  treatment = "relief",
}: { state?: DeckState; treatment?: TreatmentKey } = {}) {
  const t = TREATMENTS[treatment] ?? TREATMENTS.relief;
  return (
    <TreatmentContext.Provider value={t}>
      {/* The chassis IS the screen — full bleed, no framing canvas, no
          bounded plate. The treatment supplies the metal (sheen/brush/
          gloss) so the entire app reads as one instrument face. */}
      <div className="flex h-full flex-col" style={t.chassis}>
        <StatusBar />
        <Masthead />

        {/* The PAD — a full-bleed instrument console. The trackpad IS the
            chassis here: the signals (device + status) float along the top,
            the command keys sit along the bottom, the drag readout /
            transcript lives in the center. Bleeds to the side edges;
            height is the one knob. */}
        <Pad state={state} />

        {/* Lower key well — a full-bleed field that runs to the bottom +
            side edges. The keybed fills it edge to edge. How deep the
            well reads (carved vs flat) and how the keys lift out of it is
            the treatment's job — proportions never change. */}
        <div
          className="mt-2 flex flex-1 flex-col gap-1.5 px-2.5 pb-2.5 pt-2.5"
          style={t.well}
        >
          <Silkscreen />
          <div className="min-h-0 flex-1">
            <Keybed state={state} />
          </div>
        </div>
      </div>
    </TreatmentContext.Provider>
  );
}

// ── Masthead ────────────────────────────────────────────────────
// A slim full-width title bar of the APP — accent chip + wordmark on a
// silkscreen hairline rule. No model-number gadget tell; the point is
// this reads as the app's own bar, not a label on an embedded device.
function Masthead() {
  return (
    <div className="flex items-center justify-between px-4 pb-2 pt-1">
      <div className="flex items-center gap-2">
        <span
          aria-hidden
          className="inline-block h-[7px] w-[7px]"
          style={{ background: "var(--theme-amber)" }}
        />
        <span
          className="text-[10px] tracking-[0.24em]"
          style={{
            color: "var(--theme-ink)",
            fontFamily: "var(--theme-font-mono)",
          }}
        >
          TALKIE
        </span>
        <span
          className="text-[10px] tracking-[0.24em]"
          style={{
            color: "var(--theme-ink-faint)",
            fontFamily: "var(--theme-font-mono)",
          }}
        >
          DECK
        </span>
      </div>
      <button
        className="grid h-6 w-6 place-items-center rounded-md"
        style={{
          background: "var(--theme-paper)",
          boxShadow:
            "0 1px 1.5px rgba(0,0,0,0.28), inset 0 1px 0 rgba(255,255,255,0.12)",
        }}
        aria-label="Close deck"
      >
        <CloseIcon />
      </button>
    </div>
  );
}

// ── Pad ─────────────────────────────────────────────────────────
// The instrument console — a full-bleed recessed glass band. The
// trackpad IS the chassis: signals (device + status) float along the
// top, the command keys sit along the bottom, the drag readout /
// transcript lives in the center. Bright-on-dark inks so everything
// reads on the glass. Height is the one knob (grows with the brief).
function Pad({ state }: { state: DeckState }) {
  return (
    <div
      className="relative mt-2 h-[180px] overflow-hidden"
      style={{
        background: "var(--theme-screen-bg)",
        boxShadow:
          "inset 0 2px 12px rgba(0,0,0,0.60), inset 0 1px 0 rgba(255,255,255,0.06)",
      }}
    >
      {/* tape grain — just a whisper of texture now, not a loud hatch */}
      <div
        className="absolute inset-0 opacity-[0.10]"
        style={{
          backgroundImage:
            "repeating-linear-gradient(135deg, transparent 0 13px, var(--theme-screen-trace) 13px 14px)",
        }}
        aria-hidden
      />
      {/* glass depth — a corner sheen + an edge vignette */}
      <div
        className="pointer-events-none absolute inset-0"
        style={{
          background:
            "linear-gradient(150deg, rgba(255,255,255,0.07), transparent 36%)",
        }}
        aria-hidden
      />
      <div
        className="pointer-events-none absolute inset-0"
        style={{
          background:
            "radial-gradient(120% 78% at 50% 42%, transparent 52%, rgba(0,0,0,0.45))",
        }}
        aria-hidden
      />

      {/* signals — float along the top of the pad */}
      <div className="absolute inset-x-0 top-0">
        <PadSignals state={state} />
      </div>

      {/* the readout — mag-tape transport, the centerpiece */}
      <PadCenter state={state} />

      {/* command keys — etched into the bottom of the glass */}
      <div className="absolute inset-x-0 bottom-0 px-2.5 pb-2.5">
        <ControlStrip />
      </div>
    </div>
  );
}

// Signals — device identity + connection status, floating on the glass.
function PadSignals({ state }: { state: DeckState }) {
  const status =
    state === "dictating"
      ? { label: "DICTATING", color: "var(--theme-amber)" }
      : { label: "LIVE", color: "#5CBD80" };
  // leading matches the Masthead (px-4) so MAC aligns under the title;
  // the status pill keeps the tighter trailing inset.
  return (
    <div className="flex items-center justify-between pl-4 pr-3 pt-2.5">
      <button
        className="flex items-center gap-1.5 text-[10px] tracking-[0.14em]"
        style={{
          fontFamily: "var(--theme-font-mono)",
          color: "rgba(255,255,255,0.55)",
        }}
        aria-label="Change computer or deck"
      >
        <ComputerIcon />
        <span style={{ color: "rgba(255,255,255,0.92)" }}>MAC MINI</span>
        <span style={{ color: "rgba(255,255,255,0.35)" }}>·</span>
        <span style={{ color: "rgba(255,255,255,0.55)" }}>MAC</span>
        <ChevronDownIcon />
      </button>

      <div
        className="flex items-center gap-1.5 rounded-full px-2 py-0.5"
        style={{
          background: `color-mix(in srgb, ${status.color} 18%, transparent)`,
          boxShadow: `inset 0 0 0 1px color-mix(in srgb, ${status.color} 45%, transparent)`,
        }}
      >
        <span
          className="inline-block h-1.5 w-1.5 rounded-full"
          style={{ background: status.color }}
          aria-hidden
        />
        <span
          className="text-[9px] tracking-[0.18em]"
          style={{ color: status.color, fontFamily: "var(--theme-font-mono)" }}
        >
          {status.label}
        </span>
      </div>
    </div>
  );
}

// Center readout — the mag-tape transport is the centerpiece: VU bars on
// an amber centerline with a tape-head playhead. A label rides above, the
// transcript (dictating) / last-result echo (idle) reads beneath — no
// card hiding the tape.
function PadCenter({ state }: { state: DeckState }) {
  const dictating = state === "dictating";
  return (
    <div className="absolute inset-0 flex flex-col items-center justify-center gap-2.5 px-6">
      <span
        className="text-[8px] tracking-[0.28em]"
        style={{
          color: dictating ? "var(--theme-amber)" : "rgba(255,255,255,0.34)",
          fontFamily: "var(--theme-font-mono)",
        }}
      >
        {dictating ? "TRANSCRIBING…" : "DRAG TO MOVE"}
      </span>

      <Waveform active={dictating} />

      {dictating ? (
        <span
          className="max-w-full text-center text-[10.5px] leading-snug"
          style={{
            color: "rgba(255,255,255,0.82)",
            fontFamily: "var(--theme-font-body)",
            display: "-webkit-box",
            WebkitLineClamp: 2,
            WebkitBoxOrient: "vertical",
            overflow: "hidden",
          }}
        >
          {SAMPLE_TRANSCRIPT}
        </span>
      ) : (
        <span
          className="text-[10px] tracking-[0.04em]"
          style={{
            color: "var(--theme-amber)",
            fontFamily: "var(--theme-font-mono)",
            opacity: 0.9,
          }}
        >
          ↳ "close tab" sent · 0:00:24
        </span>
      )}
    </div>
  );
}

// Magnetic-tape waveform — symmetric VU bars centered on an amber
// centerline, with a tape-head playhead at center. Heights are a fixed
// pattern (livelier when active). The brand's voice motif.
const WAVE_IDLE = [
  3, 4, 3, 5, 4, 3, 4, 3, 5, 4, 3, 4, 3, 4, 5, 3, 4, 3, 5, 4, 3, 4, 3, 5, 4, 3,
  4, 3,
];
const WAVE_ACTIVE = [
  5, 11, 7, 17, 10, 22, 13, 26, 15, 20, 9, 24, 14, 28, 12, 21, 8, 23, 13, 18, 10,
  25, 11, 16, 7, 19, 9, 6,
];

function Waveform({ active }: { active: boolean }) {
  const heights = active ? WAVE_ACTIVE : WAVE_IDLE;
  return (
    <div className="relative flex h-9 w-full items-center justify-between">
      {/* centerline */}
      <div
        className="pointer-events-none absolute inset-x-0 top-1/2 h-px -translate-y-1/2"
        style={{
          background: "var(--theme-amber)",
          opacity: active ? 0.55 : 0.4,
          boxShadow: "0 0 6px var(--theme-amber-glow)",
        }}
        aria-hidden
      />
      {/* symmetric VU bars */}
      {heights.map((h, i) => (
        <span
          key={i}
          className="w-[2px] rounded-full"
          style={{
            height: `${h}px`,
            background: "var(--theme-amber)",
            opacity: active ? 0.9 : 0.45,
          }}
        />
      ))}
      {/* tape-head playhead */}
      <div
        className="pointer-events-none absolute left-1/2 top-1/2 h-8 w-px -translate-x-1/2 -translate-y-1/2"
        style={{ background: "rgba(255,255,255,0.45)" }}
        aria-hidden
      />
      <div
        className="pointer-events-none absolute left-1/2 top-1/2 -translate-x-1/2"
        style={{
          marginTop: "-18px",
          width: 0,
          height: 0,
          borderLeft: "3px solid transparent",
          borderRight: "3px solid transparent",
          borderTop: "4px solid rgba(255,255,255,0.6)",
        }}
        aria-hidden
      />
    </div>
  );
}

// ── Silkscreen ──────────────────────────────────────────────────
// A printed legend line between the control strip and the keybed — the
// kind TE screens onto the chassis. Left names the module, right names
// what the bindings target (the bound app), so the keys read as a
// labelled, app-contextual macro field.
function Silkscreen() {
  return (
    <div className="flex items-baseline justify-between px-0.5">
      <span
        className="text-[7px] tracking-[0.26em]"
        style={{
          color: "var(--theme-ink-subtle)",
          fontFamily: "var(--theme-font-mono)",
        }}
      >
        KEYBED
      </span>
      <span
        className="text-[7px] tracking-[0.26em]"
        style={{
          color: "var(--theme-ink-subtle)",
          fontFamily: "var(--theme-font-mono)",
        }}
      >
        16 · SAFARI
      </span>
    </div>
  );
}

// Glassy reflection overlay — a treatment-supplied specular catch across
// the top of a keycap. Sits above the cap fill, below the glyph (the
// glyph wrapper is positioned, so it paints over this). Null treatments
// (matte/satin) render nothing.
function Sheen({ sheen }: { sheen: SheenSpec | null }) {
  if (!sheen) return null;
  return (
    <span
      aria-hidden
      className="pointer-events-none absolute inset-x-0 top-0 rounded-t-lg"
      style={{ height: sheen.height, background: sheen.gradient }}
    />
  );
}

// ── Control Strip ───────────────────────────────────────────────
// The command keys, etched into the bottom of the glass console. Unlike
// the keybed (which wears the Treatment), these are dark keys integrated
// INTO the screen — a translucent fill + a bright top edge + bright
// glyphs — so they read as part of the instrument, not chips floating on
// it. esc aligns left with the keybed's first column; ↵ aligns right.
const CONSOLE_KEY: CSSProperties = {
  background:
    "linear-gradient(180deg, rgba(255,255,255,0.11), rgba(255,255,255,0.035))",
  boxShadow:
    "inset 0 1px 0 rgba(255,255,255,0.14), inset 0 -1px 0 rgba(0,0,0,0.35), 0 1px 2px rgba(0,0,0,0.32)",
};

type Key =
  | { kind: "text"; label: string; a11y: string }
  | { kind: "cmd"; letter: string; a11y: string }
  | { kind: "icon"; icon: KeyIconName; a11y: string };

type KeyIconName =
  | "arrow-left"
  | "arrow-up"
  | "arrow-down"
  | "arrow-right"
  | "backspace"
  | "return";

function ControlStrip() {
  const groups: Key[][] = [
    [
      { kind: "text", label: "esc", a11y: "Escape" },
      { kind: "cmd", letter: "C", a11y: "Copy" },
      { kind: "cmd", letter: "V", a11y: "Paste" },
    ],
    [
      { kind: "icon", icon: "arrow-left", a11y: "Left" },
      { kind: "icon", icon: "arrow-up", a11y: "Up" },
      { kind: "icon", icon: "arrow-down", a11y: "Down" },
      { kind: "icon", icon: "arrow-right", a11y: "Right" },
    ],
    [
      { kind: "cmd", letter: "A", a11y: "Select all" },
      { kind: "icon", icon: "backspace", a11y: "Backspace" },
      { kind: "icon", icon: "return", a11y: "Enter" },
    ],
  ];
  return (
    <div className="flex items-stretch gap-3">
      {groups.map((group, gi) => (
        <div key={gi} className="flex flex-1 gap-1">
          {group.map((k, ki) => (
            <button
              key={ki}
              aria-label={k.a11y}
              className="grid flex-1 place-items-center rounded-md"
              style={{ ...CONSOLE_KEY, height: "26px" }}
            >
              <KeyGlyph k={k} />
            </button>
          ))}
        </div>
      ))}
    </div>
  );
}

function KeyGlyph({ k }: { k: Key }) {
  if (k.kind === "text") {
    return (
      <span
        className="text-[9px] uppercase leading-none tracking-[0.08em]"
        style={{
          color: "rgba(255,255,255,0.72)",
          fontFamily: "var(--theme-font-mono)",
        }}
      >
        {k.label}
      </span>
    );
  }
  if (k.kind === "cmd") {
    return (
      <span className="flex items-baseline gap-[1px] leading-none">
        <span
          className="text-[10px]"
          style={{ color: "rgba(255,255,255,0.50)" }}
        >
          ⌘
        </span>
        <span
          className="text-[10px]"
          style={{ color: "rgba(255,255,255,0.78)" }}
        >
          {k.letter}
        </span>
      </span>
    );
  }
  return <KeyIcon name={k.icon} />;
}

function KeyIcon({ name }: { name: KeyIconName }) {
  const stroke = "rgba(255,255,255,0.72)";
  const sw = 1.6;
  switch (name) {
    case "arrow-left":
      return (
        <svg viewBox="0 0 14 14" className="h-3 w-3" fill="none" aria-hidden>
          <path d="M9 3L4 7L9 11M4 7H12" stroke={stroke} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      );
    case "arrow-up":
      return (
        <svg viewBox="0 0 14 14" className="h-3 w-3" fill="none" aria-hidden>
          <path d="M3 6L7 2L11 6M7 2V12" stroke={stroke} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      );
    case "arrow-down":
      return (
        <svg viewBox="0 0 14 14" className="h-3 w-3" fill="none" aria-hidden>
          <path d="M3 8L7 12L11 8M7 12V2" stroke={stroke} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      );
    case "arrow-right":
      return (
        <svg viewBox="0 0 14 14" className="h-3 w-3" fill="none" aria-hidden>
          <path d="M5 3L10 7L5 11M2 7H10" stroke={stroke} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      );
    case "backspace":
      return (
        <svg viewBox="0 0 16 14" className="h-3 w-3.5" fill="none" aria-hidden>
          <path
            d="M5 2L1 7L5 12H14C14.5 12 15 11.5 15 11V3C15 2.5 14.5 2 14 2H5Z"
            stroke={stroke}
            strokeWidth={sw}
            strokeLinecap="round"
            strokeLinejoin="round"
          />
          <path d="M7.5 5L11 9M11 5L7.5 9" stroke={stroke} strokeWidth={sw} strokeLinecap="round" />
        </svg>
      );
    case "return":
      return (
        <svg viewBox="0 0 14 14" className="h-3 w-3" fill="none" aria-hidden>
          <path
            d="M11 3V7C11 7.55 10.55 8 10 8H3M3 8L6 5M3 8L6 11"
            stroke={stroke}
            strokeWidth={sw}
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        </svg>
      );
  }
}

// ── Keybed ──────────────────────────────────────────────────────
// The 16-key macro field. No pocket of its own — it fills the full-bleed
// key WELL (its parent provides the recess + groove), so the grid runs
// edge to edge to the bottom of the screen. Keys are raised in the well;
// the gaps show the recessed floor, so they read as seated, not floating.
function Keybed({ state }: { state: DeckState }) {
  return (
    <div className="grid h-full grid-cols-4 grid-rows-4 gap-2">
      {TILES.map((tile, idx) =>
        idx === 0 ? (
          <DictationKey key={idx} state={state} index={idx} />
        ) : (
          <KeyCell key={idx} tile={tile} firing={false} index={idx} />
        )
      )}
    </div>
  );
}

// Top-left key is state-aware. Idle = "DICTATE" mic (with the one always-
// on accent dot — its functional color marks it as the live key).
// Dictating = "FINISH" enter. Same physical position starts AND commits.
function DictationKey({ state, index }: { state: DeckState; index: number }) {
  const t = useTreatment();
  const dictating = state === "dictating";
  return (
    <button
      className="relative flex min-h-[60px] flex-col items-center justify-center rounded-lg px-1"
      style={{
        ...(dictating ? t.active : t.keytop),
        transform: dictating ? "translateY(-0.5px)" : "none",
        transition: "transform 160ms ease, box-shadow 160ms ease",
      }}
      aria-label={dictating ? "Finish dictation" : "Start dictation"}
    >
      <Sheen sheen={t.sheen} />
      <Index n={index} />
      {!dictating && (
        <span
          aria-hidden
          className="absolute right-1.5 top-1.5 h-1 w-1 rounded-full"
          style={{ background: "var(--theme-amber)" }}
        />
      )}
      <span className="relative flex flex-col items-center gap-1.5">
        <span
          style={{ color: dictating ? "var(--theme-amber)" : "var(--theme-ink)" }}
        >
          {dictating ? TILE_ICONS["enter"] : TILE_ICONS["mic"]}
        </span>
        <Legend active={dictating}>{dictating ? "Finish" : "Dictate"}</Legend>
      </span>
    </button>
  );
}

function KeyCell({
  tile,
  firing,
  index,
}: {
  tile: Tile | null;
  firing: boolean;
  index: number;
}) {
  const t = useTreatment();
  if (!tile) {
    return (
      <div
        className="grid min-h-[60px] place-items-center rounded-lg"
        style={{ ...t.emptyWell, color: "var(--theme-ink-faint)" }}
      >
        <PlusIcon />
      </div>
    );
  }
  return (
    <button
      className="relative flex min-h-[60px] flex-col items-center justify-center rounded-lg px-1"
      style={{
        ...(firing ? t.active : t.keytop),
        transform: firing ? "translateY(-0.5px)" : "none",
        transition: "transform 160ms ease, box-shadow 160ms ease",
      }}
    >
      <Sheen sheen={t.sheen} />
      <Index n={index} />
      <span className="relative flex flex-col items-center gap-1.5">
        <span
          style={{ color: firing ? "var(--theme-amber)" : "var(--theme-ink-dim)" }}
        >
          {TILE_ICONS[tile.icon]}
        </span>
        <Legend active={firing}>{tile.label}</Legend>
      </span>
    </button>
  );
}

// Tiny corner index — the TE step/pad number. Low-contrast, consistent
// corner; reads as a numbered system, not clutter.
function Index({ n }: { n: number }) {
  if (!SHOW_INDEX) return null;
  return (
    <span
      aria-hidden
      className="absolute left-1.5 top-1.5 text-[6px] leading-none tracking-[0.04em]"
      style={{
        color: "var(--theme-ink-subtle)",
        fontFamily: "var(--theme-font-mono)",
      }}
    >
      {String(n + 1).padStart(2, "0")}
    </span>
  );
}

// Keytop legend — small all-caps mono, the TE silkscreen register.
function Legend({
  active,
  children,
}: {
  active?: boolean;
  children: ReactNode;
}) {
  return (
    <span
      className="text-[8px] uppercase leading-none tracking-[0.12em]"
      style={{
        color: active ? "var(--theme-amber)" : "var(--theme-ink-muted)",
        fontFamily: "var(--theme-font-mono)",
        whiteSpace: "nowrap",
      }}
    >
      {children}
    </span>
  );
}

// ── Icons ───────────────────────────────────────────────────────

function CloseIcon() {
  return (
    <svg viewBox="0 0 12 12" className="h-3 w-3" fill="none">
      <path
        d="M2 2L10 10M10 2L2 10"
        stroke="var(--theme-ink-muted)"
        strokeWidth="1.4"
        strokeLinecap="round"
      />
    </svg>
  );
}

function ComputerIcon() {
  return (
    <svg viewBox="0 0 12 12" className="h-3 w-3" fill="none" aria-hidden>
      <rect
        x="1.5"
        y="2"
        width="9"
        height="6"
        rx="0.8"
        stroke="currentColor"
        strokeWidth="1"
      />
      <path d="M4 10H8" stroke="currentColor" strokeWidth="1" strokeLinecap="round" />
    </svg>
  );
}

function ChevronDownIcon() {
  return (
    <svg viewBox="0 0 10 10" className="h-2 w-2" fill="none" aria-hidden>
      <path
        d="M2 4L5 7L8 4"
        stroke="currentColor"
        strokeWidth="1.3"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function PlusIcon() {
  return (
    <svg viewBox="0 0 12 12" className="h-3 w-3" fill="none">
      <path
        d="M6 2V10M2 6H10"
        stroke="currentColor"
        strokeWidth="1.2"
        strokeLinecap="round"
      />
    </svg>
  );
}

const TILE_ICONS = {
  mic: (
    <svg viewBox="0 0 20 20" className="h-[18px] w-[18px]" fill="none">
      <rect
        x="7.5"
        y="3"
        width="5"
        height="9"
        rx="2.5"
        stroke="currentColor"
        strokeWidth="1.4"
      />
      <path
        d="M5 10A5 5 0 0 0 15 10M10 15V17M7 17H13"
        stroke="currentColor"
        strokeWidth="1.4"
        strokeLinecap="round"
      />
    </svg>
  ),
  enter: (
    <svg viewBox="0 0 20 20" className="h-[18px] w-[18px]" fill="none">
      <path
        d="M16 5V10A2 2 0 0 1 14 12H5M5 12L9 8M5 12L9 16"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  ),
  "tab-plus": (
    <svg viewBox="0 0 20 20" className="h-[18px] w-[18px]" fill="none">
      <rect x="3" y="6" width="14" height="10" rx="1.5" stroke="currentColor" strokeWidth="1.3" />
      <path d="M10 9V13M8 11H12" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" />
    </svg>
  ),
  "tab-x": (
    <svg viewBox="0 0 20 20" className="h-[18px] w-[18px]" fill="none">
      <rect x="3" y="6" width="14" height="10" rx="1.5" stroke="currentColor" strokeWidth="1.3" />
      <path d="M8 9L12 13M12 9L8 13" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" />
    </svg>
  ),
  reload: (
    <svg viewBox="0 0 20 20" className="h-[18px] w-[18px]" fill="none">
      <path
        d="M16 10A6 6 0 1 1 13.5 5.5M16 4V7H13"
        stroke="currentColor"
        strokeWidth="1.3"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  ),
  "arrow-left": (
    <svg viewBox="0 0 20 20" className="h-[18px] w-[18px]" fill="none">
      <path
        d="M13 4L7 10L13 16"
        stroke="currentColor"
        strokeWidth="1.4"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  ),
  "arrow-right": (
    <svg viewBox="0 0 20 20" className="h-[18px] w-[18px]" fill="none">
      <path
        d="M7 4L13 10L7 16"
        stroke="currentColor"
        strokeWidth="1.4"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  ),
  find: (
    <svg viewBox="0 0 20 20" className="h-[18px] w-[18px]" fill="none">
      <circle cx="9" cy="9" r="4.5" stroke="currentColor" strokeWidth="1.3" />
      <path
        d="M12.5 12.5L15.5 15.5"
        stroke="currentColor"
        strokeWidth="1.4"
        strokeLinecap="round"
      />
    </svg>
  ),
  bookmark: (
    <svg viewBox="0 0 20 20" className="h-[18px] w-[18px]" fill="none">
      <path
        d="M6 3H14V17L10 14L6 17V3Z"
        stroke="currentColor"
        strokeWidth="1.3"
        strokeLinejoin="round"
      />
    </svg>
  ),
  window: (
    <svg viewBox="0 0 20 20" className="h-[18px] w-[18px]" fill="none">
      <rect x="3" y="4" width="14" height="12" rx="1.5" stroke="currentColor" strokeWidth="1.3" />
      <path d="M3 8H17" stroke="currentColor" strokeWidth="1.3" />
    </svg>
  ),
} as const;
