# Workflow Capabilities

This is the quick human-readable map of the workflow step vocabulary available to the agent.

## Core text and reasoning

- `llm`
  - generate or transform text with a prompt
  - best for summaries, rewrites, classification, structured output, and drafting
- `transform`
  - reshape earlier output without another model call
  - good for simple extraction or format cleanup
- `conditional`
  - gate later behavior based on an expression

## System and scripting

- `shell`
  - run a local executable with arguments, stdin, environment, and timeout
  - best for tiny text-processing helpers, local scripts, file utilities, or `ffmpeg`/`ffprobe` over attached clips
- `saveFile`
  - write content to disk
- `clipboard`
  - copy content to the clipboard

## Voice and memo flow

- `transcribe`
  - create or refresh transcript text from memo audio
- `speak`
  - read text aloud with TTS
- `notification`
  - show a local macOS notification
- `iOSPush`
  - push a notification to iPhone

## Intent and orchestration

- `trigger`
  - detect phrase matches before continuing
- `intentExtract`
  - detect intents from text
- `executeWorkflows`
  - fan out into other workflows based on extracted intents

## Apple app actions

- `appleReminders`
  - create reminders
- `appleNotes`
  - create or update notes
- `appleCalendar`
  - create calendar events

## Network and outbound actions

- `webhook`
  - call an HTTP endpoint
- `email`
  - prepare outbound email
- `cloudUpload`
  - upload a generated artifact to cloud storage

## Practical advice

- When the user wants something cute or fast, start with `shell`, `llm`, `speak`, `notification`, or `saveFile`.
- When they want a “smart memo” workflow, start from `{{TRANSCRIPT}}`.
- When they want to process video, use `{{CLIP_PATH}}` / `{{VIDEO_PATH}}` for the first attached clip, `{{CLIP_PATHS}}` for all clips, and `{{CLIP_CONTEXT}}` for readable clip metadata.
- When they want a chain, give each step a clear `outputKey` and reference it later with `{{output_key}}`.
- Prefer the smallest viable workflow first. Then add pinning, auto-run, or action-surface configuration only if requested.
