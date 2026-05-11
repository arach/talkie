import type { Command } from "commander";
import { getDb, queryAll, queryOne, findByIdPrefix } from "../db";
import {
  getFormatOptions,
  output,
  outputTable,
  formatDate,
  truncate,
} from "../format";
import { parseSince } from "./shared";

export function registerWorkflowsCommand(program: Command): void {
  program
    .command("workflows [id]")
    .description("List workflow runs, or get details for a specific run")
    .option("--limit <n>", "max results", "50")
    .option("--since <date>", "filter by date (e.g. 2025-02-01 or 7d)")
    .option("--status <status>", "filter by status (completed, failed, running)")
    .action((id: string | undefined, opts) => {
      const globalOpts = program.opts();
      getDb(globalOpts.db);
      const fmt = getFormatOptions(globalOpts);

      if (id) {
        return getWorkflowRun(id, fmt);
      }

      const limit = parseInt(opts.limit, 10);
      const since = opts.since ? parseSince(opts.since) : null;

      let query = `
        SELECT id, workflowName, workflowIcon, status, createdAt,
               durationMs, memoId, stepCount, triggerSource, errorMessage
        FROM workflow_runs
        WHERE 1=1
      `;
      const params: unknown[] = [];

      if (since) {
        query += ` AND createdAt >= ?`;
        params.push(since);
      }
      if (opts.status) {
        query += ` AND status = ?`;
        params.push(opts.status);
      }

      query += ` ORDER BY createdAt DESC LIMIT ?`;
      params.push(limit);

      const rows = queryAll(query, ...params);

      if (fmt.pretty) {
        outputTable(rows, [
          { key: "id", label: "ID", width: 8, format: (v) => String(v ?? "").slice(0, 8) },
          { key: "workflowName", label: "Workflow", width: 25, format: (v) => truncate(v as string, 25) },
          { key: "status", label: "Status", width: 10 },
          { key: "durationMs", label: "Duration", width: 10, format: (v) => v ? `${((v as number) / 1000).toFixed(1)}s` : "—" },
          { key: "stepCount", label: "Steps", width: 5 },
          { key: "createdAt", label: "Created", width: 20, format: (v) => formatDate(v as string) },
        ], fmt);
      } else {
        output(rows, fmt);
      }
    });
}

function getWorkflowRun(
  id: string,
  fmt: { pretty: boolean; json: boolean }
): void {
  const run = findByIdPrefix("workflow_runs", id);

  if (!run) {
    console.error(`Workflow run not found: ${id}`);
    process.exit(1);
  }

  const steps = queryAll(
    `SELECT * FROM workflow_steps WHERE runId = ? ORDER BY stepNumber`,
    run.id as string
  );

  if (fmt.pretty) {
    const icon = run.workflowIcon ? `${run.workflowIcon} ` : "";
    console.log(`# ${icon}${run.workflowName}\n`);
    console.log(`ID:       ${run.id}`);
    console.log(`Status:   ${run.status}`);
    console.log(`Created:  ${formatDate(run.createdAt as string)}`);
    console.log(`Duration: ${run.durationMs ? `${((run.durationMs as number) / 1000).toFixed(1)}s` : "—"}`);
    console.log(`Trigger:  ${run.triggerSource}`);
    console.log(`Memo:     ${run.memoId}`);

    if (run.errorMessage) {
      console.log(`\n## Error\n${run.errorMessage}`);
    }

    if (steps.length > 0) {
      console.log(`\n## Steps\n`);
      for (const step of steps) {
        const status =
          step.status === "completed" ? "✓" : step.status === "failed" ? "✗" : "○";
        const dur = step.durationMs
          ? ` (${((step.durationMs as number) / 1000).toFixed(1)}s)`
          : "";
        console.log(
          `  ${status} Step ${step.stepNumber}: ${step.outputKey} [${step.stepType}]${dur}`
        );
        if (step.outputValue) {
          const preview = truncate(String(step.outputValue), 200);
          console.log(`    → ${preview}`);
        }
        if (step.errorMessage) {
          console.log(`    ✗ ${step.errorMessage}`);
        }
      }
    }

    if (run.finalOutputs) {
      try {
        const outputs = JSON.parse(run.finalOutputs as string);
        console.log(`\n## Outputs\n`);
        for (const [key, value] of Object.entries(outputs)) {
          console.log(`### ${key}\n${value}\n`);
        }
      } catch {}
    }
  } else {
    const result: Record<string, unknown> = { ...run };
    for (const jsonField of ["finalOutputs", "stepOutputsJSON"]) {
      if (result[jsonField]) {
        try { result[jsonField] = JSON.parse(result[jsonField] as string); } catch {}
      }
    }
    result.steps = steps.map((s) => {
      const step = { ...s };
      if (step.stepConfig) {
        try { step.stepConfig = JSON.parse(step.stepConfig as string); } catch {}
      }
      return step;
    });
    output(result, { pretty: false, json: true });
  }
}
