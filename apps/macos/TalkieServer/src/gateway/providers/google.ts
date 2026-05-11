import { log } from "../../log";
import { readProviderAPIKey } from "../../talkie/settings";
import type { Provider, InferenceRequest, InferenceResponse } from "./types";

const GOOGLE_API_URL = "https://generativelanguage.googleapis.com/v1beta/models";

interface GoogleGenerateResponse {
  candidates?: Array<{
    content?: {
      parts?: Array<{
        text?: string;
      }>;
    };
    finishReason?: string;
  }>;
  usageMetadata?: {
    promptTokenCount?: number;
    candidatesTokenCount?: number;
  };
}

export class GoogleProvider implements Provider {
  name = "google";

  async inference(request: InferenceRequest): Promise<InferenceResponse> {
    const apiKey = this.apiKey;
    const url = `${GOOGLE_API_URL}/${request.model}:generateContent?key=${apiKey}`;

    const systemPrompt = request.messages.find((message) => message.role === "system")?.content;
    const userMessages = request.messages.filter((message) => message.role !== "system");
    const combinedPrompt = userMessages
      .map((message) => `${message.role.toUpperCase()}:\n${message.content}`)
      .join("\n\n");

    const payload: Record<string, unknown> = {
      contents: [
        {
          parts: [{ text: combinedPrompt }],
        },
      ],
      generationConfig: {
        temperature: request.temperature ?? 0.3,
        topK: 40,
        topP: 0.9,
        maxOutputTokens: request.maxTokens ?? 2048,
      },
    };

    if (systemPrompt) {
      payload.systemInstruction = {
        parts: [{ text: systemPrompt }],
      };
    }

    log.info(`Google Gemini: ${request.model} (${request.messages.length} messages)`);

    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      const errorText = await response.text();
      log.error(`Google Gemini error: ${response.status} ${errorText}`);
      throw new Error(`Google Gemini API error: ${response.status}`);
    }

    const data = (await response.json()) as GoogleGenerateResponse;
    const content =
      data.candidates?.[0]?.content?.parts
        ?.map((part) => part.text ?? "")
        .join("")
        .trim() || "";

    if (!content) {
      throw new Error("Google Gemini returned no text");
    }

    return {
      provider: this.name,
      model: request.model,
      content,
      usage: data.usageMetadata
        ? {
            inputTokens: data.usageMetadata.promptTokenCount ?? 0,
            outputTokens: data.usageMetadata.candidatesTokenCount ?? 0,
          }
        : undefined,
      finishReason: data.candidates?.[0]?.finishReason,
    };
  }

  async listModels(): Promise<string[]> {
    return [
      "gemini-2.0-flash",
      "gemini-2.0-flash-lite",
      "gemini-1.5-flash-latest",
      "gemini-1.5-pro-latest",
    ];
  }

  private get apiKey(): string {
    const key = process.env.GEMINI_API_KEY || readProviderAPIKey("google") || "";
    if (!key) {
      log.warn("Google Gemini API key not configured for TalkieServer");
    }
    return key;
  }
}
