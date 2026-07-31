import { describe, expect, test } from "bun:test";
import { DEFAULT_GATEWAY_PORT, resolveGatewayPort } from "./network";

describe("Talkie gateway port", () => {
  test("uses the Talkie-owned default", () => {
    expect(resolveGatewayPort([], {})).toBe(DEFAULT_GATEWAY_PORT);
    expect(DEFAULT_GATEWAY_PORT).toBe(19_825);
  });

  test("allows an environment override and gives CLI arguments precedence", () => {
    expect(resolveGatewayPort([], { TALKIE_GATEWAY_PORT: "20100" })).toBe(20_100);
    expect(resolveGatewayPort(["--port", "20200"], { TALKIE_GATEWAY_PORT: "20100" })).toBe(20_200);
  });

  test("rejects invalid ports", () => {
    expect(() => resolveGatewayPort(["--port", "70000"], {})).toThrow("Invalid Talkie gateway port");
  });
});
