/** Network defaults owned by the Talkie gateway process. */
export const DEFAULT_GATEWAY_PORT = 19_825;
export const LEGACY_GATEWAY_PORT = 8_765;

export function resolveGatewayPort(
  args: string[],
  environment: NodeJS.ProcessEnv = process.env,
): number {
  const argumentIndex = args.findIndex((argument) => argument === "--port" || argument === "-p");
  const rawValue = argumentIndex >= 0
    ? args[argumentIndex + 1]
    : environment.TALKIE_GATEWAY_PORT;
  if (rawValue === undefined || rawValue.trim() === "") return DEFAULT_GATEWAY_PORT;

  const port = Number(rawValue);
  if (!Number.isInteger(port) || port < 1 || port > 65_535) {
    throw new Error(`Invalid Talkie gateway port: ${rawValue}`);
  }
  return port;
}
