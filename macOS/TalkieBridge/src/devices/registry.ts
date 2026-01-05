/**
 * Device Registry
 *
 * Stores paired iOS devices and their public keys.
 * Devices are stored in ~/.talkie-bridge/devices.json
 *
 * Features:
 * - Manual revocation via removeDevice()
 * - Auto-expiration for devices not seen in DEVICE_EXPIRY_DAYS
 * - Clean slate via revokeAllDevices()
 */

import { deriveSharedKeyFromBase64, deriveAuthKeyFromBase64 } from "../crypto/keypair";
import { getOrCreateKeyPair } from "../crypto/store";
import { log } from "../log";

const DEVICES_FILE = `${process.env.HOME}/.talkie-bridge/devices.json`;

/** Devices not seen in this many days are considered expired */
const DEVICE_EXPIRY_DAYS = 30;

export interface PairedDevice {
  id: string;
  name: string;
  publicKey: string;
  pairedAt: string;
  lastSeen?: string;
}

export interface PendingPairing {
  id: string;
  name: string;
  publicKey: string;
  requestedAt: string;
}

// In-memory pending pairings (not persisted)
const pendingPairings = new Map<string, PendingPairing>();

/**
 * Load paired devices from disk
 */
export async function getDevices(): Promise<PairedDevice[]> {
  try {
    const file = Bun.file(DEVICES_FILE);
    if (!(await file.exists())) {
      return [];
    }
    const data = await file.json();
    return data.devices || [];
  } catch {
    return [];
  }
}

/**
 * Save devices to disk
 */
async function saveDevices(devices: PairedDevice[]): Promise<void> {
  await Bun.write(DEVICES_FILE, JSON.stringify({ devices }, null, 2));
}

/**
 * Add a pending pairing request
 */
export function addPendingPairing(
  id: string,
  name: string,
  publicKey: string
): PendingPairing {
  const pending: PendingPairing = {
    id,
    name,
    publicKey,
    requestedAt: new Date().toISOString(),
  };
  pendingPairings.set(id, pending);
  return pending;
}

/**
 * Get pending pairing by device ID
 */
export function getPendingPairing(id: string): PendingPairing | undefined {
  return pendingPairings.get(id);
}

/**
 * List all pending pairings
 */
export function getPendingPairings(): PendingPairing[] {
  return Array.from(pendingPairings.values());
}

/**
 * Approve a pending pairing
 */
export async function approvePairing(deviceId: string): Promise<PairedDevice | null> {
  const pending = pendingPairings.get(deviceId);
  if (!pending) {
    return null;
  }

  const devices = await getDevices();

  // Check if already paired
  const existing = devices.find((d) => d.id === deviceId);
  if (existing) {
    // Update existing device
    existing.publicKey = pending.publicKey;
    existing.pairedAt = new Date().toISOString();
    existing.name = pending.name;
    await saveDevices(devices);
    pendingPairings.delete(deviceId);
    return existing;
  }

  // Add new device
  const device: PairedDevice = {
    id: pending.id,
    name: pending.name,
    publicKey: pending.publicKey,
    pairedAt: new Date().toISOString(),
  };

  devices.push(device);
  await saveDevices(devices);
  pendingPairings.delete(deviceId);

  return device;
}

/**
 * Reject a pending pairing
 */
export function rejectPairing(deviceId: string): boolean {
  return pendingPairings.delete(deviceId);
}

/**
 * Remove a paired device
 */
export async function removeDevice(deviceId: string): Promise<boolean> {
  const devices = await getDevices();
  const index = devices.findIndex((d) => d.id === deviceId);
  if (index === -1) {
    return false;
  }
  devices.splice(index, 1);
  await saveDevices(devices);
  return true;
}

/**
 * Check if a device is paired
 */
export async function isDevicePaired(deviceId: string): Promise<boolean> {
  const devices = await getDevices();
  return devices.some((d) => d.id === deviceId);
}

/**
 * Get the shared key for a paired device
 * @deprecated Use getDeviceAuthKey or getDeviceEncryptionKey
 */
export async function getDeviceSharedKey(deviceId: string): Promise<CryptoKey | null> {
  const devices = await getDevices();
  const device = devices.find((d) => d.id === deviceId);
  if (!device) {
    return null;
  }

  const serverKeyPair = await getOrCreateKeyPair();
  return deriveSharedKeyFromBase64(serverKeyPair.privateKey, device.publicKey);
}

/**
 * Get the HMAC auth key for a paired device (for request signing)
 * Uses HKDF with info="talkie-bridge-auth"
 * Returns null for expired devices (must re-pair)
 */
export async function getDeviceAuthKey(deviceId: string): Promise<CryptoKey | null> {
  const devices = await getDevices();
  const device = devices.find((d) => d.id === deviceId);
  if (!device) {
    return null;
  }

  // Reject expired devices
  if (isDeviceExpired(device)) {
    log.warn(`Device ${deviceId} (${device.name}) has expired - must re-pair`);
    return null;
  }

  const serverKeyPair = await getOrCreateKeyPair();
  return deriveAuthKeyFromBase64(serverKeyPair.privateKey, device.publicKey);
}

/**
 * Update last seen time for a device
 */
export async function updateLastSeen(deviceId: string): Promise<void> {
  const devices = await getDevices();
  const device = devices.find((d) => d.id === deviceId);
  if (device) {
    device.lastSeen = new Date().toISOString();
    await saveDevices(devices);
  }
}

// MARK: - Device Expiration

/**
 * Check if a device is expired (not seen in DEVICE_EXPIRY_DAYS)
 */
export function isDeviceExpired(device: PairedDevice): boolean {
  if (!device.lastSeen) {
    // Never seen since pairing - use pairedAt
    const pairedAt = new Date(device.pairedAt).getTime();
    const expiryMs = DEVICE_EXPIRY_DAYS * 24 * 60 * 60 * 1000;
    return Date.now() - pairedAt > expiryMs;
  }

  const lastSeen = new Date(device.lastSeen).getTime();
  const expiryMs = DEVICE_EXPIRY_DAYS * 24 * 60 * 60 * 1000;
  return Date.now() - lastSeen > expiryMs;
}

/**
 * Get only active (non-expired) devices
 */
export async function getActiveDevices(): Promise<PairedDevice[]> {
  const devices = await getDevices();
  return devices.filter((d) => !isDeviceExpired(d));
}

/**
 * Remove all expired devices from storage
 * Call this periodically or on server start
 */
export async function pruneExpiredDevices(): Promise<number> {
  const devices = await getDevices();
  const active = devices.filter((d) => !isDeviceExpired(d));
  const pruned = devices.length - active.length;

  if (pruned > 0) {
    await saveDevices(active);
    log.info(`Pruned ${pruned} expired device(s)`);
  }

  return pruned;
}

// MARK: - Revocation

/**
 * Revoke all paired devices (clean slate)
 * Returns number of devices revoked
 */
export async function revokeAllDevices(): Promise<number> {
  const devices = await getDevices();
  const count = devices.length;

  if (count > 0) {
    await saveDevices([]);
    log.info(`Revoked all ${count} paired device(s)`);
  }

  return count;
}

/**
 * Get device summary for management UI
 */
export async function getDeviceSummary(): Promise<{
  total: number;
  active: number;
  expired: number;
  devices: Array<{
    id: string;
    name: string;
    pairedAt: string;
    lastSeen: string | null;
    isExpired: boolean;
    daysUntilExpiry: number | null;
  }>;
}> {
  const devices = await getDevices();

  const summary = devices.map((d) => {
    const expired = isDeviceExpired(d);
    let daysUntilExpiry: number | null = null;

    if (!expired) {
      const lastActivity = d.lastSeen ? new Date(d.lastSeen) : new Date(d.pairedAt);
      const expiryDate = new Date(lastActivity.getTime() + DEVICE_EXPIRY_DAYS * 24 * 60 * 60 * 1000);
      daysUntilExpiry = Math.ceil((expiryDate.getTime() - Date.now()) / (24 * 60 * 60 * 1000));
    }

    return {
      id: d.id,
      name: d.name,
      pairedAt: d.pairedAt,
      lastSeen: d.lastSeen ?? null,
      isExpired: expired,
      daysUntilExpiry,
    };
  });

  return {
    total: devices.length,
    active: summary.filter((d) => !d.isExpired).length,
    expired: summary.filter((d) => d.isExpired).length,
    devices: summary,
  };
}
