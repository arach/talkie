# @talkie/cli

Command-line access to [Talkie](https://usetalkie.com) — voice memos, dictations, screenshots, screen clips, workflows, and search. Built for humans and agents on macOS.

Requires [Bun](https://bun.sh) and Talkie.app.

## Install

```bash
bun add -g @talkie/cli
```

Or use the one-liner (installs Bun if needed, then the CLI and app):

```bash
curl -fsSL go.usetalkie.com/install | bash
```

From the monorepo:

```bash
cd packages/npm/cli && bun install && bun link
```

## Quick start

```bash
talkie doctor              # check app, CLI, permissions, and services
talkie open                # launch Talkie.app
talkie memos --limit 5     # recent voice memos
talkie screenshots 3 --paths   # tray screenshot paths for scripts
talkie search "launch plan"    # full-text search
talkie stats               # usage overview
```

Install or update the desktop app:

```bash
talkie install             # download Talkie.app to /Applications
talkie upgrade             # install if a newer version is available
```

## Requirements

| Requirement | Notes |
|-------------|-------|
| **macOS** | Darwin only |
| **Bun** ≥ 1.0 | Runtime for the CLI |
| **Talkie.app** | Required for querying local data (`talkie install`) |

Optional: `brew install qrencode` for terminal QR codes (`talkie pair`, `talkie companion`, `talkie terminal pair`).

## Output

- **Interactive terminal** — human-readable tables and status lines (default)
- **Piped or scripted** — JSON (default when stdout is not a TTY)

```bash
talkie memos --pretty              # force table output
talkie memos --json | jq '.[0].text'   # force JSON
talkie screenshots 5 --paths       # plain paths, one per line
```

## Global flags

| Flag | Description |
|------|-------------|
| `--json` | JSON output |
| `--pretty` | Human-readable output |
| `--db <path>` | Override SQLite database path |

## Data commands

### `talkie memos [id]`

List voice memos or fetch one by ID prefix.

```bash
talkie memos
talkie memos --since 7d --limit 10
talkie memos a1b2c3          # full transcript, summary, tasks
```

### `talkie dictations [id]`

List keyboard dictations or fetch one by ID prefix.

```bash
talkie dictations --since 24h
talkie dictations f9e8d7
```

### `talkie search <query>`

Full-text search across memos and dictations (SQLite FTS5).

```bash
talkie search "product launch"
talkie search "email draft" --type dictation --limit 5
```

### `talkie captures [id]`

Screenshots and screen clips from the tray, library, and recordings.

```bash
talkie captures
talkie captures --kind screenshot --source tray
talkie captures d9d3cc46 --ocr

# Shortcuts for agents and shell scripts
talkie screenshots 3 --paths
talkie screencaps 3 --paths          # alias
talkie clips 3 --paths
talkie screenshots 10 --all-sources --json

# Visual-context bundles (contact sheets, frame dirs)
talkie captures --kind clip --limit 3 --context
talkie captures --kind clip --contact-sheet --paths
talkie captures --kind clip --frames --paths
```

Options: `--since`, `--kind`, `--source`, `--recording`, `--app`, `--ocr`, `--paths`, `--open`, `--reveal`, `--context`, `--contact-sheet`, `--frames`.

### `talkie workflows [id]`

Workflow run history and step outputs.

```bash
talkie workflows --status completed
talkie workflows a1b2c3
```

### `talkie stats`

Dictation counts, word totals, streaks, and top apps.

## App & setup

| Command | Description |
|---------|-------------|
| `talkie install` | Download and install Talkie.app |
| `talkie upgrade` / `update` | Upgrade when a newer release exists |
| `talkie install --check` | Compare installed vs latest version |
| `talkie uninstall` | Remove Talkie.app from `/Applications` |
| `talkie open` | Open Talkie.app |
| `talkie pro` | Open Pro Tools onboarding |
| `talkie where` | Show app, CLI, and data paths |
| `talkie doctor` | Permissions, services, and Pro Tools readiness |

`talkie install` supports `--target <version>`, `--force`, `--launch`, and `--no-restart`.

## iPhone & iPad

| Command | Description |
|---------|-------------|
| `talkie companion` | App Store QR for the iOS companion app |
| `talkie pair` | Mac Bridge pairing QR for iOS |
| `talkie pair pending` | List pending pairing requests |
| `talkie pair approve <id>` | Approve a request |
| `talkie pair reject <id>` | Reject a request |
| `talkie terminal pair` | SSH terminal access QR (iOS imports key) |
| `talkie terminal status` | SSH pairing status |

Pairing flows accept `--payload`, `--no-qr`, and `--wait` where applicable.

## Sync & data

```bash
talkie sync                  # sync status
talkie sync now              # trigger a sync pass
talkie sync providers        # list sync providers

talkie data path             # Application Support location
talkie data archive          # archive user data
talkie data clean            # remove Talkie data (destructive)
```

## Tips

- **ID prefixes** — `talkie memos a1b2` matches any ID starting with `a1b2`
- **`--since`** — relative (`7d`, `24h`, `30m`) or absolute (`2026-06-01`)
- **Agents** — use `--paths` / `--json` for stable machine-readable output
- **jq** — `talkie memos --since 7d --json | jq '[.[] | {title, summary}]'`

## For AI agents

See [SKILL.md](./SKILL.md) in this package for agent-oriented command reference and capture path conventions.

## Development (monorepo)

Published `@talkie/cli` does not include dev tooling. In the Talkie repo, link the package and use `talkie-dev`:

```bash
cd packages/npm/cli && bun link
# creates ~/.bun/bin/talkie-dev

talkie-dev status
talkie-dev rebuild agent
talkie-dev logs agent --pretty
```

## License

[PolyForm Noncommercial 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0/)