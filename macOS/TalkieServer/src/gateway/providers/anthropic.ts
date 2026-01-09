/**
 * Anthropic Provider
 */

import { log } from "../../log";
import type { Provider, InferenceRequest, InferenceResponse } from "./types";

const ANTHROPIC_API_URL = "https://api.anthropic.com/v1";
const ANTHROPIC_VERSION = "2023-06-01";

// ===== Anthropic API Types =====

interface AnthropicRequest {
  model: string;
  messages: Array<{ role: "user" | "assistant"; content: string }>;
  system?: string;
  temperature?: number;
  max_tokens: number;
  stream?: boolean;
}

interface AnthropicResponse {
  id: string;
  content: Array<{ type: string; text: string }>;
  stop_reason: string;
  usage: {
    input_tokens: number;
    output_tokens: number;
  };
}

// ===== Provider Implementation =====

export class AnthropicProvider implements Provider {
  name = "anthropic";
  private apiKey: string;

  constructor() {
    const key = process.env.ANTHROPIC_API_KEY;
    if (!key) {
      log.warn("ANTHROPIC_API_KEY not set");
    }
    this.apiKey = key || "";
  }

  async inference(request: InferenceRequest): Promise<InferenceResponse> {
    // Anthropic handles system messages separately
    const systemMessage = request.messages.find((m) => m.role === "system");
    const messages = request.messages
      .filter((m) => m.role !== "system")
      .map((m) => ({
        role: m.role as "user" | "assistant",
        content: m.content,
      }));

    const payload: AnthropicRequest = {
      model: request.model,
      messages,
      system: systemMessage?.content,
      temperature: request.temperature,
      max_tokens: request.maxTokens || 4096,
      stream: false,
    };

    log.info(`Anthropic: ${request.model} (${messages.length} messages)`);

    const response = await fetch(`${ANTHROPIC_API_URL}/messages`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": this.apiKey,
        "anthropic-version": ANTHROPIC_VERSION,
      },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      const error = await response.text();
      log.error(`Anthropic error: ${response.status} ${error}`);
      throw new Error(`Anthropic API error: ${response.status}`);
    }

    const data = (await response.json()) as AnthropicResponse;
    const textContent = data.content
      .filter((c) => c.type === "text")
      .map((c) => c.text)
      .join("");

    return {
      provider: this.name,
      model: request.model,
      content: textContent,
      usage: {
        inputTokens: data.usage.input_tokens,
        outputTokens: data.usage.output_tokens,
      },
      finishReason: data.stop_reason,
    };
  }

  async listModels(): Promise<string[]> {
    // Anthropic doesn't have a models endpoint
    return [
      "claude-3-5-sonnet-20241022",
      "claude-3-5-haiku-20241022",
      "claude-3-opus-20240229",
      "claude-3-sonnet-20240229",
      "claude-3-haiku-20240307",
    ];
  }
}
