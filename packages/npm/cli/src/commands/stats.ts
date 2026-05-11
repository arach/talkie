import type { Command } from "commander";
import { getDb, queryOne } from "../db";
import { getFormatOptions, output } from "../format";

export function registerStatsCommand(program: Command): void {
  program
    .command("stats")
    .description("Show app statistics (dictation counts, streaks, word counts)")
    .action(() => {
      const globalOpts = program.opts();
      const db = getDb(globalOpts.db);
      const fmt = getFormatOptions(globalOpts);

      const stats = queryOne(`SELECT * FROM app_stats WHERE id = 1`);

      if (!stats) {
        console.error("No stats found. Use Talkie to generate some data first.");
        process.exit(1);
      }

      // Live counts from recordings table
      const counts = queryOne(`
        SELECT
          COUNT(*) FILTER (WHERE type = 'memo' AND deletedAt IS NULL) AS memoCount,
          COUNT(*) FILTER (WHERE type = 'dictation') AS dictationCount,
          COUNT(*) AS totalRecordings
        FROM recordings
      `)!;

      if (fmt.pretty) {
        console.log("# Talkie Stats\n");
        console.log(`Memos:              ${counts.memoCount}`);
        console.log(`Dictations:         ${counts.dictationCount}`);
        console.log(`Total recordings:   ${counts.totalRecordings}`);
        console.log(`Dictations today:   ${stats.dictations_today}`);
        console.log(`Dictations (week):  ${stats.dictations_week}`);
        console.log(`Dictations (total): ${stats.dictations_total}`);
        console.log(`Total words:        ${(stats.words_total as number).toLocaleString()}`);
        console.log(`Streak:             ${stats.streak_days} day${(stats.streak_days as number) !== 1 ? "s" : ""}`);

        if (stats.top_apps_json) {
          try {
            const topApps = JSON.parse(stats.top_apps_json as string) as {
              name: string;
              count: number;
            }[];
            if (topApps.length > 0) {
              console.log("\nTop apps:");
              for (const app of topApps.slice(0, 10)) {
                console.log(`  ${app.name}: ${app.count}`);
              }
            }
          } catch {}
        }
      } else {
        const result: Record<string, unknown> = {
          ...stats,
          memoCount: counts.memoCount,
          dictationCount: counts.dictationCount,
          totalRecordings: counts.totalRecordings,
        };
        if (result.top_apps_json) {
          try { result.topApps = JSON.parse(result.top_apps_json as string); } catch { result.topApps = null; }
          delete result.top_apps_json;
        }
        output(result, fmt);
      }
    });
}
