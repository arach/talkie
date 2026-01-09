/**
 * Device Management Routes
 *
 * GET    /devices          - List all paired devices
 * DELETE /devices/:id      - Remove a specific device
 * DELETE /devices          - Remove all devices (revoke all)
 */

import {
  getDeviceSummary,
  removeDevice,
  revokeAllDevices,
} from "../../devices/registry";
import { log } from "../../log";
import { notFound } from "./responses";

// ===== Types =====

export interface DeviceInfo {
  id: string;
  name: string;
  pairedAt: string;
  lastSeen: string | null;
  isExpired: boolean;
  daysUntilExpiry: number | null;
}

export interface DevicesResponse {
  total: number;
  active: number;
  expired: number;
  devices: DeviceInfo[];
}

export interface DeviceRemoveResponse {
  success: boolean;
  message: string;
}

export interface DevicesRevokeResponse {
  success: boolean;
  count: number;
  message: string;
}

// ===== Handlers =====

/**
 * GET /devices
 * List all paired devices with status info
 */
export async function devicesListRoute(): Promise<DevicesResponse> {
  const summary = await getDeviceSummary();

  log.info(`Devices: ${summary.active} active, ${summary.expired} expired`);

  return summary;
}

/**
 * DELETE /devices/:id
 * Remove a specific paired device
 */
export async function deviceRemoveRoute(deviceId: string): Promise<DeviceRemoveResponse | Response> {
  const removed = await removeDevice(deviceId);

  if (!removed) {
    return notFound("Device not found");
  }

  log.info(`Removed device: ${deviceId}`);

  return {
    success: true,
    message: "Device removed",
  };
}

/**
 * DELETE /devices
 * Revoke all paired devices
 */
export async function devicesRevokeAllRoute(): Promise<DevicesRevokeResponse> {
  const count = await revokeAllDevices();

  return {
    success: true,
    count,
    message: count > 0 ? `Revoked ${count} device(s)` : "No devices to revoke",
  };
}
