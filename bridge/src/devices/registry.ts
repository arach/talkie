/**
 * Device Registry
 *
 * Stores paired iOS devices and their public keys.
 * Devices are stored in ~/.talkie-bridge/devices.json
 */

import { deriveSharedKeyFromBase64 } from "../crypto/keypair";
import { getOrCreateKeyPair } from "../crypto/store";

const DEVICES_FILE = `${process.env.HOME}/.talkie-bridge/devices.json`;

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
