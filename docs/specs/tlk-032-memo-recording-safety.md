# TLK-032: Memo Recording Safety Contract

**Status**: Draft
**Owner**: Talkie
**Date**: 2026-06-16
**Studio**: /eng/tlk-032

## Problem

Mac memo recording treated wall-clock elapsed time as the recording truth. If the
audio recorder stopped or finalized a shorter file, Talkie could show and save a
long memo whose audio only contained the first part of the recording. The raw
source file also lived in system temporary storage, so failed or clipped memos
could lose the only useful recovery artifact.

## Contract

1. Original capture is sacred. A memo recording writes to durable app support
   storage as soon as capture starts.
2. The user is told immediately when input health is jeopardized. A stopped
   recorder cannot keep looking like a healthy recording.
3. Stop finalizes audio before any transcription or memo processing.
4. Actual finalized media duration is the duration of record. Wall-clock time is
   diagnostic only.
5. Canonical audio is saved and validated before transcription starts.
6. Transcription is secondary. If transcription fails, the memo still exists with
   audio and a retryable failed/pending transcript state.
7. Original artifacts follow a user-level retention policy. Successful originals
   use the user's retention window. Problem originals are kept until reviewed by
   default.
8. Any derived or copied audio is spot checked for decodability and duration
   before it replaces or represents the original.

## Gaps Found

- Recording started in `/var/folders` temporary storage.
- Failed stop validation deleted the temp file instead of preserving it.
- The live timer still tracked wall-clock time during capture.
- Memo creation waited for transcription, so transcription failure could leave
  only an audio file with no memo row.
- Memo original retention was not user configurable.

## Implemented

- Memo recording now writes the original capture directly to durable app support
  storage.
- Finalized originals are measured with `AVAudioFile`; severe wall-clock versus
  media-duration mismatch fails the recording and preserves the original.
- The live timer uses recorder-captured duration instead of wall-clock duration.
- Canonical audio is copied through a staged file, validated, then swapped into
  `Audio/` with rollback for any existing destination.
- Recording start does not require the transcription engine to be online.
- New memos, note audio, and continuation segments create or update pending
  database rows after audio save and before transcription starts.
- Transcription failure marks the row failed/retryable and keeps both canonical
  audio and the original artifact.
- The memo detail JSON exposes storage metadata: canonical audio, raw original
  audio, local transcript/export paths, and active original-retention policy.
- Successful originals are pruned from flat file storage after the user
  retention window.
- Problem originals use a `.problem.m4a` filename suffix and are not pruned
  while the safety override is enabled. If the user disables that override
  later, existing problem originals re-enter the normal retention window.

## Implementation Notes

- Original memo captures live as flat files under
  `~/Library/Application Support/Talkie/MemoRecordings/`.
  The default raw filename is `<recording-id>.original.m4a`; problem originals
  are renamed to `<recording-id>.problem.m4a`. Repeated note captures may use a
  timestamp suffix to avoid overwriting a prior original for the same note id.
- Memo recording does not write a per-recording folder or `manifest.json`.
  Metadata that needs to be shared for debugging belongs in the memo detail JSON
  and export system.
- The canonical playable audio remains in `~/Library/Application Support/Talkie/Audio/`.
- Interrupted, mismatched, unreadable, or transcription-failed originals are
  treated as problem originals and are not assigned automatic deletion while the
  safety override is enabled.
