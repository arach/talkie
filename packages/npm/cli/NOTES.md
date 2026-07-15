# CLI notes

## Commander → gunshi migration

**Decision (2026-07-09):** adopt [gunshi](https://github.com/kazupon/gunshi) as the modern replacement for `commander`.

**Implemented (2026-07-10):** both the published `talkie` CLI and the repo-only `talkie-dev` entry point now run through a small compatibility adapter in `src/gunshi-command.ts`. Existing command registrations keep their Commander-shaped API while Gunshi owns parsing, help, validation, subcommands, aliases, and lifecycle hooks.

### Why gunshi
- Declarative, type-safe args (`string` | `boolean` | `number` | `enum` | `positional` | `custom`)
- Nested + lazy subcommands, Bun-friendly
- Hooks: `onAfterCommand` / `onErrorCommand` (replace `postAction` → `closeDb`)
- `--no-*` via `negatable: true` on booleans
- Active (v0.36+); citty-inspired with plugins/i18n headroom

### Completed scope
1. Migrated the published `@talkie/cli` entry point and commands.
2. Migrated `talkie-dev` and its nested dev commands.
3. Replaced `commander` with `gunshi` in `package.json` and the Bun lockfile.
4. Preserved global options, nested commands, aliases, optional option values, and post-action database cleanup through the adapter.

### Migration map (commander → gunshi)
| Today | Gunshi |
|-------|--------|
| `new Command()` + `.command()` | `define({ name, args, run, subCommands })` + `cli(argv, entry, opts)` |
| `.option("--limit <n>", …, "50")` | `args: { limit: { type: "number", default: 50 } }` |
| `memos [id]` | `id: { type: "positional", required: false }` |
| `--no-qr` | `qr: { type: "boolean", negatable: true, default: true }` |
| `.aliases([...])` | duplicate entries in `subCommands` map or alias field if available |
| `program.opts()` / `optsWithGlobals()` | shared global args on entry + each subcommand, or a small gunshi plugin |
| `program.hook("postAction", closeDb)` | `onAfterCommand` + `onErrorCommand` → `closeDb()` |
| `program.parse()` | `await cli(process.argv.slice(2), main, { name, version, subCommands })` |

### Compatibility requirements
- Global `--json` / `--pretty` / `--db` touch most actions — design shared args once
- Nested trees: `pair/*`, `sync/*`, `data/*`, `terminal/*`, full `talkie-dev`
- Optional flag values like `--wait [seconds]` need an explicit default or always-required value
- Golden smoke tests before swap: `memos`, `search`, `captures`/`clips`/`screenshots --paths`, `stats`, `data`, `pair --help`

### Non-goals
- Rewrite business logic; parser/register layer only
- Publishing from this working tree

### Verification

- `bun run build`
- `bun run src/index.ts --version`
- `bun run src/index.ts --help`
- `bun run src/dev.ts --help`
