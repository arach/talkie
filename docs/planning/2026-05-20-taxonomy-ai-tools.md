# Taxonomy prior art — AI / agentic tools

**Status:** research brief · AI-tools survey · 2026-05-20
**Context:** companion to `2026-05-20-taxonomy-prior-art.md` (classical automation tools)
**Scope:** How modern AI/agentic tools name their packaged-capability units. Includes light read on what it means for Talkie at the end.

## Claude Skills (Anthropic)

Anthropic's top-level packaged-capability primitive is the **Skill**. A Skill is a filesystem-based bundle: a `SKILL.md` file with YAML frontmatter (name, description, when-to-use) plus markdown instructions, optionally accompanied by scripts, templates, and reference files in the same directory. Claude auto-discovers skills, reads `SKILL.md` only when relevant, and bash-loads supplementary files on-demand. Anthropic publishes ~17 official skills in their public repo as of May 2026 (PDF/Word/PowerPoint creation, brand guidelines, MCP builder, webapp testing, internal comms, algorithmic art). Skills work across Claude.ai (web), Claude Code (CLI), and via the Agent SDK. Sources: [Introducing Agent Skills](https://www.anthropic.com/news/skills), [Agent Skills overview](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview), [anthropics/skills GitHub](https://github.com/anthropics/skills), [Extend Claude with skills](https://code.claude.com/docs/en/skills).

## Claude Cowork (Anthropic)

A separate product from Skills — **Cowork** is autonomous agentic execution on the user's machine. It reads, edits, and creates files in user-specified folders; can run multi-step work without coordination; and surfaces **scheduled tasks** ("check email every morning", "run my weekly Slack digest"). The unit here is the *task* (one-off or scheduled), not the Skill. Built on Claude desktop, paid plans only. Cowork uses Skills as building blocks — Skills define *capabilities*, Cowork defines *engagements*. Sources: [Claude Cowork](https://www.anthropic.com/product/claude-cowork), [Cowork product page](https://claude.com/product/cowork).

## Cursor + Windsurf (cross-tool SKILL.md adoption)

Both Cursor (Composer) and Windsurf (Cascade) have **adopted Anthropic's SKILL.md format unchanged**. Same YAML frontmatter, same activation rules, same markdown body. Directory paths: `.cursor/skills/`, `.windsurf/skills/`, `~/.claude/skills/`. This makes "Agent Skills" an emerging *open cross-vendor standard* — a SKILL.md authored once works in all three editors. Rules files (`.cursorrules`, `.windsurfrules`, `CLAUDE.md`) are a separate, complementary concept — always-on project context, not invocable capabilities. Sources: [Windsurf Skills Guide](https://www.agensi.io/learn/windsurf-skills-how-to-add-skill-md), [Claude Code vs Cursor vs Codex Skills](https://www.agensi.io/learn/claude-code-skills-vs-cursor-rules-vs-codex-skills), [Cursor vs Windsurf 2026](https://vibecoding.app/blog/cursor-vs-windsurf).

## Claude Code's hierarchy (the reference framing)

Inside Claude Code itself, Anthropic distinguishes four kinds of "thing you can invoke" by *scope*:

| Concept | Scope | When |
|---|---|---|
| **Slash commands** | Typed entry points, fixed logic | "I want a stable named command" |
| **Skills** | Prompt-based capabilities, in main context | "Work stays in front of me" |
| **Subagents** | Specialized AI in own context window | "Work runs in a side process" |
| **MCP tools** | Atomic function calls | "Single primitive operation" |

The framing isn't "user picks one name for everything" — it's "*scope* dictates which primitive." Sources: [Claude Code Customization](https://alexop.dev/posts/claude-code-customization-guide-claudemd-skills-subagents/), [Understanding Claude Code's Full Stack](https://alexop.dev/posts/understanding-claude-code-full-stack/), [How to Use Claude Code](https://www.producttalk.org/how-to-use-claude-code-features/).

## MCP (Model Context Protocol) — the cross-vendor standard

MCP defines three primitives every server can expose:

- **Tools** — functions the AI can call. Atomic, single-purpose. ("The verb tier.")
- **Resources** — data the AI can read. Read-only context.
- **Prompts** — predefined instruction templates clients fill with variables.

3000+ MCP servers exist in the wild as of May 2026. Adopted by Anthropic (originator), OpenAI, Google, Goose, Cursor, Windsurf. This is the *most aligned cross-vendor agentic vocabulary that exists today*. Sources: [MCP Tools/Resources/Prompts](https://workos.com/blog/mcp-features-guide), [MCP Demystified](https://techcommunity.microsoft.com/blog/azuredevcommunityblog/mcp-demystified-tools-vs-resources-vs-prompts-explained-simply/4508057), [MCP Cheat Sheet](https://www.webfuse.com/mcp-cheat-sheet).

## OpenAI's taxonomy

Five overlapping container-level things, plus the MCP overlay:

- **Custom GPTs** — top-level user-authored bots with instructions + knowledge + tools
- **Actions** — OpenAPI-described external API calls a Custom GPT can invoke
- **Apps** — newer connector concept; *mutually exclusive with Actions on a single GPT*
- **Tools** — built-in capabilities (web search, image gen, code interpreter)
- **Workspace Agents** (2026) — Codex-powered persistent shared agents, cross-tool, retain state

OpenAI's vocabulary is the messiest — actions vs apps vs tools is contested terminology even inside their own docs. The "Actions" name is being deprecated in favor of "Apps." Sources: [GPT Actions](https://developers.openai.com/api/docs/actions/introduction), [Introducing GPTs](https://openai.com/index/introducing-gpts/), [GPTs vs Assistants](https://help.openai.com/en/articles/8673914-gpts-vs-assistants), [Workspace Agents](https://decrypt.co/365220/openai-workspace-agents-feature-chatgpt).

## ChatGPT Tasks / Routines

Scheduled prompts. **Tasks** = one-off or recurring AI-executed prompts. **Routines** = the informal product name for recurring ones (daily briefings, weekly digests). 10 active tasks limit. Push notifications + email delivery. ChatGPT picked "Task" as the unit name, not "Skill" or "Workflow" — but Task here means "scheduled instance of a prompt," not "reusable capability." Sources: [Tasks in ChatGPT](https://help.openai.com/en/articles/10291617-scheduled-tasks-in-chatgpt), [ChatGPT Schedules](https://chatgpt.com/schedules).

## Goose (Block / Linux Foundation AAIF)

Two-tier vocabulary: **Extensions** = MCP-based connectors (the "what Goose can do" plane); **Recipes** = YAML-packaged reusable workflows with parameters, retry logic, and sub-recipes. Recipes are the closest analogue to Claude Skills, but Goose explicitly named them "Recipes" instead — emphasizing composition / shareability over capability-packaging. 44.7k GitHub stars; works with 15+ LLM providers. Sources: [Goose Recipes](https://block.github.io/goose/docs/guides/recipes/), [Goose Documentation](https://block-goose.mintlify.app/).

## Devin (Cognition)

**Tasks** = asynchronous units of delegated work. **Sessions** = persistent workspaces with terminal + editor + browser. **Managed Devins** = parallel sub-agent delegation pattern (one Devin spawns others, each in its own VM). Pricing in **ACUs** (Agent Compute Units). No "Skill" concept — Devin works at the task-completion level. Sources: [Devin Intro](https://docs.devin.ai/get-started/devin-intro), [Devin 2.0](https://cognition.ai/blog/devin-2), [Devin Manages Devins](https://cognition.ai/blog/devin-can-now-manage-devins).

## App-building agents (Replit Agent / v0 / Lovable / Bolt)

Largely outside this taxonomy — they're project-as-output agents. The unit isn't "a skill," it's "the app itself." Replit Agent 4 (March 2026) supports parallel task execution + Design Mode. Less directly relevant to Talkie's question. Sources: [Bolt vs Replit vs Lovable](https://lovable.dev/guides/bolt-vs-replit-vs-lovable), [AI Prototyping Stack Comparison](https://annaarteeva.medium.com/choosing-your-ai-prototyping-stack-lovable-v0-bolt-replit-cursor-magic-patterns-compared-9a5194f163e9).

## Synthesis — what the AI-tools world calls things

**"Skill" has become the convergent term for packaged, reusable, file-based agent capabilities.** Anthropic originated the SKILL.md format; Cursor and Windsurf adopted it unchanged; an "Agent Skills open standard" is forming. ~17 official Anthropic skills published. The format is opinionated: YAML frontmatter for *when-to-use*, markdown for *what-to-do*, optional bundled scripts/templates.

**"Tool" is the convergent atomic-verb name** via MCP. Tools = functions, Resources = data, Prompts = templates. Cross-vendor: Anthropic, OpenAI, Google, Goose, Cursor, Windsurf, 3000+ third-party servers.

**"Action" is fading in the AI/agentic space.** OpenAI still uses it (Custom GPT Actions = OpenAPI calls) but is migrating to "Apps." It survives mostly as a classical-automation term (Zapier, Alfred, Shortcuts). In agentic-AI it's been displaced by MCP "Tools."

**"Workflow" is largely absent at the unit level in AI tools.** Goose says "Recipes." Devin says "Tasks." Anthropic Cowork says "Tasks." Microsoft Power Automate still says "Flows" but that's classical. No major agentic tool brands its primary user-authored unit as a "Workflow."

**Scope determines the name, not domain.** Claude Code's hierarchy (slash command / skill / subagent / MCP tool) is by *size and isolation*, not by topic. This is the most useful framing I found: a "skill" is what stays in front of you, a "subagent" is what runs in a side process, a "tool" is an atomic primitive.

## Implications for Talkie (claude's read)

Three things worth weighing in our taxonomy decision:

1. **"Skill" is now the strongest cross-vendor convention in the AI space.** Anthropic + Cursor + Windsurf converge on SKILL.md. If Talkie picks "Skill," it aligns with the vocabulary users already learn from Claude Code, Claude.ai, Cursor, and Windsurf. The Raycast collision (SKILL.md as AI context) is the *outlier*, not the rule.

2. **The WHEN/WITH/DO/THEN syntax we sketched maps almost 1:1 to SKILL.md frontmatter.** YAML frontmatter has `name`, `description`, `when-to-use` (= WHEN), and the markdown body holds instructions (= DO). Talkie could ship its skill files *as* SKILL.md files compatible with the cross-vendor format — meaning a power user could potentially share/reuse a Talkie skill via Claude Code. That's a real interop play.

3. **The MCP layer answers "what's the action tier called?"** It's *tools* (cross-vendor) or *modules/nodes* (graph tools). Internally Talkie's `WorkflowStep.StepType` is fine; if it ever becomes user-facing, "tool" or "step" matches the convention. "Action" is the safest term for *user-authored skill output* (the chip the user invokes on selected content) — that's how Compose currently uses it, and it doesn't collide with the AI-tools sense.

The cleanest taxonomy stack, if we lean into the agentic convention:

- **Skill** = user-authored, voice-triggered, WHEN/WITH/DO/THEN. Stored as `WorkflowDefinition`; surfaced as a `.skill.md`-ish file.
- **Tool** = atomic step the engine knows how to perform. Internal name; doesn't have to surface.
- **Action** = a one-shot transformation on current content (the Compose chip). Distinct sense from AI "action."
- **Workflow** = internal data-model name only. Not surfaced to users.

That's the synthesis. The fork from `2026-05-20-workflows-skills-actions-taxonomy.md` lands on Option 1 (one user-facing concept), and the cross-vendor evidence now points to that concept being called **Skill**.
