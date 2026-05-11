import { log } from "../../log";
import { readProviderAPIKey } from "../../talkie/settings";
import type { Provider, InferenceRequest, InferenceResponse } from "./types";

const GROQ_API_URL = "https://api.groq.com/openai/v1";

interface GroqChatResponse {
  choices: Array<{
    message?: {
      content?: string;
    };
    finish_reason?: string;
  }>;
  usage?: {
    prompt_tokens?: number;
    completion_tokens?: number;
  };
}

export class GroqProvider implements Provider {
  name = "groq";

  async inference(request: InferenceRequest): Promise<InferenceResponse> {
    const apiKey = this.apiKey;

    const payload = {
      model: request.model,
      messages: request.messages,
      temperature: request.temperature ?? 0.3,
      max_tokens: request.maxTokens ?? 2048,
      stream: false,
    };

    log.info(`Groq: ${request.model} (${request.messages.length} messages)`);

    const response = await fetch(`${GROQ_API_URL}/chat/completions`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      const errorText = await response.text();
      log.error(`Groq error: ${response.status} ${errorText}`);
      throw new Error(`Groq API error: ${response.status}`);
    }

    const data = (await response.json()) as GroqChatResponse;
    const content = data.choices?.[0]?.message?.content?.trim() || "";
    if (!content) {
      throw new Error("Groq returned no text");
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
      finishReason: data.choices?.[0]?.finish_reason,
    };
  }

  async listModels(): Promise<string[]> {
    return [
      "llama-3.3-70b-versatile",
      "llama-3.1-8b-instant",
      "mixtral-8x7b-32768",
      "gemma2-9b-it",
    ];
  }

  private get apiKey(): string {
    const key = process.env.GROQ_API_KEY || readProviderAPIKey("groq") || "";
    if (!key) {
      log.warn("Groq API key not configured for TalkieServer");
    }
    return key;
  }
}
