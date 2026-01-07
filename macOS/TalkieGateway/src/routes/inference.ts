/**
 * LLM Inference Router
 *
 * Translates a unified inference request into provider-specific API calls.
 * Gateway translates protocols, not intent - Talkie decides what/why, Gateway handles how.
 *
 * Supported providers:
 * - openai: OpenAI GPT models
 * - anthropic: Claude models
 * - gemini: Google Gemini models
 * - groq: Groq-hosted models (fast inference)
 */

import OpenAI from "openai";
import Anthropic from "@anthropic-ai/sdk";
import { GoogleGenerativeAI } from "@google/generative-ai";
import { log } from "../log";

// Types
interface InferenceRequest {
  provider: "openai" | "anthropic" | "gemini" | "groq";
  model: string;
  prompt: string;
  systemPrompt?: string;
  temperature?: number;
  maxTokens?: number;
  topP?: number;
  stream?: boolean;
}

interface InferenceResponse {
  content: string;
  provider: string;
  model: string;
  usage?: {
    promptTokens: number;
    completionTokens: number;
    totalTokens: number;
  };
  durationMs: number;
}

// API key getters (from environment or Talkie-provided headers)
function getApiKey(provider: string, req: Request): string | null {
  // Check header first (Talkie may pass keys per-request)
  const headerKey = req.headers.get(`X-${provider.toUpperCase()}-API-KEY`);
  if (headerKey) return headerKey;

  // Fall back to environment
  switch (provider) {
    case "openai":
      return process.env.OPENAI_API_KEY || null;
    case "anthropic":
      return process.env.ANTHROPIC_API_KEY || null;
    case "gemini":
      return process.env.GEMINI_API_KEY || null;
    case "groq":
      return process.env.GROQ_API_KEY || null;
    default:
      return null;
  }
}

// Provider implementations
async function callOpenAI(
  req: Request,
  body: InferenceRequest
): Promise<InferenceResponse> {
  const apiKey = getApiKey("openai", req);
  if (!apiKey) throw new Error("OpenAI API key not configured");

  const client = new OpenAI({ apiKey });
  const startTime = performance.now();

  const messages: OpenAI.Chat.Completions.ChatCompletionMessageParam[] = [];
  if (body.systemPrompt) {
    messages.push({ role: "system", content: body.systemPrompt });
  }
  messages.push({ role: "user", content: body.prompt });

  const response = await client.chat.completions.create({
    model: body.model,
    messages,
    temperature: body.temperature ?? 0.7,
    max_tokens: body.maxTokens ?? 2048,
    top_p: body.topP ?? 1.0,
  });

  const content = response.choices[0]?.message?.content || "";
  const durationMs = Math.round(performance.now() - startTime);

  return {
    content,
    provider: "openai",
    model: body.model,
    usage: response.usage
      ? {
          promptTokens: response.usage.prompt_tokens,
          completionTokens: response.usage.completion_tokens,
          totalTokens: response.usage.total_tokens,
        }
      : undefined,
    durationMs,
  };
}

async function callAnthropic(
  req: Request,
  body: InferenceRequest
): Promise<InferenceResponse> {
  const apiKey = getApiKey("anthropic", req);
  if (!apiKey) throw new Error("Anthropic API key not configured");

  const client = new Anthropic({ apiKey });
  const startTime = performance.now();

  const response = await client.messages.create({
    model: body.model,
    max_tokens: body.maxTokens ?? 2048,
    system: body.systemPrompt,
    messages: [{ role: "user", content: body.prompt }],
  });

  const content =
    response.content[0]?.type === "text" ? response.content[0].text : "";
  const durationMs = Math.round(performance.now() - startTime);

  return {
    content,
    provider: "anthropic",
    model: body.model,
    usage: {
      promptTokens: response.usage.input_tokens,
      completionTokens: response.usage.output_tokens,
      totalTokens: response.usage.input_tokens + response.usage.output_tokens,
    },
    durationMs,
  };
}

async function callGemini(
  req: Request,
  body: InferenceRequest
): Promise<InferenceResponse> {
  const apiKey = getApiKey("gemini", req);
  if (!apiKey) throw new Error("Gemini API key not configured");

  const genAI = new GoogleGenerativeAI(apiKey);
  const model = genAI.getGenerativeModel({ model: body.model });
  const startTime = performance.now();

  // Gemini uses a different structure - system instruction is set on the model
  const prompt = body.systemPrompt
    ? `${body.systemPrompt}\n\n${body.prompt}`
    : body.prompt;

  const result = await model.generateContent({
    contents: [{ role: "user", parts: [{ text: prompt }] }],
    generationConfig: {
      temperature: body.temperature ?? 0.7,
      maxOutputTokens: body.maxTokens ?? 2048,
      topP: body.topP ?? 1.0,
    },
  });

  const content = result.response.text();
  const durationMs = Math.round(performance.now() - startTime);

  // Gemini doesn't always return usage metadata
  const usage = result.response.usageMetadata;

  return {
    content,
    provider: "gemini",
    model: body.model,
    usage: usage
      ? {
          promptTokens: usage.promptTokenCount || 0,
          completionTokens: usage.candidatesTokenCount || 0,
          totalTokens: usage.totalTokenCount || 0,
        }
      : undefined,
    durationMs,
  };
}

async function callGroq(
  req: Request,
  body: InferenceRequest
): Promise<InferenceResponse> {
  // Groq uses OpenAI-compatible API
  const apiKey = getApiKey("groq", req);
  if (!apiKey) throw new Error("Groq API key not configured");

  const client = new OpenAI({
    apiKey,
    baseURL: "https://api.groq.com/openai/v1",
  });
  const startTime = performance.now();

  const messages: OpenAI.Chat.Completions.ChatCompletionMessageParam[] = [];
  if (body.systemPrompt) {
    messages.push({ role: "system", content: body.systemPrompt });
  }
  messages.push({ role: "user", content: body.prompt });

  const response = await client.chat.completions.create({
    model: body.model,
    messages,
    temperature: body.temperature ?? 0.7,
    max_tokens: body.maxTokens ?? 2048,
    top_p: body.topP ?? 1.0,
  });

  const content = response.choices[0]?.message?.content || "";
  const durationMs = Math.round(performance.now() - startTime);

  return {
    content,
    provider: "groq",
    model: body.model,
    usage: response.usage
      ? {
          promptTokens: response.usage.prompt_tokens,
          completionTokens: response.usage.completion_tokens,
          totalTokens: response.usage.total_tokens,
        }
      : undefined,
    durationMs,
  };
}

// Route handler
export async function inferenceRoute(req: Request): Promise<Response> {
  try {
    const body = (await req.json()) as InferenceRequest;

    // Validate required fields
    if (!body.provider || !body.model || !body.prompt) {
      return Response.json(
        { error: "Missing required fields: provider, model, prompt" },
        { status: 400 }
      );
    }

    log.info(`Inference: ${body.provider}/${body.model}`);

    let result: InferenceResponse;

    switch (body.provider) {
      case "openai":
        result = await callOpenAI(req, body);
        break;
      case "anthropic":
        result = await callAnthropic(req, body);
        break;
      case "gemini":
        result = await callGemini(req, body);
        break;
      case "groq":
        result = await callGroq(req, body);
        break;
      default:
        return Response.json(
          { error: `Unknown provider: ${body.provider}` },
          { status: 400 }
        );
    }

    log.info(
      `Inference complete: ${result.durationMs}ms, ${result.usage?.totalTokens || "?"} tokens`
    );

    return Response.json(result);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    log.error(`Inference error: ${message}`);
    return Response.json({ error: message }, { status: 500 });
  }
}

// Health check for available providers
export async function inferenceProvidersRoute(req: Request): Promise<Response> {
  const providers = [
    {
      id: "openai",
      name: "OpenAI",
      available: !!getApiKey("openai", req),
    },
    {
      id: "anthropic",
      name: "Anthropic",
      available: !!getApiKey("anthropic", req),
    },
    {
      id: "gemini",
      name: "Gemini",
      available: !!getApiKey("gemini", req),
    },
    {
      id: "groq",
      name: "Groq",
      available: !!getApiKey("groq", req),
    },
  ];

  return Response.json({ providers });
}
