"use client";

import { useState } from "react";

/**
 * Mac Learn — the agent-powered interstitial that replaces the Stats
 * page. See `app/mac-learn/NOTES.md` for the design rationale.
 *
 * Section order:
 *   1. TopBand    — "Learn" identity + small chrome
 *   2. Hero       — "Ask Talkie about Talkie." page identity
 *   3. AskTalkie  — onboarding-to-AI when not configured; real input
 *                   when an LLM is enabled (decided 2026-05-17: NO
 *                   simulated responses, NO pre-filled interactions —
 *                   the box is the moment we get users to enable an
 *                   LLM, with Apple Intelligence as the easy default)
 *   4. DidYouKnow — recap cards for existing features
 *   5. FeatureAtlas — illustrated grid of surfaces
 *   6. Integrations — LLM provider tiles + APIs
 *   7. WhatsNew   — recently shipped strip
 */

export function MacLearn() {
  return (
    <div
      className="mx-auto rounded-md"
      style={{
        width: "1100px",
        background: "#FBFBFA",
        boxShadow: "0 8px 30px rgba(0,0,0,0.08), 0 2px 6px rgba(0,0,0,0.04)",
        border: "0.5px solid #E0DCD3",
      }}
    >
      <TopBand />
      <div className="px-8 pt-4 pb-8">
        <div className="flex flex-col gap-9">
          <Hero />
          <AskTalkie />
          <DidYouKnow />
          <FeatureAtlas />
          <Integrations />
          <WhatsNew />
        </div>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────────────
// Top band

function TopBand() {
  return (
    <div className="flex items-center gap-3 border-b border-studio-edge px-8 py-3">
      <div className="font-display text-[15px] font-medium tracking-tight text-studio-ink">
        Learn
      </div>
      <div className="ml-auto text-[9px] font-mono uppercase tracking-[0.18em] text-studio-ink-faint">
        AGENT · INTERSTITIAL
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────────────
// Hero — phrased as a question so the agent box below reads as the
// natural continuation, not a tagline.

function Hero() {
  return (
    <div className="flex flex-col gap-1.5">
      <h1 className="m-0 font-display text-[44px] font-medium leading-none tracking-tight text-studio-ink">
        Learn
      </h1>
      <div className="text-[10px] font-mono uppercase tracking-[0.18em] text-studio-ink-faint">
        Ask · explore · revisit features
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────────────
// Ask Talkie — the anchor section.
//
// Studio behavior: demonstrative. Input is live, chips pre-fill, and
// a stubbed example response is shown to convey the *feel* of the
// agent. Studio can fake; the eventual Swift port cannot.
//
// Product behavior (eventual): the box dispatches the input to the
// user's configured LLM (or surfaces a "set up AI" path if none is
// configured — but that's product wiring, not the studio mock).

const SUGGESTED: string[] = [
  "How do workflows trigger?",
  "Can a context rule scope to one app?",
  "What's bound to Hyper+S?",
  "Which LLM providers can I plug in?",
  "How do diffs work in Compose?",
];

// Stub answers per chip — studio fake to show response shape.
const STUB_ANSWERS: Record<string, { body: string; link: string }> = {
  "How do workflows trigger?": {
    body: "Three triggers — recording finished, context rule matched, manual run. Each step pipes its output to the next.",
    link: "Open Workflows",
  },
  "Can a context rule scope to one app?": {
    body: "Yes. The matcher reads the foreground app at trigger time. You can scope to one app, a list, or an everywhere-except set.",
    link: "Manage Context Rules",
  },
  "What's bound to Hyper+S?": {
    body: "Hyper+S triggers the screenshot chord. Pick A (region), S (fullscreen), or D (window). The grab attaches to the current recording if one's running.",
    link: "Open Shortcuts",
  },
  "Which LLM providers can I plug in?": {
    body: "Anthropic and OpenAI by API key, local via Ollama, Apple Intelligence on-device on 15.1+. Provider chosen per-feature in Settings.",
    link: "Open Integrations",
  },
  "How do diffs work in Compose?": {
    body: "Voice instructions revise existing text. The change shows as an inline diff — accept the whole thing, accept span-by-span, or reject.",
    link: "Open Compose",
  },
};

function AskTalkie() {
  const [value, setValue] = useState("");
  const stub = STUB_ANSWERS[value.trim()];

  return (
    <SectionBlock
      eyebrow="Ask Talkie"
      trailing="Apple Intelligence · Anthropic · OpenAI · Local"
    >
      <div className="flex flex-col gap-4 rounded-md border border-studio-edge bg-white/50 p-5">
        {/* Live input — placeholder carries the cute self-reference. */}
        <div className="flex items-center gap-3 rounded-md border border-studio-edge bg-white px-4 py-3">
          <span className="font-mono text-[12px] text-studio-ink-faint">»</span>
          <input
            type="text"
            value={value}
            onChange={(e) => setValue(e.target.value)}
            placeholder="Ask Talkie about Talkie…"
            className="flex-1 bg-transparent text-[14px] text-studio-ink placeholder:text-studio-ink-faint outline-none"
          />
          <span className="font-mono text-[10px] text-studio-ink-faint">↵</span>
        </div>

        {/* Suggested chips — clicking pre-fills the input. */}
        <div className="flex flex-wrap gap-2">
          {SUGGESTED.map((q) => (
            <button
              key={q}
              onClick={() => setValue(q)}
              className="rounded-[3px] border border-studio-edge bg-white/40 px-2.5 py-1 text-[10px] text-studio-ink-faint transition-colors hover:border-studio-ink hover:text-studio-ink"
            >
              {q}
            </button>
          ))}
        </div>

        {/* Response area — stubbed answers when a known chip is
            selected, faded prompt otherwise. Studio fake only. */}
        <div
          className="min-h-[68px] rounded-md border border-dashed px-4 py-3"
          style={{ borderColor: "#E0DCD3" }}
        >
          {stub ? (
            <div className="flex flex-col gap-2">
              <div className="flex items-start gap-2">
                <span className="font-mono text-[9px] uppercase tracking-[0.20em] text-studio-ink-faint mt-0.5 shrink-0">
                  TALKIE
                </span>
                <span className="text-[12px] leading-relaxed text-studio-ink">
                  {stub.body}
                </span>
              </div>
              <button className="self-start text-[9px] font-mono uppercase tracking-[0.20em] text-[#9A6A22] hover:text-[#7A521A] transition-colors">
                {stub.link} →
              </button>
            </div>
          ) : (
            <span className="text-[11px] text-studio-ink-faint">
              The agent's answer lands here — grounded in Talkie's capabilities, with quick links to the surfaces it touches.
            </span>
          )}
        </div>
      </div>
    </SectionBlock>
  );
}

// ────────────────────────────────────────────────────────────────────
// Did you know? — recap cards for existing features. Each card has a
// small illustration + the "did you know" hook + an action.

interface Recap {
  hook: string;
  detail: string;
  action: string;
  glyph: "diff" | "screenshot" | "context";
}

const RECAPS: Recap[] = [
  {
    hook: "You can diff Compose edits",
    detail: "Voice instructions revise existing text; the changes show as inline diffs before you accept.",
    action: "OPEN COMPOSE",
    glyph: "diff",
  },
  {
    hook: "Hyper+S captures with audio",
    detail: "The screen grab joins the current recording — pinned alongside the words, not separately.",
    action: "TRY HYPER+S",
    glyph: "screenshot",
  },
  {
    hook: "Context rules scope to apps",
    detail: "Bind a rule to iTerm only, or to anywhere except Slack. The matcher reads the foreground app at trigger time.",
    action: "MANAGE RULES",
    glyph: "context",
  },
];

function DidYouKnow() {
  return (
    <SectionBlock
      eyebrow="Did you know?"
      trailing="Existing features · worth a revisit"
    >
      <div className="grid grid-cols-3 gap-4">
        {RECAPS.map((r) => (
          <RecapCard key={r.hook} recap={r} />
        ))}
      </div>
    </SectionBlock>
  );
}

function RecapCard({ recap }: { recap: Recap }) {
  return (
    <button className="group flex flex-col gap-3 rounded-md border border-studio-edge bg-white/50 px-4 py-3.5 text-left transition-colors hover:border-studio-ink">
      <div className="flex items-start gap-3">
        <div
          className="flex h-9 w-9 shrink-0 items-center justify-center rounded-[3px] border"
          style={{ borderColor: "#E0DCD3", background: "#FAF6E8" }}
        >
          <RecapGlyph kind={recap.glyph} />
        </div>
        <div className="font-display text-[14px] font-medium leading-snug tracking-tight text-studio-ink">
          {recap.hook}
        </div>
      </div>
      <p className="text-[11px] leading-relaxed text-studio-ink-faint">{recap.detail}</p>
      <div className="mt-auto flex items-center gap-2 border-t border-studio-edge/70 pt-2">
        <span className="text-[9px] font-mono uppercase tracking-[0.20em] text-[#9A6A22] group-hover:text-[#7A521A] transition-colors">
          {recap.action} →
        </span>
      </div>
    </button>
  );
}

function RecapGlyph({ kind }: { kind: Recap["glyph"] }) {
  switch (kind) {
    case "diff":
      // Two horizontal lines, second shifted — "before/after"
      return (
        <svg width="22" height="22" viewBox="0 0 22 22" aria-hidden>
          <rect x="3" y="6" width="11" height="2" fill="#9A6A22" opacity="0.4" />
          <rect x="3" y="6" width="11" height="2" fill="none" stroke="#9A6A22" strokeWidth="0.5" />
          <rect x="3" y="14" width="16" height="2" fill="#9A6A22" />
        </svg>
      );
    case "screenshot":
      // Corner brackets + dot
      return (
        <svg width="22" height="22" viewBox="0 0 22 22" aria-hidden>
          <path d="M 2 5 L 2 2 L 5 2" stroke="#9A6A22" strokeWidth="1.2" fill="none" />
          <path d="M 17 2 L 20 2 L 20 5" stroke="#9A6A22" strokeWidth="1.2" fill="none" />
          <path d="M 2 17 L 2 20 L 5 20" stroke="#9A6A22" strokeWidth="1.2" fill="none" />
          <path d="M 17 20 L 20 20 L 20 17" stroke="#9A6A22" strokeWidth="1.2" fill="none" />
          <circle cx="11" cy="11" r="2.5" fill="#9A6A22" />
        </svg>
      );
    case "context":
      // Tag/chip shape
      return (
        <svg width="22" height="22" viewBox="0 0 22 22" aria-hidden>
          <rect x="3" y="7" width="13" height="8" rx="2" fill="none" stroke="#9A6A22" strokeWidth="1" />
          <circle cx="6.5" cy="11" r="1.2" fill="#9A6A22" />
          <line x1="9.5" y1="11" x2="13.5" y2="11" stroke="#9A6A22" strokeWidth="1" />
        </svg>
      );
  }
}

// ────────────────────────────────────────────────────────────────────
// Feature atlas — illustrated grid of all surfaces. Each card has a
// glyph, name, single data line, and an open action. No marketing copy.

interface Feature {
  name: string;
  state: string;
  action: string;
  glyph: "workflows" | "context" | "console" | "compose" | "keys" | "memos";
}

const FEATURES: Feature[] = [
  { name: "Workflows",     state: "3 ran today",        action: "OPEN",   glyph: "workflows" },
  { name: "Context rules", state: "12 active",          action: "OPEN",   glyph: "context"   },
  { name: "Console",       state: "2 tabs open",        action: "OPEN",   glyph: "console"   },
  { name: "Compose",       state: "Last · 9:34 AM",     action: "OPEN",   glyph: "compose"   },
  { name: "Hyper keys",    state: "5 bindings",         action: "MANAGE", glyph: "keys"      },
  { name: "Memos",         state: "436 in last 7 days", action: "OPEN",   glyph: "memos"     },
];

function FeatureAtlas() {
  return (
    <SectionBlock eyebrow="Features">
      <div className="grid grid-cols-3 gap-4">
        {FEATURES.map((f) => (
          <FeatureCard key={f.name} feature={f} />
        ))}
      </div>
    </SectionBlock>
  );
}

function FeatureCard({ feature }: { feature: Feature }) {
  return (
    <button className="group flex flex-col rounded-md border border-studio-edge bg-white/50 text-left transition-colors hover:border-studio-ink">
      {/* Illustration band */}
      <div
        className="flex h-[88px] items-center justify-center rounded-t-md border-b border-studio-edge"
        style={{ background: "linear-gradient(to bottom, #FAF6E8 0%, #F4EFE0 100%)" }}
      >
        <FeatureGlyph kind={feature.glyph} />
      </div>
      {/* Identity row */}
      <div className="flex items-baseline gap-3 px-4 pt-3 pb-1.5">
        <span className="font-display text-[14px] font-medium tracking-tight text-studio-ink">
          {feature.name}
        </span>
      </div>
      {/* State row */}
      <div className="px-4 pb-2">
        <div className="text-[10px] font-mono uppercase tracking-[0.16em] text-studio-ink-faint">
          {feature.state}
        </div>
      </div>
      {/* Action row */}
      <div className="flex items-center gap-2 border-t border-studio-edge/70 px-4 py-2">
        <span className="text-[9px] font-mono uppercase tracking-[0.20em] text-[#9A6A22] group-hover:text-[#7A521A] transition-colors">
          {feature.action} →
        </span>
      </div>
    </button>
  );
}

function FeatureGlyph({ kind }: { kind: Feature["glyph"] }) {
  switch (kind) {
    case "workflows":
      // Simple node graph: 3 nodes connected
      return (
        <svg width="56" height="40" viewBox="0 0 56 40" aria-hidden>
          <line x1="12" y1="20" x2="28" y2="10" stroke="#9A6A22" strokeWidth="1" opacity="0.6" />
          <line x1="12" y1="20" x2="28" y2="30" stroke="#9A6A22" strokeWidth="1" opacity="0.6" />
          <line x1="28" y1="10" x2="44" y2="20" stroke="#9A6A22" strokeWidth="1" opacity="0.6" />
          <line x1="28" y1="30" x2="44" y2="20" stroke="#9A6A22" strokeWidth="1" opacity="0.6" />
          <circle cx="12" cy="20" r="4" fill="#9A6A22" />
          <circle cx="28" cy="10" r="3" fill="none" stroke="#9A6A22" strokeWidth="1" />
          <circle cx="28" cy="30" r="3" fill="none" stroke="#9A6A22" strokeWidth="1" />
          <circle cx="44" cy="20" r="4" fill="#9A6A22" />
        </svg>
      );
    case "context":
      // Stack of tag chips
      return (
        <svg width="56" height="40" viewBox="0 0 56 40" aria-hidden>
          <rect x="8" y="6" width="36" height="8" rx="2" fill="none" stroke="#9A6A22" strokeWidth="1" />
          <rect x="12" y="16" width="32" height="8" rx="2" fill="#9A6A22" opacity="0.2" />
          <rect x="12" y="16" width="32" height="8" rx="2" fill="none" stroke="#9A6A22" strokeWidth="1" />
          <rect x="16" y="26" width="28" height="8" rx="2" fill="none" stroke="#9A6A22" strokeWidth="1" />
        </svg>
      );
    case "console":
      // Terminal prompt
      return (
        <svg width="56" height="40" viewBox="0 0 56 40" aria-hidden>
          <rect x="6" y="6" width="44" height="28" rx="2" fill="none" stroke="#9A6A22" strokeWidth="1" />
          <text x="12" y="22" fill="#9A6A22" fontSize="9" fontFamily="monospace">$</text>
          <rect x="18" y="16" width="14" height="2" fill="#9A6A22" opacity="0.6" />
          <rect x="34" y="16" width="6" height="6" fill="#9A6A22" />
        </svg>
      );
    case "compose":
      // Text with cursor + diff bar
      return (
        <svg width="56" height="40" viewBox="0 0 56 40" aria-hidden>
          <rect x="8" y="8" width="40" height="2" fill="#9A6A22" opacity="0.6" />
          <rect x="8" y="14" width="32" height="2" fill="#9A6A22" />
          <rect x="42" y="14" width="2" height="2" fill="#9A6A22" />
          <rect x="8" y="20" width="20" height="2" fill="#9A6A22" opacity="0.4" />
          <rect x="8" y="26" width="36" height="2" fill="#9A6A22" opacity="0.6" />
        </svg>
      );
    case "keys":
      // Keycap stack
      return (
        <svg width="56" height="40" viewBox="0 0 56 40" aria-hidden>
          {[
            { x: 8, label: "⌃" },
            { x: 21, label: "⇧" },
            { x: 34, label: "⌘" },
            { x: 47, label: "S" },
          ].map((k, i) => (
            <g key={i}>
              <rect x={k.x - 4} y="14" width="11" height="14" rx="2" fill="none" stroke="#9A6A22" strokeWidth="1" />
              <text x={k.x + 1.5} y="24" fill="#9A6A22" fontSize="8" textAnchor="middle" fontFamily="ui-monospace, monospace">{k.label}</text>
            </g>
          ))}
        </svg>
      );
    case "memos":
      // Mini waveform
      return (
        <svg width="56" height="40" viewBox="0 0 56 40" aria-hidden>
          {[8, 14, 6, 18, 10, 22, 12, 16, 8, 20, 14, 6, 18, 10].map((h, i) => (
            <rect
              key={i}
              x={4 + i * 3.5}
              y={20 - h / 2}
              width="2"
              height={h}
              fill="#9A6A22"
              opacity={0.5 + (i % 3) * 0.15}
            />
          ))}
        </svg>
      );
  }
}

// ────────────────────────────────────────────────────────────────────
// Integrations — LLM provider tiles + APIs. Status per tile (configured
// or not). Stubs the eventual config screen.

interface Provider {
  name: string;
  category: "LLM" | "Service";
  status: "configured" | "available" | "soon";
  detail: string;
}

const PROVIDERS: Provider[] = [
  { name: "Apple Intelligence", category: "LLM", status: "available",  detail: "on-device · macOS 15.1+" },
  { name: "Anthropic",          category: "LLM", status: "configured", detail: "claude-opus-4-7" },
  { name: "OpenAI",             category: "LLM", status: "configured", detail: "gpt-4o" },
  { name: "Local",              category: "LLM", status: "available",  detail: "ollama · mistral 7b" },
  { name: "Gemini",             category: "LLM", status: "available",  detail: "your API key" },
  { name: "Hugging Face",       category: "LLM", status: "soon",       detail: "inference endpoints" },
  { name: "iCloud",             category: "Service", status: "configured", detail: "private sync" },
  { name: "Bridge API",         category: "Service", status: "available",  detail: "local HTTP · port 7745" },
];

function Integrations() {
  return (
    <SectionBlock
      eyebrow="Integrations"
      trailing="LLMs · services · your keys"
    >
      <div className="grid grid-cols-3 gap-3">
        {PROVIDERS.map((p) => (
          <ProviderTile key={p.name} provider={p} />
        ))}
      </div>
    </SectionBlock>
  );
}

function ProviderTile({ provider }: { provider: Provider }) {
  const statusColor =
    provider.status === "configured" ? "#54A06A" :
    provider.status === "available"  ? "#9A6A22" :
                                       "#A8A29E";
  const statusLabel =
    provider.status === "configured" ? "CONFIGURED" :
    provider.status === "available"  ? "AVAILABLE"  :
                                       "SOON";

  return (
    <button className="group flex items-center gap-3 rounded-md border border-studio-edge bg-white/50 px-3.5 py-3 text-left transition-colors hover:border-studio-ink">
      <span
        aria-hidden
        className="h-2 w-2 rounded-full"
        style={{ background: statusColor, boxShadow: `0 0 4px ${statusColor}55` }}
      />
      <div className="flex flex-1 flex-col gap-0.5">
        <div className="flex items-baseline gap-2">
          <span className="text-[12px] font-medium text-studio-ink">{provider.name}</span>
          <span className="text-[8px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint">
            {provider.category}
          </span>
        </div>
        <div className="text-[10px] font-mono uppercase tracking-[0.14em] text-studio-ink-faint">
          {statusLabel} · {provider.detail}
        </div>
      </div>
    </button>
  );
}

// ────────────────────────────────────────────────────────────────────
// What's new — recently shipped strip. Lightweight, dated.

const NEW_ITEMS: { date: string; title: string }[] = [
  { date: "2026-05-17", title: "Bay scheme picker · 4 light-mode schemes (Pearl, Porcelain, Chiffon, Vellum)" },
  { date: "2026-05-17", title: "Design Studio · in-repo HTML lab for native app treatments" },
  { date: "2026-05-17", title: "Scope Home · reintegrated Routines, Discovery, scheme-aware System Status" },
  { date: "2026-05-14", title: "Library readout body system · 3 readout variants" },
];

function WhatsNew() {
  return (
    <SectionBlock eyebrow="What's new">
      <div className="rounded-md border border-studio-edge bg-white/40">
        {NEW_ITEMS.map((item, i) => (
          <div
            key={i}
            className="flex items-baseline gap-4 border-b border-studio-edge/60 px-4 py-2.5 last:border-b-0"
          >
            <span className="font-mono text-[10px] tracking-[0.06em] text-studio-ink-faint w-[88px]">
              {item.date}
            </span>
            <span className="text-[12px] text-studio-ink">{item.title}</span>
          </div>
        ))}
      </div>
    </SectionBlock>
  );
}

// ────────────────────────────────────────────────────────────────────
// Section wrapper — matches MacHome study's pattern.

function SectionBlock({
  eyebrow,
  trailing,
  children,
}: {
  eyebrow: string;
  trailing?: string;
  children: React.ReactNode;
}) {
  return (
    <section>
      <div className="mb-3 flex items-baseline gap-3">
        <div className="text-[9px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">
          · {eyebrow}
        </div>
        {trailing ? (
          <div className="ml-auto text-[9px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint">
            {trailing}
          </div>
        ) : null}
      </div>
      {children}
    </section>
  );
}
