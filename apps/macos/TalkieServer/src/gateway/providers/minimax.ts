import { log } from "../../log";
import { readProviderAPIKey } from "../../talkie/settings";
import type { Provider, InferenceRequest, InferenceResponse } from "./types";

const MINIMAX_API_BASE_URL = process.env.MINIMAX_BASE_URL || "https://api.minimax.io/v1";

interface MiniMaxChatResponse {
  choices: Array<{
    message?: {
      content?: string;
      reasoning_details?: Array<{ text?: string }>;
    };
    finish_reason?: string;
  }>;
  usage?: {
    prompt_tokens?: number;
    completion_tokens?: number;
  };
}

export class MiniMaxProvider implements Provider {
  name = "minimax";

  async inference(request: InferenceRequest): Promise<InferenceResponse> {
    const apiKey = this.apiKey;
    if (!apiKey) {
      throw new Error("MiniMax API key not configured");
    }

    const temperature = Math.min(1, Math.max(0.01, request.temperature ?? 0.3));

    const payload = {
      model: request.model,
      messages: request.messages,
      temperature,
      top_p: request.topP ?? 0.95,
      max_tokens: request.maxTokens ?? 2048,
      stream: false,
      reasoning_split: true,
    };

    log.info(`MiniMax: ${request.model} (${request.messages.length} messages)`);

    const response = await fetch(`${MINIMAX_API_BASE_URL}/chat/completions`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      const errorText = await response.text();
      log.error(`MiniMax error: ${response.status} ${errorText}`);
      throw new Error(`MiniMax API error: ${response.status} - ${errorText.slice(0, 200)}`);
    }

    const data = (await response.json()) as MiniMaxChatResponse;
    const choice = data.choices?.[0];
    const content = choice?.message?.content?.trim() || "";
    if (!content) {
      const reason = choice?.finish_reason ? ` (${choice.finish_reason})` : "";
      throw new Error(`MiniMax returned no final text${reason}`);
    }

    return {
      provider: this.name,
      model: request.model,
      content,
      usage: data.usage
        ? {
            inputTokens: data.usage.prompt_tokens ?? 0,
            outputTokens: data.usage.completion_tokens ?? 0,
          }
        : undefined,
      finishReason: choice?.finish_reason,
    };
  }

  async listModels(): Promise<string[]> {
    return [
      "MiniMax-M2.7",
      "MiniMax-M2.7-highspeed",
      "MiniMax-M2.5",
      "MiniMax-M2.5-highspeed",
      "MiniMax-M2.1",
      "MiniMax-M2.1-highspeed",
      "MiniMax-M2",
    ];
  }

  private get apiKey(): string {
    const key = process.env.MINIMAX_API_KEY || readProviderAPIKey("minimax") || "";
    if (!key) {
      log.warn("MiniMax API key not configured for TalkieServer");
    }
    return key;
  }
}
