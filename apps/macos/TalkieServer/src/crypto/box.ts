/**
 * AES-GCM Encryption/Decryption
 *
 * Encrypts messages with a shared secret derived from ECDH key exchange.
 * Format: nonce (12 bytes) | ciphertext | auth tag
 */

const NONCE_LENGTH = 12; // 96 bits for AES-GCM

export interface EncryptedMessage {
  ciphertext: string; // Base64 encoded (includes nonce + ciphertext + tag)
}

/**
 * Encrypt a message with AES-GCM
 */
export async function encrypt(
  plaintext: string,
  sharedKey: CryptoKey
): Promise<EncryptedMessage> {
  // Generate random nonce
  const nonce = crypto.getRandomValues(new Uint8Array(NONCE_LENGTH));

  // Encode plaintext as UTF-8
  const encoder = new TextEncoder();
  const data = encoder.encode(plaintext);

  // Encrypt
  const ciphertext = await crypto.subtle.encrypt(
    {
      name: "AES-GCM",
      iv: nonce,
    },
    sharedKey,
    data
  );

  // Combine nonce + ciphertext
  const combined = new Uint8Array(NONCE_LENGTH + ciphertext.byteLength);
  combined.set(nonce, 0);
  combined.set(new Uint8Array(ciphertext), NONCE_LENGTH);

  return {
    ciphertext: bufferToBase64(combined.buffer),
  };
}

/**
 * Decrypt a message with AES-GCM
 */
export async function decrypt(
  encryptedMessage: EncryptedMessage,
  sharedKey: CryptoKey
): Promise<string> {
  // Decode from base64
  const combined = new Uint8Array(base64ToBuffer(encryptedMessage.ciphertext));

  // Extract nonce and ciphertext
  const nonce = combined.slice(0, NONCE_LENGTH);
  const ciphertext = combined.slice(NONCE_LENGTH);

  // Decrypt
  const plaintext = await crypto.subtle.decrypt(
    {
      name: "AES-GCM",
      iv: nonce,
    },
    sharedKey,
    ciphertext
  );

  // Decode as UTF-8
  const decoder = new TextDecoder();
  return decoder.decode(plaintext);
}

/**
 * Encrypt a JSON object
 */
export async function encryptJson(
  data: unknown,
  sharedKey: CryptoKey
): Promise<EncryptedMessage> {
  return encrypt(JSON.stringify(data), sharedKey);
}

/**
 * Decrypt to a JSON object
 */
export async function decryptJson<T = unknown>(
  encryptedMessage: EncryptedMessage,
  sharedKey: CryptoKey
): Promise<T> {
  const plaintext = await decrypt(encryptedMessage, sharedKey);
  return JSON.parse(plaintext) as T;
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
