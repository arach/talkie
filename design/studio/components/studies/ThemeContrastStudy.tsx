"use client";

/**
 * Where the theme contrast sweep stands.
 *
 * Two halves. The checkpoints are the commits that got us here, in order, so
 * it is obvious what to roll back to. The sweep is the evidence: every theme
 * in both modes on both surfaces, with the numbers measured off those exact
 * pixels rather than off the tokens that were declared.
 *
 * The distinction matters — a token tuned to land on 4.5:1 can arrive at the
 * glass well under it once gradients, sheens and alpha have had their turn.
 * Every failure this sweep found lived in that gap.
 */

import { useState } from "react";
import { cn } from "@/lib/utils";
import { ToggleBar } from "@/components/ToggleBar";

export const AA_SMALL_TEXT = 4.5;

export interface Row {
  region: string;
  values: Array<number | null>;
}

export interface ContrastData {
  themes: string[];
  views: Record<string, Record<string, Row[]>>;
}

export interface Checkpoint {
  hash: string;
  subject: string;
  note: string;
  /** Commits that moved a measured number, as opposed to setup or new palette. */
  measured?: boolean;
}

const VIEWS = ["deck", "home"] as const;
const MODES = ["light", "dark"] as const;

/** Warmer as the margin over the bar shrinks. Nothing here is failing, so
 *  this reads as headroom, not as an alarm. */
function marginTint(v: number | null): string {
  if (v === null) return "text-studio-ink-faint/45";
  if (v < AA_SMALL_TEXT) return "bg-[#B3261E] text-white";
  if (v < AA_SMALL_TEXT * 1.15) return "bg-[#F2E6C7] text-[#4A3B14]";
  if (v < AA_SMALL_TEXT * 1.6) return "bg-[#EAEFE7] text-[#33422F]";
  return "text-studio-ink-faint";
}

export function ThemeContrastStudy({
  data,
  checkpoints,
}: {
  data: ContrastData;
  checkpoints: Checkpoint[];
}) {
  const [view, setView] = useState<(typeof VIEWS)[number]>("deck");
  const [mode, setMode] = useState<(typeof MODES)[number]>("light");
  const [zoom, setZoom] = useState<string | null>(null);

  const rows = data.views[view][mode];
  const themes = data.themes;

  // The floor for each theme in this view+mode, and the region that set it —
  // derived, so the callouts can never drift from the table under them.
  const floors = themes.map((_, i) => {
    let worst: { region: string; value: number } | null = null;
    for (const r of rows) {
      const v = r.values[i];
      if (v === null) continue;
      if (!worst || v < worst.value) worst = { region: r.region, value: v };
    }
    return worst;
  });

  const all = rows.flatMap((r) => r.values).filter((v): v is number => v !== null);
  const globalFloor = Math.min(...all);
  const failing = all.filter((v) => v < AA_SMALL_TEXT).length;

  return (
    <>
      {/* ---- checkpoints ------------------------------------------------ */}
      <section className="mb-8">
        <h2 className="mb-1 font-display text-[17px] font-medium text-studio-ink">
          Checkpoints
        </h2>
        <p className="mb-3 max-w-[62ch] text-[12px] leading-relaxed text-studio-ink-faint">
          Newest first. Each is a standalone revert point — the palette work,
          the harness that drives theme and mode without a tap, and the two
          surfaces, in that order.
        </p>
        <ol className="m-0 list-none space-y-px p-0">
          {checkpoints.map((c) => (
            <li
              key={c.hash}
              className="flex items-baseline gap-3 border-b border-studio-edge py-2 last:border-0"
            >
              <code className="shrink-0 font-mono text-[10px] tracking-tight text-studio-ink-faint">
                {c.hash}
              </code>
              <span
                aria-hidden
                className={cn(
                  "mt-[5px] h-1.5 w-1.5 shrink-0 rounded-full",
                  c.measured ? "bg-[#B3261E]" : "bg-studio-edge"
                )}
              />
              <div className="min-w-0">
                <div className="text-[13px] leading-snug text-studio-ink">
                  {c.subject}
                </div>
                <div className="text-[11.5px] leading-relaxed text-studio-ink-faint">
                  {c.note}
                </div>
              </div>
            </li>
          ))}
        </ol>
        <p className="mt-2 text-[10px] uppercase tracking-ch text-studio-ink-faint">
          <span className="mr-1.5 inline-block h-1.5 w-1.5 rounded-full bg-[#B3261E] align-middle" />
          moved a measured number
        </p>
      </section>

      {/* ---- controls --------------------------------------------------- */}
      <ToggleBar
        label="Surface"
        toggles={VIEWS.map((v) => ({
          key: v,
          label: v === "deck" ? "Codex deck" : "Home",
          on: view === v,
          onClick: () => setView(v),
        }))}
      />
      <ToggleBar
        label="Mode"
        variant="light"
        toggles={MODES.map((m) => ({
          key: m,
          label: m,
          on: mode === m,
          onClick: () => setMode(m),
        }))}
      />

      {/* ---- the sweep -------------------------------------------------- */}
      <section className="mb-9 mt-5">
        <div className="mb-3 flex items-baseline gap-4">
          <h2 className="m-0 font-display text-[17px] font-medium text-studio-ink">
            {view === "deck" ? "Codex deck" : "Home"} · {mode}
          </h2>
          <span className="font-mono text-[10px] uppercase tracking-ch text-studio-ink-faint">
            {failing === 0
              ? `all clear · floor ${globalFloor.toFixed(2)}:1`
              : `${failing} under ${AA_SMALL_TEXT}:1`}
          </span>
        </div>
        <div className="grid grid-cols-[repeat(auto-fill,minmax(150px,1fr))] gap-3">
          {themes.map((t, i) => {
            const floor = floors[i];
            return (
              <button
                key={t}
                onClick={() => setZoom(`${t}-${mode}-${view}`)}
                className="group block text-left"
              >
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={`/studies/theme-contrast/${t}-${mode}-${view}.png`}
                  alt={`${t}, ${mode} mode, ${view}`}
                  className="w-full rounded-[6px] border border-studio-edge shadow-artifact transition-shadow group-hover:border-studio-ink"
                />
                <div className="mt-1.5 flex items-baseline justify-between gap-2">
                  <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.10em] text-studio-ink">
                    {t}
                  </span>
                  {floor ? (
                    <span
                      className={cn(
                        "rounded-[3px] px-1 font-mono text-[10px] tabular-nums",
                        marginTint(floor.value)
                      )}
                      title={`worst region: ${floor.region}`}
                    >
                      {floor.value.toFixed(2)}
                    </span>
                  ) : null}
                </div>
                {floor ? (
                  <div className="text-[9.5px] leading-tight text-studio-ink-faint">
                    floor · {floor.region}
                  </div>
                ) : null}
              </button>
            );
          })}
        </div>
      </section>

      {/* ---- measurements ----------------------------------------------- */}
      <section className="mb-6">
        <h2 className="mb-1 font-display text-[17px] font-medium text-studio-ink">
          Measured off the pixels
        </h2>
        <p className="mb-3 max-w-[68ch] text-[12px] leading-relaxed text-studio-ink-faint">
          Each cell is the WCAG ratio inside one sampled rect of the capture
          above — background taken as the rect&rsquo;s median luminance, ink as
          the 2% of pixels furthest from it. This is what reached the glass,
          not what the token declared.{" "}
          <code>n/a</code>{" "}is Carbon&rsquo;s
          icon-only deck, whose keys carry no caption to sample.
        </p>
        <div className="overflow-x-auto">
          <table className="w-full border-collapse text-[11px] tabular-nums">
            <thead>
              <tr>
                <th className="sticky left-0 z-10 border-b border-studio-edge bg-studio-canvas px-2 py-1.5 text-left font-mono text-[9px] font-semibold uppercase tracking-ch text-studio-ink-faint">
                  region
                </th>
                {themes.map((t) => (
                  <th
                    key={t}
                    className="border-b border-studio-edge px-2 py-1.5 text-right font-mono text-[9px] font-semibold uppercase tracking-[0.08em] text-studio-ink-faint"
                  >
                    {t.slice(0, 6)}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.region} className="border-b border-studio-edge/60">
                  <td className="sticky left-0 z-10 bg-studio-canvas px-2 py-1 font-mono text-[10px] text-studio-ink">
                    {r.region}
                  </td>
                  {r.values.map((v, i) => (
                    <td key={themes[i]} className="px-1 py-1 text-right">
                      <span
                        className={cn(
                          "inline-block rounded-[3px] px-1",
                          marginTint(v)
                        )}
                      >
                        {v === null ? "n/a" : v.toFixed(2)}
                      </span>
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      {/* ---- zoom ------------------------------------------------------- */}
      {zoom ? (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-8"
          onClick={() => setZoom(null)}
        >
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={`/studies/theme-contrast/${zoom}.png`}
            alt={zoom}
            className="max-h-full rounded-[10px] shadow-artifact"
          />
        </div>
      ) : null}
    </>
  );
}
