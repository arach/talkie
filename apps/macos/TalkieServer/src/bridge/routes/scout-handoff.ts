/**
 * Scout Handoff Route
 *
 * POST /handoff/scout - Hand off an agent conversation to Scout
 *
 * Creates a conversation in Scout's broker with the memo context
 * and prior agent turns, so the user can continue in Scout's
 * multi-turn agent environment.
 *
 * Scout broker: http://127.0.0.1:65535 (default)
 */

import { log } from "../../log";

// ===== Types =====

export interface ScoutHandoffRequest {
  memoId: string;
  memoTitle: string;
  memoTranscript: string;
  turns: Array<{
    role: string;     // "user" | "assistant"
    content: string;
    timestamp: string; // ISO 8601
  }>;
  claudeSessionId?: string;
}

export interface ScoutHandoffResponse {
  success: boolean;
  conversationId?: string;
  messageCount?: number;
  error?: string;
}

// ===== Config =====

const SCOUT_BROKER_URL =
  process.env.OPENSCOUT_BROKER_URL ?? "http://127.0.0.1:65535";

const TALKIE_NODE_ID = "talkie-bridge";
const TALKIE_ACTOR_ID = "talkie:operator";

// ===== Helpers =====

function scoutId(): string {
  return crypto.randomUUID();
}

async function brokerPost(path: string, body: unknown): Promise<Response> {
  return fetch(`${SCOUT_BROKER_URL}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

// ===== Handler =====

export async function scoutHandoffRoute(
  body: ScoutHandoffRequest
): Promise<Response> {
  const { memoId, memoTitle, memoTranscript, turns, claudeSessionId } = body;

  if (!memoTitle || !turns || turns.length === 0) {
    return Response.json(
      { success: false, error: "Missing memoTitle or turns" } satisfies ScoutHandoffResponse,
      { status: 400 }
    );
  }

  log.info(
    `Scout handoff: memo="${memoTitle}", ${turns.length} turns, sessionId=${claudeSessionId ?? "(none)"}`
  );

  try {
    // 1. Check broker is reachable
    const healthResp = await fetch(`${SCOUT_BROKER_URL}/v1/node`, {
      signal: AbortSignal.timeout(3000),
    }).catch(() => null);

    if (!healthResp || !healthResp.ok) {
      return Response.json(
        {
          success: false,
          error: "Scout broker not reachable. Is Scout running?",
        } satisfies ScoutHandoffResponse,
        { status: 502 }
      );
    }

    // 2. Create conversation
    const conversationId = scoutId();

    const conversationResp = await brokerPost("/v1/conversations", {
      id: conversationId,
      kind: "direct",
      title: `Talkie: ${memoTitle}`,
      visibility: "private",
      shareMode: "local",
      authorityNodeId: TALKIE_NODE_ID,
      participantIds: [TALKIE_ACTOR_ID],
      topic: `Voice memo handoff from Talkie`,
      metadata: {
        source: "talkie",
        memoId,
        memoTitle,
        claudeSessionId: claudeSessionId ?? null,
      },
    });

    if (!conversationResp.ok) {
      const err = await conversationResp.text();
      log.error(`Scout handoff: failed to create conversation: ${err}`);
      return Response.json(
        { success: false, error: "Failed to create Scout conversation" } satisfies ScoutHandoffResponse,
        { status: 500 }
      );
    }

    // 3. Post context message with memo transcript
    const contextMessageId = scoutId();
    await brokerPost("/v1/messages", {
      id: contextMessageId,
      conversationId,
      actorId: TALKIE_ACTOR_ID,
      originNodeId: TALKIE_NODE_ID,
      class: "system",
      body: [
        `**Handoff from Talkie** — Voice memo: *${memoTitle}*`,
        "",
        "---",
        "",
        "**Transcript:**",
        memoTranscript,
        ...(claudeSessionId
          ? ["", `**Claude Session:** \`${claudeSessionId}\``]
          : []),
      ].join("\n"),
      visibility: "private",
      policy: "durable",
      createdAt: Date.now(),
      metadata: { kind: "talkie-handoff-context" },
    });

    // 4. Replay conversation turns as messages
    let messageCount = 1; // context message

    for (const turn of turns) {
      const msgId = scoutId();
      const actorId =
        turn.role === "user" ? TALKIE_ACTOR_ID : "claude:assistant";
      const msgClass = turn.role === "user" ? "agent" : "agent";

      await brokerPost("/v1/messages", {
        id: msgId,
        conversationId,
        actorId,
        originNodeId: TALKIE_NODE_ID,
        class: msgClass,
        body: turn.content,
        visibility: "private",
        policy: "durable",
        createdAt: turn.timestamp
          ? new Date(turn.timestamp).getTime()
          : Date.now(),
        metadata: {
          kind: "talkie-handoff-turn",
          originalRole: turn.role,
        },
      });
      messageCount++;
    }

    log.info(
      `Scout handoff complete: conversationId=${conversationId}, ${messageCount} messages`
    );

    return Response.json({
      success: true,
      conversationId,
      messageCount,
    } satisfies ScoutHandoffResponse);
  } catch (error) {
    log.error(`Scout handoff error: ${error}`);
    return Response.json(
      { success: false, error: String(error) } satisfies ScoutHandoffResponse,
      { status: 500 }
    );
  }
}

/**
 * GET /handoff/scout/status
 * Check if Scout broker is reachable
 */
export async function scoutHandoffStatusRoute(): Promise<{
  available: boolean;
  brokerUrl: string;
  error?: string;
}> {
  try {
    const resp = await fetch(`${SCOUT_BROKER_URL}/v1/node`, {
      signal: AbortSignal.timeout(3000),
    });

    if (resp.ok) {
      return { available: true, brokerUrl: SCOUT_BROKER_URL };
    }
    return {
      available: false,
      brokerUrl: SCOUT_BROKER_URL,
      error: `Broker returned ${resp.status}`,
    };
  } catch (error) {
    return {
      available: false,
      brokerUrl: SCOUT_BROKER_URL,
      error: String(error),
    };
  }
}
