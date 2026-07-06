"use client";

import Link from "next/link";
import { StudioPage } from "@/components/StudioPage";
import { RecordingAnimations } from "@/components/studies/RecordingAnimations";

/**
 * Cross-platform recording animation canon.
 *
 * Side-by-side reference for the four states that matter during capture:
 * recording + transcribing on iPhone and Mac. Each cell mirrors what
 * ships in Swift today — tune timing and vocabulary here before porting.
 *
 * Related studies:
 *   /tape-transport        — iOS tape-head gesture (deeper controls)
 *   /recording-sheet       — legacy iPhone scheme lab
 *   /mac-recording-state   — Mac companion finalists (drafting sheet)
 *   /mac-record-to-memo    — wave → transcript emergence
 */

export default function RecordingAnimationsStudy() {
  return (
    <StudioPage
      eyebrow="Recording · Cross-platform · animation canon"
      title="Recording animations"
      help="edit components/studies/RecordingAnimations.tsx"
    >
      <div className="flex flex-col gap-10 py-2">
        <Intro />
        <RecordingAnimations />
        <RelatedStudies />
        <SwiftTargets />
      </div>
    </StudioPage>
  );
}

function Intro() {
  return (
    <p className="m-0 max-w-[820px] text-[12.5px] leading-[1.65] text-studio-ink">
      Four live states, two platforms. iPhone invests motion in the{" "}
      <strong>recording sheet</strong> — toggle <strong>Tape</strong> (the{" "}
      <a href="/tape-transport" className="underline decoration-studio-edge underline-offset-2 hover:decoration-studio-ink">
        Tape Transport
      </a>{" "}
      study — center head, flowing tape, crossing ticks) or <strong>Particles</strong>{" "}
      (the donor RecordingView cloud) — with live preview. It
      keeps <strong>transcribing</strong> quiet on the memo detail — a pulsing
      dot and italic label while the pass runs off-screen. Mac carries motion
      through both phases: reactive red bars while recording, then a luminous{" "}
      <strong>sweep</strong> and pipeline steps while transcribing. The
      companion surface adds a third Mac story — wave settle → transcript
      emerge — documented separately.
    </p>
  );
}

function RelatedStudies() {
  const links = [
    {
      href: "/tape-transport",
      label: "Tape Transport",
      blurb: "iOS signature gesture — fixed head · flowing tape · crossing ticks",
    },
    {
      href: "/recording-sheet",
      label: "Recording Sheet",
      blurb: "Legacy iPhone scheme lab — sparkle / phosphor trace variants",
    },
    {
      href: "/mac-recording-state",
      label: "Mac Recording State",
      blurb: "Companion finalists — drafting sheet + light instrument",
    },
    {
      href: "/mac-record-to-memo",
      label: "Record → Memo",
      blurb: "Wave decelerates, flattens, transcript reveals in place",
    },
  ];

  return (
    <section>
      <h2 className="m-0 mb-3 font-display text-[17px] font-medium tracking-tight text-studio-ink">
        Related studies
      </h2>
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
        {links.map((l) => (
          <Link
            key={l.href}
            href={l.href}
            className="rounded-md border border-studio-edge bg-white px-3.5 py-2.5 transition-colors hover:border-studio-ink"
          >
            <div className="font-mono text-[10px] font-semibold uppercase tracking-[0.14em] text-studio-ink">
              {l.label}
            </div>
            <div className="mt-0.5 text-[11px] leading-[1.45] text-studio-ink-faint">
              {l.blurb}
            </div>
          </Link>
        ))}
      </div>
    </section>
  );
}

function SwiftTargets() {
  const rows = [
    {
      cell: "iPhone · recording (tape)",
      swift: "apps/ios/Talkie iOS/Views/Next/RecordingSheetNext.swift",
      parts: "TapeTransport gesture · TapeWaveformView · LiveTranscriptMonitor",
    },
    {
      cell: "iPhone · recording (particles)",
      swift: "apps/ios/Talkie iOS/Views/RecordingView.swift",
      parts: "ParticlesWaveformView · LiveWaveformView · .recording red",
    },
    {
      cell: "iPhone · transcribing",
      swift: "apps/ios/Talkie iOS/Views/Next/VoiceMemoDetailNext.swift",
      parts: "PulsingAccentDot · isTranscribing gate on reading body",
    },
    {
      cell: "Mac · recording",
      swift: "apps/macos/Talkie/Views/MacRecordingView.swift",
      parts: "LiveWaveformBars · Activity.recording",
    },
    {
      cell: "Mac · transcribing",
      swift: "apps/macos/Talkie/Views/MacRecordingView.swift",
      parts: "TranscribingSweep · processingSteps pipeline",
    },
    {
      cell: "Mac · companion (alt)",
      swift: "apps/macos/Talkie/Views/RecordingCompanionSurface.swift",
      parts: "WaveOnlyContent phase machine · emergingTranscript mask",
    },
    {
      cell: "Mac · HUD (alt)",
      swift: "apps/macos/Talkie/Views/RecordingHUDView.swift",
      parts: "Proximity ramps · InkFlourishShape",
    },
  ];

  return (
    <section>
      <h2 className="m-0 mb-3 font-display text-[17px] font-medium tracking-tight text-studio-ink">
        Swift port map
      </h2>
      <div
        className="overflow-hidden rounded-md border border-studio-edge"
        style={{ fontSize: 11 }}
      >
        <table className="w-full border-collapse text-left">
          <thead>
            <tr className="border-b border-studio-edge bg-[#F8F8F7]">
              <th className="px-3 py-2 font-mono text-[9px] font-semibold uppercase tracking-[0.16em] text-studio-ink-faint">
                Cell
              </th>
              <th className="px-3 py-2 font-mono text-[9px] font-semibold uppercase tracking-[0.16em] text-studio-ink-faint">
                Swift
              </th>
              <th className="hidden px-3 py-2 font-mono text-[9px] font-semibold uppercase tracking-[0.16em] text-studio-ink-faint md:table-cell">
                Key types
              </th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr
                key={r.cell}
                className="border-b border-studio-edge last:border-0"
              >
                <td className="px-3 py-2 font-mono text-[10px] text-studio-ink">
                  {r.cell}
                </td>
                <td className="px-3 py-2 font-mono text-[10px] text-studio-ink-faint">
                  <code>{r.swift}</code>
                </td>
                <td className="hidden px-3 py-2 text-[10px] text-studio-ink-faint md:table-cell">
                  {r.parts}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}