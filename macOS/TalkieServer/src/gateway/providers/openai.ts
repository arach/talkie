/**
 * OpenAI Provider
 */

import { log } from "../../log";
import type { Provider, InferenceRequest, InferenceResponse } from "./types";

const OPENAI_API_URL = "https://api.openai.com/v1";

// ===== OpenAI API Types =====

interface OpenAIRequest {
  model: string;
  messages: Array<{ role: string; content: string }>;
  temperature?: number;
  max_tokens?: number;
  stream?: boolean;
}

interface OpenAIResponse {
  id: string;
  choices: Array<{
    message: { role: string; content: string };
    finish_reason: string;
  }>;
  usage?: {
    prompt_tokens: number;
    completion_tokens: number;
  };
}

// ===== Provider Implementation =====

export class OpenAIProvider implements Provider {
  name = "openai";
  private apiKey: string;

  constructor() {
    const key = process.env.OPENAI_API_KEY;
    if (!key) {
      log.warn("OPENAI_API_KEY not set");
    }
    this.apiKey = key || "";
  }

  async inference(request: InferenceRequest): Promise<InferenceResponse> {
    const payload: OpenAIRequest = {
      model: request.model,
      messages: request.messages,
      temperature: request.temperature,
      max_tokens: request.maxTokens,
      stream: false,
    };

    log.info(`OpenAI: ${request.model} (${request.messages.length} messages)`);

    const response = await fetch(`${OPENAI_API_URL}/chat/completions`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${this.apiKey}`,
      },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      const error = await response.text();
      log.error(`OpenAI error: ${response.status} ${error}`);
      throw new Error(`OpenAI API error: ${response.status}`);
    }

    const data = (await response.json()) as OpenAIResponse;
    const choice = data.choices[0];

    return {
      provider: this.name,
      model: request.model,
      content: choice.message.content,
      usage: data.usage
        ? {
            inputTokens: data.usage.prompt_tokens,
            outputTokens: data.usage.completion_tokens,
          }
        : undefined,
      finishReason: choice.finish_reason,
    };
  }

  async listModels(): Promise<string[]> {
    const response = await fetch(`${OPENAI_API_URL}/models`, {
      headers: { Authorization: `Bearer ${this.apiKey}` },
    });

    if (!response.ok) {
      throw new Error(`Failed to list models: ${response.status}`);
    }

    const data = (await response.json()) as { data: Array<{ id: string }> };
    return data.data
      .map((m) => m.id)
      .filter((id) => id.startsWith("gpt-"))
      .sort();
  }
}
