"use client";

const activity = [
  { time: "09:42", label: "Recorded quick note", detail: "Voice memo saved to Inbox" },
  { time: "09:37", label: "Transcript polished", detail: "3 speaker labels resolved" },
  { time: "09:31", label: "Sync complete", detail: "Mac and iPhone are current" },
];

const metrics = [
  { label: "Capture", value: "Ready", tone: "mint" },
  { label: "Queue", value: "3 clips", tone: "blue" },
  { label: "Sync", value: "Live", tone: "amber" },
];

const states = [
  {
    name: "Ready",
    status: "Listening ready",
    queue: "3 clips",
    progress: 64,
    accent: "mint",
  },
  {
    name: "Processing",
    status: "Cleaning transcript",
    queue: "8 clips",
    progress: 38,
    accent: "blue",
  },
  {
    name: "Needs review",
    status: "One note needs a title",
    queue: "1 item",
    progress: 82,
    accent: "amber",
  },
];

export function ActorHoverDashboard() {
  return (
    <div className="space-y-8">
      <section className="rounded-[8px] border border-studio-edge bg-studio-canvas-alt p-6">
        <div className="mb-4 flex items-center justify-between gap-4">
          <div>
            <div className="font-mono text-[9px] font-semibold uppercase tracking-[0.22em] text-studio-ink-faint">
              Actor hover surface
            </div>
            <h2 className="mt-1 font-display text-[24px] font-medium text-studio-ink">
              Flat WebView dashboard
            </h2>
          </div>
          <div className="font-mono text-[9px] uppercase tracking-[0.18em] text-studio-ink-faint">
            380 x 260
          </div>
        </div>

        <DesktopStage>
          <ActorIcon />
          <HUDPanel />
        </DesktopStage>
      </section>

      <section>
        <div className="mb-3 flex items-baseline justify-between border-b border-studio-edge pb-2">
          <div className="font-mono text-[9px] font-semibold uppercase tracking-[0.22em] text-studio-ink">
            State variants
          </div>
          <div className="font-mono text-[9px] uppercase tracking-[0.12em] text-studio-ink-faint">
            same geometry, different app mood
          </div>
        </div>
        <div className="grid gap-4 xl:grid-cols-3">
          {states.map((state) => (
            <StateTile key={state.name} state={state} />
          ))}
        </div>
      </section>
    </div>
  );
}

function DesktopStage({ children }: { children: React.ReactNode }) {
  return (
    <div className="relative overflow-hidden rounded-[8px] border border-black/10 bg-[linear-gradient(135deg,#cbd3cf_0%,#d1d8df_48%,#d7cec7_100%)] p-8 shadow-[inset_0_1px_0_rgba(255,255,255,0.56)]">
      <div className="absolute left-8 top-8 h-[180px] w-[280px] rounded-[8px] border border-white/38 bg-white/16 shadow-[0_14px_34px_rgba(45,55,62,0.12)] backdrop-blur-md" />
      <div className="absolute bottom-10 right-10 h-[220px] w-[340px] rounded-[8px] border border-white/30 bg-[#66737a]/10 shadow-[0_16px_42px_rgba(45,55,62,0.11)] backdrop-blur-md" />
      <div className="relative flex min-h-[420px] items-center justify-center gap-4">
        {children}
      </div>
    </div>
  );
}

function ActorIcon() {
  return (
    <div className="grid h-[82px] w-[82px] shrink-0 place-items-center rounded-[21px] border border-white/48 bg-[linear-gradient(150deg,rgba(84,132,214,0.92),rgba(78,188,153,0.88)_58%,rgba(210,169,86,0.90))] shadow-[0_14px_28px_rgba(38,49,57,0.24),inset_0_1px_0_rgba(255,255,255,0.46)]">
      <div className="grid h-[52px] w-[52px] place-items-center rounded-[16px] bg-white/18 ring-1 ring-white/38">
        <div className="h-[25px] w-[25px] rounded-[9px] bg-white/86 shadow-[0_5px_12px_rgba(38,49,57,0.14)]" />
      </div>
    </div>
  );
}

function HUDPanel() {
  return (
    <div className="w-full max-w-[380px] rounded-[14px] border border-white/62 bg-[rgba(247,248,244,0.78)] p-4 text-[#243039] shadow-[0_18px_48px_rgba(45,55,62,0.22),inset_0_1px_0_rgba(255,255,255,0.72)] backdrop-blur-2xl">
      <Header />
      <MetricRow />
      <ActivityList />
      <WaveStrip />
      <Footer />
    </div>
  );
}

function Header() {
  return (
    <div className="flex items-start justify-between gap-4">
      <div>
        <div className="font-mono text-[9px] uppercase tracking-[0.18em] text-[#66727a]">
          Talkie
        </div>
        <div className="mt-1 font-sans text-[18px] font-semibold leading-none text-[#1f2930]">
          Latest app state
        </div>
      </div>
      <div className="rounded-full border border-[#8fc6b4]/50 bg-[#dcefe8]/72 px-2.5 py-1 font-mono text-[9px] uppercase tracking-[0.14em] text-[#2d725f]">
        Ready
      </div>
    </div>
  );
}

function MetricRow() {
  return (
    <div className="mt-4 grid grid-cols-3 overflow-hidden rounded-[8px] border border-[#d8dfdc]/82 bg-white/42">
      {metrics.map((metric, index) => (
        <div
          key={metric.label}
          className={index === 0 ? "p-3" : "border-l border-[#d8dfdc]/82 p-3"}
        >
          <div className="font-mono text-[8px] uppercase tracking-[0.16em] text-[#728087]">
            {metric.label}
          </div>
          <div className={`mt-1 text-[12px] font-medium ${toneClass(metric.tone)}`}>
            {metric.value}
          </div>
        </div>
      ))}
    </div>
  );
}

function ActivityList() {
  return (
    <div className="mt-4">
      <div className="mb-1.5 font-mono text-[9px] uppercase tracking-[0.18em] text-[#66727a]">
        Latest activity
      </div>
      <div className="divide-y divide-[#d9e0dc]/80">
        {activity.map((item) => (
          <div key={`${item.time}-${item.label}`} className="grid grid-cols-[38px_1fr] gap-3 py-2">
            <div className="pt-0.5 font-mono text-[10px] text-[#748188]">{item.time}</div>
            <div className="min-w-0">
              <div className="truncate text-[12px] font-medium leading-tight text-[#263139]">
                {item.label}
              </div>
              <div className="mt-0.5 truncate text-[11px] leading-tight text-[#67737a]">
                {item.detail}
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function WaveStrip() {
  const bars = [10, 18, 28, 16, 36, 24, 42, 18, 30, 14, 24, 34, 20, 12];

  return (
    <div className="mt-3 rounded-[8px] border border-[#d8dfdc]/82 bg-[#eef2ed]/64 px-3 py-2.5">
      <div className="flex items-center justify-between gap-3">
        <div className="flex h-[34px] items-center gap-1.5">
          {bars.map((height, index) => (
            <span
              key={`${height}-${index}`}
              className="w-[3px] rounded-full bg-[#77aeb6]/70"
              style={{ height }}
            />
          ))}
        </div>
        <div className="min-w-[118px] text-right">
          <div className="text-[11px] font-medium text-[#364148]">Processing 3 clips</div>
          <div className="mt-1 h-1.5 overflow-hidden rounded-full bg-[#d7dfdc]">
            <div className="h-full w-[64%] rounded-full bg-[linear-gradient(90deg,#54b994,#70a8d3,#d5aa42)]" />
          </div>
        </div>
      </div>
    </div>
  );
}

function Footer() {
  return (
    <div className="mt-3 flex items-center justify-between border-t border-[#d8dfdc]/82 pt-3">
      <div className="text-[11px] text-[#657178]">Updated just now</div>
      <div className="flex gap-1.5">
        <IconButton label="Open" mark="O" />
        <IconButton label="Pin" mark="P" />
      </div>
    </div>
  );
}

function IconButton({ label, mark }: { label: string; mark: string }) {
  return (
    <button
      type="button"
      aria-label={label}
      className="grid h-7 w-7 place-items-center rounded-[7px] border border-[#d4ddda] bg-white/52 font-mono text-[10px] text-[#536169] shadow-[inset_0_1px_0_rgba(255,255,255,0.62)]"
    >
      {mark}
    </button>
  );
}

function StateTile({
  state,
}: {
  state: { name: string; status: string; queue: string; progress: number; accent: string };
}) {
  return (
    <div className="rounded-[8px] border border-studio-edge bg-studio-canvas-alt p-4">
      <div className="mb-3 flex items-center justify-between">
        <div>
          <div className="font-display text-[18px] font-medium text-studio-ink">
            {state.name}
          </div>
          <div className="mt-0.5 text-[11px] text-studio-ink-faint">{state.status}</div>
        </div>
        <div className={`h-2.5 w-2.5 rounded-full ${stateDotClass(state.accent)}`} />
      </div>
      <div className="rounded-[8px] border border-[#d8dfdc] bg-white/58 p-3 text-[#263139] shadow-[0_12px_26px_rgba(45,55,62,0.12)]">
        <div className="flex items-center justify-between text-[11px]">
          <span className="text-[#6b767c]">Queue</span>
          <span className="font-medium text-[#263139]">{state.queue}</span>
        </div>
        <div className="mt-3 h-1.5 overflow-hidden rounded-full bg-[#d7dfdc]">
          <div
            className={`h-full rounded-full ${stateProgressClass(state.accent)}`}
            style={{ width: `${state.progress}%` }}
          />
        </div>
      </div>
    </div>
  );
}

function toneClass(tone: string) {
  if (tone === "mint") return "text-[#2d725f]";
  if (tone === "blue") return "text-[#366f96]";
  return "text-[#84631d]";
}

function stateDotClass(tone: string) {
  if (tone === "mint") return "bg-[#47b88f]";
  if (tone === "blue") return "bg-[#4aa0ce]";
  return "bg-[#d5aa42]";
}

function stateProgressClass(tone: string) {
  if (tone === "mint") return "bg-[#54b994]";
  if (tone === "blue") return "bg-[#70a8d3]";
  return "bg-[#d5aa42]";
}
