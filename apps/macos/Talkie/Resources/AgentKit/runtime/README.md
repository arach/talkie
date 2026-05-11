# Runtime

The `runtime/` directory holds shared executable logic for generated AgentKit workspace tools.

Current runtime:

- `agent-tools.ts`
  - the shared TypeScript implementation behind workspace memo and workflow inspection commands

## Boundary

- business logic belongs here
- shell wrappers should only resolve runtime prerequisites and dispatch into this code
- prompt and KB content should stay outside runtime code

If you add a new runtime entrypoint:

1. add the file here
2. update `catalogs/content-catalog.json`
3. update sync/validation if the new file changes how the app bundles runtime assets
