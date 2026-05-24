"use client";

/**
 * Mac Walkie — Direction 1 · "Radio"
 *
 * Full commit to walkie-talkie hardware iconography. Dark gunmetal
 * panel, mock LCD channel display, circular transmitter, chamfered
 * keycaps. The point: the surface feels like a piece of equipment
 * sitting on the desk, not a chat app.
 *
 * Showcase composition: idle. The hardware idle hero is the most
 * distinctive moment of this direction.
 */

export function MacWalkieRadio() {
  return (
    <div
      className="flex h-full flex-col"
      style={{
        background:
          "radial-gradient(ellipse at top, #2D2D34 0%, #1B1B20 60%, #131318 100%)",
        fontFamily: "var(--theme-font-sans)",
        color: "#D8D8DC",
      }}
    >
      <RadioHeader />
      <RadioDivider />
      <RadioIdleBody />
      <RadioPromptBar />
    </div>
  );
}

// ── Chrome ─────────────────────────────────────────────────────────

function RadioHeader() {
  return (
    <div
      className="flex items-center justify-between px-6 pt-4 pb-3"
      style={{
        background:
          "linear-gradient(180deg, rgba(255,255,255,0.04) 0%, transparent 100%)",
      }}
    >
      <div className="flex items-center gap-4">
        <span
          className="inline-flex items-center gap-1.5 text-[10px] font-medium uppercase"
          style={{
            color: "#7F7F87",
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.30em",
          }}
        >
          <Screw />
          TALKIE · WALKIE
        </span>
        <LCDChannelDisplay />
      </div>

      <div className="flex items-center gap-3">
        <SignalMeter bars={4} />
        <BatteryBadge level={0.78} />
        <CloseDot />
      </div>
    </div>
  );
}

function LCDChannelDisplay() {
  return (
    <div
      className="flex items-center gap-3 rounded px-3 py-1.5"
      style={{
        background: "#06120A",
        border: "1px solid #122618",
        boxShadow:
          "inset 0 1px 0 rgba(0,0,0,0.6), 0 0 8px rgba(108,255,176,0.08)",
        fontFamily: "var(--theme-font-mono)",
      }}
    >
      <div className="flex flex-col gap-0.5">
        <span
          className="text-[8px] uppercase"
          style={{
            color: "#3D8A5A",
            letterSpacing: "0.22em",
          }}
        >
          Channel
        </span>
        <span
          className="text-[14px] font-medium tabular-nums"
          style={{
            color: "#6FFFB0",
            letterSpacing: "0.05em",
            textShadow: "0 0 4px rgba(111,255,176,0.45)",
          }}
        >
          01 · NIGHTOPS
        </span>
      </div>
      <span
        className="text-[8px] tabular-nums"
        style={{
          color: "#3D8A5A",
          letterSpacing: "0.15em",
        }}
      >
        467.5625
        <br />
        MHz · FM
      </span>
    </div>
  );
}

function SignalMeter({ bars }: { bars: number }) {
  return (
    <div className="flex items-end gap-[2px]">
      {[1, 2, 3, 4, 5].map((i) => (
        <span
          key={i}
          className="rounded-[1px]"
          style={{
            width: 3,
            height: 4 + i * 2,
            background: i <= bars ? "#FFA940" : "#37373D",
            boxShadow: i <= bars ? "0 0 4px rgba(255,169,64,0.55)" : "none",
          }}
        />
      ))}
    </div>
  );
}

function BatteryBadge({ level }: { level: number }) {
  return (
    <div
      className="flex items-center gap-1 rounded px-1.5 py-0.5"
      style={{
        border: "0.5px solid #37373D",
        fontFamily: "var(--theme-font-mono)",
      }}
    >
      <span
        className="inline-block"
        style={{
          width: 14,
          height: 6,
          background: `linear-gradient(90deg, #FFA940 ${level * 100}%, #2A2A30 ${level * 100}%)`,
          border: "0.5px solid #4A4A52",
          borderRadius: 1,
        }}
      />
      <span className="text-[8px] tabular-nums" style={{ color: "#7F7F87" }}>
        {Math.round(level * 100)}%
      </span>
    </div>
  );
}

function CloseDot() {
  return (
    <button
      aria-label="Close"
      className="h-5 w-5 rounded-full"
      style={{
        background: "linear-gradient(180deg, #FF6B5A 0%, #D74A3C 100%)",
        boxShadow:
          "inset 0 1px 0 rgba(255,255,255,0.25), 0 0 4px rgba(0,0,0,0.4)",
      }}
    />
  );
}

function Screw() {
  return (
    <span
      className="inline-block h-2 w-2 rounded-full"
      style={{
        background: "radial-gradient(circle at 35% 35%, #6A6A72 0%, #2A2A30 80%)",
        border: "0.5px solid #1A1A20",
      }}
    />
  );
}

function RadioDivider() {
  return (
    <div
      style={{
        height: 1,
        background:
          "linear-gradient(90deg, transparent 0%, #3A3A42 12%, #3A3A42 88%, transparent 100%)",
      }}
    />
  );
}

// ── Body — idle hero ──────────────────────────────────────────────

function RadioIdleBody() {
  return (
    <div className="flex flex-1 flex-col items-center justify-center px-10 py-12">
      <Transmitter />

      <div className="mt-9 flex flex-col items-center gap-1.5">
        <span
          className="text-[26px] font-light"
          style={{
            color: "#F1F1F4",
            fontFamily: "var(--theme-font-display)",
            letterSpacing: "-0.01em",
          }}
        >
          Press &amp; hold to transmit.
        </span>
        <span
          className="text-[10px]"
          style={{
            color: "#7F7F87",
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.24em",
          }}
        >
          ⇧ ⌃ ⌥ ⌘ T · WALKIE-TALKIE STYLE · RELEASE TO SEND
        </span>
      </div>

      <div className="mt-10 grid w-full max-w-[520px] grid-cols-2 gap-3">
        <ModeCard glyph="♪" label="Verbal" body="Short answers come back spoken." />
        <ModeCard glyph="⟳" label="Async" body="Long jobs ack now, report later." />
        <ModeCard glyph="◎" label="Context" body="Selection, clipboard, recent tray." />
        <ModeCard glyph="↻" label="Channels" body="Switch agent persona per channel." />
      </div>
    </div>
  );
}

function Transmitter() {
  return (
    <div className="relative">
      <PulseRing diameter={148} delay={0} />
      <PulseRing diameter={120} delay={0.8} />

      <div
        className="relative flex items-center justify-center"
        style={{
          width: 96,
          height: 96,
          borderRadius: "50%",
          background:
            "radial-gradient(circle at 35% 30%, #FFD37A 0%, #FFA940 30%, #C77B1F 70%, #6E430D 100%)",
          boxShadow:
            "0 0 24px rgba(255,169,64,0.45), inset 0 2px 4px rgba(255,255,255,0.4), inset 0 -3px 6px rgba(0,0,0,0.35)",
          border: "1px solid #2A2A30",
        }}
      >
        <span
          className="text-[34px] font-medium"
          style={{
            color: "#3D2706",
            fontFamily: "var(--theme-font-mono)",
            textShadow: "0 1px 0 rgba(255,255,255,0.35)",
          }}
        >
          T
        </span>
      </div>
    </div>
  );
}

function PulseRing({ diameter, delay }: { diameter: number; delay: number }) {
  return (
    <span
      className="absolute left-1/2 top-1/2 animate-ping"
      style={{
        width: diameter,
        height: diameter,
        marginLeft: -diameter / 2,
        marginTop: -diameter / 2,
        borderRadius: "50%",
        border: "1px solid rgba(255,169,64,0.25)",
        animationDelay: `${delay}s`,
        animationDuration: "2.4s",
      }}
    />
  );
}

function ModeCard({ glyph, label, body }: { glyph: string; label: string; body: string }) {
  return (
    <div
      className="flex items-start gap-3 rounded px-3.5 py-3"
      style={{
        background:
          "linear-gradient(180deg, #25252B 0%, #1B1B20 100%)",
        border: "0.5px solid #2F2F35",
        boxShadow: "inset 0 1px 0 rgba(255,255,255,0.04)",
      }}
    >
      <span
        className="flex h-7 w-7 items-center justify-center rounded text-[13px]"
        style={{
          background: "#0F0F13",
          color: "#FFA940",
          border: "0.5px solid #2A2A30",
          fontFamily: "var(--theme-font-mono)",
        }}
      >
        {glyph}
      </span>
      <div className="flex flex-col gap-0.5">
        <span
          className="text-[10px] uppercase"
          style={{
            color: "#D8D8DC",
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.18em",
          }}
        >
          {label}
        </span>
        <span
          className="text-[11px]"
          style={{ color: "#7F7F87" }}
        >
          {body}
        </span>
      </div>
    </div>
  );
}

// ── Prompt bar ────────────────────────────────────────────────────

function RadioPromptBar() {
  return (
    <div
      className="flex items-center gap-3 px-5 py-4"
      style={{
        background:
          "linear-gradient(180deg, #1A1A1F 0%, #131318 100%)",
        borderTop: "1px solid #2F2F35",
        boxShadow: "inset 0 1px 0 rgba(255,255,255,0.03)",
      }}
    >
      <PttKeyCombo />
      <span
        className="flex-1 text-[11px]"
        style={{
          color: "#7F7F87",
          fontFamily: "var(--theme-font-mono)",
        }}
      >
        T01 · to transmit · release to send · auto-routes ♪/⟳
      </span>
      <button
        className="rounded-full px-3.5 py-1.5 text-[10px] uppercase"
        style={{
          border: "0.5px solid #37373D",
          color: "#7F7F87",
          fontFamily: "var(--theme-font-mono)",
          letterSpacing: "0.18em",
        }}
      >
        Type
      </button>
    </div>
  );
}

function PttKeyCombo() {
  return (
    <div className="flex items-center gap-1.5">
      <HardKeycap label="⇧" />
      <HardKeycap label="⌃" />
      <HardKeycap label="⌥" />
      <HardKeycap label="⌘" />
      <HardKeycap label="T" wide accent />
    </div>
  );
}

function HardKeycap({
  label,
  wide = false,
  accent = false,
}: {
  label: string;
  wide?: boolean;
  accent?: boolean;
}) {
  return (
    <span
      className={`flex items-center justify-center text-[11px] font-medium ${
        wide ? "px-2.5" : "px-2"
      }`}
      style={{
        height: 24,
        minWidth: 24,
        borderRadius: 4,
        background: accent
          ? "linear-gradient(180deg, #FFD37A 0%, #FFA940 60%, #C77B1F 100%)"
          : "linear-gradient(180deg, #3A3A42 0%, #25252B 60%, #1B1B20 100%)",
        color: accent ? "#3D2706" : "#E1E1E5",
        border: "0.5px solid #1A1A20",
        boxShadow: accent
          ? "inset 0 1px 0 rgba(255,255,255,0.45), 0 1px 2px rgba(0,0,0,0.55), 0 0 8px rgba(255,169,64,0.35)"
          : "inset 0 1px 0 rgba(255,255,255,0.08), 0 1px 2px rgba(0,0,0,0.5)",
        fontFamily: "var(--theme-font-mono)",
      }}
    >
      {label}
    </span>
  );
}
