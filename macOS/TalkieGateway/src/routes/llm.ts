/**
 * LLM Router
 *
 * OpenRouter-style unified API for multiple LLM providers.
 * Gateway translates protocols, not intent.
 *
 * Endpoints:
 * - POST /llm/chat     - Chat completions (unified interface)
 * - GET  /llm/providers - List available providers
 * - GET  /llm/models    - List models by provider
 */

import OpenAI from "openai";
import Anthropic from "@anthropic-ai/sdk";
import { GoogleGenerativeAI } from "@google/generative-ai";

// Types

interface Message {
  role: "system" | "user" | "assistant";
  content: string;
}

interface ChatRequest {
  provider: "openai" | "anthropic" | "gemini" | "groq";
  model: string;
  messages: Message[];
  temperature?: number;
  max_tokens?: number;
  top_p?: number;
  stream?: boolean;
}

interface ChatResponse {
  id: string;
  provider: string;
  model: string;
  choices: Array<{
    index: number;
    message: Message;
    finish_reason: string;
  }>;
  usage?: {
    prompt_tokens: number;
    completion_tokens: number;
    total_tokens: number;
  };
}

interface Provider {
  id: string;
  name: string;
  available: boolean;
  models: string[];
}

// Provider registry

const PROVIDER_MODELS: Record<string, string[]> = {
  openai: [
    "gpt-4o",
    "gpt-4o-mini",
    "gpt-4-turbo",
    "gpt-4",
    "gpt-3.5-turbo",
    "o1",
    "o1-mini",
    "o3-mini",
  ],
  anthropic: [
    "claude-3-5-sonnet-latest",
    "claude-3-5-haiku-latest",
    "claude-3-opus-latest",
  ],
  gemini: [
    "gemini-2.0-flash-exp",
    "gemini-1.5-pro",
    "gemini-1.5-flash",
  ],
  groq: [
    "llama-3.3-70b-versatile",
    "llama-3.1-8b-instant",
    "mixtral-8x7b-32768",
  ],
};

// API Key helpers

function getApiKey(provider: string): string | null {
  // Check environment variables
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

async function chatOpenAI(req: ChatRequest): Promise<ChatResponse> {
  const apiKey = getApiKey("openai");
  if (!apiKey) throw new Error("OpenAI API key not configured");

  const client = new OpenAI({ apiKey });

  const response = await client.chat.completions.create({
    model: req.model,
    messages: req.messages,
    temperature: req.temperature ?? 0.7,
    max_tokens: req.max_tokens ?? 2048,
    top_p: req.top_p ?? 1.0,
  });

  return {
    id: response.id,
    provider: "openai",
    model: req.model,
    choices: response.choices.map((c, i) => ({
      index: i,
      message: {
        role: c.message.role as "assistant",
        content: c.message.content || "",
      },
      finish_reason: c.finish_reason || "stop",
    })),
    usage: response.usage
      ? {
          prompt_tokens: response.usage.prompt_tokens,
          completion_tokens: response.usage.completion_tokens,
          total_tokens: response.usage.total_tokens,
        }
      : undefined,
  };
}

async function chatAnthropic(req: ChatRequest): Promise<ChatResponse> {
  const apiKey = getApiKey("anthropic");
  if (!apiKey) throw new Error("Anthropic API key not configured");

  const client = new Anthropic({ apiKey });

  // Extract system message if present
  const systemMessage = req.messages.find((m) => m.role === "system");
  const nonSystemMessages = req.messages.filter((m) => m.role !== "system");

  const response = await client.messages.create({
    model: req.model,
    max_tokens: req.max_tokens ?? 2048,
    system: systemMessage?.content,
    messages: nonSystemMessages.map((m) => ({
      role: m.role as "user" | "assistant",
      content: m.content,
    })),
  });

  const content =
    response.content[0]?.type === "text" ? response.content[0].text : "";

  return {
    id: response.id,
    provider: "anthropic",
    model: req.model,
    choices: [
      {
        index: 0,
        message: { role: "assistant", content },
        finish_reason: response.stop_reason || "stop",
      },
    ],
    usage: {
      prompt_tokens: response.usage.input_tokens,
      completion_tokens: response.usage.output_tokens,
      total_tokens: response.usage.input_tokens + response.usage.output_tokens,
    },
  };
}

async function chatGemini(req: ChatRequest): Promise<ChatResponse> {
  const apiKey = getApiKey("gemini");
  if (!apiKey) throw new Error("Gemini API key not configured");

  const genAI = new GoogleGenerativeAI(apiKey);
  const model = genAI.getGenerativeModel({ model: req.model });

  // Gemini has different message format
  // Concatenate system + user messages for simplicity
  const systemMessage = req.messages.find((m) => m.role === "system");
  const lastUserMessage = req.messages.filter((m) => m.role === "user").pop();

  const prompt = systemMessage
    ? `${systemMessage.content}\n\n${lastUserMessage?.content || ""}`
    : lastUserMessage?.content || "";

  const result = await model.generateContent({
    contents: [{ role: "user", parts: [{ text: prompt }] }],
    generationConfig: {
      temperature: req.temperature ?? 0.7,
      maxOutputTokens: req.max_tokens ?? 2048,
      topP: req.top_p ?? 1.0,
    },
  });

  const content = result.response.text();
  const usage = result.response.usageMetadata;

  return {
    id: `gemini-${Date.now()}`,
    provider: "gemini",
    model: req.model,
    choices: [
      {
        index: 0,
        message: { role: "assistant", content },
        finish_reason: "stop",
      },
    ],
    usage: usage
      ? {
          prompt_tokens: usage.promptTokenCount || 0,
          completion_tokens: usage.candidatesTokenCount || 0,
          total_tokens: usage.totalTokenCount || 0,
        }
      : undefined,
  };
}

async function chatGroq(req: ChatRequest): Promise<ChatResponse> {
  const apiKey = getApiKey("groq");
  if (!apiKey) throw new Error("Groq API key not configured");

  // Groq uses OpenAI-compatible API
  const client = new OpenAI({
    apiKey,
    baseURL: "https://api.groq.com/openai/v1",
  });

  const response = await client.chat.completions.create({
    model: req.model,
    messages: req.messages,
    temperature: req.temperature ?? 0.7,
    max_tokens: req.max_tokens ?? 2048,
    top_p: req.top_p ?? 1.0,
  });

  return {
    id: response.id,
    provider: "groq",
    model: req.model,
    choices: response.choices.map((c, i) => ({
      index: i,
      message: {
        role: c.message.role as "assistant",
        content: c.message.content || "",
      },
      finish_reason: c.finish_reason || "stop",
    })),
    usage: response.usage
      ? {
          prompt_tokens: response.usage.prompt_tokens,
          completion_tokens: response.usage.completion_tokens,
          total_tokens: response.usage.total_tokens,
        }
      : undefined,
  };
}

// Route handlers

export async function chatRoute(req: Request): Promise<Response> {
  try {
    const body = (await req.json()) as ChatRequest;

    // Validate required fields
    if (!body.provider || !body.model || !body.messages?.length) {
      return Response.json(
        { error: "Missing required fields: provider, model, messages" },
        { status: 400 }
      );
    }

    let response: ChatResponse;

    switch (body.provider) {
      case "openai":
        response = await chatOpenAI(body);
        break;
      case "anthropic":
        response = await chatAnthropic(body);
        break;
      case "gemini":
        response = await chatGemini(body);
        break;
      case "groq":
        response = await chatGroq(body);
        break;
      default:
        return Response.json(
          { error: `Unknown provider: ${body.provider}` },
          { status: 400 }
        );
    }

    return Response.json(response);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return Response.json({ error: message }, { status: 500 });
  }
}

export async function providersRoute(_req: Request): Promise<Response> {
  const providers: Provider[] = Object.keys(PROVIDER_MODELS).map((id) => ({
    id,
    name: id.charAt(0).toUpperCase() + id.slice(1),
    available: !!getApiKey(id),
    models: PROVIDER_MODELS[id],
  }));

  return Response.json({ providers });
}

export async function modelsRoute(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const provider = url.searchParams.get("provider");

  if (provider) {
    if (!PROVIDER_MODELS[provider]) {
      return Response.json(
        { error: `Unknown provider: ${provider}` },
        { status: 400 }
      );
    }
    return Response.json({
      provider,
      models: PROVIDER_MODELS[provider],
      available: !!getApiKey(provider),
    });
  }

  // Return all models grouped by provider
  const models = Object.entries(PROVIDER_MODELS).map(([id, modelList]) => ({
    provider: id,
    models: modelList,
    available: !!getApiKey(id),
  }));

  return Response.json({ models });
}
