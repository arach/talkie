# Catalogs

This directory contains machine-readable inventories for AgentKit.

Current catalogs:

- `content-catalog.json`
  - the source-of-truth inventory for bundled AgentKit assets
- `workflow-step-catalog.json`
  - the workflow step vocabulary exposed to generated workspaces

`content-catalog.json` is intentionally strict. Every managed file inside `docs/`, `prompts/`, `catalogs/`, and `runtime/` should be represented there so the package can detect drift.
