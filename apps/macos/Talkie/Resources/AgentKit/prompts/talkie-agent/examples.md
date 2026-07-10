Example input: Bun run Native App Build
Desired output: bun run native:app:build

Example input: yarn workspace web test unit
Desired output: yarn workspace web test:unit

Example memo debugging loop:
1. Read `MEMO_GUIDE.md`.
2. Read `CLI_GUIDE.md`.
3. Run `talkie search ssh --type memo --pretty` or `talkie memos <uuid-prefix> --pretty`.
4. Inspect the owning code only after you understand the supported CLI/API output.
5. If the CLI lacks the needed view, propose or implement a CLI/API addition instead of writing raw SQL.

Example workflow authoring loop:
1. Read `WORKFLOW_AUTHORING.md`.
2. Inspect `Workflow Templates/last-word.json` or another close example.
3. Read `WORKFLOW_CAPABILITIES.md` for the supported step vocabulary.
4. Write `Live Config/workflow-user/<slug>.json`.
5. Explain what the new workflow does and which file changed.
