"use client";

/**
 * Mac Capture HUD — scheme-grid study, anchored on the PEARL · SLATE ·
 * AMBER trio.
 *
 * The shipping HUD (CaptureHUDPanel.swift) ships one tone — a near-black
 * glass panel with white text. On a light desktop wallpaper it lands hard.
 * This study locks in three siblings that, between them, hold across every
 * wallpaper class:
 *
 *   PEARL  — the lightest cool surface. For light desktops where the HUD
 *            should feel like frosted instrument glass, not a black slab.
 *   SLATE  — mid-tone dark cool gray. The all-purpose middle pick. Reads
 *            cleanly over busy / mid-tone wallpapers.
 *   AMBER  — dark with warm amber accent. For dark desktops where the
 *            HUD should announce itself as a piece of hardware.
 *
 * The trio is one ladder, not three modes — pick by wallpaper luminance
 * (or expose as a Setting later).
 */

import { useState } from "react";
import { StudioPage } from "@/components/StudioPage";
import { SchemeCard } from "@/components/SchemeCard";
import { ToggleBar, type Toggle } from "@/components/ToggleBar";
import { MacCaptureHUD, type CaptureHUDMode } from "@/components/studies/MacCaptureHUD";
import { MacCaptureFreeze } from "@/components/studies/MacCaptureFreeze";
import { SCHEMES } from "@/lib/schemes";

const TRIO = ["pearl", "slate", "amber"] as const;
type TrioKey = (typeof TRIO)[number];

const TRIO_PAIRING: Record<
  TrioKey,
  { wall: WallKey; tagline: string }
> = {
  pearl: { wall: "light", tagline: "for light desktops · frosted instrument glass" },
  slate: { wall: "busy",  tagline: "for busy mid-tone wallpapers · all-purpose" },
  amber: { wall: "dark",  tagline: "for dark desktops · warm metal on black" },
};

// ─────────────────────────────────────────────────────────────────────
// Desktop wallpaper swatches — synthetic tiles that stand in for a real
// macOS wallpaper. Strongest reads: a light cool gradient (typical macOS
// Sonoma default), a dark photo (mountains/night), and a busy mid-tone
// (the worst case — neither dark nor light to lean on).

const WALLPAPERS = {
  light:
    "linear-gradient(135deg, #E8EAF0 0%, #D6DBE5 45%, #C6CBD7 100%)",
  dark:
    "radial-gradient(circle at 30% 20%, #2A3441 0%, #181E27 55%, #0C1117 100%)",
  busy:
    "linear-gradient(120deg, #6B5A4E 0%, #8E7F6F 30%, #C9A87E 55%, #5A6E7E 80%, #2E3A48 100%)",
} as const;

type WallKey = keyof typeof WALLPAPERS;

const WALL_LABEL: Record<WallKey, string> = {
  light: "Light desktop",
  dark: "Dark desktop",
  busy: "Busy mid-tone",
};

// ─────────────────────────────────────────────────────────────────────

export default function MacCaptureHUDStudy() {
  const [mode, setMode] = useState<CaptureHUDMode>("screenshot");

  const modeToggles: Toggle[] = [
    {
      key: "screenshot",
      label: "Screenshot",
      on: mode === "screenshot",
      onClick: () => setMode("screenshot"),
    },
    {
      key: "video",
      label: "Video · Record",
      on: mode === "video",
      onClick: () => setMode("video"),
    },
  ];

  return (
    <StudioPage
      eyebrow="· Capture HUD · floating chord menu · Hyper+S / Hyper+R"
      title="PEARL · SLATE · AMBER — the trio"
      help="three siblings, one ladder · pick by wallpaper luminance"
    >
      <ToggleBar label="· Mode" toggles={modeToggles} variant="dark" className="mb-5" />

      {/* ── 00a · NEW · Mode picker + tab toggle ───────────────────── */}
      <section className="mb-12">
        <SectionEyebrow
          label="00a · NEW · Mode picker + tab toggle"
          help="REGION preselected · A/S/D switch · ↵ commits · top tabs swap Screenshot ↔ Video in place"
        />
        <div className="grid grid-cols-3 gap-6">
          <Tile label="Region preselected · click tabs to switch" wallpaper="busy">
            <SchemeWrap schemeKey="slate">
              <MacCaptureHUD mode={mode} activeChord="A" onModeChange={setMode} />
            </SchemeWrap>
          </Tile>
          <Tile label="Switched to Screen (S pressed)" wallpaper="busy">
            <SchemeWrap schemeKey="slate">
              <MacCaptureHUD mode={mode} activeChord="S" onModeChange={setMode} />
            </SchemeWrap>
          </Tile>
          <Tile label="Switched to Window (D pressed)" wallpaper="busy">
            <SchemeWrap schemeKey="slate">
              <MacCaptureHUD mode={mode} activeChord="D" onModeChange={setMode} />
            </SchemeWrap>
          </Tile>
        </div>
      </section>

      {/* ── 00b · NEW · Freeze overlay ──────────────────────────────── */}
      <section className="mb-12">
        <SectionEyebrow
          label="00b · NEW · Freeze overlay"
          help="desktop snapshots at overlay-mount · user crops the frozen image · today drag runs against the live desktop"
        />
        <div className="grid grid-cols-2 gap-6">
          <div className="flex flex-col gap-2">
            <div className="font-mono text-[9px] uppercase tracking-[0.18em] text-studio-ink-faint">
              · Armed · before crop · frozen-snapshot semantic visible
            </div>
            <MacCaptureFreeze state="armed-ready" />
          </div>
          <div className="flex flex-col gap-2">
            <div className="font-mono text-[9px] uppercase tracking-[0.18em] text-studio-ink-faint">
              · Drag in progress · 460 × 260 crop · ↵ commits
            </div>
            <MacCaptureFreeze state="drag-in-progress" />
          </div>
        </div>
      </section>

      {/* ── 1. The trio ────────────────────────────────────────────── */}
      <section className="mb-12">
        <SectionEyebrow
          label="01 · The trio"
          help="each on its native wallpaper class · this is the canonical lineup"
        />
        <div className="grid grid-cols-3 gap-6">
          {TRIO.map((key) => {
            const pairing = TRIO_PAIRING[key];
            const scheme = SCHEMES.find((s) => s.key === key)!;
            return (
              <Tile
                key={key}
                label={`${scheme.name} · ${pairing.tagline}`}
                wallpaper={pairing.wall}
              >
                <SchemeWrap schemeKey={key}>
                  <MacCaptureHUD mode={mode} />
                </SchemeWrap>
              </Tile>
            );
          })}
        </div>
      </section>

      {/* ── 2. Cross-wallpaper holdup ──────────────────────────────── */}
      <section className="mb-12">
        <SectionEyebrow
          label="02 · Cross-wallpaper holdup"
          help="trio × 3 wallpapers · which siblings can swap, which can't"
        />
        <div className="grid grid-cols-3 gap-3">
          {/* Header row — wallpaper labels */}
          <div />
          {(Object.keys(WALLPAPERS) as WallKey[]).map((wall) => (
            <div
              key={`hdr-${wall}`}
              className="font-mono text-[9px] uppercase tracking-[0.22em] text-studio-ink-faint"
            >
              · {WALL_LABEL[wall]}
            </div>
          ))}

          {/* Per-scheme row */}
          {TRIO.map((schemeKey) => {
            const scheme = SCHEMES.find((s) => s.key === schemeKey)!;
            return (
              <RowGroup key={schemeKey}>
                <div className="flex items-center font-mono text-[10px] font-semibold uppercase tracking-[0.20em] text-studio-ink">
                  <span
                    aria-hidden
                    className="mr-2 inline-block h-[8px] w-[8px] rounded-full"
                    style={{ background: scheme.swatch }}
                  />
                  {scheme.name}
                </div>
                {(Object.keys(WALLPAPERS) as WallKey[]).map((wall) => (
                  <Tile key={`${schemeKey}-${wall}`} wallpaper={wall} compact>
                    <SchemeWrap schemeKey={schemeKey}>
                      <MacCaptureHUD mode={mode} />
                    </SchemeWrap>
                  </Tile>
                ))}
              </RowGroup>
            );
          })}
        </div>
      </section>

      {/* ── 3. Vs. legacy ──────────────────────────────────────────── */}
      <section className="mb-12">
        <SectionEyebrow
          label="03 · Vs. legacy"
          help="the dark slab we ship today · A/B against the trio"
        />
        <div className="grid grid-cols-3 gap-6">
          <Tile label="Legacy · over light desktop" wallpaper="light">
            <LegacyHUD mode={mode} />
          </Tile>
          <Tile label="Legacy · over busy mid-tone" wallpaper="busy">
            <LegacyHUD mode={mode} />
          </Tile>
          <Tile label="Legacy · over dark desktop" wallpaper="dark">
            <LegacyHUD mode={mode} />
          </Tile>
        </div>
      </section>

      {/* ── 4. Trio detail — pure scheme cards ─────────────────────── */}
      <section>
        <SectionEyebrow
          label="04 · Trio detail"
          help="each scheme on its own bg · the chrome reads clean even without a wallpaper"
        />
        <div className="grid grid-cols-3 gap-6">
          {TRIO.map((key) => {
            const scheme = SCHEMES.find((s) => s.key === key)!;
            return (
              <SchemeCard key={key} scheme={scheme}>
                <div
                  className="flex items-center justify-center rounded-md p-7"
                  style={{ background: "var(--scheme-bg)" }}
                >
                  <MacCaptureHUD mode={mode} />
                </div>
              </SchemeCard>
            );
          })}
        </div>
      </section>
    </StudioPage>
  );
}

// ─────────────────────────────────────────────────────────────────────
// Layout helpers.

function RowGroup({ children }: { children: React.ReactNode }) {
  // 4-column row: 1 label cell + 3 wallpaper tiles. Spans the grid.
  return <div className="contents">{children}</div>;
}

// ─────────────────────────────────────────────────────────────────────
// Section eyebrow.

function SectionEyebrow({ label, help }: { label: string; help: string }) {
  return (
    <div className="mb-3 flex items-baseline justify-between border-b border-studio-edge pb-2">
      <div className="font-mono text-[9px] font-semibold uppercase tracking-[0.22em] text-studio-ink">
        {label}
      </div>
      <div className="font-mono text-[9px] uppercase tracking-[0.12em] text-studio-ink-faint">
        {help}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────
// Desktop tile — fakes a piece of macOS wallpaper with the HUD anchored
// top-center, mimicking where the real panel lands.

function Tile({
  label,
  wallpaper,
  children,
  compact = false,
}: {
  label?: string;
  wallpaper: WallKey;
  children: React.ReactNode;
  compact?: boolean;
}) {
  const height = compact ? 220 : 280;
  return (
    <div className="flex flex-col gap-2">
      {label ? (
        <div className="font-mono text-[9px] uppercase tracking-[0.18em] text-studio-ink-faint">
          · {label}
        </div>
      ) : null}
      <div
        className="relative overflow-hidden rounded-md"
        style={{
          height,
          background: WALLPAPERS[wallpaper],
          border: "0.5px solid #DEDEDD",
          boxShadow: "0 6px 22px rgba(46,68,82,0.08)",
        }}
      >
        {/* Mac menu bar stripe — selling the "this is a desktop" framing */}
        <div
          className="flex items-center px-3"
          style={{
            height: 22,
            background:
              wallpaper === "dark"
                ? "rgba(20,24,28,0.55)"
                : "rgba(255,255,255,0.55)",
            backdropFilter: "blur(20px) saturate(1.4)",
            WebkitBackdropFilter: "blur(20px) saturate(1.4)",
            borderBottom:
              wallpaper === "dark"
                ? "0.5px solid rgba(255,255,255,0.10)"
                : "0.5px solid rgba(0,0,0,0.06)",
          }}
        >
          <span
            className="text-[9px]"
            style={{
              color: wallpaper === "dark" ? "#E8EAEC" : "#1F2226",
            }}
          >
            Talkie
          </span>
          <div className="ml-auto flex items-center gap-2.5">
            {["File", "Edit", "View", "Window", "Help"].map((m) => (
              <span
                key={m}
                className="text-[9px]"
                style={{
                  color:
                    wallpaper === "dark"
                      ? "rgba(232,234,236,0.78)"
                      : "rgba(31,34,38,0.72)",
                }}
              >
                {m}
              </span>
            ))}
          </div>
        </div>

        {/* HUD slot — anchored top-center, 18pt below the menu bar */}
        <div
          className="absolute left-1/2"
          style={{ top: 22 + 18, transform: "translateX(-50%)" }}
        >
          {children}
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────
// SchemeWrap — applies one scheme's CSS vars to a slot. Lets us use the
// HUD outside SchemeCard (e.g., on a wallpaper tile).

function SchemeWrap({
  schemeKey,
  children,
}: {
  schemeKey: string;
  children: React.ReactNode;
}) {
  const scheme = SCHEMES.find((s) => s.key === schemeKey);
  if (!scheme) return <>{children}</>;
  return <div style={scheme.vars as React.CSSProperties}>{children}</div>;
}

// ─────────────────────────────────────────────────────────────────────
// LegacyHUD — pixel-faithful (enough) reproduction of the shipping
// CaptureHUDPanel.swift so we have an honest A/B against the proposal.

function LegacyHUD({ mode }: { mode: CaptureHUDMode }) {
  const isVideo = mode === "video";
  const base = isVideo
    ? "rgb(28, 12, 14)" /* warm-tinted near-black for video */
    : "rgb(14, 15, 19)" /* cool-tinted near-black for screenshot */;

  return (
    <div
      className="font-sans"
      style={{
        width: 280,
        borderRadius: 14,
        background: base,
        border: `0.5px solid ${
          isVideo ? "rgba(255,80,80,0.30)" : "rgba(255,255,255,0.15)"
        }`,
        boxShadow: "0 18px 38px rgba(0,0,0,0.45)",
        overflow: "hidden",
      }}
    >
      <div className="flex items-center px-2.5 pt-2.5 pb-1.5" style={{ gap: 4 }}>
        <span
          className="inline-block h-[5px] w-[5px] rounded-full"
          style={{
            background: isVideo ? "#FF4040" : "rgba(255,255,255,0.5)",
          }}
        />
        <span
          className="text-[9px] font-semibold"
          style={{
            color: isVideo ? "rgba(255,64,64,0.8)" : "rgba(255,255,255,0.5)",
          }}
        >
          {isVideo ? "Video" : "Screenshot"}
        </span>
      </div>

      <div
        style={{
          height: 0.5,
          background: "rgba(255,255,255,0.08)",
          margin: "0 10px",
        }}
      />

      <div className="flex px-2.5 py-2" style={{ gap: 8 }}>
        {[
          { k: "A", l: "Region" },
          { k: "S", l: "Screen" },
          { k: "D", l: "Window" },
        ].map((c) => (
          <div
            key={c.k}
            className="flex flex-1 flex-col items-center"
            style={{ padding: "6px 0" }}
          >
            <div
              style={{
                width: 14,
                height: 14,
                borderRadius: 2,
                background: "rgba(255,255,255,0.18)",
                marginBottom: 4,
              }}
            />
            <div className="flex items-center" style={{ gap: 3 }}>
              <span
                className="flex items-center justify-center text-[10px] font-bold"
                style={{
                  width: 16,
                  height: 16,
                  borderRadius: 3,
                  background: "rgba(255,255,255,0.1)",
                  border: "0.5px solid rgba(255,255,255,0.15)",
                  color: "rgba(255,255,255,0.95)",
                }}
              >
                {c.k}
              </span>
              <span
                className="text-[10px] font-medium"
                style={{ color: "rgba(255,255,255,0.5)" }}
              >
                {c.l}
              </span>
            </div>
          </div>
        ))}
      </div>

      <div
        style={{
          height: 0.5,
          background: "rgba(255,255,255,0.08)",
          margin: "0 10px",
        }}
      />

      <div
        className="flex px-2.5 pt-1.5 pb-2.5"
        style={{ gap: 8, alignItems: "center" }}
      >
        {[
          { k: "⇥", l: "Mode", c: "#FFFFFF" },
          { k: "C", l: "Camera", c: "#FFA500" },
          { k: "N", l: "Save", c: "#7BE0BC" },
          { k: "F", l: "Paste", c: "#7BE07B" },
          { k: "W", l: "Tray", c: "#7BD7E0" },
        ].map((c) => (
          <div key={c.k} className="flex flex-1 items-center" style={{ gap: 4 }}>
            <span
              className="flex items-center justify-center text-[10px] font-bold"
              style={{
                padding: "2px 4px",
                borderRadius: 3,
                border: `0.5px solid ${c.c}55`,
                color: c.c,
              }}
            >
              {c.k}
            </span>
            <span
              className="text-[10px]"
              style={{ color: `${c.c}99` }}
            >
              {c.l}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
