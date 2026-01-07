/**
 * headless.ts - Headless mode for Claude Code sessions
 *
 * Uses Claude CLI directly (bypasses Talkie/TalkieLive):
 * - `claude --resume <sessionId> --print "message" --output-format stream-json`
 * - Works when screen is locked (no UI/AX needed)
 * - Returns streaming response to client
 *
 * This is the "invest here" mode from the architecture:
 * iOS → TalkieGateway → CLI → Response → iOS
 */

import { spawn, type Subprocess } from "bun";
import { log } from "../log";
import { getSession } from "../discovery/sessions";

interface HeadlessRequest {
  sessionId: string;
  message: string;
  projectDir?: string;  // Optional - will use session's projectPath if not provided
  stream?: boolean;     // If true, stream responses (default: false, return complete response)
}

interface StreamMessage {
  type: "assistant" | "result" | "error" | "system" | "tool_use" | "tool_result";
  subtype?: string;
  content?: string;
  message?: {
    role?: string;
    content?: Array<{ type: string; text?: string; thinking?: string }>;
  };
  [key: string]: unknown;
}

/**
 * Extract text content from a stream message
 */
function extractTextFromMessage(msg: StreamMessage): string {
  // Handle direct content
  if (typeof msg.content === "string") {
    return msg.content;
  }

  // Handle message.content array
  if (msg.message?.content && Array.isArray(msg.message.content)) {
    return msg.message.content
      .filter((block) => block.type === "text" && block.text)
      .map((block) => block.text)
      .join("");
  }

  return "";
}

/**
 * POST /headless - Send message to Claude session in headless mode
 *
 * Uses Claude CLI directly without UI automation.
 * Works when screen is locked.
 */
export async function headlessRoute(req: Request): Promise<Response> {
  let body: HeadlessRequest;

  try {
    body = await req.json();
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const { sessionId, message, projectDir, stream = false } = body;

  if (!sessionId || typeof sessionId !== "string") {
    return Response.json({ error: "sessionId is required" }, { status: 400 });
  }

  if (!message || typeof message !== "string") {
    return Response.json({ error: "message is required" }, { status: 400 });
  }

  // Get project directory from session if not provided
  let workingDir = projectDir;
  if (!workingDir) {
    const session = await getSession(sessionId);
    if (session?.projectPath) {
      workingDir = session.projectPath;
    }
  }

  log.info(`Headless: sessionId=${sessionId}, projectDir=${workingDir || "not set"}, message=${message.slice(0, 100)}...`);

  // Build CLI command
  const args = [
    "--resume", sessionId,
    "--print",
    "--output-format", "stream-json",
    "--verbose",  // Required for stream-json output format
    message,
  ];

  // Spawn claude CLI process
  const proc = spawn({
    cmd: ["npx", "claude", ...args],
    cwd: workingDir || process.cwd(),
    stdout: "pipe",
    stderr: "pipe",
    env: {
      ...process.env,
      // Ensure proper terminal handling
      TERM: "dumb",
      NO_COLOR: "1",
    },
  });

  if (stream) {
    // Return Server-Sent Events stream
    return new Response(
      new ReadableStream({
        async start(controller) {
          const encoder = new TextEncoder();

          try {
            const reader = proc.stdout.getReader();
            let buffer = "";

            while (true) {
              const { done, value } = await reader.read();
              if (done) break;

              const text = new TextDecoder().decode(value);
              buffer += text;

              // Process complete JSON lines
              const lines = buffer.split("\n");
              buffer = lines.pop() || "";  // Keep incomplete line in buffer

              for (const line of lines) {
                if (line.trim()) {
                  try {
                    const msg = JSON.parse(line) as StreamMessage;
                    const content = extractTextFromMessage(msg);
                    if (content) {
                      controller.enqueue(encoder.encode(`data: ${JSON.stringify({ type: msg.type, content })}\n\n`));
                    }
                  } catch {
                    // Skip malformed JSON
                  }
                }
              }
            }

            // Process any remaining buffer
            if (buffer.trim()) {
              try {
                const msg = JSON.parse(buffer) as StreamMessage;
                const content = extractTextFromMessage(msg);
                if (content) {
                  controller.enqueue(encoder.encode(`data: ${JSON.stringify({ type: msg.type, content })}\n\n`));
                }
              } catch {
                // Skip malformed JSON
              }
            }

            controller.enqueue(encoder.encode("data: [DONE]\n\n"));
            controller.close();
          } catch (error) {
            log.error(`Headless stream error: ${error}`);
            controller.enqueue(encoder.encode(`data: ${JSON.stringify({ type: "error", error: String(error) })}\n\n`));
            controller.close();
          }
        },
      }),
      {
        headers: {
          "Content-Type": "text/event-stream",
          "Cache-Control": "no-cache",
          "Connection": "keep-alive",
        },
      }
    );
  }

  // Non-streaming: collect full response
  try {
    const stdout = await new Response(proc.stdout).text();
    const stderr = await new Response(proc.stderr).text();
    const exitCode = await proc.exited;

    if (exitCode !== 0) {
      log.error(`Headless CLI error (exit ${exitCode}): ${stderr}`);
      return Response.json(
        {
          success: false,
          error: `Claude CLI exited with code ${exitCode}`,
          stderr: stderr.slice(0, 500),
        },
        { status: 500 }
      );
    }

    // Parse streaming JSON output and extract text
    const messages: StreamMessage[] = [];
    let fullResponse = "";

    for (const line of stdout.split("\n")) {
      if (line.trim()) {
        try {
          const msg = JSON.parse(line) as StreamMessage;
          messages.push(msg);

          // Extract text from assistant messages
          if (msg.type === "assistant") {
            fullResponse += extractTextFromMessage(msg);
          }
        } catch {
          // Skip malformed JSON lines
        }
      }
    }

    log.info(`Headless complete: ${fullResponse.length} chars response`);

    return Response.json({
      success: true,
      response: fullResponse,
      messageCount: messages.length,
      sessionId,
    });
  } catch (error) {
    log.error(`Headless error: ${error}`);
    return Response.json(
      {
        success: false,
        error: String(error),
      },
      { status: 500 }
    );
  }
}

/**
 * GET /headless/status - Check if headless mode is available
 *
 * Verifies Claude CLI is installed and accessible.
 */
export async function headlessStatusRoute(_req: Request): Promise<Response> {
  try {
    const proc = spawn({
      cmd: ["npx", "claude", "--version"],
      stdout: "pipe",
      stderr: "pipe",
    });

    const stdout = await new Response(proc.stdout).text();
    const exitCode = await proc.exited;

    if (exitCode === 0) {
      return Response.json({
        available: true,
        version: stdout.trim(),
      });
    }

    return Response.json({
      available: false,
      error: "Claude CLI not responding",
    });
  } catch (error) {
    return Response.json({
      available: false,
      error: String(error),
    });
  }
}
