/**
 * Lightweight auth handshake for client identification.
 *
 * This is NOT a security gate — it's a friendly "hello, I'm Hudson" so the
 * service knows who's connected. All access is granted in legacy mode (no auth).
 *
 * Three states:
 * - No serviceKey in discovery → legacy mode (skip register entirely)
 * - serviceKey present, server returns "Unknown method: register" → legacy mode
 * - serviceKey present, server handles register → authenticated (token stored)
 *
 * Down the road, the server can use granted capabilities to actually gate
 * access. For now it's purely informational.
 */

import type { WebSocketTransport } from "./transport";
import type { AuthState, Capability } from "./types";

export interface AuthOptions {
  serviceKey?: string;
  capabilities: Capability[];
  clientId: string;
}

/**
 * Attempt to register with the service. Returns the auth state.
 * Never throws — always degrades gracefully to legacy mode.
 */
export async function authenticate(
  transport: WebSocketTransport,
  options: AuthOptions,
): Promise<AuthState> {
  // No service key → nothing to register with, legacy mode
  if (!options.serviceKey) {
    return { mode: "legacy" };
  }

  try {
    const result = await transport.call("register", {
      serviceKey: options.serviceKey,
      capabilities: options.capabilities,
      clientId: options.clientId,
    });

    const sessionToken = result.sessionToken as string | undefined;
    const grantedCapabilities = result.grantedCapabilities as Capability[] | undefined;

    if (sessionToken) {
      return {
        mode: "authenticated",
        sessionToken,
        grantedCapabilities: grantedCapabilities ?? options.capabilities,
      };
    }

    // Server returned something but no token — treat as legacy
    return { mode: "legacy" };
  } catch (err) {
    // "Unknown method: register" → server doesn't support auth yet, that's fine
    // Any other error → also degrade gracefully, this is identification not security
    return { mode: "legacy" };
  }
}
