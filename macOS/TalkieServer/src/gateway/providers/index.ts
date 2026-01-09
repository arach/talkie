/**
 * Provider Registry (Gateway Module)
 *
 * Central registry for all inference providers.
 * This is the "Gateway" entry point.
 */

import { log } from "../../log";
import { OpenAIProvider } from "./openai";
import { AnthropicProvider } from "./anthropic";
import type { Provider, ProviderName, InferenceRequest, InferenceResponse } from "./types";

// Re-export types
export type { Provider, ProviderName, InferenceRequest, InferenceResponse, Message } from "./types";

// ===== Provider Registry =====

const providers: Map<ProviderName, Provider> = new Map();

function initProviders(): void {
  providers.set("openai", new OpenAIProvider());
  providers.set("anthropic", new AnthropicProvider());
  // TODO: Add google, groq providers
  log.info(`Gateway initialized: ${providers.size} providers`);
}

export function getProvider(name: ProviderName): Provider | undefined {
  if (providers.size === 0) {
    initProviders();
  }
  return providers.get(name);
}

export function listProviders(): ProviderName[] {
  if (providers.size === 0) {
    initProviders();
  }
  return Array.from(providers.keys());
}

// ===== Convenience Functions =====

/**
 * Run inference through the appropriate provider
 */
export async function inference(request: InferenceRequest): Promise<InferenceResponse> {
  const provider = getProvider(request.provider);
  if (!provider) {
    throw new Error(`Unknown provider: ${request.provider}`);
  }
  return provider.inference(request);
}

/**
 * List models for a provider
 */
export async function listModels(providerName: ProviderName): Promise<string[]> {
  const provider = getProvider(providerName);
  if (!provider) {
    throw new Error(`Unknown provider: ${providerName}`);
  }
  if (!provider.listModels) {
    return [];
  }
  return provider.listModels();
}
