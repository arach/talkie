/**
 * Parse a date value into an ISO date string.
 * Supports: "7d", "30d", "2h", "2025-02-01", ISO strings
 */
function parseDate(value: string): string {
  // Relative: "7d", "30d", "2h"
  const relMatch = value.match(/^(\d+)([dhm])$/);
  if (relMatch) {
    const amount = parseInt(relMatch[1], 10);
    const unit = relMatch[2];
    const now = new Date();
    switch (unit) {
      case "d":
        now.setDate(now.getDate() - amount);
        break;
      case "h":
        now.setHours(now.getHours() - amount);
        break;
      case "m":
        now.setMinutes(now.getMinutes() - amount);
        break;
    }
    return now.toISOString();
  }

  // Absolute date
  const d = new Date(value);
  if (isNaN(d.getTime())) {
    console.error(`Invalid date: ${value}. Use formats like "7d", "2h", or "2025-02-01".`);
    process.exit(1);
  }
  return d.toISOString();
}

export function parseSince(value: string): string {
  return parseDate(value);
}

export function parseUntil(value: string): string {
  return parseDate(value);
}
