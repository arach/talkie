import { mkdir } from "node:fs/promises";
import { dirname } from "node:path";
import { SECURITY_EVENTS_FILE } from "../paths";
import { log } from "../log";

export type SecurityEventType =
  | "bridge_pair_payload_created"
  | "bridge_pair_requested"
  | "bridge_device_approved"
  | "ssh_terminal_payload_created"
  | "ssh_terminal_key_authorized"
  | "ssh_terminal_imported"
  | "ssh_terminal_connected";

export type SecurityEventSeverity = "info" | "notice" | "warning" | "critical";
export type SecurityEventSource = "cli" | "mac_app" | "bridge" | "ios";

export interface SecurityEvent {
  id: string;
  type: SecurityEventType;
  severity: SecurityEventSeverity;
  source: SecurityEventSource;
  title: string;
  message: string;
  createdAt: string;
  macName?: string;
  deviceId?: string;
  deviceName?: string;
  metadata?: Record<string, unknown>;
  acknowledgedBy: string[];
}

export interface CreateSecurityEventRequest {
  type?: SecurityEventType;
  severity?: SecurityEventSeverity;
  source?: SecurityEventSource;
  title?: string;
  message?: string;
  macName?: string;
  deviceId?: string;
  deviceName?: string;
  metadata?: Record<string, unknown>;
}

interface SecurityEventStore {
  events: SecurityEvent[];
}

const MAX_EVENTS = 200;
let storeMutationQueue: Promise<void> = Promise.resolve();

async function readStore(): Promise<SecurityEventStore> {
  try {
    const file = Bun.file(SECURITY_EVENTS_FILE);
    if (!(await file.exists())) {
      return { events: [] };
    }

    const data = await file.json() as Partial<SecurityEventStore>;
    return {
      events: Array.isArray(data.events) ? data.events : [],
    };
  } catch (error) {
    log.warn(`Failed to read security events: ${error}`);
    return { events: [] };
  }
}

async function writeStore(store: SecurityEventStore): Promise<void> {
  await mkdir(dirname(SECURITY_EVENTS_FILE), { recursive: true });
  await Bun.write(SECURITY_EVENTS_FILE, JSON.stringify({
    events: store.events.slice(-MAX_EVENTS),
  }, null, 2));
}

async function mutateStore<T>(
  mutation: (store: SecurityEventStore) => Promise<{ result: T; changed: boolean }> | { result: T; changed: boolean }
): Promise<T> {
  const operation = storeMutationQueue.then(async () => {
    const store = await readStore();
    const { result, changed } = await mutation(store);
    if (changed) {
      await writeStore(store);
    }
    return result;
  });

  storeMutationQueue = operation.then(
    () => undefined,
    () => undefined
  );

  return operation;
}

export async function createSecurityEvent(request: CreateSecurityEventRequest): Promise<SecurityEvent> {
  const now = new Date().toISOString();
  const event: SecurityEvent = {
    id: crypto.randomUUID(),
    type: request.type ?? "bridge_pair_payload_created",
    severity: request.severity ?? "notice",
    source: request.source ?? "bridge",
    title: (request.title ?? "Talkie security event").trim(),
    message: (request.message ?? "A Talkie security event occurred.").trim(),
    createdAt: now,
    macName: request.macName?.trim() || undefined,
    deviceId: request.deviceId?.trim() || undefined,
    deviceName: request.deviceName?.trim() || undefined,
    metadata: request.metadata,
    acknowledgedBy: [],
  };

  await mutateStore((store) => {
    store.events.push(event);
    return { result: event, changed: true };
  });
  log.info(`Security event recorded: ${event.type}`, event.title);
  return event;
}

export async function listSecurityEvents(options: {
  deviceId?: string;
  includeAcknowledged?: boolean;
  limit?: number;
} = {}): Promise<SecurityEvent[]> {
  const store = await readStore();
  let events = store.events;

  if (options.deviceId && !options.includeAcknowledged) {
    events = events.filter((event) => !event.acknowledgedBy.includes(options.deviceId!));
  }

  if (options.limit && options.limit > 0) {
    events = events.slice(-options.limit);
  }

  return [...events].reverse();
}

export async function acknowledgeSecurityEvent(eventId: string, deviceId: string): Promise<SecurityEvent | null> {
  const trimmedEventId = eventId.trim();
  const trimmedDeviceId = deviceId.trim();
  if (!trimmedEventId || !trimmedDeviceId) return null;

  return mutateStore((store) => {
    const event = store.events.find((candidate) => candidate.id === trimmedEventId);
    if (!event) return { result: null, changed: false };

    if (!event.acknowledgedBy.includes(trimmedDeviceId)) {
      event.acknowledgedBy.push(trimmedDeviceId);
      return { result: event, changed: true };
    }

    return { result: event, changed: false };
  });
}
