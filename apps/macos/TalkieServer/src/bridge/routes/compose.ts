import { log } from "../../log";
import { encryptJson, type EncryptedMessage } from "../../crypto/box";
import { getDeviceEncryptionKey } from "../../devices/registry";
import {
  defaultModelForProvider,
  inferenceProviderToTalkieProvider,
  loadComposeSettings,
  providerDisplayName,
  readProviderAPIKey,
  talkieProviderToInferenceProvider,
} from "../../talkie/settings";
import { inference } from "../../gateway/providers";
import type { ProviderName } from "../../gateway/providers";

const DEFAULT_PROVIDER_ORDER: ProviderName[] = [
  "groq",
  "openai",
  "anthropic",
  "google",
];
const DIRECT_COMPOSE_PROVIDER_ORDER = ["groq", "openai"] as const;
type DirectComposeProviderName = (typeof DIRECT_COMPOSE_PROVIDER_ORDER)[number];

const DIRECT_COMPOSE_MODEL_OPTIONS: Record<
  DirectComposeProviderName,
  Array<{ id: string; name: string }>
> = {
  groq: [
    { id: "llama-3.3-70b-versatile", name: "Llama 3.3 70B" },
    { id: "llama-3.1-8b-instant", name: "Llama 3.1 8B Instant" },
    { id: "gemma2-9b-it", name: "Gemma 2 9B" },
  ],
  openai: [
    { id: "gpt-5.5", name: "GPT-5.5" },
    { id: "gpt-5.4", name: "GPT-5.4" },
    { id: "gpt-5.4-mini", name: "GPT-5.4 Mini" },
    { id: "gpt-5-nano", name: "GPT-5 Nano" },
    { id: "gpt-5.2-chat-latest", name: "GPT-5.2" },
    { id: "o4-mini", name: "o4-mini" },
    { id: "gpt-5.2-pro", name: "GPT-5.2 Pro" },
  ],
};

const DEFAULT_COMPOSE_TEMPERATURE = 0.3;
const DEFAULT_COMPOSE_MAX_TOKENS = 2048;

export interface ComposeRevisionRequestBody {
  text: string;
  instruction: string;
}

export interface ComposeCommandRequestBody {
  context: string;
  instruction: string;
  title?: string | null;
  sourceDescription?: string | null;
}

export interface ComposeBorrowedProviderRequestBody {
  providerId?: string | null;
  modelId?: string | null;
}

export interface ComposeRevisionEnvelope {
  ok: boolean;
  result?: {
    revisedText: string;
    providerId: string;
    providerName: string;
    modelId: string;
    usedConfiguredProvider: boolean;
    usedConfiguredModel: boolean;
    fallbackReason?: string;
  };
  error?: string;
}

export interface ComposeBorrowedProviderEnvelope {
  ok: boolean;
  encrypted?: EncryptedMessage;
  error?: string;
}

export interface ComposeCommandEnvelope {
  ok: boolean;
  result?: {
    outputText: string;
    providerId: string;
    providerName: string;
    modelId: string;
    usedConfiguredProvider: boolean;
    usedConfiguredModel: boolean;
    fallbackReason?: string;
  };
  error?: string;
}

export interface ComposeDirectOptionsEnvelope {
  ok: boolean;
  result?: {
    providers: Array<{
      providerId: string;
      providerName: string;
      models: Array<{ id: string; name: string }>;
    }>;
    selectedProviderId: string;
    selectedModelId: string;
  };
  error?: string;
}

interface ComposeBorrowedProviderPayload {
  providerId: string;
  providerName: string;
  modelId: string;
  apiKey: string;
  assistantPrompt: string;
  fallbackReason?: string;
}

export async function composeRevisionRoute(
  body: ComposeRevisionRequestBody
): Promise<ComposeRevisionEnvelope> {
  const text = body.text.trim();
  const instruction = body.instruction.trim();

  if (!text) {
    return { ok: false, error: "Compose needs text before it can revise anything." };
  }

  if (!instruction) {
    return { ok: false, error: "Compose needs an instruction." };
  }

  try {
    const composeSettings = await loadComposeSettings();
    const configuredProviderId = composeSettings.providerId?.trim() || null;
    const configuredProvider = talkieProviderToInferenceProvider(configuredProviderId);
    const resolution = resolveComposeProvider(configuredProvider, configuredProviderId);

    if (!resolution) {
      return {
        ok: false,
        error:
          "No Mac cloud provider is configured for Compose yet. Add an API key on your Mac and try again.",
      };
    }

    const resolvedModel =
      resolution.provider === configuredProvider && composeSettings.modelId
        ? composeSettings.modelId
        : defaultModelForProvider(resolution.provider);

    const prompt = buildComposePrompt(text, instruction);
    const result = await inference({
      provider: resolution.provider,
      model: resolvedModel,
      messages: [
        { role: "system", content: composeSettings.assistantPrompt },
        { role: "user", content: prompt },
      ],
      temperature: DEFAULT_COMPOSE_TEMPERATURE,
      maxTokens: DEFAULT_COMPOSE_MAX_TOKENS,
    });

    const talkieProviderId = inferenceProviderToTalkieProvider(resolution.provider);
    const fallbackReason =
      resolution.provider === configuredProvider ? undefined : resolution.reason;

    log.info(
      `Compose revision via ${talkieProviderId}/${resolvedModel} ` +
        `(configured=${configuredProviderId || "none"})`
    );

    return {
      ok: true,
      result: {
        revisedText: result.content.trim(),
        providerId: talkieProviderId,
        providerName: providerDisplayName(talkieProviderId),
        modelId: resolvedModel,
        usedConfiguredProvider: resolution.provider === configuredProvider,
        usedConfiguredModel:
          resolution.provider === configuredProvider && resolvedModel === composeSettings.modelId,
        fallbackReason,
      },
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    log.error(`Compose revision failed: ${message}`);
    return {
      ok: false,
      error: message,
    };
  }
}

export async function composeCommandRoute(
  body: ComposeCommandRequestBody
): Promise<ComposeCommandEnvelope> {
  const context = body.context.trim();
  const instruction = body.instruction.trim();
  const title = body.title?.trim() || undefined;
  const sourceDescription = body.sourceDescription?.trim() || undefined;

  if (!context) {
    return { ok: false, error: "AI Commands needs captured text before it can answer anything." };
  }

  if (!instruction) {
    return { ok: false, error: "AI Commands needs a command." };
  }

  try {
    const composeSettings = await loadComposeSettings();
    const configuredProviderId = composeSettings.providerId?.trim() || null;
    const configuredProvider = talkieProviderToInferenceProvider(configuredProviderId);
    const resolution = resolveComposeProvider(configuredProvider, configuredProviderId);

    if (!resolution) {
      return {
        ok: false,
        error:
          "No Mac cloud provider is configured for AI Commands yet. Add an API key on your Mac and try again.",
      };
    }

    const resolvedModel =
      resolution.provider === configuredProvider && composeSettings.modelId
        ? composeSettings.modelId
        : defaultModelForProvider(resolution.provider);

    const result = await inference({
      provider: resolution.provider,
      model: resolvedModel,
      messages: [
        { role: "system", content: buildComposeCommandAssistantPrompt() },
        {
          role: "user",
          content: buildComposeCommandPrompt({
            context,
            instruction,
            title,
            sourceDescription,
          }),
        },
      ],
      temperature: DEFAULT_COMPOSE_TEMPERATURE,
      maxTokens: DEFAULT_COMPOSE_MAX_TOKENS,
    });

    const talkieProviderId = inferenceProviderToTalkieProvider(resolution.provider);
    const fallbackReason =
      resolution.provider === configuredProvider ? undefined : resolution.reason;

    log.info(
      `Compose command via ${talkieProviderId}/${resolvedModel} ` +
        `(configured=${configuredProviderId || "none"})`
    );

    return {
      ok: true,
      result: {
        outputText: result.content.trim(),
        providerId: talkieProviderId,
        providerName: providerDisplayName(talkieProviderId),
        modelId: resolvedModel,
        usedConfiguredProvider: resolution.provider === configuredProvider,
        usedConfiguredModel:
          resolution.provider === configuredProvider && resolvedModel === composeSettings.modelId,
        fallbackReason,
      },
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    log.error(`Compose command failed: ${message}`);
    return {
      ok: false,
      error: message,
    };
  }
}

export async function composeBorrowedProviderRoute(
  deviceId: string | null,
  body: ComposeBorrowedProviderRequestBody
): Promise<ComposeBorrowedProviderEnvelope> {
  if (!deviceId) {
    return {
      ok: false,
      error: "Missing paired device identity.",
    };
  }

  try {
    const composeSettings = await loadComposeSettings();
    const configuredProviderId = composeSettings.providerId?.trim() || null;
    const configuredProvider = talkieProviderToInferenceProvider(configuredProviderId);

    const requestedProviderId = body.providerId?.trim() || null;
    const requestedModelId = body.modelId?.trim() || null;

    let selectedProvider: DirectComposeProviderName;
    let fallbackReason: string | undefined;

    if (requestedProviderId) {
      const requestedProvider = talkieProviderToInferenceProvider(requestedProviderId);
      if (!isDirectComposeProvider(requestedProvider)) {
        log.warn(`Borrowed compose provider rejected unsupported provider: ${requestedProviderId}`);
        return {
          ok: false,
          error: "That provider is not available for direct iPhone Compose.",
        };
      }

      if (!hasAPIKey(requestedProvider)) {
        log.warn(`Borrowed compose provider missing API key for requested provider: ${requestedProvider}`);
        return {
          ok: false,
          error:
            `${providerDisplayName(inferenceProviderToTalkieProvider(requestedProvider))} ` +
            "is not configured on your Mac.",
        };
      }

      selectedProvider = requestedProvider;
    } else {
      const resolution = resolveDirectComposeProvider(configuredProvider, configuredProviderId);

      if (!resolution) {
        log.warn("Borrowed compose provider unavailable: no OpenAI or Groq provider has an API key");
        return {
          ok: false,
          error:
            "No paired Mac Groq or OpenAI provider is configured for iPhone Compose yet.",
        };
      }

      selectedProvider = resolution.provider;
      fallbackReason =
        resolution.provider === configuredProvider ? undefined : resolution.reason;
    }

    const apiKey = readProviderAPIKey(selectedProvider);
    if (!apiKey) {
      log.warn(`Borrowed compose provider missing API key for selected provider: ${selectedProvider}`);
      return {
        ok: false,
        error: "The paired Mac provider is missing an API key.",
      };
    }

    const resolvedModel = resolveDirectModelId(
      selectedProvider,
      requestedModelId ||
        (selectedProvider === configuredProvider && composeSettings.modelId
          ? composeSettings.modelId
          : null)
    );

    const talkieProviderId = inferenceProviderToTalkieProvider(selectedProvider);
    const encryptionKey = await getDeviceEncryptionKey(deviceId);

    if (!encryptionKey) {
      log.warn(`Borrowed compose provider rejected unauthorized paired device: ${deviceId}`);
      return {
        ok: false,
        error: "The paired iPhone is no longer authorized. Re-pair and try again.",
      };
    }

    const encrypted = await encryptJson(
      {
        providerId: talkieProviderId,
        providerName: providerDisplayName(talkieProviderId),
        modelId: resolvedModel,
        apiKey,
        assistantPrompt: composeSettings.assistantPrompt,
        fallbackReason,
      } satisfies ComposeBorrowedProviderPayload,
      encryptionKey
    );

    log.info(
      `Borrowed compose provider via ${talkieProviderId}/${resolvedModel} ` +
        `for paired device ${deviceId}`
    );

    return {
      ok: true,
      encrypted,
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    log.error(`Borrowed compose provider failed: ${message}`);
    return {
      ok: false,
      error: message,
    };
  }
}

export async function composeDirectOptionsRoute(): Promise<ComposeDirectOptionsEnvelope> {
  try {
    const composeSettings = await loadComposeSettings();
    const configuredProviderId = composeSettings.providerId?.trim() || null;
    const configuredProvider = talkieProviderToInferenceProvider(configuredProviderId);
    const availableProviders = DIRECT_COMPOSE_PROVIDER_ORDER.filter(hasAPIKey);

    if (availableProviders.length === 0) {
      return {
        ok: false,
        error: "Add an OpenAI or Groq API key on your Mac to use direct iPhone Compose.",
      };
    }

    const selectedProvider =
      isDirectComposeProvider(configuredProvider) && hasAPIKey(configuredProvider)
        ? configuredProvider
        : availableProviders[0];
    const selectedModelId = resolveDirectModelId(
      selectedProvider,
      selectedProvider === configuredProvider ? composeSettings.modelId : null
    );

    return {
      ok: true,
      result: {
        providers: availableProviders.map((provider) => ({
          providerId: inferenceProviderToTalkieProvider(provider),
          providerName: providerDisplayName(inferenceProviderToTalkieProvider(provider)),
          models: directComposeModelOptions(
            provider,
            provider === configuredProvider ? composeSettings.modelId : null
          ),
        })),
        selectedProviderId: inferenceProviderToTalkieProvider(selectedProvider),
        selectedModelId,
      },
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    log.error(`Compose direct options failed: ${message}`);
    return {
      ok: false,
      error: message,
    };
  }
}

function resolveComposeProvider(
  configuredProvider: ProviderName | null,
  configuredProviderId: string | null
): { provider: ProviderName; reason?: string } | null {
  if (configuredProvider && hasAPIKey(configuredProvider)) {
    return { provider: configuredProvider };
  }

  for (const provider of DEFAULT_PROVIDER_ORDER) {
    if (hasAPIKey(provider)) {
      return configuredProviderId
        ? {
            provider,
            reason:
              `${providerDisplayNameFromConfigured(configuredProvider, configuredProviderId)} ` +
              "is not available to iPhone Compose, so Talkie used another configured Mac provider.",
          }
        : {
            provider,
            reason: "Talkie used the first configured Mac provider because Compose has no saved provider.",
          };
    }
  }

  return null;
}

function resolveDirectComposeProvider(
  configuredProvider: ProviderName | null,
  configuredProviderId: string | null
): { provider: (typeof DIRECT_COMPOSE_PROVIDER_ORDER)[number]; reason?: string } | null {
  if (isDirectComposeProvider(configuredProvider) && hasAPIKey(configuredProvider)) {
    return { provider: configuredProvider };
  }

  for (const provider of DIRECT_COMPOSE_PROVIDER_ORDER) {
    if (hasAPIKey(provider)) {
      return configuredProviderId
        ? {
            provider,
            reason:
              `${providerDisplayNameFromConfigured(configuredProvider, configuredProviderId)} ` +
              "is not available for direct iPhone Compose, so Talkie borrowed another Mac provider.",
          }
        : {
            provider,
            reason:
              "Talkie borrowed the first paired Mac provider available for direct iPhone Compose.",
          };
    }
  }

  return null;
}

function isDirectComposeProvider(
  provider: ProviderName | null
): provider is DirectComposeProviderName {
  return provider === "groq" || provider === "openai";
}

function directComposeModelOptions(
  provider: DirectComposeProviderName,
  preferredModelId: string | null
): Array<{ id: string; name: string }> {
  const options = [...DIRECT_COMPOSE_MODEL_OPTIONS[provider]];
  const normalizedPreferredModel = preferredModelId?.trim();

  if (
    normalizedPreferredModel &&
    !options.some((option) => option.id === normalizedPreferredModel)
  ) {
    options.unshift({
      id: normalizedPreferredModel,
      name: normalizedPreferredModel,
    });
  }

  return options;
}

function resolveDirectModelId(
  provider: DirectComposeProviderName,
  preferredModelId: string | null
): string {
  const normalizedPreferredModel = preferredModelId?.trim();
  if (
    normalizedPreferredModel &&
    !isLegacyDirectDefaultModel(provider, normalizedPreferredModel)
  ) {
    return normalizedPreferredModel;
  }

  return directComposeModelOptions(provider, null)[0]?.id ?? defaultModelForProvider(provider);
}

function isLegacyDirectDefaultModel(
  provider: DirectComposeProviderName,
  modelId: string
): boolean {
  return (
    provider === "openai" &&
    (modelId === "gpt-5.2-chat-latest" || modelId === "gpt-5.4-mini")
  );
}

function providerDisplayNameFromConfigured(
  configuredProvider: ProviderName | null,
  configuredProviderId: string
): string {
  if (configuredProvider) {
    return providerDisplayName(inferenceProviderToTalkieProvider(configuredProvider));
  }

  if (configuredProviderId === "apple-local") {
    return providerDisplayName("apple-local");
  }

  return configuredProviderId;
}

function hasAPIKey(provider: ProviderName): boolean {
  return !!readProviderAPIKey(provider);
}

function buildComposePrompt(text: string, instruction: string): string {
  return [
    "User instruction:",
    instruction,
    "",
    "Editing scope:",
    "Entire document.",
    "",
    "Current target text:",
    text,
    "",
    "Current full document:",
    text,
    "",
    "Revision history (oldest to newest):",
    "No prior revisions.",
    "",
    "Return only the revised text for the current target text.",
  ].join("\n");
}

function buildComposeCommandAssistantPrompt(): string {
  return [
    "You help the user run quick AI commands against captured text from their device.",
    "Use the captured text as the primary context.",
    "Answer directly in concise, speech-friendly prose unless the user explicitly asks for another format.",
    "If the capture does not contain enough information, say so briefly and answer with the best grounded help you can.",
    "Return only the answer.",
  ].join("\n");
}

function buildComposeCommandPrompt({
  context,
  instruction,
  title,
  sourceDescription,
}: {
  context: string;
  instruction: string;
  title?: string;
  sourceDescription?: string;
}): string {
  const lines: string[] = [];

  lines.push("Source:");
  lines.push(sourceDescription || "Captured text");

  if (title) {
    lines.push("");
    lines.push("Title:");
    lines.push(title);
  }

  lines.push("");
  lines.push("Captured text:");
  lines.push(context);
  lines.push("");
  lines.push("User instruction:");
  lines.push(instruction);
  lines.push("");
  lines.push("Return only the answer.");

  return lines.join("\n");
}
