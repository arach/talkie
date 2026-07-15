# @talkie/cli

**Voice memos, dictations, screenshots, and screen clips — from the terminal.**

[Talkie](https://usetalkie.com) is a voice-first productivity suite for macOS. This package is the official CLI: query your local library, pipe paths into agent workflows, install/upgrade the app, and pair iPhone/iPad companions.

[![npm version](https://img.shields.io/npm/v/@talkie/cli.svg)](https://www.npmjs.com/package/@talkie/cli)
[![platform](https://img.shields.io/badge/platform-macOS-black)](https://usetalkie.com)
[![runtime](https://img.shields.io/badge/runtime-Bun-fbf0df)](https://bun.sh)
[![license](https://img.shields.io/npm/l/@talkie/cli.svg)](https://polyformproject.org/licenses/noncommercial/1.0.0/)

```bash
npm install -g @talkie/cli
talkie doctor
talkie clips 5 --all-sources --paths
```

## What you can do

| Area | Commands | Examples |
|------|----------|----------|
| **Voice** | `memos`, `dictations`, `search`, `stats` | Transcripts, summaries, FTS5 search |
| **Capture** | `captures`, `screenshots`, `clips` | Screen clips, tray shots, OCR, contact sheets |
| **Automation** | `--json`, `--paths`, `workflows` | Agent-friendly paths and machine output |
| **App** | `install`, `upgrade`, `doctor`, `open` | Install Talkie.app, permissions, paths |
| **Devices** | `pair`, `companion`, `terminal` | iPhone/iPad bridge + SSH terminal |

Built for **humans in a terminal** and **agents in a loop**. Pretty tables in a TTY; JSON when piped.

## Install

Requires [Bun](https://bun.sh) ≥ 1.0 and macOS. Talkie.app is needed for local data (`talkie install`).

```bash
# npm (recommended for most setups)
npm install -g @talkie/cli

# bun
bun add -g @talkie/cli

# one-liner — installs Bun if needed, then CLI + app
curl -fsSL go.usetalkie.com/install | bash
```

From the monorepo:

```bash
cd packages/npm/cli && bun install && bun link
```

## Quick start

```bash
talkie doctor                 # app, CLI, permissions, services
talkie open                   # launch Talkie.app
talkie memos --limit 5        # recent voice memos
talkie screenshots 3 --paths  # tray screenshot paths
talkie clips 5 --paths        # tray screen clips
talkie search "launch plan"   # full-text search
talkie stats                  # usage overview
```

Desktop app:

```bash
talkie install                # download Talkie.app → /Applications
talkie upgrade                # install a newer release when available
talkie install --check        # compare installed vs latest
```

## Example output

```text
$ talkie captures --kind clip --limit 2 --pretty
ID          Kind   Source     Created              Target   Size        Duration  Path
f1bb9aa8    clip   recording  Jul 9, 2026 at 06:46 region   3838x1374   31s       …/Videos/…f1bb9aa8…
6effeaf5    clip   recording  Jul 9, 2026 at 06:43 region   3838x1374   1m 4s     …/Videos/…6effeaf5…
```

```bash
# Agent recipe: latest clips as paths, then inspect one
talkie clips 5 --all-sources --paths
talkie captures f1bb9aa8 --context
```

## Requirements

| Requirement | Notes |
|-------------|-------|
| **macOS** | Darwin only (`os: ["darwin"]`) |
| **Bun** ≥ 1.0 | CLI runtime (`#!/usr/bin/env bun`) |
| **Talkie.app** | Local SQLite + media library |

Optional: `brew install qrencode` for terminal QR codes (`talkie pair`, `talkie companion`, `talkie terminal pair`).

## Output modes

| Context | Default |
|---------|---------|
| Interactive terminal | Human-readable tables (`--pretty`) |
| Piped / non-TTY | JSON (`--json`) |

```bash
talkie memos --pretty
talkie memos --json | jq '.[0].text'
talkie screenshots 5 --paths          # plain paths, one per line
```

### Global flags

| Flag | Description |
|------|-------------|
| `--json` | Force JSON |
| `--pretty` | Force tables |
| `--db <path>` | Override SQLite database path |

## Data commands

### `talkie memos [id]`

List voice memos, or fetch one by ID prefix (full transcript, summary, tasks).

```bash
talkie memos
talkie memos --since 7d --limit 10
talkie memos a1b2c3
```

### `talkie dictations [id]`

List live keyboard dictations, or fetch one by ID prefix.

```bash
talkie dictations --since 24h
talkie dictations f9e8d7
```

### `talkie search [query]`

Full-text search **and** filter-only queries (SQLite FTS5). Query text is optional.

```bash
talkie search "product launch"
talkie search "email draft" --type dictation --limit 5

# Filter-only (no text query)
talkie search --type dictation --app Cursor --since 24h
talkie search --has screenshots --since 7d --pretty
talkie search --longer-than 60 --sort longest --since 30d
```

| Flag | Description |
|------|-------------|
| `--type` | `memo` \| `dictation` |
| `--since` / `--until` | Relative (`7d`, `24h`) or absolute date |
| `--app` | Target app name or bundle ID |
| `--source` | `mac`, `iphone`, `watch`, `live` |
| `--has` | `screenshots`, `clips`, `summary`, `tasks`, `audio`, `segments`, … |
| `--longer-than` / `--shorter-than` | Duration in seconds |
| `--sort` | `newest`, `oldest`, `longest`, `shortest`, `relevance` |

### `talkie captures [id]`

Screenshots and screen clips from **tray**, **library**, and **recordings**.

```bash
talkie captures
talkie captures --kind screenshot --source tray
talkie captures --kind clip --limit 10
talkie captures d9d3cc46 --ocr
talkie captures f1bb9aa8 --context
```

| Flag | Description |
|------|-------------|
| `--kind` | `screenshot`, `clip`, `video`, or `all` |
| `--source` | `tray`, `recording`, `library`, or `all` |
| `--since` | Capture/file date filter |
| `--recording` | Attached recording ID prefix |
| `--app` | App, window, display, or filename |
| `--ocr` | Include OCR text when available |
| `--paths` / `--path` | Print absolute paths only |
| `--open` / `--reveal` | Open file or show in Finder |
| `--context` | Visual-context bundle metadata |
| `--contact-sheet` / `--frames` | Print contact sheet / frames dir paths |

### `talkie screenshots [n]` · `talkie clips [n]`

Shortcuts for agents and scripts. Default source is **tray**; use `--all-sources` for library + recording captures too.

```bash
talkie screenshots 3 --paths
talkie screencaps 3 --paths          # alias
talkie clips 3 --paths
talkie clips 5 --all-sources --json
talkie screenshots 10 --all-sources --json
```

Aliases: `screencaps`, `screen-caps`, `screen-captures`, `screen-clips`, `screenclips`.

### `talkie workflows [id]`

Workflow run history and step outputs.

```bash
talkie workflows --status completed
talkie workflows --status failed
talkie workflows a1b2c3
```

### `talkie stats`

Dictation counts, word totals, streaks, and top apps.

## App & setup

| Command | Description |
|---------|-------------|
| `talkie install` | Download and install Talkie.app |
| `talkie upgrade` / `update` | Upgrade when a newer release exists |
| `talkie install --check` | Compare installed vs latest |
| `talkie uninstall` | Remove Talkie.app from `/Applications` |
| `talkie open` | Open Talkie.app |
| `talkie pro` | Open Pro Tools onboarding |
| `talkie where` | Show app, CLI, and data paths |
| `talkie doctor` | Permissions, services, Pro Tools readiness |

`talkie install` supports `--target <version>`, `--force`, `--launch`, and `--no-restart`.

## iPhone & iPad

| Command | Description |
|---------|-------------|
| `talkie companion` | App Store QR for the iOS companion |
| `talkie pair` | Mac Bridge pairing QR |
| `talkie pair pending` | Pending pairing requests |
| `talkie pair approve <id>` | Approve a request |
| `talkie pair reject <id>` | Reject a request |
| `talkie terminal pair` | SSH terminal access QR |
| `talkie terminal status` | SSH pairing status |

Pairing flows accept `--payload`, `--no-qr`, and `--wait` where applicable.

## Sync & data

```bash
talkie data                   # storage locations + size
talkie data path              # Application Support path
talkie data archive           # zip backup
talkie data clean             # wipe local data (destructive)

talkie sync                   # sync overview
talkie sync status            # detailed status
talkie sync now               # trigger a sync pass
talkie sync providers         # list providers
talkie sync ping              # reachability check
```

## Tips

- **ID prefixes** — `talkie memos a1b2` matches any ID starting with `a1b2`
- **`--since`** — relative (`7d`, `24h`, `30m`) or absolute (`2026-06-01`)
- **Agents** — prefer `--paths` and `--json` for stable machine-readable output
- **jq** — `talkie memos --since 7d --json | jq '[.[] | {title, summary}]'`

## For AI agents

See [SKILL.md](./SKILL.md) in this package for the agent-oriented command reference, capture path conventions, and visual-context layout under Application Support.

## Development (monorepo)

Published `@talkie/cli` does **not** include dev tooling. In the Talkie repo:

```bash
cd packages/npm/cli && bun link   # creates ~/.bun/bin/talkie-dev

talkie-dev status
talkie-dev rebuild agent
talkie-dev logs agent --pretty
```

## Links

- Product: [usetalkie.com](https://usetalkie.com)
- Repo: [github.com/arach/talkie](https://github.com/arach/talkie) (`packages/npm/cli`)
- Issues: [github.com/arach/talkie/issues](https://github.com/arach/talkie/issues)
- npm: [npmjs.com/package/@talkie/cli](https://www.npmjs.com/package/@talkie/cli)

## License

[PolyForm Noncommercial 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0/)
