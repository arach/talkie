# Talkie CLI

Access Talkie voice memos, dictations, workflows, and search from the command line. Talkie is a voice-first productivity suite for macOS that stores recordings in a local SQLite database.

## Setup

The CLI requires [Bun](https://bun.sh) and a running Talkie installation.

```bash
cd packages/npm/cli && bun install && bun link
```

After linking, the `talkie` command is available globally.

## Commands

### memos — Voice memos

```bash
# List all memos (newest first)
talkie memos

# List memos from last 7 days
talkie memos --since 7d

# List memos from a specific date
talkie memos --since 2025-02-01

# Get a specific memo by ID prefix (returns full transcript + summary + tasks)
talkie memos a1b2c3

# Limit results
talkie memos --limit 10
```

### dictations — Keyboard dictations

```bash
# List recent dictations
talkie dictations

# Last 24 hours
talkie dictations --since 24h

# Get a specific dictation
talkie dictations f9e8d7
```

### search — Full-text search across all recordings

```bash
# Search across all memos and dictations
talkie search "product launch"

# Search only memos
talkie search "meeting notes" --type memo

# Search only dictations
talkie search "email draft" --type dictation

# Limit search results
talkie search "project" --limit 5
```

### workflows — Workflow execution history

```bash
# List recent workflow runs
talkie workflows

# Filter by status
talkie workflows --status completed
talkie workflows --status failed

# Get workflow run details (includes step outputs)
talkie workflows a1b2c3
```

### stats — App statistics

```bash
talkie stats
```

Returns: dictation counts (today/week/total), word counts, streak days, top apps.

## Output Formats

**JSON (default)** — Machine-readable, pipes to `jq`:
```bash
talkie memos | jq '.[0].text'
talkie search "meeting" | jq '.[].title'
```

**Pretty** — Human-readable tables:
```bash
talkie memos --pretty
talkie search "meeting" --pretty
```

## Global Flags

| Flag | Description |
|------|-------------|
| `--json` | JSON output (default) |
| `--pretty` | Human-readable formatted output |
| `--db <path>` | Override database path |

## Data Model

- **Memos** have: id, title, text (transcript), duration, summary, tasks, source, createdAt
- **Dictations** have: id, text, duration, source, metadata (target app), createdAt
- **Workflow runs** have: id, workflowName, status, steps with outputs, durationMs
- **Search** uses SQLite FTS5 — matches across title, text, and notes fields

## Dev Commands

The `talkie dev` command group provides tools for managing Talkie services during development.

### dev status — Service status snapshot

```bash
# Show all services with states (JSON)
talkie dev status

# Human-readable output
talkie dev status --pretty
```

Returns: service name, status (running/crashed/stopped/not_registered), PID, launchd label, type (app/launchd), stale flag, database info.

### dev start — Launch services from DerivedData

```bash
# Launch all services
talkie dev start

# Launch a specific service
talkie dev start agent
talkie dev start engine
talkie dev start talkie
```

Service aliases: `talkie`/`app`, `agent`, `engine`

### dev stop — Stop dev services

```bash
# Stop all dev services
talkie dev stop

# Stop a specific service
talkie dev stop agent
```

Safely stops only dev (DerivedData) builds. Never kills production `/Applications/` builds.

### dev restart — Stop + start

```bash
talkie dev restart agent
talkie dev restart        # All services
```

### dev clean — Remove stale launchd registrations

```bash
talkie dev clean --pretty
```

Detects crashed/stopped launchd registrations and boots them out.

### dev build — Build via xcodebuild

```bash
# Build a specific service
talkie dev build agent

# Build all services
talkie dev build

# Build and restart if running
talkie dev build agent --restart
```

### dev rebuild — Build + clean slate + launch

The thorough version: builds, kills ALL traces (launchd, app-launched, duplicates, stale registrations), verifies a clean process state, then launches fresh.

```bash
# Rebuild and relaunch a service
talkie dev rebuild agent

# Rebuild all services
talkie dev rebuild

# Skip the build (just clean + relaunch existing build)
talkie dev rebuild agent --skip-build
```

### dev logs — Tail service logs

```bash
# Stream all service logs (live)
talkie dev logs --pretty

# Stream logs for a specific service
talkie dev logs engine --pretty

# Show historical logs
talkie dev logs --since 5m --pretty
talkie dev logs agent --since 1h

# Set minimum log level
talkie dev logs --level debug --pretty
```

### dev db — Database inspection

```bash
# Show database info (path, size, table summary)
talkie dev db

# List all tables with row counts
talkie dev db tables

# Run raw SQL
talkie dev db "SELECT count(*) FROM recordings"
talkie dev db "SELECT count(*) FROM recordings WHERE type='dictation'"
```

## Tips

- Use ID prefixes: `talkie memos a1b2` matches any memo starting with "a1b2"
- Pipe to `jq` for filtering: `talkie memos --since 7d | jq '[.[] | {title, summary}]'`
- Combine with other tools: `talkie search "TODO" | jq -r '.[].text'`
- The `--since` flag accepts relative (`7d`, `24h`, `30m`) or absolute (`2025-02-01`) dates
- Use `talkie dev status` to get a quick snapshot before debugging service issues
- Use `talkie dev clean` to clear stale registrations that block XPC connections
