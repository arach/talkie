"use client";

/**
 * DeckPlayground — the studio harness for the deck's MATERIAL treatments.
 *
 * Layout + proportions of IOSDeck are frozen; this lets you swap the
 * texture (chassis metal · key well · keycap lift/gloss/sheen) live and
 * compare. Two views:
 *   1. Playground — pick a treatment + state, see it across a light /
 *      white / dark / neutral theme spread at once.
 *   2. Board — all treatments side by side in one theme, at a glance.
 */

import { useState } from "react";
import { PhoneFrame } from "./PhoneFrame";
import {
  IOSDeck,
  TREATMENT_LIST,
  type TreatmentKey,
  type DeckState,
} from "./IOSDeck";
import { IOS_THEMES } from "@/lib/themes";

// A spread that stresses metal/glass differently: cream, pure white,
// blue-dark, neutral-dark.
const PLAYGROUND_THEME_KEYS = ["scope", "lift", "midnight", "graphite"];
const BOARD_THEME_KEY = "scope";

function themesByKey(keys: string[]) {
  return keys
    .map((k) => IOS_THEMES.find((t) => t.key === k))
    .filter((t): t is (typeof IOS_THEMES)[number] => Boolean(t));
}

export function DeckTreatmentsStudio() {
  return (
    <div className="flex flex-col gap-12">
      <Playground />
      <Board />
    </div>
  );
}

function Playground() {
  const [treatment, setTreatment] = useState<TreatmentKey>("relief");
  const [state, setState] = useState<DeckState>("idle");
  const themes = themesByKey(PLAYGROUND_THEME_KEYS);
  const active = TREATMENT_LIST.find((t) => t.key === treatment);

  return (
    <div className="flex flex-col gap-5">
      <SectionHeading
        label="Playground"
        hint="pick a treatment + state — see it across cream / white / dark / neutral"
      />

      <div className="flex flex-wrap items-center gap-3">
        <Segmented
          options={TREATMENT_LIST.map((t) => ({ value: t.key, label: t.name }))}
          value={treatment}
          onChange={(v) => setTreatment(v as TreatmentKey)}
        />
        <Segmented
          options={[
            { value: "idle", label: "Idle" },
            { value: "dictating", label: "Dictating" },
          ]}
          value={state}
          onChange={(v) => setState(v as DeckState)}
        />
      </div>

      {active && (
        <p className="max-w-[680px] text-[12.5px] italic leading-relaxed text-stone-500">
          <span className="font-mono not-italic uppercase tracking-[0.14em] text-stone-700">
            {active.name}
          </span>
          {" — "}
          {active.blurb}
        </p>
      )}

      <div className="flex flex-wrap gap-7">
        {themes.map((theme) => (
          <PhoneFrame key={theme.key} theme={theme}>
            <IOSDeck state={state} treatment={treatment} />
          </PhoneFrame>
        ))}
      </div>
    </div>
  );
}

function Board() {
  const theme = themesByKey([BOARD_THEME_KEY])[0];
  if (!theme) return null;
  return (
    <div className="flex flex-col gap-5">
      <SectionHeading
        label="Milled vs Relief · Scope"
        hint="the two finalists side by side, idle, in one theme"
      />
      <div className="flex flex-wrap gap-7">
        {TREATMENT_LIST.map((t) => (
          <div key={t.key} className="flex flex-col gap-2">
            <div className="flex items-baseline gap-2 px-1">
              <span className="font-mono text-[11px] font-semibold uppercase tracking-[0.14em] text-stone-700">
                {t.name}
              </span>
            </div>
            <PhoneFrame theme={theme}>
              <IOSDeck state="idle" treatment={t.key} />
            </PhoneFrame>
          </div>
        ))}
      </div>
    </div>
  );
}

function SectionHeading({ label, hint }: { label: string; hint: string }) {
  return (
    <div className="flex items-baseline gap-3">
      <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.22em] text-stone-600">
        {label}
      </span>
      <span className="italic text-stone-400" style={{ fontSize: 12 }}>
        {hint}
      </span>
      <div className="ml-1 flex-1" style={{ height: 1, background: "#E4E4E3" }} />
    </div>
  );
}

function Segmented({
  options,
  value,
  onChange,
}: {
  options: { value: string; label: string }[];
  value: string;
  onChange: (v: string) => void;
}) {
  return (
    <div className="inline-flex rounded-lg border border-stone-200 bg-white p-1">
      {options.map((o) => {
        const on = o.value === value;
        return (
          <button
            key={o.value}
            onClick={() => onChange(o.value)}
            className={`rounded-md px-3 py-1.5 font-mono text-[11px] uppercase tracking-[0.12em] transition ${
              on
                ? "bg-stone-900 text-white"
                : "text-stone-500 hover:text-stone-800"
            }`}
          >
            {o.label}
          </button>
        );
      })}
    </div>
  );
}
