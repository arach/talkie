# AgentKit

AgentKit is the source of truth for Talkie's embedded agent content:

- prompts that shape agent behavior
- knowledge-base docs that generated workspaces expose to the agent
- machine-readable catalogs
- shared TypeScript runtime code used by workspace tools

The macOS app does not author these files directly. It consumes a bundled copy under `apps/macos/Talkie/Resources/AgentKit/` that is mirrored from this package.

## Content model

- `prompts/`
  - behavior-shaping prompt files for embedded agent profiles
- `docs/`
  - durable knowledge-base material and workspace document templates
- `catalogs/`
  - machine-readable inventories and vocabularies
- `runtime/`
  - shared TypeScript runtime used by generated workspace tools

The inventory for every bundled asset lives in `catalogs/content-catalog.json`.

## Source of truth

This package is the editable source.

The app bundle is a mirrored artifact:

- source package: `apps/macos/TalkieServer/packages/agent-kit/`
- bundled copy: `apps/macos/Talkie/Resources/AgentKit/`

`scripts/sync-to-app.ts` mirrors the collections declared in the content catalog into the app bundle.

## Editing workflow

1. Add or edit the asset in this package.
2. Update `catalogs/content-catalog.json`.
3. Run `bun run validate`.
4. Run `bun run sync`.
5. Rebuild Talkie if the app needs the new bundled copy.

Validation fails if:

- an asset exists on disk but is not listed in the catalog
- a catalog entry points at a missing file
- duplicate asset ids or collection ids exist
- an asset is listed under the wrong collection

## Prompt and KB authoring rules

- Keep prompts directive and minimal. They should shape behavior, not duplicate the knowledge base.
- Keep docs factual and durable. Docs are the knowledge base, not the turn-specific instruction surface.
- Put reusable operational reference material in `docs/`, not in prompts.
- Put executable logic in `runtime/`, not in shell wrappers.

## Packaging strategy

For content, the right model is to bundle files with the app:

- prompts, docs, and catalogs should stay pinned to the app version
- they should work offline
- they should not depend on live registry state

For executable runtimes, two pinned distribution models are reasonable:

1. Install a pinned registry version.
   - Example: `npm install @talkie/agent-tools@0.3.1`
   - The app controls the exact version string it installs.
2. Ship a packed artifact.
   - Example: bundle a `.tgz` produced by `npm pack` and install from disk
   - This removes registry availability from runtime startup while keeping the install shape package-based

Today AgentKit still bundles runtime source into the app. If we later move the executable runtime to a package artifact, prompts/docs/catalogs should remain bundled here.
