import { EngMarkdown } from "@/components/EngMarkdown";
import { statusPalette, type EngDoc } from "@/lib/eng-docs";

/**
 * Unified data-sheet header for an engineering doc.
 *
 * One bordered container. Every line — identifier, target system,
 * status, owner, title, subtitle, summary, goal, decision — is a row
 * in the same two-column grid. The label column has a fixed width so
 * the eye runs straight down it; the value column types each kind of
 * data as appropriate (identifier mono, title display, summary prose).
 *
 * Rows that depend on optional fields (owner, subtitle, goal,
 * decision) render only when the underlying value is present.
 */
export function EngDocHeader({ doc }: { doc: EngDoc }) {
  const tone = statusPalette(doc.status);
  const tlk = `TLK-${String(doc.number).padStart(3, "0")}`;

  return (
    <div className="-mx-7 border-y border-studio-edge bg-studio-canvas/95">
      <div className="divide-y divide-studio-edge/60">
        <DataRow label="Proposal">
          <span className="font-mono text-[12.5px] font-semibold uppercase tracking-eyebrow text-studio-ink">
            {tlk}
          </span>
        </DataRow>
        <DataRow label="Target System">
          <span className="font-mono text-[12.5px] uppercase tracking-eyebrow text-studio-ink">
            {doc.tag}
          </span>
        </DataRow>
        <DataRow label="Status">
          <span
            className="inline-block rounded-[3px] px-1.5 py-0.5 font-mono text-[9px] font-semibold tracking-[0.18em]"
            style={{ color: tone.fg, background: tone.bg }}
          >
            {tone.label}
          </span>
        </DataRow>
        {doc.owner && doc.owner !== "TBD" ? (
          <DataRow label="Owner">
            <span className="font-mono text-[12.5px] text-studio-ink">
              {doc.owner}
            </span>
          </DataRow>
        ) : null}
        <DataRow label="Title">
          <h1 className="m-0 font-display text-[22px] font-medium leading-tight tracking-tight text-studio-ink">
            {doc.title}
          </h1>
        </DataRow>
        {doc.subtitle ? (
          <DataRow label="Subtitle">
            <p className="m-0 font-sans text-[14px] leading-snug text-studio-ink/85">
              {doc.subtitle}
            </p>
          </DataRow>
        ) : null}
        {doc.headerSections.map((section) => (
          <DataRow key={section.label} label={section.label}>
            <EngMarkdown body={section.body} fromSlug={doc.slug} compact />
          </DataRow>
        ))}
      </div>
    </div>
  );
}

function DataRow({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div className="grid grid-cols-[120px_1fr] gap-6 px-7 py-3">
      <div className="pt-[3px] font-mono text-[9px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint/80">
        {label}
      </div>
      <div className="min-w-0">{children}</div>
    </div>
  );
}
