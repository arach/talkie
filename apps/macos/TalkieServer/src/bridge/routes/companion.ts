import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { log } from "../../log";
import { listSecurityEvents, type SecurityEvent } from "../../security/events";
import { badRequest, proxyError, serverError, serviceUnavailable } from "./responses";

export interface CompanionStateResponse {
  isAvailable: boolean;
  requestedSurface: "normal" | "shortcut";
  shortcutSlots: string[];
  shortcutPages?: CompanionShortcutPage[];
  shortcutStates: CompanionShortcutRuntimeState[];
  recentResults: CompanionShortcutRecentResult[];
  appSwitcherApps: CompanionAppSwitcherApp[];
  securityEvents: SecurityEvent[];
  publishRevision: number;
  lastPublishedAt?: string;
}

export interface CompanionShortcutPage {
  id: string;
  title: string;
  shortcutSlots: string[];
}

interface CompanionStateOptions {
  deviceId?: string;
  deviceClass?: "ipad" | "iphone";
}

interface CompanionRuntimeState {
  shortcutStates: CompanionShortcutRuntimeState[];
  recentResults: CompanionShortcutRecentResult[];
  appSwitcherApps: CompanionAppSwitcherApp[];
}

export interface CompanionTriggerRequest {
  shortcutId?: string;
}

export interface CompanionPasteImageRequest {
  imageBase64?: string;
  mimeType?: string;
  autoPaste?: boolean;
}

export interface CompanionShortcutRuntimeState {
  shortcutId: string;
  phase: "preparing" | "recording" | "processing";
  canStop: boolean;
  detail?: string;
  elapsedSeconds?: number;
  signalLevel?: number;
}

export interface CompanionShortcutRecentResult {
  shortcutId: string;
  resultText: string;
  completedAt: string;
}

export interface CompanionAppSwitcherApp {
  processIdentifier: number;
  bundleIdentifier?: string;
  displayName: string;
  isFrontmost: boolean;
  iconPNGBase64?: string;
}

export interface CompanionTriggerResponse {
  ok: boolean;
  handledShortcutId?: string;
  message?: string;
  error?: string;
  runtimeState?: CompanionShortcutRuntimeState;
}

export interface CompanionActivateAppRequest {
  processIdentifier?: number;
  bundleIdentifier?: string;
}

interface TalkieSettingsFile {
  bridge?: {
    shortcutBoardEnabled?: boolean;
    companionShortcutModeEnabled?: boolean;
    companionShortcutSlots?: string[];
  };
  devices?: {
    publishRevision?: number;
    lastPublishedAt?: string;
    defaults?: {
      shortcutBoard?: ShortcutBoard;
    };
    classes?: Partial<Record<"ipad" | "iphone", DeviceClassSettings>>;
    overrides?: Record<string, DeviceOverrideSettings>;
  };
}

interface ShortcutBoard {
  version?: number;
  spaces?: ShortcutBoardSpace[];
}

interface ShortcutBoardSpace {
  id?: string;
  title?: string;
  tiles?: ShortcutBoardTile[];
}

interface ShortcutBoardTile {
  id?: string;
  legacySlotID?: string;
}

interface ShortcutBoardOverride {
  spaceOverrides?: ShortcutBoardSpaceOverride[];
}

interface ShortcutBoardSpaceOverride {
  id?: string;
  title?: string;
  tileOrder?: string[];
  tileOverrides?: ShortcutBoardTileOverride[];
}

interface ShortcutBoardTileOverride {
  id?: string;
  legacySlotID?: string;
}

interface DeviceClassSettings {
  shortcutBoardOverride?: ShortcutBoardOverride;
}

interface DeviceOverrideSettings {
  displayName?: string;
  platform?: "ipad" | "iphone";
  shortcutBoardOverride?: ShortcutBoardOverride;
}

const appSupportDirectoryNames = [
  "Talkie.dev",
  "Talkie.staging",
  "Talkie",
];

const settingsFilePaths = appSupportDirectoryNames.map((directoryName) =>
  path.join(
    process.env.HOME ?? "",
    "Library",
    "Application Support",
    directoryName,
    "settings",
    "config.json"
  )
);

const runtimeSignalFilePaths = appSupportDirectoryNames.map((directoryName) =>
  path.join(
    process.env.HOME ?? "",
    "Library",
    "Application Support",
    directoryName,
    "Bridge",
    ".config",
    "companion-runtime.signal"
  )
);

const TALKIESERVER_PORT = 8766;
const TALKIESERVER_URL = `http://127.0.0.1:${TALKIESERVER_PORT}`;
const TALKIEAGENT_PORT = 8767;
const TALKIEAGENT_URL = `http://127.0.0.1:${TALKIEAGENT_PORT}`;

export async function companionStateRoute(
  options: CompanionStateOptions = {}
): Promise<CompanionStateResponse> {
  const settings = readSettingsFile();
  const runtimeState = await readRuntimeState();
  const securityEvents = options.deviceId
    ? await listSecurityEvents({ deviceId: options.deviceId, limit: 5 })
    : [];

  return {
    isAvailable: true,
    requestedSurface: readShortcutModeEnabled(settings) ? "shortcut" : "normal",
    shortcutSlots: readShortcutSlots(options, settings),
    shortcutPages: readShortcutPages(options, settings),
    shortcutStates: runtimeState.shortcutStates,
    recentResults: runtimeState.recentResults,
    appSwitcherApps: runtimeState.appSwitcherApps,
    securityEvents,
    publishRevision: settings?.devices?.publishRevision ?? 0,
    lastPublishedAt: settings?.devices?.lastPublishedAt,
  };
}

export async function companionTriggerRoute(
  body: CompanionTriggerRequest
): Promise<CompanionTriggerResponse | Response> {
  const shortcutId = typeof body.shortcutId === "string" ? body.shortcutId.trim() : "";
  if (!shortcutId) {
    return badRequest("shortcutId is required");
  }

  const agentResult = await tryAgentTrigger(shortcutId);
  if (agentResult.kind === "handled") {
    return agentResult.response;
  }

  if (!(await checkTalkieServer())) {
    return serviceUnavailable(
      "Talkie not running",
      "Start Talkie.app to enable companion shortcuts, or try an agent-owned shortcut again after TalkieAgent is ready"
    );
  }

  try {
    const response = await fetch(`${TALKIESERVER_URL}/companion/trigger`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ shortcutId }),
      signal: AbortSignal.timeout(5000),
    });

    if (!response.ok) {
      const errorText = await response.text();
      log.error(`Companion trigger failed (${response.status}): ${errorText}`);
      return proxyError(response.status, "Companion trigger failed", errorText);
    }

    return await response.json() as CompanionTriggerResponse;
  } catch (error) {
    log.error(`Companion trigger proxy failed: ${error}`);
    return serverError("Failed to trigger companion shortcut", String(error));
  }
}

type AgentTriggerOutcome =
  | { kind: "handled"; response: CompanionTriggerResponse }
  | { kind: "unhandled" };

async function tryAgentTrigger(shortcutId: string): Promise<AgentTriggerOutcome> {
  try {
    const response = await fetch(`${TALKIEAGENT_URL}/v1/agent/companion/trigger`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ shortcutId }),
      signal: AbortSignal.timeout(5000),
    });

    if (response.ok) {
      return {
        kind: "handled",
        response: await response.json() as CompanionTriggerResponse,
      };
    }

    if (response.status === 404) {
      return { kind: "unhandled" };
    }

    const errorText = await response.text().catch(() => "");
    log.warn(`Agent companion trigger returned ${response.status}: ${errorText}`);
    return { kind: "unhandled" };
  } catch (error) {
    log.debug(`Agent companion trigger unavailable, falling back to Talkie.app: ${error}`);
    return { kind: "unhandled" };
  }
}

export async function companionActivateAppRoute(
  body: CompanionActivateAppRequest
): Promise<CompanionTriggerResponse | Response> {
  const processIdentifier = typeof body.processIdentifier === "number"
    ? body.processIdentifier
    : undefined;
  const bundleIdentifier = typeof body.bundleIdentifier === "string"
    ? body.bundleIdentifier.trim()
    : undefined;

  if (processIdentifier === undefined && !bundleIdentifier) {
    return badRequest("processIdentifier or bundleIdentifier is required");
  }

  if (!(await checkTalkieServer())) {
    return serviceUnavailable("Talkie not running", "Start Talkie.app to enable companion app switching");
  }

  try {
    const response = await fetch(`${TALKIESERVER_URL}/companion/activate-app`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ processIdentifier, bundleIdentifier }),
      signal: AbortSignal.timeout(5000),
    });

    if (!response.ok) {
      const errorText = await response.text();
      log.error(`Companion app activation failed (${response.status}): ${errorText}`);
      return proxyError(response.status, "Companion app activation failed", errorText);
    }

    return await response.json() as CompanionTriggerResponse;
  } catch (error) {
    log.error(`Companion app activation proxy failed: ${error}`);
    return serverError("Failed to activate companion app", String(error));
  }
}

export interface CompanionTrackpadRequest {
  event: "move" | "click" | "rightClick" | "scroll" | "mouseDown" | "mouseUp" | "drag";
  dx?: number;
  dy?: number;
}

export async function companionTrackpadRoute(
  body: CompanionTrackpadRequest
): Promise<{ ok: boolean } | Response> {
  if (!body.event) {
    return badRequest("event is required");
  }

  if (!(await checkTalkieServer())) {
    return serviceUnavailable("Talkie not running", "Start Talkie.app to enable trackpad");
  }

  try {
    const response = await fetch(`${TALKIESERVER_URL}/companion/trackpad`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(2000),
    });

    if (!response.ok) {
      const errorText = await response.text();
      return proxyError(response.status, "Trackpad event failed", errorText);
    }

    return await response.json() as { ok: boolean };
  } catch (error) {
    return serverError("Failed to send trackpad event", String(error));
  }
}

export async function companionPasteImageRoute(
  body: CompanionPasteImageRequest
): Promise<CompanionTriggerResponse | Response> {
  const imageBase64 = typeof body.imageBase64 === "string" ? body.imageBase64.trim() : "";
  if (!imageBase64) {
    return badRequest("imageBase64 is required");
  }

  if (!(await checkTalkieServer())) {
    return serviceUnavailable("Talkie not running", "Start Talkie.app to paste images from your companion device");
  }

  try {
    const response = await fetch(`${TALKIESERVER_URL}/companion/paste-image`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        imageBase64,
        mimeType: body.mimeType,
        autoPaste: body.autoPaste ?? true,
      }),
      signal: AbortSignal.timeout(15000),
    });

    if (!response.ok) {
      const errorText = await response.text();
      log.error(`Companion paste image failed (${response.status}): ${errorText}`);
      return proxyError(response.status, "Companion image paste failed", errorText);
    }

    return await response.json() as CompanionTriggerResponse;
  } catch (error) {
    log.error(`Companion paste image proxy failed: ${error}`);
    return serverError("Failed to paste image from companion device", String(error));
  }
}

function readSettingsFile(): TalkieSettingsFile | null {
  const settingsFilePath = resolveSettingsFilePath();
  if (!settingsFilePath) {
    return null;
  }

  try {
    const raw = readFileSync(settingsFilePath, "utf8");
    return JSON.parse(raw) as TalkieSettingsFile;
  } catch {
    return null;
  }
}

function readShortcutModeEnabled(settings: TalkieSettingsFile | null): boolean {
  if (!settings) {
    return false;
  }

  return settings.bridge?.shortcutBoardEnabled === true || settings.bridge?.companionShortcutModeEnabled === true;
}

function readShortcutSlots(options: CompanionStateOptions, settings: TalkieSettingsFile | null): string[] {
  const shortcutPages = readShortcutPages(options, settings);
  const talkiePage = shortcutPages.find((page) => page.id === "talkie") ?? shortcutPages[0];
  if (talkiePage) {
    return talkiePage.shortcutSlots;
  }

  const fallback = defaultShortcutSlots();
  if (!settings) {
    return fallback;
  }

  const resolvedSlots = resolveBoardShortcutSlots(settings, options);
  if (resolvedSlots.some((slot) => slot.length > 0)) {
    return resolvedSlots;
  }

  const slots = settings.bridge?.companionShortcutSlots;
  if (!Array.isArray(slots)) {
    return fallback;
  }

  const normalized = slots.slice(0, 16).map((slot) => typeof slot === "string" ? slot : "");
  while (normalized.length < 16) {
    normalized.push("");
  }
  return normalized;
}

function readShortcutPages(
  options: CompanionStateOptions,
  settings: TalkieSettingsFile | null
): CompanionShortcutPage[] {
  if (!settings) {
    return defaultShortcutPages();
  }

  const resolvedPages = resolveBoardShortcutPages(settings, options);
  if (resolvedPages.length > 0) {
    return mergeDefaultPages(resolvedPages);
  }

  return defaultShortcutPages();
}

function resolveBoardShortcutSlots(
  settings: TalkieSettingsFile,
  options: CompanionStateOptions
): string[] {
  const baseBoard = settings.devices?.defaults?.shortcutBoard;
  if (!baseBoard) {
    return [];
  }

  let resolved = cloneBoard(baseBoard);

  if (options.deviceClass) {
    const classOverride = settings.devices?.classes?.[options.deviceClass]?.shortcutBoardOverride;
    if (classOverride) {
      resolved = applyBoardOverride(resolved, classOverride);
    }
  }

  if (options.deviceId) {
    const deviceOverride = settings.devices?.overrides?.[options.deviceId]?.shortcutBoardOverride;
    if (deviceOverride) {
      resolved = applyBoardOverride(resolved, deviceOverride);
    }
  }

  return shortcutSlotsFromBoard(resolved);
}

function resolveBoardShortcutPages(
  settings: TalkieSettingsFile,
  options: CompanionStateOptions
): CompanionShortcutPage[] {
  const baseBoard = settings.devices?.defaults?.shortcutBoard;
  if (!baseBoard) {
    return [];
  }

  let resolved = cloneBoard(baseBoard);

  if (options.deviceClass) {
    const classOverride = settings.devices?.classes?.[options.deviceClass]?.shortcutBoardOverride;
    if (classOverride) {
      resolved = applyBoardOverride(resolved, classOverride);
    }
  }

  if (options.deviceId) {
    const deviceOverride = settings.devices?.overrides?.[options.deviceId]?.shortcutBoardOverride;
    if (deviceOverride) {
      resolved = applyBoardOverride(resolved, deviceOverride);
    }
  }

  return shortcutPagesFromBoard(resolved);
}

function cloneBoard(board: ShortcutBoard): ShortcutBoard {
  return JSON.parse(JSON.stringify(board)) as ShortcutBoard;
}

function applyBoardOverride(board: ShortcutBoard, override: ShortcutBoardOverride): ShortcutBoard {
  const spaces = Array.isArray(board.spaces) ? board.spaces : [];

  for (const spaceOverride of override.spaceOverrides ?? []) {
    if (!spaceOverride?.id) continue;
    const space = spaces.find((candidate) => candidate.id === spaceOverride.id);
    if (!space) continue;

    if (typeof spaceOverride.title === "string" && spaceOverride.title.length > 0) {
      space.title = spaceOverride.title;
    }

    if (Array.isArray(space.tiles)) {
      for (const tileOverride of spaceOverride.tileOverrides ?? []) {
        if (!tileOverride?.id) continue;
        const tile = space.tiles.find((candidate) => candidate.id === tileOverride.id);
        if (!tile) continue;
        if (typeof tileOverride.legacySlotID === "string") {
          tile.legacySlotID = tileOverride.legacySlotID;
        }
      }
    }

    if (Array.isArray(spaceOverride.tileOrder) && Array.isArray(space.tiles) && spaceOverride.tileOrder.length === space.tiles.length) {
      const tileMap = new Map(space.tiles.map((tile) => [tile.id, tile] as const));
      const reordered = spaceOverride.tileOrder
        .map((tileId) => tileMap.get(tileId))
        .filter((tile): tile is ShortcutBoardTile => Boolean(tile));
      if (reordered.length === space.tiles.length) {
        space.tiles = reordered;
      }
    }
  }

  return board;
}

function shortcutSlotsFromBoard(board: ShortcutBoard): string[] {
  const pages = shortcutPagesFromBoard(board);
  const talkiePage = pages.find((page) => page.id === "talkie") ?? pages[0];
  return talkiePage?.shortcutSlots ?? defaultShortcutSlots();
}

function shortcutPagesFromBoard(board: ShortcutBoard): CompanionShortcutPage[] {
  const spaces = Array.isArray(board.spaces) ? board.spaces : [];
  const pages = spaces
    .map((space) => shortcutPageFromSpace(space))
    .filter((page): page is CompanionShortcutPage => Boolean(page));

  return mergeDefaultPages(pages);
}

function shortcutPageFromSpace(space: ShortcutBoardSpace | undefined): CompanionShortcutPage | null {
  if (!space) {
    return null;
  }

  const title = typeof space.title === "string" && space.title.trim().length > 0
    ? space.title.trim()
    : defaultTitleForPage(space.id);
  const id = typeof space.id === "string" && space.id.trim().length > 0
    ? space.id.trim()
    : title.toLowerCase().replace(/\s+/g, "-");

  const tiles = Array.isArray(space.tiles) ? space.tiles : [];
  const shortcutSlots = tiles.slice(0, 16).map((tile) => resolveLegacySlotId(tile));
  while (shortcutSlots.length < 16) {
    shortcutSlots.push("");
  }

  if (!shortcutSlots.some((slot) => slot.length > 0)) {
    return null;
  }

  return { id, title, shortcutSlots };
}

function resolveLegacySlotId(tile: ShortcutBoardTile): string {
  if (typeof tile.legacySlotID === "string") {
    return tile.legacySlotID;
  }

  switch (tile.id) {
    case "memo-record":
      return "talkie-record";
    case "dictation":
      return "talkie-dictate";
    case "search":
      return "talkie-search";
    case "workflow-picker":
      return "mac-sessions";
    case "screenshot":
      return "mac-windows";
    case "open-claude":
      return "mac-claude";
    case "ssh":
      return "talkie-ssh";
    case "voice-command":
      return "talkie-settings";
    case "memos":
      return "talkie-memos";
    case "screen-record":
      return "talkie-keyboard";
    case "talkie-home":
    case "home":
      return "talkie-home";
    case "talkie-agent":
    case "agent":
      return "talkie-agent";
    case "talkie-pending":
    case "pending":
      return "talkie-pending";
    case "talkie-command":
    case "command":
      return "talkie-command";
    case "talkie-recent":
    case "recent":
      return "talkie-recent";
    case "talkie-devices":
    case "devices":
      return "talkie-devices";
    default:
      return "";
  }
}

function defaultShortcutSlots(): string[] {
  return defaultShortcutPages()[0]?.shortcutSlots ?? [];
}

function defaultShortcutPages(): CompanionShortcutPage[] {
  return [
    {
      id: "talkie",
      title: "Talkie",
      shortcutSlots: [
        "talkie-dictate",
        "talkie-record",
        "talkie-settings",
        "talkie-search",
        "mac-claude",
        "talkie-agent",
        "talkie-ssh",
        "mac-sessions",
        "mac-windows",
        "talkie-keyboard",
        "talkie-memos",
        "talkie-command",
        "talkie-pending",
        "talkie-recent",
        "talkie-home",
        "talkie-devices",
      ],
    },
    {
      id: "mac",
      title: "Mac",
      shortcutSlots: [
        "mac-windows",
        "talkie-keyboard",
        "iterm-dictate",
        "mac-sessions",
        "mac-claude",
        "talkie-agent",
        "talkie-ssh",
        "talkie-command",
        "talkie-search",
        "talkie-memos",
        "talkie-recent",
        "talkie-devices",
        "talkie-home",
        "talkie-pending",
        "",
        "",
      ],
    },
  ];
}

function mergeDefaultPages(pages: CompanionShortcutPage[]): CompanionShortcutPage[] {
  const merged = [...pages];
  const defaults = defaultShortcutPages();

  for (const page of defaults) {
    if (!merged.some((candidate) => candidate.id === page.id)) {
      merged.push(page);
    }
  }

  return merged.sort((lhs, rhs) => pageRank(lhs.id) - pageRank(rhs.id));
}

function pageRank(id: string): number {
  switch (id) {
    case "talkie":
      return 0;
    case "mac":
      return 1;
    default:
      return 10;
  }
}

function defaultTitleForPage(id?: string): string {
  switch (id) {
    case "talkie":
      return "Talkie";
    case "mac":
      return "Mac";
    default:
      return "Deck";
  }
}

export function resolveSettingsFilePath(): string | null {
  return settingsFilePaths.find((candidate) => existsSync(candidate)) ?? null;
}

export function resolveRuntimeSignalFilePaths(): string[] {
  return [...runtimeSignalFilePaths];
}

async function checkTalkieServer(): Promise<boolean> {
  try {
    const response = await fetch(`${TALKIESERVER_URL}/health`, {
      signal: AbortSignal.timeout(2000),
    });
    return response.ok;
  } catch {
    return false;
  }
}

async function readRuntimeState(): Promise<CompanionRuntimeState> {
  const [talkieState, agentState] = await Promise.all([
    readTalkieRuntimeState(),
    readAgentRuntimeState(),
  ]);

  const merged = mergeRuntimeStates(talkieState, agentState);
  if (agentState.shortcutStates.length > 0 || agentState.recentResults.length > 0) {
    log.debug(
      `Merged agent companion runtime: active=${agentState.shortcutStates.length} recent=${agentState.recentResults.length}`
    );
  }

  return merged;
}

async function readTalkieRuntimeState(): Promise<CompanionRuntimeState> {
  if (!(await checkTalkieServer())) {
    return emptyRuntimeState();
  }

  try {
    const response = await fetch(`${TALKIESERVER_URL}/companion/runtime-state`, {
      signal: AbortSignal.timeout(2000),
    });

    if (!response.ok) {
      return emptyRuntimeState();
    }

    return normalizeRuntimePayload(await response.json());
  } catch {
    return emptyRuntimeState();
  }
}

async function readAgentRuntimeState(): Promise<CompanionRuntimeState> {
  try {
    const response = await fetch(`${TALKIEAGENT_URL}/v1/agent/companion/runtime-state`, {
      signal: AbortSignal.timeout(2000),
    });

    if (!response.ok) {
      return emptyRuntimeState();
    }

    return normalizeRuntimePayload(await response.json());
  } catch (error) {
    log.debug(`Agent companion runtime unavailable: ${error}`);
    return emptyRuntimeState();
  }
}

function emptyRuntimeState(): CompanionRuntimeState {
  return { shortcutStates: [], recentResults: [], appSwitcherApps: [] };
}

function normalizeRuntimePayload(payload: unknown): CompanionRuntimeState {
  const candidate = payload as Partial<CompanionRuntimeState> | undefined;
  return {
    shortcutStates: Array.isArray(candidate?.shortcutStates) ? candidate.shortcutStates : [],
    recentResults: Array.isArray(candidate?.recentResults) ? candidate.recentResults : [],
    appSwitcherApps: Array.isArray(candidate?.appSwitcherApps) ? candidate.appSwitcherApps : [],
  };
}

function mergeRuntimeStates(
  talkieState: CompanionRuntimeState,
  agentState: CompanionRuntimeState
): CompanionRuntimeState {
  return {
    shortcutStates: dedupeShortcutStates([
      ...agentState.shortcutStates,
      ...talkieState.shortcutStates,
    ]),
    recentResults: dedupeRecentResults([
      ...agentState.recentResults,
      ...talkieState.recentResults,
    ]),
    appSwitcherApps: dedupeAppSwitcherApps([
      ...talkieState.appSwitcherApps,
      ...agentState.appSwitcherApps,
    ]),
  };
}

function dedupeShortcutStates(states: CompanionShortcutRuntimeState[]): CompanionShortcutRuntimeState[] {
  const byShortcut = new Map<string, CompanionShortcutRuntimeState>();
  for (const state of states) {
    if (typeof state.shortcutId !== "string" || !state.shortcutId) continue;
    if (!byShortcut.has(state.shortcutId)) {
      byShortcut.set(state.shortcutId, state);
    }
  }
  return [...byShortcut.values()];
}

function dedupeRecentResults(results: CompanionShortcutRecentResult[]): CompanionShortcutRecentResult[] {
  const byShortcut = new Map<string, CompanionShortcutRecentResult>();
  for (const result of results) {
    if (typeof result.shortcutId !== "string" || !result.shortcutId) continue;
    const existing = byShortcut.get(result.shortcutId);
    if (!existing || Date.parse(result.completedAt) >= Date.parse(existing.completedAt)) {
      byShortcut.set(result.shortcutId, result);
    }
  }
  return [...byShortcut.values()];
}

function dedupeAppSwitcherApps(apps: CompanionAppSwitcherApp[]): CompanionAppSwitcherApp[] {
  const byApp = new Map<string, CompanionAppSwitcherApp>();
  for (const app of apps) {
    const key = app.bundleIdentifier ?? `pid-${app.processIdentifier}`;
    if (!byApp.has(key)) {
      byApp.set(key, app);
    }
  }
  return [...byApp.values()];
}
