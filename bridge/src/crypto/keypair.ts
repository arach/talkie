/**
 * X25519 Key Pair Generation and Management
 *
 * Uses Web Crypto API for ECDH key exchange with P-256 curve
 * (X25519 not directly supported in Web Crypto, P-256 is the standard alternative)
 */

export interface KeyPair {
  publicKey: string; // Base64 encoded
  privateKey: string; // Base64 encoded
}

/**
 * Generate a new ECDH key pair for key exchange
 */
export async function generateKeyPair(): Promise<KeyPair> {
  const keyPair = await crypto.subtle.generateKey(
    {
      name: "ECDH",
      namedCurve: "P-256",
    },
    true, // extractable
    ["deriveKey", "deriveBits"]
  );

  const publicKeyRaw = await crypto.subtle.exportKey("raw", keyPair.publicKey);
  const privateKeyRaw = await crypto.subtle.exportKey("pkcs8", keyPair.privateKey);

  return {
    publicKey: bufferToBase64(publicKeyRaw),
    privateKey: bufferToBase64(privateKeyRaw),
  };
}

/**
 * Import a public key from base64 for key exchange
 */
export async function importPublicKey(base64Key: string): Promise<CryptoKey> {
  const keyData = base64ToBuffer(base64Key);

  return crypto.subtle.importKey(
    "raw",
    keyData,
    {
      name: "ECDH",
      namedCurve: "P-256",
    },
    true,
    []
  );
}

/**
 * Import a private key from base64
 */
export async function importPrivateKey(base64Key: string): Promise<CryptoKey> {
  const keyData = base64ToBuffer(base64Key);

  return crypto.subtle.importKey(
    "pkcs8",
    keyData,
    {
      name: "ECDH",
      namedCurve: "P-256",
    },
    true,
    ["deriveKey", "deriveBits"]
  );
}

/**
 * Derive a shared secret from our private key and their public key
 * Returns an AES-GCM key for encryption/decryption
 */
export async function deriveSharedKey(
  privateKey: CryptoKey,
  publicKey: CryptoKey
): Promise<CryptoKey> {
  return crypto.subtle.deriveKey(
    {
      name: "ECDH",
      public: publicKey,
    },
    privateKey,
    {
      name: "AES-GCM",
      length: 256,
    },
    true,
    ["encrypt", "decrypt"]
  );
}

/**
 * Derive shared key from base64 encoded keys
 */
export async function deriveSharedKeyFromBase64(
  privateKeyBase64: string,
  publicKeyBase64: string
): Promise<CryptoKey> {
  const privateKey = await importPrivateKey(privateKeyBase64);
  const publicKey = await importPublicKey(publicKeyBase64);
  return deriveSharedKey(privateKey, publicKey);
}

// Helper functions
function bufferToBase64(buffer: ArrayBuffer): string {
  return btoa(String.fromCharCode(...new Uint8Array(buffer)));
}

function base64ToBuffer(base64: string): ArrayBuffer {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}
