import { log } from "../../log";
import {
  inference,
  type Message,
  type ProviderName,
} from "../../gateway/providers";
import {
  defaultModelForProvider,
  inferenceProviderToTalkieProvider,
  loadComposeSettings,
  providerDisplayName,
  readProviderAPIKey,
  talkieProviderToInferenceProvider,
} from "../../talkie/settings";

const DEFAULT_PROVIDER_ORDER: ProviderName[] = [
  "groq",
  "openai",
  "anthropic",
  "google",
  "minimax",
];

export interface ConfiguredInferenceRequestBody {
  messages: Message[];
  temperature?: number;
  maxTokens?: number;
}

export interface ConfiguredInferenceEnvelope {
  ok: boolean;
  result?: {
    content: string;
    providerId: string;
    providerName: string;
    modelId: string;
  };
  error?: string;
  errorCode?:
    | "configuration_required"
    | "credentials_rejected"
    | "network"
    | "request_failed";
}

/**
 * Run a generic structured conversation through the Mac's configured provider.
 * The bridge resolves Talkie settings; protocol translation remains in the
 * reusable Gateway provider registry.
 */
export async function configuredInferenceRoute(
  body: ConfiguredInferenceRequestBody
): Promise<ConfiguredInferenceEnvelope> {
  const messages: Message[] = [];
  for (const message of body.messages ?? []) {
    const content = message.content?.trim();
    if (
      content &&
      (message.role === "system" || message.role === "user" || message.role === "assistant")
    ) {
      messages.push({ role: message.role, content });
    }
  }

  if (messages.length === 0) {
    return { ok: false, error: "Inference needs at least one message." };
  }

  try {
    const settings = await loadComposeSettings();
    const configured = talkieProviderToInferenceProvider(settings.providerId);
    const provider = resolveProvider(configured);

    if (!provider) {
      return {
        ok: false,
        error: "No Mac AI provider is configured. Add an API key on the Mac and try again.",
        errorCode: "configuration_required",
      };
    }

    const model =
      provider === configured && settings.modelId
        ? settings.modelId
        : defaultModelForProvider(provider);
    const response = await inference({
      provider,
      model,
      messages,
      temperature: body.temperature ?? 0.3,
      maxTokens: body.maxTokens ?? 2048,
    });
    const providerId = inferenceProviderToTalkieProvider(provider);

    log.info(`Configured inference via ${providerId}/${model}`);
    return {
      ok: true,
      result: {
        content: response.content.trim(),
        providerId,
        providerName: providerDisplayName(providerId),
        modelId: model,
      },
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    log.error(`Configured inference failed: ${message}`);
    return { ok: false, error: message, errorCode: classifyError(message) };
  }
}

function resolveProvider(configured: ProviderName | null): ProviderName | null {
  if (configured && readProviderAPIKey(configured)) {
    return configured;
  }

  return DEFAULT_PROVIDER_ORDER.find((provider) => readProviderAPIKey(provider)) ?? null;
}

function classifyError(
  message: string
): NonNullable<ConfiguredInferenceEnvelope["errorCode"]> {
  const normalized = message.toLowerCase();
  if (normalized.includes("not configured") || normalized.includes("api key")) {
    return "configuration_required";
  }
  if (/\b(?:401|403)\b/.test(normalized) || normalized.includes("unauthorized")) {
    return "credentials_rejected";
  }
  if (
    normalized.includes("fetch failed") ||
    normalized.includes("network") ||
    normalized.includes("timed out") ||
    normalized.includes("timeout") ||
    normalized.includes("econn") ||
    normalized.includes("unable to connect")
  ) {
    return "network";
  }
  return "request_failed";
}
