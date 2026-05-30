/**
 * Inference Routes (Gateway)
 *
 * POST /inference           - Run inference through any provider
 * GET  /inference/providers - List available providers
 * GET  /inference/models    - List models for a provider
 */

import { log } from "../../log";
import {
  inference as runInference,
  listProviders,
  listModels,
  type InferenceRequest,
  type InferenceResponse,
  type ProviderName,
} from "../providers";
import { badRequest, serverError } from "./responses";

// ===== Types =====

export interface InferenceBody {
  provider: ProviderName;
  model: string;
  messages: Array<{ role: "system" | "user" | "assistant"; content: string }>;
  temperature?: number;
  topP?: number;
  maxTokens?: number;
}

export interface ProvidersResponse {
  providers: Array<{
    id: ProviderName;
    name: string;
    available: boolean;
  }>;
}

export interface ModelsResponse {
  provider: ProviderName;
  models: string[];
}

// ===== Handlers =====

/**
 * POST /inference
 * Run inference through a provider
 */
export async function inferenceRoute(
  body: InferenceBody
): Promise<InferenceResponse | Response> {
  if (!body.provider || !body.model || !body.messages?.length) {
    return badRequest("provider, model, and messages are required");
  }

  const validProviders = listProviders();
  if (!validProviders.includes(body.provider)) {
    return badRequest(`Invalid provider. Valid: ${validProviders.join(", ")}`);
  }

  log.info(`Inference: ${body.provider}/${body.model}`);

  try {
    const request: InferenceRequest = {
      provider: body.provider,
      model: body.model,
      messages: body.messages,
      temperature: body.temperature,
      topP: body.topP,
      maxTokens: body.maxTokens,
    };

    return await runInference(request);
  } catch (error) {
    log.error(`Inference failed: ${error}`);
    return serverError("Inference failed", String(error));
  }
}

/**
 * GET /inference/providers
 * List available providers
 */
export function providersRoute(): ProvidersResponse {
  return {
    providers: listProviders().map((provider) => ({
      id: provider,
      name: providerDisplayName(provider),
      available: true,
    })),
  };
}

/**
 * GET /inference/models?provider=openai
 * List models for a provider
 */
export async function modelsRoute(
  provider: string | undefined
): Promise<ModelsResponse | Response> {
  if (!provider) {
    return badRequest("provider query param required");
  }

  const validProviders = listProviders();
  if (!validProviders.includes(provider as ProviderName)) {
    return badRequest(`Invalid provider. Valid: ${validProviders.join(", ")}`);
  }

  try {
    const models = await listModels(provider as ProviderName);
    return {
      provider: provider as ProviderName,
      models,
    };
  } catch (error) {
    return serverError("Failed to list models", String(error));
  }
}

function providerDisplayName(provider: ProviderName): string {
  switch (provider) {
    case "openai":
      return "OpenAI";
    case "anthropic":
      return "Anthropic";
    case "google":
      return "Google Gemini";
    case "groq":
      return "Groq";
    case "minimax":
      return "MiniMax";
  }
}
