---
name: talkie
description: >
  Query Talkie voice memos, dictations, workflows, and stats via the CLI.
  Use when the user asks about their recordings, transcripts, dictation history,
  or anything related to Talkie data. Also provides context about what Talkie
  can do — voice memos, live dictation, screenshots, and workflow automation.
---

# Talkie

Voice-first productivity suite for macOS. Talkie captures speech — voice memos and live keyboard dictation — transcribes it on-device, and routes the text where it needs to go.

## What Talkie Does

**Voice Memos** — Long-form recordings with transcription, AI summaries, task extraction, and workflow automation. Think voice notes that turn into structured documents.

**Live Dictation** — Press a hotkey, speak, release. Talkie transcribes and pastes directly into whatever app you're in. Sub-second latency, works everywhere.

**Screenshots** — During any recording, Hyper+S captures a fullscreen screenshot timestamped to the recording timeline. Screenshots are interleaved with the transcript.

**Workflows** — Post-processing pipelines that run on recordings: summarize, extract tasks, polish prose, translate, etc.

## Data

Everything lives in a local SQLite database (`~/Library/Application Support/Talkie/talkie.sqlite`). The unified `recordings` table holds both memos and dictations. Key fields:

| Field | Description |
|-------|-------------|
| `id` | UUID |
| `type` | `memo` or `dictation` |
| `text` | Transcript |
| `title` | Auto-generated or user-set (memos) |
| `summary` | AI-generated summary (memos) |
| `tasks` | Extracted action items (memos) |
| `notes` | User notes or interleaved screenshot markdown |
| `duration` | Recording length in seconds |
| `source` | `mac`, `iphone`, `watch`, `live` |
| `segmentsJSON` | Word-level timestamps |
| `screenshotsJSON` | Screenshot metadata array |
| `metadataJSON` | Dictation context (target app, routing mode) |
| `createdAt` | Timestamp |

## CLI Tool

The `talkie` command provides read access to all Talkie data.

**Output format:** Pretty (human-readable) in a terminal, JSON when piped. Override with `--json` or `--pretty`.

> **Note for Claude Code:** Since the Bash tool is not a TTY, `talkie` commands output JSON by default in this context. Add `--pretty` explicitly when human-readable output is needed. When composing with `jq`, omit `--pretty` to get clean JSON.

### Querying recordings

```bash
# Recent memos
talkie memos --pretty
talkie memos --since 7d --pretty

# Recent dictations
talkie dictations --since 24h --pretty

# Get a specific recording by ID prefix
talkie memos a1b2c3 --pretty
talkie dictations f9e8 --pretty

# Word-level timestamps
talkie memos a1b2c3 --segments --pretty
```

### Search & filters

`talkie search` is the primary query interface. Text query is optional — use filters alone or combine them.

```bash
# Full-text search
talkie search "meeting notes" --pretty
talkie search "budget" --type memo --pretty

# Filter-only (no text query)
talkie search --since 7d --type memo --pretty
talkie search --type dictation --app Cursor --since 24h --pretty

# Text + filters
talkie search "API redesign" --type dictation --has summary --pretty

# Date ranges
talkie search --since 2026-02-01 --until 2026-02-15 --pretty

# Duration filters
talkie search --longer-than 60 --shorter-than 300 --sort longest --pretty

# Feature filters
talkie search --has screenshots --pretty
talkie search --has summary --type memo --since 7d --pretty

# Source filter
talkie search --source mac --since 7d --pretty

# Sort options: newest (default), oldest, longest, shortest, relevance
talkie search "project" --sort relevance --pretty
talkie search --since 30d --sort longest --pretty
```

**Filter reference:**

| Flag | Values | Description |
|------|--------|-------------|
| `--since` | `7d`, `24h`, `2026-02-01` | Created after |
| `--until` | `7d`, `2026-02-15` | Created before |
| `--type` | `memo`, `dictation` | Recording type |
| `--app` | app name or bundle ID | Target app (dictations) |
| `--source` | `mac`, `iphone`, `watch`, `live` | Recording source |
| `--has` | `screenshots`, `summary`, `tasks`, `audio`, `segments` | Has specific data |
| `--longer-than` | seconds | Minimum duration |
| `--shorter-than` | seconds | Maximum duration |
| `--sort` | `newest`, `oldest`, `longest`, `shortest`, `relevance` | Sort order |

### Composing queries with jq

```bash
# Titles and summaries from this week's memos
talkie memos --since 7d | jq '[.[] | {title, summary}]'

# All dictation text from today
talkie dictations --since 1d | jq -r '.[].text'

# Count words across recent dictations
talkie dictations --since 7d | jq '[.[].text | split(" ") | length] | add'

# Extract just dates and titles from search results
talkie search "project update" | jq -r '.[] | "\(.createdAt | split("T")[0]): \(.title // .text[:80])"'
```

### Raw database access

For queries that go beyond search filters:

```bash
# Database info
talkie dev db

# List tables with row counts
talkie dev db tables

# Aggregations and GROUP BY (not available via search)
talkie dev db "SELECT count(*) as total, type FROM recordings GROUP BY type"
talkie dev db "SELECT date(createdAt) as day, count(*) as n FROM recordings WHERE type='dictation' GROUP BY day ORDER BY day DESC LIMIT 7"
```

### Workflow history

```bash
# Recent workflow runs
talkie workflows --pretty

# Filter by status
talkie workflows --status completed
talkie workflows --status failed

# Details of a specific run (includes step outputs)
talkie workflows a1b2 --pretty
```

### Dev tools

```bash
# Service status (running/crashed/stopped)
talkie dev status --pretty

# Tail live logs
talkie dev logs --pretty
talkie dev logs engine --level debug --pretty

# Build and relaunch
talkie dev rebuild agent
talkie dev rebuild --skip-build  # just clean + relaunch
```

## Common Use Cases

**"What did I talk about this week?"**
```bash
talkie search --type memo --since 7d --has summary --pretty
```

**"Find that dictation where I mentioned the API redesign"**
```bash
talkie search "API redesign" --type dictation --pretty
```

**"Show me memos that have screenshots attached"**
```bash
talkie search --type memo --has screenshots --pretty
```

**"Long recordings from the past month"**
```bash
talkie search --since 30d --longer-than 120 --sort longest --pretty
```

**"What did I dictate into Cursor this week?"**
```bash
talkie search --type dictation --app Cursor --since 7d --pretty
```

**"What workflows failed recently?"**
```bash
talkie workflows --status failed --pretty
```

**"Get the full transcript of my most recent memo"**
```bash
talkie memos --limit 1 | jq -r '.[0].text'
```

**"How many dictations did I do each day this month?"**
```bash
talkie dev db "SELECT date(createdAt) as day, count(*) as n FROM recordings WHERE type='dictation' AND createdAt > date('now', '-30 days') GROUP BY day ORDER BY day DESC"
```
