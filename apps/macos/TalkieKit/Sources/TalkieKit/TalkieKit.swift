//
//  TalkieKit.swift
//  TalkieKit
//
//  Shared components for Talkie apps
//

// Re-export all public types
@_exported import Foundation
@_exported import SwiftUI
@_exported import TalkieCore

// Console components are available via:
// - ConsoleView
// - ConsoleEntry
// - ConsoleLogLevel
// - ConsoleTheme

// LLM Provider components are available via:
// - LLMProvider (protocol)
// - LLMProviderRegistry
// - LLMModel, LLMModelType
// - LLMGenerationOptions
// - LLMError
// - LLMAPIKeyStore, LLMAPIKeyProvider
// - LLMOpenAIProvider, LLMAnthropicProvider, LLMGeminiProvider, LLMGroqProvider

// Diff components are available via:
// - TextDiff
// - DiffEngine
// - DiffOperation

// SmartAction components are available via:
// - SmartAction

// Unified Tracing components are available via:
// - TraceSource (.talkie, .live, .engine)
// - TraceSpan (a single timed operation)
// - UnifiedTrace (collects spans for a flow)
// - CorrelatedTrace (spans from multiple apps correlated by traceId)
