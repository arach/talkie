# Runtime

The `runtime/` directory holds shared executable logic for generated AgentKit workspace utilities.

Current runtime:

- `agent-tools.ts`
  - legacy support for older generated workspace utilities and non-database debug actions

## Boundary

- agents should use supported `talkie` CLI commands or Talkie bridge/API surfaces for normal app-data inspection
- database schema knowledge belongs in docs and owning code references, not in agent-facing shell helpers
- shell wrappers, when present, should only dispatch to supported app/debug entrypoints
- prompt and KB content should stay outside runtime code

If you add a new runtime entrypoint:

1. add the file here
2. update `catalogs/content-catalog.json`
3. update sync/validation if the new file changes how the app bundles runtime assets
