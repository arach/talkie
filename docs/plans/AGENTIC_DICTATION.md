# Agentic Dictation

> Voice-first interaction with AI coding assistants and developer tools.

## Problem

Dictating to AI assistants (Claude Code, Codex, Gemini) and developer tools requires speaking technical syntax that doesn't map naturally to speech. Users say "slash commit" but want `/commit`. They say "at Claude" but want `@claude`.

Current symbolic mapping (Layer 1 of SSR) handles basic symbols deterministically, but agentic contexts have:
- **Tool-specific vocabulary** - slash commands, mentions, flags
- **Semantic ambiguity** - "slash" in "revenue slash expenses" vs "type slash"
- **Evolving patterns** - new tools, new commands, frequent updates

## Vision

A system that:
1. **Learns from documentation** - Ingest tool docs, derive patterns automatically
2. **Understands context** - Apply rules based on active app, semantic signals
3. **Handles ambiguity** - Distinguish "slash the budget" from "slash commit"

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   Rule Sources                          │
├──────────────────┬─────────────────┬────────────────────┤
│  Doc Ingestion   │  User Custom    │  Built-in          │
│  (claude-code,   │  (dictionary)   │  (symbolic mapper) │
│   APIs, CLIs)    │                 │                    │
└────────┬─────────┴────────┬────────┴──────────┬─────────┘
         │                  │                   │
         ▼                  ▼                   ▼
┌─────────────────────────────────────────────────────────┐
│              Unified Rule Registry                      │
│  - Pattern: spoken form + context conditions            │
│  - Output: replacement text or transformation           │
│  - Source: doc-derived | user | builtin                 │
└─────────────────────────┬───────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│           Context-Aware Rule Selector                   │
├─────────────────────────────────────────────────────────┤
│  Signals:                                               │
│  - Active app bundle ID (com.anthropic.claude-code)     │
│  - Semantic context embedding (code vs prose)           │
│  - Surrounding words (disambiguation)                   │
│  - User intent history                                  │
└─────────────────────────────────────────────────────────┘
```

## Rule Sources

### 1. Documentation Ingestion

Parse tool documentation to extract patterns:

**Input:** Claude Code docs, API references, CLI help text
**Output:** Structured rules with context constraints

```
Source: claude-code-docs
Commands extracted:
  /commit  → "slash commit"
  /help    → "slash help"
  /pr      → "slash PR", "slash pull request"
  /review  → "slash review"

Context: active_app contains "claude" OR "terminal"
```

**Ingestion pipeline:**
1. Fetch/read documentation (markdown, HTML, man pages)
2. Extract command patterns (slash commands, flags, syntax)
3. Generate spoken variants (phonetic, common misheard)
4. Store with source attribution for updates

### 2. User Custom Rules (Existing)

The dictionary system already handles user-defined replacements.
Agentic rules layer on top without replacing this.

### 3. Built-in Patterns (Existing)

SymbolicMapper handles deterministic symbol mapping.
Agentic patterns are context-conditional extensions.

## Context Signals

### Active App Detection

Already captured via `CapturedContext.appBundleId`:
- `com.anthropic.claude-code` → Claude Code rules
- `com.microsoft.VSCode` → VS Code / Copilot rules
- `com.apple.Terminal` → CLI rules
- `com.googlecode.iterm2` → CLI rules

### Semantic Context

Use lightweight embedding to classify text:
- **Code context**: technical terms, camelCase, syntax patterns
- **Prose context**: natural sentences, conversational tone
- **Command context**: imperative verbs, tool names

Could reuse existing NL embedding infrastructure.

### Disambiguation Heuristics

When "slash" appears:
- After "type", "enter", "press" → likely symbol intent
- After numbers or in "X slash Y" pattern → likely division/comparison
- At sentence start or after pause → likely command prefix

## Implementation Phases

### Phase 1: Static Command Extraction
- Parse Claude Code slash commands from docs
- Generate "slash X" → `/X` rules
- Gate by app bundle ID (claude, terminal, IDE)
- No ML, pure pattern matching

### Phase 2: Doc Ingestion Pipeline
- Build generic doc parser (markdown, HTML)
- Extract patterns: commands, flags, syntax
- Generate spoken variants automatically
- Support multiple doc sources

### Phase 3: Semantic Disambiguation
- Add embedding-based context detection
- Classify code vs prose context
- Use surrounding words for disambiguation
- Confidence thresholds for ambiguous cases

### Phase 4: Learning & Feedback
- Track user corrections (undo/retype)
- Adjust confidence based on usage patterns
- Surface suggestions for custom rules

## Example Transformations

| Spoken | Context | Output |
|--------|---------|--------|
| "slash commit" | Claude Code | `/commit` |
| "slash commit" | Google Docs | "slash commit" (no change) |
| "at Claude fix this bug" | Claude Code | `@claude fix this bug` |
| "revenue slash expenses" | Any | "revenue slash expenses" (no change) |
| "dash dash verbose" | Terminal | `--verbose` |
| "flag verbose" | Terminal | `--verbose` |

## Open Questions

1. **Update frequency** - How often to re-ingest docs? On-demand vs scheduled?
2. **Conflict resolution** - When user rule conflicts with doc-derived rule?
3. **Confidence display** - Show user when ambiguous transformation applied?
4. **Offline support** - Cache doc-derived rules for offline use?

## Prior Art

- **SSR Design Doc**: `docs/gemini-plans/SPEECH_TO_TECHNICAL_SYNTAX.md`
- **SymbolicMapper**: `apps/macos/TalkieEngine/TalkieEngine/TextPostProcessor.swift`
- **CapturedContext**: Already captures app bundle ID

## Success Metrics

- Reduction in manual corrections when dictating to Claude/Codex
- Time saved vs typing commands manually
- User adoption of agentic workflows via voice
