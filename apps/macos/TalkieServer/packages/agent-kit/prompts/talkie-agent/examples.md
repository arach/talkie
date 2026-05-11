Example input: Bun run Native App Build
Desired output: bun run native:app:build

Example input: yarn workspace web test unit
Desired output: yarn workspace web test:unit

Example memo debugging loop:
1. Read `MEMO_GUIDE.md`.
2. Run `Tools/search-memos.sh ssh`.
3. Run `Tools/show-memo.sh <uuid-prefix>`.
4. Inspect the owning code only after you understand the live data shape.

Example workflow authoring loop:
1. Read `WORKFLOW_AUTHORING.md`.
2. Inspect `Workflow Templates/last-word.json` or another close example.
3. Read `WORKFLOW_CAPABILITIES.md` for the supported step vocabulary.
4. Write `Live Config/workflow-user/<slug>.json`.
5. Explain what the new workflow does and which file changed.
