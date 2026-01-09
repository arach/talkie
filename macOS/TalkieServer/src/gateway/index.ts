/**
 * Gateway Module
 *
 * External API translation - unified interface to cloud inference providers.
 *
 * ROUTES:
 *   POST /inference           - Run inference through any provider
 *   GET  /inference/providers - List available providers
 *   GET  /inference/models    - List models for a provider
 *
 * PROVIDERS:
 *   openai    - GPT-4, GPT-3.5, etc.
 *   anthropic - Claude 3.5, Claude 3, etc.
 *   google    - Gemini (planned)
 *   groq      - Fast inference (planned)
 *
 * DEPENDS ON:
 *   OPENAI_API_KEY     - For OpenAI provider
 *   ANTHROPIC_API_KEY  - For Anthropic provider
 */

import { Elysia, t } from "elysia";
import {
  inferenceRoute,
  providersRoute,
  modelsRoute,
} from "./routes/inference";

export const gateway = new Elysia({ name: "gateway" })
  // ===== Inference =====
  .post("/inference", ({ body }) => inferenceRoute(body), {
    body: t.Object({
      provider: t.String(),
      model: t.String(),
      messages: t.Array(t.Object({
        role: t.String(),
        content: t.String(),
      })),
      temperature: t.Optional(t.Number()),
      maxTokens: t.Optional(t.Number()),
    }),
  })
  .get("/inference/providers", () => providersRoute())
  .get("/inference/models", ({ query }) => modelsRoute(query.provider), {
    query: t.Object({
      provider: t.Optional(t.String()),
    }),
  });

// Re-export provider types for external use
export type { InferenceRequest, InferenceResponse, ProviderName } from "./providers";
