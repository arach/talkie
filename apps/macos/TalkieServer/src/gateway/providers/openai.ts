/**
 * OpenAI Provider
 */

import { log } from "../../log";
import type { Provider, InferenceRequest, InferenceResponse } from "./types";
import { readProviderAPIKey } from "../../talkie/settings";

const OPENAI_API_URL = "https://api.openai.com/v1";

// ===== OpenAI API Types =====

interface OpenAIRequest {
  model: string;
  messages: Array<{ role: string; content: string }>;
  temperature?: number;
  max_tokens?: number;
  max_completion_tokens?: number;
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

  async inference(request: InferenceRequest): Promise<InferenceResponse> {
    const apiKey = this.apiKey;
    const model = request.model;

    // Newer models (o1, o3, gpt-5+, gpt-4o) use max_completion_tokens instead of max_tokens
    const useNewTokenParam =
      model.startsWith("o1") ||
      model.startsWith("o3") ||
      model.startsWith("gpt-5") ||
      model.startsWith("gpt-4o");

    // Reasoning-family models and GPT-5 chat models ignore temperature.
    const supportsTemperature =
      !model.startsWith("o1") &&
      !model.startsWith("o3") &&
      !model.startsWith("gpt-5");

    const payload: OpenAIRequest = {
      model: model,
      messages: request.messages,
      temperature: supportsTemperature ? request.temperature : undefined,
      stream: false,
    };

    // Use appropriate token parameter
    if (useNewTokenParam) {
      payload.max_completion_tokens = request.maxTokens;
    } else {
      payload.max_tokens = request.maxTokens;
    }

    log.info(`OpenAI: ${model} (${request.messages.length} messages, tokenParam=${useNewTokenParam ? "max_completion_tokens" : "max_tokens"})`);

    const response = await fetch(`${OPENAI_API_URL}/chat/completions`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      const errorText = await response.text();
      let errorMessage = `OpenAI API error (HTTP ${response.status})`;

      // Try to parse OpenAI's error response for better message
      try {
        const errorJson = JSON.parse(errorText);
        if (errorJson.error?.message) {
          errorMessage = `OpenAI: ${errorJson.error.message}`;
          if (errorJson.error.type) {
            errorMessage += ` [${errorJson.error.type}]`;
          }
          if (errorJson.error.code) {
            errorMessage += ` (code: ${errorJson.error.code})`;
          }
        }
      } catch {
        // Use raw text if not JSON
        errorMessage = `OpenAI API error: ${response.status} - ${errorText.slice(0, 200)}`;
      }

      log.error(errorMessage);
      throw new Error(errorMessage);
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
    const apiKey = this.apiKey;
    const response = await fetch(`${OPENAI_API_URL}/models`, {
      headers: { Authorization: `Bearer ${apiKey}` },
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

  private get apiKey(): string {
    const key = process.env.OPENAI_API_KEY || readProviderAPIKey("openai") || "";
    if (!key) {
      log.warn("OpenAI API key not configured for TalkieServer");
    }
    return key;
  }
}
