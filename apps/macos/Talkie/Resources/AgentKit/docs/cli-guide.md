# Talkie CLI Guide

Use the Talkie CLI as the supported agent-facing interface for local app data.

## First choice

- `talkie memos --limit 20 --pretty`
- `talkie memos <id-prefix> --pretty`
- `talkie dictations --since 24h --pretty`
- `talkie dictations <id-prefix> --pretty`
- `talkie search "<query>" --type memo --pretty`
- `talkie search "<query>" --type dictation --pretty`
- `talkie captures --kind screenshot --source all --paths`
- `talkie captures --kind clip --source all --paths`
- `talkie workflows --pretty`
- `talkie workflows <run-id-prefix> --pretty`
- `talkie stats --pretty`
- `talkie data path`

Use `--json` when another command or script needs structured output.

## If `talkie` is unavailable

Do not fall back to `sqlite3`, `bun:sqlite`, or raw SQL. Explain that the supported CLI is not available in the current environment. In a source checkout, inspect `packages/npm/cli` and either run the CLI through its documented development path or implement the missing command there.

## Database boundary

`talkie.sqlite` schema details are useful for understanding owning code, migrations, and data model behavior. They are not the normal runtime interface for agents.

Only inspect or modify the database directly when the user explicitly asks for a database repair, migration, or forensic recovery task. For ordinary product questions, debugging, memo lookup, dictation lookup, capture lookup, workflow history, and search, use the CLI or a first-class Talkie bridge/API surface.
