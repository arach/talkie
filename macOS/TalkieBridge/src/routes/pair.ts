/**
 * Device pairing endpoints
 * POST /pair - Request pairing from iOS
 * GET /pair/pending - List pending pairing requests (for Mac UI)
 * POST /pair/:deviceId/approve - Approve a pairing (from Mac UI)
 * POST /pair/:deviceId/reject - Reject a pairing (from Mac UI)
 * GET /pair/info - Get server public key for QR code
 */

import { getPublicKey } from "../crypto/store";
import {
  addPendingPairing,
  approvePairing,
  rejectPairing,
  getPendingPairings,
  isDevicePaired,
} from "../devices/registry";

interface PairRequest {
  deviceId: string;
  publicKey: string;
  name: string;
}

/**
 * POST /pair - iOS device requests pairing
 */
export async function pairRoute(req: Request): Promise<Response> {
  try {
    const body: PairRequest = await req.json();

    if (!body.deviceId || !body.publicKey || !body.name) {
      return Response.json(
        { error: "Missing required fields: deviceId, publicKey, name" },
        { status: 400 }
      );
    }

    // Check if already paired
    if (await isDevicePaired(body.deviceId)) {
      return Response.json({
        status: "approved",
        message: "Device already paired",
      });
    }

    console.log(`Pairing request from: ${body.name} (${body.deviceId})`);

    // Add to pending pairings
    addPendingPairing(body.deviceId, body.name, body.publicKey);

    // Auto-approve for now (TODO: proper approval UI on Mac)
    // In production, this would require user approval on Mac
    const device = await approvePairing(body.deviceId);
    if (device) {
      console.log(`✅ Auto-approved device: ${device.name}`);
      return Response.json({
        status: "approved",
        message: "Device paired successfully",
      });
    }

    return Response.json({
      status: "pending_approval",
      message: "Pairing request received. Approve on your Mac.",
    });
  } catch (error) {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 });
  }
}

/**
 * GET /pair/info - Get info for QR code
 */
export async function pairInfoRoute(
  req: Request,
  hostname: string
): Promise<Response> {
  const publicKey = await getPublicKey();

  return Response.json({
    publicKey,
    hostname,
    port: 8765,
    protocol: "talkie-bridge-v1",
  });
}

/**
 * GET /pair/pending - List pending pairing requests
 */
export async function pairPendingRoute(req: Request): Promise<Response> {
  const pending = getPendingPairings();

  return Response.json({
    pending: pending.map((p) => ({
      deviceId: p.id,
      name: p.name,
      requestedAt: p.requestedAt,
    })),
  });
}

/**
 * POST /pair/:deviceId/approve - Approve a pending pairing
 */
export async function pairApproveRoute(
  req: Request,
  deviceId: string
): Promise<Response> {
  const device = await approvePairing(deviceId);

  if (!device) {
    return Response.json(
      { error: "No pending pairing request for this device" },
      { status: 404 }
    );
  }

  console.log(`Approved pairing for: ${device.name} (${device.id})`);

  return Response.json({
    status: "approved",
    device: {
      id: device.id,
      name: device.name,
      pairedAt: device.pairedAt,
    },
  });
}

/**
 * POST /pair/:deviceId/reject - Reject a pending pairing
 */
export async function pairRejectRoute(
  req: Request,
  deviceId: string
): Promise<Response> {
  const rejected = rejectPairing(deviceId);

  if (!rejected) {
    return Response.json(
      { error: "No pending pairing request for this device" },
      { status: 404 }
    );
  }

  console.log(`Rejected pairing for device: ${deviceId}`);

  return Response.json({
    status: "rejected",
  });
}
