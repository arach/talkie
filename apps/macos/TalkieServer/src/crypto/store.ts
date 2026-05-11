/**
 * Key Storage
 *
 * Persists the server's key pair to disk.
 * Keys are stored in ~/Library/Application Support/TalkieBridge/keys/
 */

import { generateKeyPair, type KeyPair } from "./keypair";
import { KEYS_DIR } from "../paths";
import { log } from "../log";

const KEYPAIR_FILE = `${KEYS_DIR}/server.json`;

/**
 * Get or create the server's key pair
 * Creates new keys on first run, loads from disk on subsequent runs
 */
export async function getOrCreateKeyPair(): Promise<KeyPair> {
  // Try to load existing keys
  const existing = await loadKeyPair();
  if (existing) {
    return existing;
  }

  // Generate new keys
  log.info("Generating new server key pair...");
  const keyPair = await generateKeyPair();

  // Save to disk
  await saveKeyPair(keyPair);
  log.crypto("Server key pair saved", { path: KEYPAIR_FILE });

  return keyPair;
}

/**
 * Load key pair from disk
 */
async function loadKeyPair(): Promise<KeyPair | null> {
  try {
    const file = Bun.file(KEYPAIR_FILE);
    if (!(await file.exists())) {
      return null;
    }
    const data = await file.json();
    return data as KeyPair;
  } catch {
    return null;
  }
}

/**
 * Save key pair to disk
 */
async function saveKeyPair(keyPair: KeyPair): Promise<void> {
  // Ensure directory exists
  const { mkdir } = await import("node:fs/promises");
  await mkdir(KEYS_DIR, { recursive: true });

  // Write keys file
  await Bun.write(KEYPAIR_FILE, JSON.stringify(keyPair, null, 2));
}

/**
 * Get just the public key (for QR code / sharing)
 */
export async function getPublicKey(): Promise<string> {
  const keyPair = await getOrCreateKeyPair();
  return keyPair.publicKey;
}

/**
 * Delete stored keys (for testing/reset)
 */
export async function deleteKeyPair(): Promise<void> {
  const { unlink } = await import("node:fs/promises");
  try {
    await unlink(KEYPAIR_FILE);
    log.info("Server key pair deleted");
  } catch {
    // File doesn't exist
  }
}
