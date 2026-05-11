# Prompts

The `prompts/` directory contains behavior-shaping prompt content for embedded Talkie agent profiles.

Prompts are not the knowledge base. They are the control layer that tells the agent how to use the knowledge base and tools.

## Prompt roles

- `system.md`
  - the non-negotiable operating instructions for a profile
- `prompt.md`
  - the default task framing or user-facing ask for the profile
- `notes.md`
  - extra stable context that does not fit cleanly into the system prompt
- `examples.md`
  - few-shot examples and style anchors
- `bootstrap.md`
  - optional first-run guidance or startup nudge

## Authoring rules

- keep prompts concise and directive
- avoid duplicating long reference material from `docs/`
- prefer pointing the agent at a KB file over restating the KB in the prompt
- update `catalogs/content-catalog.json` for every new prompt asset
