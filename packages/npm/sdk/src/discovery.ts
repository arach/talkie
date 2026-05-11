/**
 * Service discovery: resolve a service name to a port.
 *
 * 1. Try reading ~/.talkie/services.json (written by TalkieAgent on startup)
 * 2. Fall back to hardcoded default ports
 *
 * Optionally watches the file for changes and emits when services update.
 */

import { readFileSync, watch, type FSWatcher } from "fs";
import { SERVICES_JSON_PATH, SERVICE_PORTS, type ServiceName } from "./constants";
import type { ServicesFile, ServiceEntry } from "./types";
import { Emitter } from "./events";

interface DiscoveryEvents {
  change: { services: Partial<Record<ServiceName, ServiceEntry>> };
}

export class ServiceDiscovery extends Emitter<DiscoveryEvents> {
  private watcher: FSWatcher | null = null;
  private cached: ServicesFile | null = null;

  /** Read services.json and return the parsed result, or null if missing/invalid. */
  read(): ServicesFile | null {
    try {
      const raw = readFileSync(SERVICES_JSON_PATH, "utf-8");
      const parsed = JSON.parse(raw) as ServicesFile;
      if (parsed.version && parsed.services) {
        this.cached = parsed;
        return parsed;
      }
      return null;
    } catch {
      return null;
    }
  }

  /**
   * Resolve a service name to its connection info.
   * Returns the port (from discovery or default) and an optional serviceKey.
   */
  resolve(service: ServiceName): ServiceEntry {
    const file = this.cached ?? this.read();
    const entry = file?.services[service];

    if (entry?.port) {
      return entry;
    }

    // Fall back to hardcoded defaults — no serviceKey
    const defaultPort = SERVICE_PORTS[service];
    return { port: defaultPort };
  }

  /** Watch services.json for changes. Emits 'change' on update. */
  startWatching(): void {
    if (this.watcher) return;
    try {
      this.watcher = watch(SERVICES_JSON_PATH, () => {
        const file = this.read();
        if (file) {
          this.emit("change", { services: file.services });
        }
      });
    } catch {
      // File or directory doesn't exist yet — that's fine
    }
  }

  stopWatching(): void {
    this.watcher?.close();
    this.watcher = null;
  }
}
