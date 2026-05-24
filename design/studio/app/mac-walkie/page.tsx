"use client";

import { useState } from "react";
import { StudioPage } from "@/components/StudioPage";
import { ToggleBar, type Toggle } from "@/components/ToggleBar";
import {
  MacWalkieScope,
  SCOPE_PHASES,
  type ScopePhase,
} from "@/components/studies/MacWalkieScope";

/**
 * Mac Walkie — the live surface is a floating instrument that blooms
 * in the center of the screen when Hyper+T is held. The oscilloscope
 * IS the surface. Library record of past transmissions is a separate
 * artifact and lives elsewhere.
 *
 * Phase toggle scrubs through the four sequential moments of one
 * transmission so the ceremony is legible across the whole arc.
 *
 *   ready → transmitting → over → receiving
 *
 * Showcase backdrop is a faded studio canvas — meant to evoke the
 * modal floating over your actual screen, not to be pixel-faithful.
 */
export default function MacWalkieStudy() {
  const [phase, setPhase] = useState<ScopePhase>("transmitting");

  const toggles: Toggle[] = SCOPE_PHASES.map((p) => ({
    key: p.key,
    label: p.label,
    on: phase === p.key,
    onClick: () => setPhase(p.key),
  }));

  return (
    <StudioPage
      eyebrow="Walkie · macOS · Floating instrument · v2"
      title="Mac Walkie"
      help="components/studies/MacWalkieScope.tsx · centered modal that blooms on Hyper+T · oscilloscope is the surface"
    >
      <div className="flex flex-col gap-6 py-2">
        <ToggleBar label="Phase" toggles={toggles} variant="dark" />
        <p
          className="max-w-[760px] text-[12px] italic leading-relaxed"
          style={{ color: "var(--studio-ink-faint)" }}
        >
          {PHASE_BLURBS[phase]}
        </p>

        <div
          className="relative overflow-hidden rounded-lg"
          style={{
            height: 540,
            border: "0.5px solid #DEDEDD",
            boxShadow: "0 8px 30px rgba(0,0,0,0.08)",
          }}
        >
          <MacWalkieScope phase={phase} />
        </div>
      </div>
    </StudioPage>
  );
}

const PHASE_BLURBS: Record<ScopePhase, string> = {
  ready:
    "Hyper+T just pressed. Instrument blooms in. Scope at rest, channel armed, signal LED quiet. No sound yet — you haven't said anything.",
  transmitting:
    "Holding the key. Your voice drives the trace, the channel LED pulses, a red signal dot says we're recording. Timecode counts up. The footer hint flips to ‘release to send.’",
  over:
    "Key released. Brief settle moment — trace decays to baseline, ‘OVER’ badge replaces ‘TRANSMITTING.’ Half a second of ceremony before the answer lands. The walkie radio convention is the whole point.",
  receiving:
    "Talkie speaks back. Trace shows the TTS waveform, the agent voice plays on the default audio device, and a short caption sits beneath in display serif italic — the spoken line, in writing, so you can scan it after the audio passes.",
};
