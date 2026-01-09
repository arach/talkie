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
  maxTokens?: number;
}

export interface ProvidersResponse {
  providers: ProviderName[];
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

  const validProviders: ProviderName[] = ["openai", "anthropic", "google", "groq"];
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
    providers: listProviders(),
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

  const validProviders: ProviderName[] = ["openai", "anthropic", "google", "groq"];
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
