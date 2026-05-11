# Workflow Authoring

Use this guide when the user describes a workflow in plain language and wants Talkie to set it up.

## Fast path

1. Pick a kebab-case filename like `daily-standup-summary.json`.
2. Create or update the file in `Live Config/workflow-user/`.
3. Use the simplified flat JSON format, not the full encoded `WorkflowDefinition` shape with nested wrappers and UUIDs.
4. Start from the closest example in `Workflow Templates/` whenever possible.
5. Read `WORKFLOW_CAPABILITIES.md` or `WORKFLOW_STEP_CATALOG.json` if you need the exact step vocabulary.
6. Tell the user what the workflow now does and which file was created.

Talkie hot-reloads workflow definition files, so saving the JSON file is usually enough to make the workflow appear.

## Root shape

```json
{
  "name": "Workflow Name",
  "description": "What it does",
  "icon": "wand.and.stars",
  "color": "blue",
  "steps": [
    {
      "type": "llm",
      "outputKey": "summary",
      "prompt": "Summarize: {{TRANSCRIPT}}"
    }
  ]
}
```

Root fields:
- `name`: required
- `description`: required
- `icon`: optional SF Symbol
- `color`: optional Talkie workflow color like `blue`, `green`, `purple`, `orange`, `teal`
- `maintainer`: optional, usually omit for user-authored workflows
- `steps`: required array

## Variables

Use template strings inside step config:
- `{{TRANSCRIPT}}`: the memo transcript
- `{{PREVIOUS_OUTPUT}}`: the previous step's output
- `{{OUTPUT}}`: same as previous output for compatibility
- `{{some_output_key}}`: the output of a named earlier step

Keep `outputKey` values short and stable, like `summary`, `tasks`, `spoken`, or `saved_file`.

## Common authoring patterns

- summarize transcript with `llm`
- extract or reshape text with `shell`
- say the result with `speak`
- persist the result with `saveFile`
- notify with `notification`
- gate behavior with `conditional`

## Good authoring habits

- Prefer flat JSON over the compiled Swift shape.
- Keep the workflow small on the first pass.
- Use one step per real action.
- Reuse a template when the user asks for something close to summarizing, speaking, extracting tasks, or saving text.
- If the user only asked for the workflow behavior, stop after creating the definition file. Do not also pin or auto-run it unless requested.

## Example patterns

Last sentence to TTS:
- copy `Workflow Templates/last-word.json`
- adapt the shell extraction if needed
- keep the second step as `speak`

Summary to file:
- start from `Workflow Templates/quick-summary.json`
- add a second `saveFile` step with `content: "{{summary}}"`

Transcript to notification:
- use an `llm` summary step
- follow with `notification` using `body: "{{summary}}"`
