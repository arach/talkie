import { log } from "../../log";
import { talkieServerFetch } from "../talkie-local-client";
import { proxyError, serverError, serviceUnavailable } from "./responses";

const TALKIESERVER_PORT = 8766;
const TALKIESERVER_URL = `http://127.0.0.1:${TALKIESERVER_PORT}`;

export interface TerminalAccessResponse {
  ok: boolean;
  payload?: string;
  label?: string;
  host?: string;
  alternateHosts?: string[];
  fingerprint?: string;
  error?: string;
}

export async function terminalAccessRoute(): Promise<TerminalAccessResponse | Response> {
  if (!(await checkTalkieServer())) {
    return serviceUnavailable("Talkie not running", "Start Talkie.app to prepare terminal access");
  }

  try {
    const response = await talkieServerFetch(`${TALKIESERVER_URL}/terminal/access`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({}),
      signal: AbortSignal.timeout(120_000),
    });

    if (!response.ok) {
      const errorText = await response.text();
      log.error(`Terminal access preparation failed (${response.status}): ${errorText}`);
      return proxyError(response.status, "Terminal access preparation failed", errorText);
    }

    return await response.json() as TerminalAccessResponse;
  } catch (error) {
    log.error(`Terminal access proxy failed: ${error}`);
    return serverError("Failed to prepare terminal access", String(error));
  }
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
