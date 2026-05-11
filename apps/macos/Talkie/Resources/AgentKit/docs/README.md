# Knowledge Base

The `docs/` directory is AgentKit's knowledge base.

These files are durable references and workspace templates that help an embedded agent understand Talkie's operational surfaces.

## What belongs here

- stable workflow authoring guidance
- workspace instruction templates
- operational reference material that should survive across sessions
- human-readable docs that generated workspaces can expose directly

## What does not belong here

- one-off turn context
- behavioral instructions that belong in prompts
- executable logic

## File roles

- `agents.md`
  - the generated workspace contract for managed sessions
- `workspace-readme.md`
  - the generated workspace landing page template
- `workflow-guide.md`
  - workflow storage, runtime, and run-history guidance
- `workflow-authoring.md`
  - the flat workflow authoring format
- `workflow-capabilities.md`
  - supported step vocabulary and common patterns
- `workflow-templates-readme.md`
  - how to use copied starter workflow templates

When adding a new KB file, update `catalogs/content-catalog.json` and run `bun run validate`.
