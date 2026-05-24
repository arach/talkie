import { StudioPage } from "@/components/StudioPage";
import {
  IOS_SETTINGS_EXTRACTED_AT,
  IOS_SETTINGS_ROWS,
  IOS_SETTINGS_SOURCE,
  statusSummary,
} from "@/lib/ios-settings";
import { IOSSettingsTable } from "@/components/studies/IOSSettingsTable";
import { scanIOSSettings } from "./actions";

export const dynamic = "force-static";

export default function IOSSettingsPage() {
  const summary = statusSummary(IOS_SETTINGS_ROWS);
  const extractedAt = new Date(IOS_SETTINGS_EXTRACTED_AT);

  return (
    <StudioPage
      eyebrow="iOS · Settings audit"
      title="iOS Settings"
      help={`Flat extraction · ${IOS_SETTINGS_ROWS.length} rows · snapshot ${extractedAt.toISOString()}`}
    >
      <div className="space-y-4">
        <header className="flex flex-wrap items-baseline gap-x-6 gap-y-1 text-[11px] uppercase tracking-eyebrow text-studio-ink-faint/80">
          <span>
            Source:{" "}
            <code className="font-mono text-studio-ink/80">
              {IOS_SETTINGS_SOURCE}
            </code>
          </span>
          <span>
            Extracted: <span className="text-studio-ink/80">{extractedAt.toUTCString()}</span>
          </span>
          <span className="ml-auto flex gap-3">
            <Tag color="green">{summary.wired} wired</Tag>
            <Tag color="amber">{summary.computed} computed</Tag>
            <Tag color="orange">{summary.conditional} conditional</Tag>
            <Tag color="red">{summary.todo} todo</Tag>
            <Tag color="slate">{summary.debug} debug</Tag>
          </span>
        </header>
        <IOSSettingsTable rows={IOS_SETTINGS_ROWS} rescan={scanIOSSettings} />
      </div>
    </StudioPage>
  );
}

function Tag({
  color,
  children,
}: {
  color: "green" | "amber" | "orange" | "red" | "slate";
  children: React.ReactNode;
}) {
  const palette: Record<typeof color, { fg: string; bg: string }> = {
    green: { fg: "#1F5A2E", bg: "#E2F0E5" },
    amber: { fg: "#7A4A0E", bg: "#F5E6CC" },
    orange: { fg: "#8A4B17", bg: "#F4DEC2" },
    red: { fg: "#8A3030", bg: "#F0DCDC" },
    slate: { fg: "#5A554C", bg: "#ECECEB" },
  } as const;
  const tone = palette[color];
  return (
    <span
      className="inline-block rounded-[3px] px-1.5 py-0.5 font-mono text-[9px] font-semibold tracking-[0.18em]"
      style={{ color: tone.fg, background: tone.bg }}
    >
      {children}
    </span>
  );
}
