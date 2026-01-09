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
  port: number;
  protocol: string;
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

/**
 * POST /pair
 * iOS device requests pairing
 */
export async function pairRoute(body: PairRequest): Promise<PairResponse> {
  // Check if already paired
  if (await isDevicePaired(body.deviceId)) {
    return {
      status: "approved",
      message: "Device already paired",
    };
  }

  log.info(`Pairing request from: ${body.name} (${body.deviceId})`);

  // Add to pending pairings
  addPendingPairing(body.deviceId, body.name, body.publicKey);

  // Auto-approve for now (TODO: proper approval UI on Mac)
  const device = await approvePairing(body.deviceId);
  if (device) {
    log.info(`Auto-approved device: ${device.name}`);
    return {
      status: "approved",
      message: "Device paired successfully",
    };
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
export async function pairInfoRoute(hostname: string, port: number): Promise<PairInfoResponse> {
  const publicKey = await getPublicKey();

  return {
    publicKey,
    hostname,
    port,
    protocol: "talkie-bridge-v1",
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
