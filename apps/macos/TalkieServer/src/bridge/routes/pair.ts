/**
 * Device Pairing Routes
 *
 * POST /pair                    - Request pairing from iOS
 * GET  /pair/pending            - List pending pairing requests (for Mac UI)
 * POST /pair/:deviceId/approve  - Approve a pairing (from Mac UI)
 * POST /pair/:deviceId/reject   - Reject a pairing (from Mac UI)
 * GET  /pair/info               - Get server public key for QR code
 */

import { getPublicKey } from "../../crypto/store";
import {
  addPendingPairing,
  approvePairing,
  rejectPairing,
  getPendingPairings,
  isDevicePaired,
} from "../../devices/registry";
import { log } from "../../log";
import { createSecurityEvent } from "../../security/events";
import { notFound } from "./responses";

// ===== Types =====

export interface PairRequest {
  deviceId: string;
  publicKey: string;
  name: string;
}

export interface PairResponse {
  status: "approved" | "pending_approval";
  message: string;
}

export interface PairInfoResponse {
  publicKey: string;
  hostname: string;
  alternateHosts?: string[];
  port: number;
  protocol: string;
  mode: "pairing" | "nearby" | "local_dev";
  pairingReady: boolean;
}

export interface PendingPairing {
  deviceId: string;
  name: string;
  requestedAt: string;
}

export interface PairPendingResponse {
  pending: PendingPairing[];
}

export interface PairApproveResponse {
  status: "approved";
  device: {
    id: string;
    name: string;
    pairedAt: string;
  };
}

export interface PairRejectResponse {
  status: "rejected";
}

// ===== Handlers =====

// Auto-approve setting (can be disabled via --require-approval flag)
let autoApproveEnabled = true;

export function setAutoApprove(enabled: boolean): void {
  autoApproveEnabled = enabled;
  log.info(`Pairing auto-approve: ${enabled ? "enabled" : "disabled"}`);
}

export function isAutoApproveEnabled(): boolean {
  return autoApproveEnabled;
}

/**
 * POST /pair
 * iOS device requests pairing
 */
export async function pairRoute(body: PairRequest): Promise<PairResponse> {
  const alreadyPaired = await isDevicePaired(body.deviceId);
  if (alreadyPaired) {
    log.info(`Re-pairing request from: ${body.name} (${body.deviceId})`);
  } else {
    log.info(`Pairing request from: ${body.name} (${body.deviceId})`);
  }

  await createSecurityEvent({
    type: "bridge_pair_requested",
    severity: alreadyPaired ? "info" : "notice",
    source: "ios",
    title: alreadyPaired ? "Device refreshed Mac Bridge pairing" : "Device requested Mac Bridge pairing",
    message: `${body.name} requested access to this Mac Bridge.`,
    deviceId: body.deviceId,
    deviceName: body.name,
  });

  // Add to pending pairings
  addPendingPairing(body.deviceId, body.name, body.publicKey);

  // Auto-approve if enabled
  if (autoApproveEnabled) {
    const device = await approvePairing(body.deviceId);
    if (device) {
      log.info(`${alreadyPaired ? "Auto-updated" : "Auto-approved"} device: ${device.name}`);
      await createSecurityEvent({
        type: "bridge_device_approved",
        severity: alreadyPaired ? "info" : "notice",
        source: "bridge",
        title: alreadyPaired ? "Device Mac Bridge pairing refreshed" : "Device approved for Mac Bridge",
        message: `${device.name} can now control this Mac through Talkie Bridge.`,
        deviceId: device.id,
        deviceName: device.name,
      });
      return {
        status: "approved",
        message: alreadyPaired ? "Device pairing updated" : "Device paired successfully",
      };
    }
  } else {
    log.info(`${alreadyPaired ? "Re-pairing" : "Pairing"} pending approval for: ${body.name}`);
  }

  return {
    status: "pending_approval",
    message: "Pairing request received. Approve on your Mac.",
  };
}

/**
 * GET /pair/info
 * Get info for QR code
 */
export async function pairInfoRoute(
  hostname: string,
  alternateHosts: string[] | undefined,
  port: number,
  mode: "pairing" | "nearby" | "local_dev"
): Promise<PairInfoResponse> {
  const publicKey = await getPublicKey();

  return {
    publicKey,
    hostname,
    alternateHosts,
    port,
    protocol: "talkie-bridge-v1",
    mode,
    pairingReady: mode !== "local_dev",
  };
}

/**
 * GET /pair/pending
 * List pending pairing requests
 */
export function pairPendingRoute(): PairPendingResponse {
  const pending = getPendingPairings();

  return {
    pending: pending.map((p) => ({
      deviceId: p.id,
      name: p.name,
      requestedAt: p.requestedAt,
    })),
  };
}

/**
 * POST /pair/:deviceId/approve
 * Approve a pending pairing
 */
export async function pairApproveRoute(deviceId: string): Promise<PairApproveResponse | Response> {
  const device = await approvePairing(deviceId);

  if (!device) {
    return notFound("No pending pairing request for this device");
  }

  log.info(`Approved pairing for: ${device.name} (${device.id})`);
  await createSecurityEvent({
    type: "bridge_device_approved",
    severity: "notice",
    source: "mac_app",
    title: "Device approved for Mac Bridge",
    message: `${device.name} can now control this Mac through Talkie Bridge.`,
    deviceId: device.id,
    deviceName: device.name,
  });

  return {
    status: "approved",
    device: {
      id: device.id,
      name: device.name,
      pairedAt: device.pairedAt,
    },
  };
}

/**
 * POST /pair/:deviceId/reject
 * Reject a pending pairing
 */
export function pairRejectRoute(deviceId: string): PairRejectResponse | Response {
  const rejected = rejectPairing(deviceId);

  if (!rejected) {
    return notFound("No pending pairing request for this device");
  }

  log.info(`Rejected pairing for device: ${deviceId}`);

  return {
    status: "rejected",
  };
}
