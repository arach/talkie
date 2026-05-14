import { spawn, type ChildProcess } from "node:child_process";
import { existsSync } from "node:fs";

import { log } from "./log";

const DNS_SD_PATH = "/usr/bin/dns-sd";
const SERVICE_TYPE = "_talkie-bridge._tcp";
const SERVICE_DOMAIN = "local.";
const MAX_SERVICE_NAME_LENGTH = 63;
const MAX_TXT_VALUE_LENGTH = 180;

type BonjourMode = "pairing" | "nearby" | "local_dev";

interface BonjourAdvertisementConfig {
  name: string;
  hostname: string;
  port: number;
  mode: BonjourMode;
  route: string;
  capabilities: string[];
}

let activeAdvertisement: ChildProcess | undefined;

export function startBonjourAdvertisement(config: BonjourAdvertisementConfig): () => void {
  stopBonjourAdvertisement();

  if (process.platform !== "darwin") {
    log.warn("Bonjour advertiser unavailable: dns-sd is only available on macOS");
    return () => {};
  }

  if (!existsSync(DNS_SD_PATH)) {
    log.warn("Bonjour advertiser unavailable: /usr/bin/dns-sd was not found");
    return () => {};
  }

  const serviceName = sanitizeServiceName(config.name);
  const txtRecords = buildTXTRecords(config);
  const args = [
    "-R",
    serviceName,
    SERVICE_TYPE,
    SERVICE_DOMAIN,
    String(config.port),
    ...txtRecords,
  ];

  const child = spawn(DNS_SD_PATH, args, {
    stdio: ["ignore", "pipe", "pipe"],
  });
  activeAdvertisement = child;

  child.stdout?.setEncoding("utf8");
  child.stdout?.on("data", (data: string) => {
    for (const line of data.split(/\r?\n/).map((value) => value.trim()).filter(Boolean)) {
      log.debug(`Bonjour advertiser: ${line}`);
    }
  });

  child.stderr?.setEncoding("utf8");
  child.stderr?.on("data", (data: string) => {
    for (const line of data.split(/\r?\n/).map((value) => value.trim()).filter(Boolean)) {
      log.warn(`Bonjour advertiser: ${line}`);
    }
  });

  child.on("error", (error) => {
    if (activeAdvertisement === child) {
      activeAdvertisement = undefined;
    }
    log.warn(`Bonjour advertiser failed: ${error.message}`);
  });

  child.on("exit", (code, signal) => {
    if (activeAdvertisement === child) {
      activeAdvertisement = undefined;
    }

    if (code && code !== 0) {
      log.warn(`Bonjour advertiser exited with code ${code}`);
    } else if (signal && signal !== "SIGTERM") {
      log.warn(`Bonjour advertiser stopped by ${signal}`);
    } else {
      log.debug("Bonjour advertiser stopped");
    }
  });

  log.info(`Bonjour advertising "${serviceName}" on ${SERVICE_TYPE}:${config.port}`);
  return () => stopBonjourAdvertisement(child);
}

export function stopBonjourAdvertisement(child: ChildProcess | undefined = activeAdvertisement): void {
  if (!child) {
    return;
  }

  if (activeAdvertisement === child) {
    activeAdvertisement = undefined;
  }

  if (!child.killed) {
    child.kill("SIGTERM");
  }
}

function buildTXTRecords(config: BonjourAdvertisementConfig): string[] {
  return [
    txt("proto", "talkie-bridge-v1"),
    txt("mode", config.mode),
    txt("route", config.route),
    txt("host", config.hostname),
    txt("cap", config.capabilities.join(",")),
  ];
}

function txt(key: string, rawValue: string): string {
  const value = rawValue.trim().slice(0, MAX_TXT_VALUE_LENGTH);
  return `${key}=${value}`;
}

function sanitizeServiceName(rawName: string): string {
  const name = rawName
    .trim()
    .replace(/\s+/g, " ");

  if (!name) {
    return "Talkie Bridge";
  }

  return name.slice(0, MAX_SERVICE_NAME_LENGTH).trim();
}
