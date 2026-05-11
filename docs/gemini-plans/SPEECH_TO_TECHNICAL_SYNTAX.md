# Spoken Syntax Restoration (SSR) Plan

## Overview
This document outlines a system for **Spoken Syntax Restoration (SSR)**. Unlike "Semantic Translation" (which turns intent into code), SSR focuses on the **fidelity of technical input**. It bridges the gap between how transcription engines hear technical terms ("slash user slash bin") and how systems expect them (`/usr/bin`).

**Goal**: Allow users to dictate code, paths, and commands with high precision by mapping phonetic/natural transcription artifacts back to strict technical syntax and existing codebase tokens.

## 1. The Core Problem
Transcription engines are trained on natural language.
*   **Input**: "git check out dash b feature slash login"
*   **Raw Transcript**: "git check out - b feature / login" (or worse: "get checkout dash be...")
*   **Desired Output**: `git checkout -b feature/login`

## 2. Solution Architecture

### Layer 1: Symbolic & Punctuation Mapping (The "Shorthand")
A deterministic or high-probability mapping of spoken punctuation to technical symbols.

| Spoken | Symbol | Context Rules |
| :--- | :--- | :--- |
| "slash" | `/` | When inside paths |
| "dash" / "tack" | `-` | Flags, kebab-case |
| "underscore" | `_` | snake_case |
| "tilde" | `~` | Home dir |
| "open paren" | `(` | Code |
| "close bracket" | `]` | Code |

**Implementation**:
*   A post-processing text stream parser.
*   State machine: "slash" at start of word = `/`.

### Layer 2: Contextual Token Matching (The "Index")
To correctly map "get user id" to `getUserID` vs `get_user_id`, the system must know **what tokens actually exist** in the target environment.

#### A. The Indexer (Static Analysis)
We scan the user's active context (project directory, shell environment) to build a **Vocabulary Tree**.
*   **Bash**: Scan `$PATH` for executables (`git`, `docker`, `cargo`).
*   **Code**: Scan files (Tree-sitter) for:
    *   Modules / Classes
    *   Function names
    *   Variables

#### B. The Search Strategy (Scoped Fuzzy Matching)
Instead of a flat search, use the hierarchy to narrow the probability space.
*   *User says*: "Talkie dot audio dot capture"
*   *System logic*:
    1.  Match "Talkie" -> Module `Talkie`
    2.  Look inside `Talkie` scope.
    3.  Match "audio" -> Submodule `Audio`
    4.  Look inside `Talkie.Audio` scope.
    5.  Match "capture" -> Class `Capture`.
*   *Result*: `Talkie.Audio.Capture` (Preserving casing from the index).

### Layer 3: Casing & Formatting Directives
Explicit commands to override default spacing/casing.
*   "Camel case get user id" -> `getUserId`
*   "Pascal case http request" -> `HTTPRequest`
*   "Snake case parse json" -> `parse_json`
*   "Kebab case docker compose" -> `docker-compose`

## 3. The "Validation Loop" (Synthetic Training)
To build a robust mapper, we treat this as a data problem. We can generate our own training/test set using the existing Text-to-Speech (TTS) engine.

**The Cycle**:
1.  **Source**: Take real code tokens: `kubectl get pods --all-namespaces`
2.  **Generate Audio**: Use TTS to speak it: *"Kube C T L get pods dash dash all namespaces"*
3.  **Transcribe**: Feed audio to Talkie's STT: *"cube ctl get pods - - all namespaces"*
4.  **Map**: Train/Tune the algorithm to map (3) back to (1).

**Benefit**: We can generate infinite training data across different languages (Python, Swift, Bash) to find common transcription failures (e.g., `ioctl` -> "eye oh ctl").

## 4. Implementation Plan

### Phase 1: The "Technical Dictation" Mode
A specific mode in TalkieAgent where aggressive symbolic mapping is enabled.
*   **Task**: Build a `SymbolicRestoration` service.
*   **Config**: A dictionary of spoken-to-symbol regex replacements.

### Phase 2: The "Project Indexer"
*   **Task**: A background agent (using `ripgrep` or `ctags` logic) that generates a lightweight `.talkie_index` of the current folder.
*   **Data Structure**: Trie (Prefix Tree) for efficient lookups.

### Phase 3: The Fuzzy Resolver
*   **Logic**: When a user pauses or finishes an utterance, scan the transcript for n-grams that fuzzily match entry nodes in the Index Trie.
*   **Replacement**: If confidence > threshold, replace "get user id" with the exact string from the index `getUserID`.

## 5. Usage Examples

**Bash Command**
*   *Spoken*: "git commit dash m quote fixed bug quote"
*   *Mapped*: `git commit -m "fixed bug"`

**Python Coding**
*   *Spoken*: "import os dot path"
*   *Mapped*: `import os.path`

**Function Call**
*   *Context*: `class UserManager { func verifyCredentials()... }`
*   *Spoken*: "user manager verify credentials"
*   *Mapped*: `UserManager.verifyCredentials`

## 6. Research Questions
*   **Latency**: Can we search a 100k token index in <50ms locally? (Likely yes, with standard FTS or Tries).
*   **Ambiguity**: "List" -> `List` (Python type) vs `list` (function)?
    *   *Resolution*: Use surrounding syntax (e.g., "capital list" vs "list").