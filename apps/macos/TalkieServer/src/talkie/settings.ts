import { existsSync } from "node:fs";

const HOME = process.env.HOME || "";

const DEFAULT_COMPOSE_PROMPT =
  "You are helping edit transcribed speech. Apply the user's instruction to transform the text.\n" +
  "Return only the transformed text, nothing else. Preserve the original meaning unless asked otherwise.";

const DEFAULT_SETTINGS_PATHS = [
  `${HOME}/Library/Application Support/Talkie.dev/settings/config.json`,
  `${HOME}/Library/Application Support/Talkie.staging/settings/config.json`,
  `${HOME}/Library/Application Support/Talkie/settings/config.json`,
];

const DEFAULT_SHARED_SETTINGS_SUITES = [
  "to.talkie.app.shared.dev",
  "to.talkie.app.shared.staging",
  "to.talkie.app.shared",
];

type ComposeSettingsFile = {
  compose?: {
    providerId?: string | null;
    modelId?: string | null;
    assistantPrompt?: string | null;
  };
};

export type TalkieComposeProviderId =
  | "openai"
  | "anthropic"
  | "gemini"
  | "groq"
  | "apple-local";

export interface ComposeSettingsSnapshot {
  configPath: string | null;
  providerId?: string;
  modelId?: string;
  assistantPrompt: string;
}

export function talkieProviderToInferenceProvider(
  providerId: string | null | undefined
): "openai" | "anthropic" | "google" | "groq" | null {
  switch ((providerId || "").trim()) {
    case "openai":
      return "openai";
    case "anthropic":
      return "anthropic";
    case "gemini":
      return "google";
    case "groq":
      return "groq";
    default:
      return null;
  }
}

export function inferenceProviderToTalkieProvider(
  providerId: "openai" | "anthropic" | "google" | "groq"
): Exclude<TalkieComposeProviderId, "apple-local"> {
  switch (providerId) {
    case "google":
      return "gemini";
    case "openai":
    case "anthropic":
    case "groq":
      return providerId;
  }
}

export function providerDisplayName(
  providerId: TalkieComposeProviderId | "google"
): string {
  switch (providerId) {
    case "openai":
      return "OpenAI";
    case "anthropic":
      return "Anthropic";
    case "gemini":
    case "google":
      return "Google Gemini";
    case "groq":
      return "Groq";
    case "apple-local":
      return "Apple Intelligence";
  }
}

export function defaultModelForProvider(
  providerId: "openai" | "anthropic" | "google" | "groq"
): string {
  switch (providerId) {
    case "openai":
      return "gpt-5.2-chat-latest";
    case "anthropic":
      return "claude-sonnet-4-20250514";
    case "google":
      return "gemini-2.0-flash";
    case "groq":
      return "llama-3.3-70b-versatile";
  }
}

export async function loadComposeSettings(): Promise<ComposeSettingsSnapshot> {
  const configPath = resolveSettingsConfigPath();
  if (!configPath) {
    return {
      configPath: null,
      assistantPrompt: DEFAULT_COMPOSE_PROMPT,
    };
  }

  try {
    const raw = await Bun.file(configPath).text();
    const parsed = JSON.parse(raw) as ComposeSettingsFile;
    const assistantPrompt = parsed.compose?.assistantPrompt?.trim();
    const providerId = parsed.compose?.providerId?.trim() || undefined;
    const modelId = parsed.compose?.modelId?.trim() || undefined;

    return {
      configPath,
      providerId,
      modelId,
      assistantPrompt:
        assistantPrompt && assistantPrompt.length > 0
          ? assistantPrompt
          : DEFAULT_COMPOSE_PROMPT,
    };
  } catch {
    return {
      configPath,
      assistantPrompt: DEFAULT_COMPOSE_PROMPT,
    };
  }
}

export function readProviderAPIKey(
  providerId: "openai" | "anthropic" | "google" | "groq"
): string | null {
  const settingsKey = providerSettingsKey(providerId);
  const explicitSuite = process.env.TALKIE_SHARED_SETTINGS_SUITE?.trim();
  if (explicitSuite) {
    return readDefaultsValue(explicitSuite, settingsKey);
  }

  for (const suite of DEFAULT_SHARED_SETTINGS_SUITES) {
    const value = readDefaultsValue(suite, settingsKey);
    if (value) {
      return value;
    }
  }

  return null;
}

function resolveSettingsConfigPath(): string | null {
  const explicitPath = process.env.TALKIE_SETTINGS_CONFIG_PATH?.trim();
  if (explicitPath && existsSync(explicitPath)) {
    return explicitPath;
  }

  return DEFAULT_SETTINGS_PATHS.find((path) => existsSync(path)) ?? null;
}

function providerSettingsKey(
  providerId: "openai" | "anthropic" | "google" | "groq"
): string {
  switch (providerId) {
    case "openai":
      return "openai_api_key";
    case "anthropic":
      return "anthropic_api_key";
    case "google":
      return "gemini_api_key";
    case "groq":
      return "groq_api_key";
  }
}

function readDefaultsValue(suite: string, key: string): string | null {
  const result = Bun.spawnSync(["defaults", "read", suite, key], {
    stdout: "pipe",
    stderr: "pipe",
  });

  if (result.exitCode !== 0) {
    return null;
  }

  const value = result.stdout.toString().trim();
  return value.length > 0 ? value : null;
}
