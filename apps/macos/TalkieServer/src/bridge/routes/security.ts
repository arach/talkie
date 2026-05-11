import {
  acknowledgeSecurityEvent,
  createSecurityEvent,
  listSecurityEvents,
  type CreateSecurityEventRequest,
  type SecurityEvent,
} from "../../security/events";
import { badRequest, notFound } from "./responses";

export interface SecurityEventsResponse {
  events: SecurityEvent[];
}

export interface SecurityEventCreateResponse {
  event: SecurityEvent;
}

export interface SecurityEventAckResponse {
  ok: boolean;
  event: SecurityEvent;
}

export async function securityEventsRoute(query: {
  deviceId?: string;
  includeAcknowledged?: string;
  limit?: string;
}): Promise<SecurityEventsResponse> {
  const limit = query.limit ? parseInt(query.limit, 10) : 25;
  const events = await listSecurityEvents({
    deviceId: query.deviceId,
    includeAcknowledged: query.includeAcknowledged === "true",
    limit: Number.isFinite(limit) ? limit : 25,
  });

  return { events };
}

export async function securityEventCreateRoute(
  body: CreateSecurityEventRequest
): Promise<SecurityEventCreateResponse | Response> {
  if (!body.type || !body.title || !body.message) {
    return badRequest("type, title, and message are required");
  }

  const event = await createSecurityEvent(body);
  return { event };
}

export async function securityEventAckRoute(
  eventId: string,
  deviceId: string | null,
  body: { deviceId?: string } = {}
): Promise<SecurityEventAckResponse | Response> {
  const resolvedDeviceId = deviceId ?? body.deviceId;
  if (!resolvedDeviceId) {
    return badRequest("deviceId is required");
  }

  const event = await acknowledgeSecurityEvent(eventId, resolvedDeviceId);
  if (!event) {
    return notFound("Security event not found");
  }

  return { ok: true, event };
}
