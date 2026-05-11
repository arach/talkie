export interface FormatOptions {
  pretty: boolean;
  json: boolean;
}

export function getFormatOptions(opts: {
  pretty?: boolean;
  json?: boolean;
}): FormatOptions {
  // Explicit flags win
  if (opts.json) return { pretty: false, json: true };
  if (opts.pretty) return { pretty: true, json: false };
  // Default: pretty in TTY, JSON when piped
  const isTTY = process.stdout.isTTY ?? false;
  return { pretty: isTTY, json: !isTTY };
}

export function output(data: unknown, fmt: FormatOptions): void {
  if (fmt.json) {
    console.log(JSON.stringify(data, null, 2));
  }
}

export function outputTable(
  rows: Record<string, unknown>[],
  columns: { key: string; label: string; width?: number; format?: (v: unknown) => string }[],
  fmt: FormatOptions
): void {
  if (fmt.json) {
    console.log(JSON.stringify(rows, null, 2));
    return;
  }

  if (rows.length === 0) {
    console.log("No results.");
    return;
  }

  // Calculate column widths
  const widths = columns.map((col) => {
    const maxData = rows.reduce((max, row) => {
      const val = col.format ? col.format(row[col.key]) : String(row[col.key] ?? "");
      return Math.max(max, val.length);
    }, 0);
    return col.width ?? Math.max(col.label.length, Math.min(maxData, 60));
  });

  // Header
  const header = columns.map((col, i) => col.label.padEnd(widths[i])).join("  ");
  console.log(header);
  console.log(columns.map((_, i) => "─".repeat(widths[i])).join("──"));

  // Rows
  for (const row of rows) {
    const line = columns
      .map((col, i) => {
        const val = col.format ? col.format(row[col.key]) : String(row[col.key] ?? "");
        return val.slice(0, widths[i]).padEnd(widths[i]);
      })
      .join("  ");
    console.log(line);
  }

  console.log(`\n${rows.length} result${rows.length === 1 ? "" : "s"}`);
}

export function formatDuration(seconds: number | null | undefined): string {
  if (!seconds) return "—";
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return m > 0 ? `${m}m ${s}s` : `${s}s`;
}

export function formatDate(
  dateStr: string | null | undefined
): string {
  if (!dateStr) return "—";
  const d = new Date(dateStr);
  return d.toLocaleDateString("en-US", {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

export function truncate(s: string | null | undefined, len: number): string {
  if (!s) return "";
  if (s.length <= len) return s;
  return s.slice(0, len - 1) + "…";
}

export function wordCount(text: string | null | undefined): number {
  if (!text) return 0;
  return text.split(/\s+/).filter(Boolean).length;
}
