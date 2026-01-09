/**
 * Standardized response helpers for consistent API responses
 */

// ===== Error Responses =====

export function notFound(message: string = "Not found") {
  return new Response(
    JSON.stringify({ error: message }),
    { status: 404, headers: { "Content-Type": "application/json" } }
  );
}

export function badRequest(message: string = "Bad request") {
  return new Response(
    JSON.stringify({ error: message }),
    { status: 400, headers: { "Content-Type": "application/json" } }
  );
}

export function serverError(message: string = "Internal server error", details?: string) {
  return new Response(
    JSON.stringify({ error: message, ...(details && { details }) }),
    { status: 500, headers: { "Content-Type": "application/json" } }
  );
}

export function serviceUnavailable(message: string = "Service unavailable", hint?: string) {
  return new Response(
    JSON.stringify({ error: message, ...(hint && { hint }) }),
    { status: 503, headers: { "Content-Type": "application/json" } }
  );
}

export function notImplemented(message: string = "Not implemented", hint?: string) {
  return new Response(
    JSON.stringify({ error: message, ...(hint && { hint }) }),
    { status: 501, headers: { "Content-Type": "application/json" } }
  );
}

export function proxyError(status: number, message: string, details?: string) {
  return new Response(
    JSON.stringify({ error: message, ...(details && { details }) }),
    { status, headers: { "Content-Type": "application/json" } }
  );
}

// ===== Binary Responses =====

export function jpeg(data: ArrayBuffer) {
  return new Response(data, {
    headers: {
      "Content-Type": "image/jpeg",
      "Content-Length": data.byteLength.toString(),
      "Cache-Control": "no-cache",
    },
  });
}
