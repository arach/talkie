/**
 * Provider Types (Gateway Module)
 *
 * Unified inference format that translates to provider-specific APIs.
 * This is the "Gateway" - protocol translation for external services.
 */

// ===== Unified Request Format =====

export interface Message {
  role: "system" | "user" | "assistant";
  content: string;
}

export interface InferenceRequest {
  provider: ProviderName;
  model: string;
  messages: Message[];
  temperature?: number;
  maxTokens?: number;
  stream?: boolean;
}

// ===== Unified Response Format =====

export interface InferenceResponse {
  provider: string;
  model: string;
  content: string;
  usage?: {
    inputTokens: number;
    outputTokens: number;
  };
  finishReason?: string;
}

// ===== Provider Interface =====

export interface Provider {
  name: string;
  inference(request: InferenceRequest): Promise<InferenceResponse>;
  listModels?(): Promise<string[]>;
}

// ===== Supported Providers =====

export type ProviderName = "openai" | "anthropic" | "google" | "groq";
