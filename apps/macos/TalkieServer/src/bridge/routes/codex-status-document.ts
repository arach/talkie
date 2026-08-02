import path from "node:path";
import { realpathSync } from "node:fs";

export interface CodexStatusTask {
  id: string;
  title: string;
  preview: string;
  cwd: string;
  project: string;
  gitBranch?: string | null;
  gitOriginURL?: string | null;
}

export interface CodexStatusUpdate {
  id: string;
  kind: "commentary" | "tool";
  text: string;
  timestamp?: string | null;
}

export interface CodexStatusTurn {
  id: string;
  status: string;
  mode: string;
  createdAt: string;
  updatedAt: string;
  turnId?: string;
  delivery?: string;
  response?: string;
  updates?: CodexStatusUpdate[];
  error?: string;
  code?: string;
  hint?: string;
  approval?: {
    title: string;
    detail: string;
  };
}

export interface CodexStatusHistoryTurn {
  id: string;
  status: "completed" | "failed" | "aborted";
  startedAt?: string | null;
  completedAt?: string | null;
  durationMs?: number;
  instructions: string[];
  updates: CodexStatusUpdate[];
  response?: string;
  error?: string;
}

export interface CodexRepositoryFile {
  path: string;
  state: string;
  additions?: number;
  deletions?: number;
}

export interface CodexRepositoryStatus {
  root: string;
  branch: string;
  head: string;
  subject: string;
  origin?: string;
  upstream?: string;
  ahead?: number;
  behind?: number;
  files: CodexRepositoryFile[];
  additions: number;
  deletions: number;
  clean: boolean;
  unavailableReason?: string;
}

const COMMAND_TIMEOUT_MS = 2_000;
const OUTPUT_LIMIT = 256 * 1_024;

async function git(root: string, args: string[], optional = false): Promise<string | undefined> {
  const process = Bun.spawn(["/usr/bin/git", "-C", root, ...args], {
    stdout: "pipe",
    stderr: "pipe",
    env: {
      ...Bun.env,
      GIT_OPTIONAL_LOCKS: "0",
      GIT_TERMINAL_PROMPT: "0",
      LC_ALL: "C",
    },
    signal: AbortSignal.timeout(COMMAND_TIMEOUT_MS),
  });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(process.stdout).text(),
    new Response(process.stderr).text(),
    process.exited,
  ]);
  if (stdout.length > OUTPUT_LIMIT || stderr.length > OUTPUT_LIMIT) {
    throw new Error("Git status output exceeded the safety limit.");
  }
  if (exitCode !== 0) {
    if (optional) return undefined;
    throw new Error(stderr.trim() || `git ${args[0]} failed`);
  }
  return stdout.trimEnd();
}

function isWithin(root: string, candidate: string): boolean {
  const relative = path.relative(root, candidate);
  return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
}

function parseNameStatus(value: string): Map<string, string> {
  const result = new Map<string, string>();
  for (const line of value.split("\n")) {
    if (!line) continue;
    const [state, ...parts] = line.split("\t");
    const filePath = parts.at(-1);
    if (state && filePath) result.set(filePath, state.slice(0, 1));
  }
  return result;
}

function parseNumstat(value: string): Map<string, { additions?: number; deletions?: number }> {
  const result = new Map<string, { additions?: number; deletions?: number }>();
  for (const line of value.split("\n")) {
    if (!line) continue;
    const [added, deleted, ...parts] = line.split("\t");
    const filePath = parts.at(-1);
    if (!filePath) continue;
    result.set(filePath, {
      additions: /^\d+$/.test(added ?? "") ? Number(added) : undefined,
      deletions: /^\d+$/.test(deleted ?? "") ? Number(deleted) : undefined,
    });
  }
  return result;
}

/** Inspect only the task catalogue's canonical working directory, using fixed git arguments. */
export async function inspectCodexRepository(cwd: string): Promise<CodexRepositoryStatus> {
  try {
    const canonicalCwd = realpathSync(cwd);
    const reportedRoot = await git(canonicalCwd, ["rev-parse", "--show-toplevel"]);
    if (!reportedRoot) throw new Error("Git did not return a repository root.");
    const root = realpathSync(reportedRoot);
    if (!isWithin(root, canonicalCwd)) throw new Error("Task directory is outside its repository root.");

    const [branchValue, head, subject, origin, upstream, porcelain, nameStatus, numstat] = await Promise.all([
      git(root, ["symbolic-ref", "--quiet", "--short", "HEAD"], true),
      git(root, ["rev-parse", "--short=8", "HEAD"]),
      git(root, ["log", "-1", "--pretty=%s"]),
      git(root, ["config", "--get", "remote.origin.url"], true),
      git(root, ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"], true),
      git(root, ["status", "--porcelain=v1", "--untracked-files=normal"]),
      git(root, ["diff", "--name-status", "HEAD"]),
      git(root, ["diff", "--numstat", "HEAD"]),
    ]);

    const states = parseNameStatus(nameStatus ?? "");
    const counts = parseNumstat(numstat ?? "");
    for (const line of (porcelain ?? "").split("\n")) {
      if (!line) continue;
      const state = line.slice(0, 2).trim() || "M";
      const filePath = line.slice(3).split(" -> ").at(-1);
      if (filePath && !states.has(filePath)) states.set(filePath, state === "??" ? "?" : state.slice(0, 1));
    }

    let ahead: number | undefined;
    let behind: number | undefined;
    if (upstream) {
      const divergence = await git(root, ["rev-list", "--left-right", "--count", `HEAD...${upstream}`], true);
      const [left, right] = divergence?.trim().split(/\s+/) ?? [];
      if (/^\d+$/.test(left ?? "")) ahead = Number(left);
      if (/^\d+$/.test(right ?? "")) behind = Number(right);
    }

    const files = [...states.entries()].map(([filePath, state]) => ({
      path: filePath,
      state,
      ...counts.get(filePath),
    })).sort((a, b) => a.path.localeCompare(b.path));
    return {
      root,
      branch: branchValue || "DETACHED",
      head: head || "UNKNOWN",
      subject: subject || "No commit subject",
      ...(origin && { origin }),
      ...(upstream && { upstream }),
      ...(ahead !== undefined && { ahead }),
      ...(behind !== undefined && { behind }),
      files,
      additions: files.reduce((sum, file) => sum + (file.additions ?? 0), 0),
      deletions: files.reduce((sum, file) => sum + (file.deletions ?? 0), 0),
      clean: files.length === 0,
    };
  } catch (error) {
    return {
      root: cwd,
      branch: "UNAVAILABLE",
      head: "—",
      subject: "Repository status unavailable",
      files: [],
      additions: 0,
      deletions: 0,
      clean: true,
      unavailableReason: error instanceof Error ? error.message : String(error),
    };
  }
}

function escapeHTML(value: unknown): string {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function formatTime(value?: string | null): string {
  if (!value) return "—";
  const date = new Date(value);
  return Number.isNaN(date.valueOf()) ? value : date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

function formatDateTime(value?: string | null): string {
  if (!value) return "DATE UNKNOWN";
  const date = new Date(value);
  if (Number.isNaN(date.valueOf())) return value;
  return date.toLocaleString([], {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).toUpperCase();
}

function publicResponse(value?: string): string {
  return value?.split("<oai-mem-citation>", 1)[0]?.trim() ?? "";
}

function responseTitle(value: string, fallback: string): string {
  const firstLine = value.split("\n").map((line) => line.trim()).find(Boolean) ?? fallback;
  return firstLine.length > 96 ? `${firstLine.slice(0, 93).trimEnd()}…` : firstLine;
}

function renderHistoryTurn(turn: CodexStatusHistoryTurn): string {
  const response = publicResponse(turn.response);
  const fallback = turn.status === "completed" ? "Completed turn" : turn.status === "failed" ? "Turn failed" : "Turn stopped";
  const request = turn.instructions.at(-1)?.trim() ?? "";
  const updateCount = turn.updates.length;
  const requests = turn.instructions.length > 0
    ? `<div class="history-request"><span>YOU ASKED</span>${turn.instructions.map((instruction) => `<p>${escapeHTML(instruction)}</p>`).join("")}</div>`
    : "";
  const updates = updateCount > 0
    ? `<ul class="activity history-activity">${turn.updates.map((update) => `<li><time>${escapeHTML(formatTime(update.timestamp))}</time><span class="activity-kind ${update.kind}">${update.kind === "commentary" ? "AGENT NOTE" : "TOOL"}</span><p>${escapeHTML(update.text)}</p></li>`).join("")}</ul>`
    : `<p class="history-empty">No public progress notes were recorded for this turn.</p>`;
  const delivery = response
    ? `<div class="history-delivery"><span>DELIVERED</span><p>${escapeHTML(response)}</p></div>`
    : turn.error
      ? `<div class="history-delivery history-error"><span>OUTCOME</span><p>${escapeHTML(turn.error)}</p></div>`
      : "";
  const statusLabel = turn.status === "completed" ? "DONE" : turn.status === "failed" ? "FAILED" : "STOPPED";
  return `<details class="history-turn"><summary><span class="history-marker" aria-hidden="true"></span><span class="history-copy"><b>${escapeHTML(responseTitle(request || response, fallback))}</b><small>${updateCount} PUBLIC ${updateCount === 1 ? "UPDATE" : "UPDATES"}</small></span><span class="history-meta"><strong class="${turn.status}">${statusLabel}</strong><time>${escapeHTML(formatDateTime(turn.completedAt ?? turn.startedAt))}</time></span></summary><div class="history-body">${requests}${updates}${delivery}</div></details>`;
}

function row(label: string, value: unknown, tone = ""): string {
  return `<div class="datum"><span>${escapeHTML(label)}</span><strong class="${tone}">${escapeHTML(value)}</strong></div>`;
}

export function renderCodexStatusDocument(input: {
  task: CodexStatusTask;
  repository: CodexRepositoryStatus;
  turn?: CodexStatusTurn;
  history?: CodexStatusHistoryTurn[];
  host: string;
  renderedAt?: Date;
}): string {
  const { task, repository, turn } = input;
  const renderedAt = input.renderedAt ?? new Date();
  const updates = turn?.updates ?? [];
  const history = (input.history ?? [])
    .filter((item) => item.id !== turn?.turnId)
    .slice(0, 6);
  const files = repository.files.length > 0
    ? repository.files.map((file) => `<li><span class="file-state">${escapeHTML(file.state)}</span><code>${escapeHTML(file.path)}</code><span class="delta"><b>+${file.additions ?? 0}</b> <i>−${file.deletions ?? 0}</i></span></li>`).join("")
    : `<li class="quiet">${repository.unavailableReason ? escapeHTML(repository.unavailableReason) : "Working tree clean"}</li>`;
  const activity = updates.length > 0
    ? updates.map((update) => `<li><time>${escapeHTML(formatTime(update.timestamp))}</time><span class="activity-kind ${update.kind}">${update.kind === "commentary" ? "AGENT NOTE" : "TOOL"}</span><p>${escapeHTML(update.text)}</p></li>`).join("")
    : `<li class="quiet">${turn ? "Waiting for the next public update" : "No recent turn receipt for this task"}</li>`;
  const response = turn?.response
    ? `<section><div class="section-title"><span>PREVIOUS RESPONSE</span><span>${escapeHTML(formatTime(turn.updatedAt))}</span></div><div class="response">${escapeHTML(turn.response)}</div></section>`
    : "";
  const failure = turn?.error
    ? `<section class="failure"><div class="section-title"><span>ATTENTION</span><span>${escapeHTML(turn.code ?? "ERROR")}</span></div><p>${escapeHTML(turn.error)}</p>${turn.hint ? `<small>${escapeHTML(turn.hint)}</small>` : ""}</section>`
    : "";
  const approval = turn?.approval
    ? `<section><div class="section-title"><span>REMOTE APPROVAL</span><span>WAITING</span></div><div class="response"><strong>${escapeHTML(turn.approval.title)}</strong><br>${escapeHTML(turn.approval.detail)}<br><small>Use the Talkie controls above to approve or decline.</small></div></section>`
    : "";
  const historyDocument = history.length > 0
    ? history.map(renderHistoryTurn).join("")
    : `<p class="quiet">No completed turns are available yet.</p>`;

  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src 'none'; connect-src 'none'; form-action 'none'; base-uri 'none'"><style>
:root{color-scheme:dark light;--bg:#0b1320;--raised:#121e30;--ink:#f2f6fc;--secondary:#bbc8d8;--faint:#91a4ba;--rule:rgba(236,242,250,.10);--rule-strong:rgba(236,242,250,.18);--accent:#78a6ff;--success:#78a6ff;--red:#ee9184}*{box-sizing:border-box}html,body{margin:0;background:var(--bg);color:var(--ink);font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif}body{padding:4px 18px 36px}code,strong,.datum span,.section-title,.activity-kind,time,.file-state,.delta,footer{font-family:"SFMono-Regular",ui-monospace,monospace}.mast{padding:18px 0 15px;border-bottom:1px solid var(--rule-strong)}.eyebrow{display:flex;justify-content:space-between;color:var(--accent);font:600 10px/1.3 "SFMono-Regular",monospace;letter-spacing:.15em}.mast h1{font-size:25px;line-height:1.12;margin:14px 0 9px;letter-spacing:-.035em}.mast p{margin:0;color:var(--faint);font:11px/1.45 "SFMono-Regular",monospace;overflow-wrap:anywhere}.ribbon{display:grid;grid-template-columns:1fr 1fr;border-bottom:1px solid var(--rule-strong)}.datum{min-width:0;padding:12px 0;border-bottom:1px solid var(--rule)}.datum:nth-child(odd){padding-right:14px;border-right:1px solid var(--rule)}.datum:nth-child(even){padding-left:14px}.datum:nth-last-child(-n+2){border-bottom:0}.datum span{display:block;color:var(--faint);font-size:8px;letter-spacing:.13em;margin-bottom:5px}.datum strong{display:block;color:var(--secondary);font-size:11px;font-weight:500;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.datum strong.good{color:var(--success)}.datum strong.hot{color:var(--accent)}section{border-bottom:1px solid var(--rule-strong)}.section-title{display:flex;justify-content:space-between;padding:13px 0 9px;color:var(--faint);font-size:8px;letter-spacing:.15em}ul{list-style:none;padding:0;margin:0 0 8px}ul.files li{display:grid;grid-template-columns:22px minmax(0,1fr) auto;gap:8px;align-items:baseline;padding:7px 0;border-top:1px solid var(--rule);font-size:10px}.file-state{color:var(--accent)}.files code{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:var(--secondary)}.delta{color:var(--faint);font-size:9px}.delta b{color:var(--success);font-weight:500}.delta i{color:var(--red);font-style:normal}.activity li{display:grid;grid-template-columns:38px 74px minmax(0,1fr);gap:8px;padding:9px 0;border-top:1px solid var(--rule);align-items:start}.activity li.quiet{display:block}.activity time{color:var(--faint);font-size:8px}.activity-kind{font-size:8px;color:var(--accent);letter-spacing:.08em}.activity-kind.commentary{color:var(--success)}.activity p{margin:-2px 0 0;color:var(--secondary);font-size:11px;line-height:1.42;white-space:pre-wrap;overflow-wrap:anywhere}.quiet{color:var(--faint);font:10px/1.45 "SFMono-Regular",monospace;padding:12px 0}.response{color:var(--secondary);font-size:12px;line-height:1.52;white-space:pre-wrap;padding:2px 0 16px}.failure{color:var(--red)}.failure p{font:11px/1.45 "SFMono-Regular",monospace;margin:0 0 8px}.failure small{display:block;color:var(--secondary);font-size:10px;margin-bottom:14px}.history-intro{margin:0 0 10px;color:var(--faint);font-size:10px;line-height:1.45}.history-turn{border-top:1px solid var(--rule)}.history-turn summary{position:relative;display:grid;grid-template-columns:18px minmax(0,1fr) auto;gap:8px;align-items:start;padding:12px 0;cursor:pointer;list-style:none}.history-turn summary::-webkit-details-marker{display:none}.history-turn summary:focus-visible{outline:2px solid var(--accent);outline-offset:4px}.history-marker::before{content:"+";display:block;color:var(--accent);font:13px/1 "SFMono-Regular",monospace}.history-turn[open] .history-marker::before{content:"−"}.history-copy{min-width:0}.history-copy b{display:block;color:var(--secondary);font:500 11px/1.4 -apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.history-copy small{display:block;margin-top:4px;color:var(--faint);font:8px/1.3 "SFMono-Regular",monospace;letter-spacing:.09em}.history-meta{text-align:right}.history-meta strong{display:block;color:var(--success);font-size:8px;letter-spacing:.08em}.history-meta strong.failed,.history-meta strong.aborted{color:var(--red)}.history-meta time{display:block;margin-top:4px;color:var(--faint);font-size:8px;white-space:nowrap}.history-body{padding:4px 0 12px 26px}.history-request{margin:0 0 10px;border-left:2px solid var(--accent);padding:1px 0 1px 10px}.history-request span{color:var(--accent);font:8px/1.3 "SFMono-Regular",monospace;letter-spacing:.12em}.history-request p{margin:5px 0 0;color:var(--ink);font-size:11px;line-height:1.48;white-space:pre-wrap;overflow-wrap:anywhere}.history-activity{margin-bottom:2px}.history-empty{margin:0 0 10px;color:var(--faint);font:10px/1.45 "SFMono-Regular",monospace}.history-delivery{border-top:1px solid var(--rule);padding-top:10px}.history-delivery span{color:var(--faint);font:8px/1.3 "SFMono-Regular",monospace;letter-spacing:.12em}.history-delivery p{margin:6px 0 0;color:var(--secondary);font-size:11px;line-height:1.5;white-space:pre-wrap;overflow-wrap:anywhere}.history-error p{color:var(--red)}footer{padding-top:14px;color:var(--faint);font-size:8px;line-height:1.5;letter-spacing:.09em;text-transform:uppercase}@media(max-width:380px){.history-turn summary{grid-template-columns:16px minmax(0,1fr)}.history-meta{grid-column:2;text-align:left;display:flex;gap:8px;align-items:baseline}.history-meta time{margin-top:0}}@media(prefers-color-scheme:light){:root{--bg:#eef2f6;--raised:#fafbfd;--ink:#162330;--secondary:#42566b;--faint:#5b6f84;--rule:rgba(22,35,48,.12);--rule-strong:rgba(22,35,48,.22);--accent:#2f63d8;--success:#2f63d8;--red:#b14c43}}
</style></head><body>
<header class="mast"><div class="eyebrow"><span>CODEX / TASK STATUS</span><span>${escapeHTML(turn?.status?.toUpperCase() ?? "READY")}</span></div><h1>${escapeHTML(task.title)}</h1><p>${escapeHTML(task.project)} · ${escapeHTML(task.cwd)}</p></header>
<div class="ribbon">${row("HOST", input.host)}${row("TASK", task.id)}${row("BRANCH", repository.branch, "hot")}${row("HEAD", `${repository.head} · ${repository.subject}`)}${row("WORKTREE", repository.clean ? "CLEAN" : `${repository.files.length} FILES · +${repository.additions} −${repository.deletions}`, repository.clean ? "good" : "hot")}${row("DELIVERY", turn?.delivery ?? turn?.status ?? "IDLE", turn?.error ? "" : "good")}${row("MODE", turn?.mode ?? "—")}${row("UPSTREAM", repository.upstream ? `${repository.upstream} · ↑${repository.ahead ?? 0} ↓${repository.behind ?? 0}` : repository.origin ?? "—")}</div>
${approval}${failure}<section><div class="section-title"><span>LIVE ACTIVITY</span><span>${updates.length} PUBLIC UPDATES</span></div><ul class="activity">${activity}</ul></section>${response}
<section><div class="section-title"><span>WORK HISTORY</span><span>${history.length} RECENT TURNS</span></div><p class="history-intro">Public agent notes, completed actions, and delivered responses. Private reasoning is never included.</p>${historyDocument}</section>
<section><div class="section-title"><span>CHANGED FILES</span><span>${repository.files.length}</span></div><ul class="files">${files}</ul></section>
<footer>READ ONLY · HOST RENDERED ${escapeHTML(renderedAt.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }))}<br>${escapeHTML(repository.root)}</footer>
</body></html>`;
}
