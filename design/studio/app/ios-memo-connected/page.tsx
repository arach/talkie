import { StudioPage } from "@/components/StudioPage";
import { PhoneFrame } from "@/components/studies/PhoneFrame";
import { IOSMemoConnected } from "@/components/studies/IOSMemoConnected";
import { IOS_THEMES } from "@/lib/themes";

const scope = IOS_THEMES.find((t) => t.key === "scope")!;
const midnight = IOS_THEMES.find((t) => t.key === "midnight")!;

export default function IOSMemoConnectedStudy() {
  return (
    <StudioPage
      eyebrow="Memo detail · IA rebuild"
      title="iOS · Memo · Connected"
      help="edit components/studies/IOSMemoConnected.tsx · port target VoiceMemoDetailNext.swift"
    >
      <div className="flex flex-col gap-10">
        <div className="flex flex-wrap items-start gap-8">
          <Labeled tone="muted" label="Reading" caption="audio bound to the words">
            <PhoneFrame theme={scope}>
              <IOSMemoConnected mode="reading" />
            </PhoneFrame>
          </Labeled>
          <Labeled tone="accent" label="Transcribing" caption="captured signal · travelling head">
            <PhoneFrame theme={scope}>
              <IOSMemoConnected mode="transcribing" />
            </PhoneFrame>
          </Labeled>
          <Labeled tone="accent" label="Editing" caption="tap the words — caret, keyboard, Done">
            <PhoneFrame theme={scope}>
              <IOSMemoConnected mode="editing" />
            </PhoneFrame>
          </Labeled>
          <Labeled tone="muted" label="Editing · dark" caption="auto-saves · ⌘Z undo">
            <PhoneFrame theme={midnight}>
              <IOSMemoConnected mode="editing" />
            </PhoneFrame>
          </Labeled>
        </div>

        <NamesMarginalia />
        <IAChanges />
      </div>
    </StudioPage>
  );
}

function Labeled({
  label,
  caption,
  tone,
  children,
}: {
  label: string;
  caption: string;
  tone: "accent" | "muted";
  children: React.ReactNode;
}) {
  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-baseline gap-2 pl-1">
        <span
          className={`text-[11px] font-semibold uppercase tracking-eyebrow ${
            tone === "accent" ? "text-studio-amber" : "text-studio-ink"
          }`}
        >
          {label}
        </span>
        <span className="text-[11px] text-studio-ink-faint">{caption}</span>
      </div>
      {children}
    </div>
  );
}

// ── Names · marginalia ──────────────────────────────────────────────

function NamesMarginalia() {
  const parts: [string, string][] = [
    ["Source line", "Humane capture provenance — device · date · time. Replaces the cramped · MEMO · …· meta-string."],
    ["Tape strip", "Play + mag-tape waveform fused to the top of the reading body, same paper, no gap."],
    ["Transcribing pass", "Captured tape stays fixed; the amber head scans left-to-right over the signal, with a tiny Braille pulse in the empty transcript row."],
    ["Tape head", "Amber needle on the waveform at the playback position — the fixed head from the Tape Transport study."],
    ["Playhead caret", "The same head, living IN the text: played words full-ink, unplayed dim, amber caret between."],
    ["Reading body", "The transcript as the audio made readable. Tap anywhere to edit. Word count annotates the end."],
    ["Editing field", "Tap drops a caret in the words — plain full-ink text, a selection + blinking caret. The obvious way to edit text."],
    ["Edit / Done", "The iOS-canonical text-edit control in the header. Done commits; it auto-saves, ⌘Z undoes. No Accept/Cancel."],
    ["Tool rail", "One flat icon row — Share · Copy · Attach · Refine ✨. The AI transform demoted here, honestly labelled."],
    ["Workflows drawer", "Memo triggers + Mac runs folded into one collapsed strip, only when there's something to run."],
  ];
  return (
    <section className="max-w-3xl">
      <h2 className="mb-3 text-[11px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">
        · Names — name the parts
      </h2>
      <dl className="grid grid-cols-1 gap-x-8 gap-y-2.5 sm:grid-cols-2">
        {parts.map(([name, desc]) => (
          <div key={name} className="flex flex-col gap-0.5">
            <dt className="text-[12px] font-medium text-studio-ink">{name}</dt>
            <dd className="text-[12px] leading-snug text-studio-ink-muted">{desc}</dd>
          </div>
        ))}
      </dl>
    </section>
  );
}

// ── IA changes — the rationale ──────────────────────────────────────

function IAChanges() {
  const changes: [string, string][] = [
    ["Editing is direct, not routed", "“Refine in Compose” read as a separate AI surface. Now you edit text the obvious way: Edit/Done in the header, tap the body for a caret + keyboard. Done auto-saves; ⌘Z is the safety net — no Accept/Cancel."],
    ["AI Refine, told the truth", "The AI transform survives but stops impersonating the editor. It's “Refine ✨” in the tool rail when reading, and an accessory chip above the keyboard while editing — clearly a different verb than typing."],
    ["Melange → document", "Title, metadata, transcript, and a wall of action boxes become one raised paper object: source → audio → words → what's next."],
    ["Audio bound to words", "The transport fuses to the transcript and the playhead lives in the text — the words ARE the recording. While editing, the transport recedes to a quiet TAPE chip so the words are the focus."],
    ["Monochrome → hierarchy", "Stay monochrome; one amber accent (live / playhead / caret / Done) and one elevation (paper vs flat) instead of ten equal borders."],
  ];
  return (
    <section className="max-w-3xl">
      <h2 className="mb-3 text-[11px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">
        · What changed
      </h2>
      <ul className="flex flex-col gap-2.5">
        {changes.map(([head, body]) => (
          <li key={head} className="flex flex-col gap-0.5">
            <span className="text-[12.5px] font-medium text-studio-ink">{head}</span>
            <span className="text-[12.5px] leading-snug text-studio-ink-muted">{body}</span>
          </li>
        ))}
      </ul>
    </section>
  );
}
