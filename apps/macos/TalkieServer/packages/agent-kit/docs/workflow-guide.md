# Workflow Guide

Talkie workflows have three different surfaces:

1. definition files on disk
2. preference/runtime config in `config.json`
3. run history in `workflow_runs`

## Definition files

- system workflows: `{{WORKFLOW_SYSTEM_DIR}}`
- user workflows: `{{WORKFLOW_USER_DIR}}`
- imported workflows: `{{WORKFLOW_IMPORTED_DIR}}`
- owning code: `apps/macos/Talkie/Workflow/WorkflowFileRepository.swift`

These JSON files are the editable source for workflow structure and steps.

## Preferences and runtime config

- live config file: `{{WORKFLOW_CONFIG_PATH}}`
- owning code: `apps/macos/Talkie/Workflow/WorkflowConfiguration.swift` + `apps/macos/Talkie/Workflow/WorkflowConfigurationStore.swift`
- merged service view: `apps/macos/Talkie/Workflow/WorkflowService.swift`

This file owns pinned state, auto-run, sort order, action-surface placement, control-plane settings, shell allowlists, path aliases, and automation timestamps.

## Run history

- live table: `workflow_runs` in `{{MEMO_DATABASE_PATH}}`
- owning code: `apps/macos/Talkie/Data/Models/WorkflowRunModel.swift`
- execution engine: `apps/macos/Talkie/Workflow/WorkflowExecutor.swift`

## Safe interaction rules

- Edit workflow JSON files or `macos-workflows.config.json` for durable behavior changes.
- For brand-new workflows, prefer the simplified flat JSON format described in `WORKFLOW_AUTHORING.md`.
- Write user-authored workflows into `Live Config/workflow-user/<slug>.json`.
- Do not backfill `workflow_runs` by hand unless the task is a one-off repair or migration.
- When a pinned action looks wrong on iPhone, check both the workflow definition and `workflowPreferences.<workflow-id>` in `macos-workflows.config.json`.

## Useful commands

- open `Live Config/macos-workflows.config.json`
- inspect `Live Config/workflow-user/`
- inspect `Workflow Templates/`
- read `WORKFLOW_CAPABILITIES.md`
- run `talkie workflows --pretty`
- run `talkie workflows <run-id-prefix> --pretty`
- run `talkie search <query> --type memo --pretty` when you need to connect a memo to workflow output
