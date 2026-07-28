import { describe, expect, test } from "bun:test";
import { openBytes } from "../crypto/box";
import {
  isSuccessfulResponseStatus,
  sealSuccessfulResponse,
} from "./transport-encryption";

describe("transport response encryption", () => {
  test("classifies the full 2xx range as successful", () => {
    expect(isSuccessfulResponseStatus(199)).toBe(false);
    expect(isSuccessfulResponseStatus(200)).toBe(true);
    expect(isSuccessfulResponseStatus(202)).toBe(true);
    expect(isSuccessfulResponseStatus(204)).toBe(true);
    expect(isSuccessfulResponseStatus(299)).toBe(true);
    expect(isSuccessfulResponseStatus(300)).toBe(false);
    expect(isSuccessfulResponseStatus(401)).toBe(false);
  });

  test("seals a 202 receipt without rewriting its status", async () => {
    const key = await crypto.subtle.generateKey(
      { name: "AES-GCM", length: 256 },
      false,
      ["encrypt", "decrypt"],
    );
    const receipt = new TextEncoder().encode(JSON.stringify({ job: { id: "job-1" } }));

    const response = await sealSuccessfulResponse(receipt, 202, key);
    const envelope = await response.json() as { enc: number; ciphertext: string };
    const plaintext = await openBytes(envelope.ciphertext, key);

    expect(response.status).toBe(202);
    expect(response.headers.get("X-Enc")).toBe("2");
    expect(envelope.enc).toBe(2);
    expect(new TextDecoder().decode(plaintext)).toBe(JSON.stringify({ job: { id: "job-1" } }));
  });
});
