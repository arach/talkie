# Talkie Testing Strategy

## Overview

This document outlines the strategy for implementing happy path tests for Talkie's core functionality. The goal is to ensure critical user journeys work correctly and catch regressions early.

---

## Phase 1: Happy Path Tests

**Status:** Planning
**Date:** 2025-01-22

### Core User Journeys to Test

#### 1. Memo Management
- [ ] Create a new memo (manual text entry)
- [ ] Edit an existing memo
- [ ] Save memo to database (GRDB)
- [ ] Delete a memo
- [ ] Verify memo persists across app restart

#### 2. Recording & Transcription
- [ ] Start a new recording
- [ ] Stop recording and receive audio file
- [ ] Transcribe audio (via TalkieEngine/Whisper)
- [ ] Save transcription as memo
- [ ] Verify audio file is saved correctly

#### 3. Live Dictation (TalkieAgent)
- [ ] Activate live dictation hotkey
- [ ] Capture audio during dictation
- [ ] Stop and transcribe
- [ ] Paste/insert text at cursor
- [ ] Interstitial flow (lite mode)

#### 4. Workflows
- [ ] Load workflow from file
- [ ] Execute simple workflow
- [ ] Execute workflow with LLM step
- [ ] Verify workflow outputs

#### 5. Polish/LLM Integration
- [ ] Apply polish to text (via configured provider)
- [ ] Diff review flow (accept/reject)
- [ ] Voice prompt → LLM instruction flow

---

## Technical Considerations

### Testing Approach Options

#### Option A: XCTest UI Tests
**Pros:**
- Native to Xcode
- Can test actual UI flows
- Good for end-to-end validation

**Cons:**
- Slow to run
- Flaky with timing issues
- Hard to test audio/microphone

#### Option B: XCTest Unit Tests with Mocks
**Pros:**
- Fast execution
- Reliable/deterministic
- Can test business logic in isolation

**Cons:**
- Doesn't test actual UI
- Requires dependency injection
- May miss integration issues

#### Option C: Integration Tests with Test Fixtures
**Pros:**
- Tests real database operations
- Tests actual file I/O
- More realistic than mocks

**Cons:**
- Need to manage test data
- Need separate test database
- Slower than pure unit tests

#### Option D: Scripted CLI Tests
**Pros:**
- Can test lite mode directly (`--interstitial`)
- Easy to automate in CI
- Tests actual binary

**Cons:**
- Limited to CLI-accessible features
- Hard to verify UI state
- May need custom test harness

### Recommended Approach

**Hybrid strategy:**
1. **Unit tests** for pure business logic (DiffEngine, TextDiff, WorkflowParser)
2. **Integration tests** for database operations (GRDB, memo CRUD)
3. **CLI tests** for lite interstitial mode
4. **Manual smoke tests** for audio/mic-dependent features (documented checklist)

---

## Implementation Plan

### Step 1: Test Infrastructure Setup
- [ ] Create `TalkieTests` target if not exists
- [ ] Set up test database (in-memory or temp file)
- [ ] Create test fixtures directory
- [ ] Add test audio samples (short .m4a files)

### Step 2: Unit Tests (Low-hanging fruit)
- [ ] `DiffEngine.diff()` - various text comparisons
- [ ] `TextDiff.attributedOriginal/Proposed()` - formatting
- [ ] `WorkflowParser` - YAML parsing
- [ ] `SmartAction` - action resolution

### Step 3: Integration Tests
- [ ] `DatabaseManager` - memo CRUD operations
- [ ] `MemoModel` - create, update, delete
- [ ] `RecordingModel` - audio file management
- [ ] `WorkflowService` - workflow loading/execution

### Step 4: CLI/E2E Tests
- [ ] Lite interstitial launch with test payload
- [ ] Polish operation with mock LLM response
- [ ] Copy to clipboard verification

### Step 5: CI Integration
- [ ] Run unit tests on every PR
- [ ] Run integration tests on main branch
- [ ] Document manual smoke test checklist

---

## Test Data Requirements

### Mock Audio Files
- `test-short.m4a` - 1-2 seconds of speech
- `test-silence.m4a` - silence (edge case)
- `test-noise.m4a` - background noise (edge case)

### Mock Transcriptions
- Simple sentence
- Multi-paragraph text
- Text with punctuation edge cases
- Unicode/emoji content

### Mock Workflows
- Minimal workflow (single step)
- Multi-step workflow
- Workflow with LLM integration

---

## Open Questions

1. **Audio testing:** How to test actual mic input without manual intervention?
   - Option: Use pre-recorded test files + mock audio capture layer

2. **LLM testing:** How to test LLM integration without API calls?
   - Option: Mock LLM provider that returns canned responses
   - Option: Use local model in test environment

3. **XPC testing:** How to test TalkieAgent ↔ Talkie communication?
   - Option: Integration test that launches both processes
   - Option: Mock XPC protocol for unit tests

4. **CloudKit testing:** How to test sync without affecting production data?
   - Option: Test with sync disabled
   - Option: Separate CloudKit container for tests

---

## Related Ideas

### Snapshot Testing for UI
Consider adding snapshot tests for key views:
- InterstitialEditorView
- LiteInterstitialView
- MemoDetailView
- DiffReviewView

### Performance Benchmarks
Track performance metrics for critical paths:
- App launch time (full vs lite mode)
- Transcription latency
- Database query performance
- UI responsiveness during polish

---

## References

- [XCTest Documentation](https://developer.apple.com/documentation/xctest)
- [GRDB Testing Guide](https://github.com/groue/GRDB.swift/blob/master/Documentation/GRDBTests.md)
- Existing test patterns in `apps/macos/Talkie/Tests/` (if any)
