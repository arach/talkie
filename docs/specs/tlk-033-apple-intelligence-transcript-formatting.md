# TLK-033: Apple Intelligence Transcript Formatting

**Status**: Draft
**Owner**: Talkie
**Date**: 2026-07-04
**Studio**: /eng/tlk-033

## Problem

Long memo transcripts currently land as one flat block of text. This makes the
first read worse than it needs to be, and it also weakens downstream workflows:
summaries, task extraction, search snippets, and human review all work better
when the transcript has paragraph-level structure.

Talkie already has Apple Foundation Models integration on macOS through
`AppleLocalProvider`, and the iOS keyboard has an experimental
`FoundationModels` smart-transform path. We should use that existing foundation
instead of creating a separate LLM adapter for transcript cleanup.

## Current Code Shape

- `apps/macos/Talkie/Services/LLM/AppleLocalProvider.swift` wraps
  `LanguageModelSession`, checks `SystemLanguageModel.default.availability`,
  prewarms the session, and exposes the provider as `apple-local`.
- `apps/macos/Talkie/Services/Screenshots/OCRRefinementService.swift` is the
  closest local precedent: it asks Apple Intelligence to conservatively refine
  OCR text, skips when unavailable, and never treats the model as the source of
  truth.
- `apps/macos/Talkie/Services/MemoRecordingController.swift` writes raw
  transcription output directly into `memo.transcription` and mirrored
  `TalkieObject.text`.
- `apps/macos/Talkie/Services/RecordingController.swift` routes scratch-pad
  dictation straight to paste or clipboard.
- `apps/ios/TalkieKeys/KeyboardViewController.swift` imports
  `FoundationModels`, checks `SystemLanguageModel.default.availability`, and has
  disabled keyboard smart transforms.

## Apple API Landscape

There are two separate Apple surfaces that matter here:

1. **Foundation Models framework**: direct model access through
   `LanguageModelSession` and `SystemLanguageModel`. This is the right backend
   for automatic transcript cleanup because it returns a string or structured
   value that Talkie can store.
2. **Writing Tools**: UI/text-view integration through UIKit/AppKit Writing
   Tools APIs. This is right for user-invoked rewrite/proofread/summary on
   editable transcript surfaces, not for automatic background processing.

The installed Xcode 26.5 SDK includes
`SystemLanguageModel.Guardrails.permissiveContentTransformations`, which is
worth using for transcript cleanup because the task is explicitly transforming
user-owned content without adding new content.

Apple's Writing Tools guidance also distinguishes plain text, rich text, lists,
tables, and presentation intents. Talkie's stored transcript is currently plain
text, so the first automatic formatting slice should only add paragraph breaks
and maybe markdown-compatible bullets when the source clearly contains a list.
Semantic rich text can come later when the memo editor has a richer storage
model.

## Product Contract

1. Raw transcription remains recoverable.
2. Automatic formatting must be conservative: paragraph breaks only in the first
   slice, no filler removal, no summarization, no rewriting tone, no invented
   content.
3. Formatting is opportunistic. If Apple Intelligence is unavailable, rate
   limited, refuses, or exceeds context, Talkie saves the raw transcript.
4. Formatting should not block audio preservation or the creation of a pending
   memo row.
5. Workflows should receive the active formatted transcript by default, with raw
   transcript access available once transcript provenance is formalized.
6. User-invoked Writing Tools belongs in editable transcript views, not in the
   recording critical path.

## Recommended First Slice

Create a macOS `TextFormattingService` with a transcript-specific
`formatTranscriptIfUseful` entry point that mirrors `OCRRefinementService`:

- Input: raw transcript string, recording id, transcription model id.
- Skip short transcripts below a threshold, for example under 120 words.
- Use `AppleLocalProvider` or a small Foundation Models specialization with
  `SystemLanguageModel(guardrails: .permissiveContentTransformations)`.
- Prompt for paragraph breaks only:

```text
Format this voice transcript into readable paragraphs.
Preserve the exact wording as much as possible.
Do not summarize, rewrite, remove fillers, add facts, add headings, or add bullets
unless the speaker clearly dictated a list.
Return only the formatted transcript.
```

- Validate the output before accepting it:
  - non-empty
  - within a reasonable character ratio of the raw transcript
  - no obvious preamble such as "Here is..."
  - preserves enough token overlap to avoid accidental summarization
- On success, save the formatted transcript as active text.
- Save raw and formatted entries in `transcript_versions` where practical:
  - raw: `sourceType = system_macos`, `engine = <transcription-model>`
  - formatted: `sourceType = system_macos`,
    `engine = <transcription-model>+apple_formatting`

If version persistence is too much for the first code slice, do not silently
discard raw text. Land the service behind a disabled setting or keep the feature
to display-time experiments until version storage is wired.

## Pipeline Placement

For macOS memo recording:

1. Save durable audio.
2. Create pending memo/recording row.
3. Transcribe raw audio.
4. Mark transcription complete with the raw word count.
5. Run Apple formatting as an augmentation step.
6. Persist formatted active transcript and raw/format versions.
7. Run media interleaving, workflow triggers, and title generation from the
   active formatted text.

For scratch-pad paste:

- Default should remain raw or app-context controlled. Users expect paste to be
  fast, and adding a model pass changes latency and wording-risk expectations.
- Add a separate "paste formatted" action later if this proves useful.

For iOS:

- Host app memo transcription can adopt the same contract later, but iOS memory
  pressure and keyboard extension limits argue against enabling automatic
  Foundation Models formatting in the keyboard path first.
- The existing disabled keyboard smart-transform path should stay disabled until
  recording-sidecar and memory behavior are stable.

## Writing Tools Surface

Writing Tools should be added to memo editing surfaces separately:

- Standard SwiftUI `TextEditor`/AppKit `NSTextView` paths may receive basic
  support automatically.
- Custom transcript cards should expose a Writing Tools entry only if they
  support selection, replacement, undo, and state changes cleanly.
- If Talkie later stores rich transcript content, Writing Tools result options
  can be expanded from plain text to rich text/list/presentation-intent handling.

This is a user editing feature, not the automatic transcript formatter.

## Open Questions

- Should formatted transcript become active by default, or should the UI show a
  raw/formatted toggle first?
- Should workflows get `{{TRANSCRIPT_RAW}}` beside existing `{{TRANSCRIPT}}`?
- Should paragraph formatting run before screenshot interleaving, or should
  interleaving use raw word timings and then project screenshots into formatted
  paragraphs?
- Should Apple formatting be configurable per recording mode: memo, note
  dictation, continuation segment, scratch-pad, keyboard?
- Do we need a Studio visual study for transcript version/provenance controls in
  the memo detail surface before Swift polish?

## References

- Apple Developer Documentation: Foundation Models,
  `https://developer.apple.com/documentation/foundationmodels`
- Apple Developer Documentation: Writing Tools,
  `https://developer.apple.com/documentation/uikit/writing-tools`
- WWDC25 "Dive deeper into Writing Tools",
  `https://developer.apple.com/videos/play/wwdc2025/265/`
- WWDC26 "What's new in the Foundation Models framework",
  `https://developer.apple.com/videos/play/wwdc2026/241/`
