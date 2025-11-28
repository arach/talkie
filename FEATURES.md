# Talkie Features

Voice memos, supercharged with AI workflows.

## Core Features

### Voice Recording & Transcription
- **One-tap recording** - Start capturing thoughts instantly
- **Automatic transcription** - Convert speech to text with high accuracy
- **iCloud sync** - Access memos across all your Apple devices
- **Smart organization** - Library with All Memos, Recent, Processed, and Archived views

### AI-Powered Workflows
Build custom automation pipelines that process your voice memos through multiple steps:

- **Multi-step pipelines** - Chain together LLM calls, shell commands, file operations, and more
- **Multi-provider LLM support** - Use Gemini, OpenAI, Anthropic, Groq, or local MLX models
- **Template variables** - Reference transcript, title, date, and outputs from previous steps
- **Visual workflow builder** - Drag-and-drop step configuration with real-time preview

### Workflow Step Types

| Step Type | Description |
|-----------|-------------|
| **LLM Generation** | Process text with AI models (summarize, extract, transform) |
| **Shell Command** | Run CLI tools like `claude`, `gh`, `jq`, `curl` with full argument control |
| **Save to File** | Write outputs to disk with path aliases and template filenames |
| **Webhook** | Send data to external services via HTTP |
| **Email** | Send processed results via email |
| **Calendar** | Create calendar events from voice memos |
| **Clipboard** | Copy results to clipboard |
| **Notification** | Show macOS notifications |
| **Transform** | Extract JSON, format markdown, parse lists |

## Advanced Features

### Shell Command Integration
Execute powerful CLI tools directly from workflows:

- **Security-first design** - Executable allowlist prevents unauthorized command execution
- **Claude CLI support** - Leverage Claude with all your MCP servers already configured
- **Multi-line prompt templates** - Write complex prompts with `{{TRANSCRIPT}}` and `{{PREVIOUS_OUTPUT}}`
- **Environment handling** - Proper PATH configuration for tools like node, bun, homebrew
- **Content sanitization** - Protection against injection in LLM-generated content

### Path Aliases
Define shortcuts for frequently used directories:

- **Simple syntax** - Use `@Obsidian`, `@Notes`, `@Projects` in file paths
- **Real-time validation** - See whether aliases resolve correctly as you type
- **Subdirectory support** - `@Obsidian/Voice Notes/{{DATE}}.md` just works
- **Settings UI** - Easy alias management with folder picker

### Smart File Output
Save workflow results with intelligent file naming:

- **Template variables** - `{{DATE}}`, `{{DATETIME}}`, `{{TITLE}}` in filenames
- **Filename-safe formatting** - Dates as `2025-11-26`, titles with colons/slashes sanitized
- **Auto-create directories** - Missing folders created automatically
- **Append mode** - Build up daily logs or journals by appending to existing files
- **Default output directory** - Configure once in settings, use everywhere

### Multi-Provider LLM System
Connect to the AI providers you prefer:

| Provider | Models |
|----------|--------|
| **Gemini** | gemini-2.0-flash, gemini-1.5-pro, gemini-1.5-flash |
| **OpenAI** | gpt-4o, gpt-4o-mini, gpt-4-turbo, gpt-3.5-turbo |
| **Anthropic** | claude-3-5-sonnet, claude-3-opus, claude-3-haiku |
| **Groq** | llama-3.1-70b, llama-3.1-8b, mixtral-8x7b |
| **MLX (Local)** | Run models locally on Apple Silicon |

### Model Library
Browse and manage AI models:

- **Compact card UI** - See all available models at a glance
- **Provider filtering** - View models by provider
- **Capability indicators** - See context window, speed, and cost tier
- **One-click selection** - Set default model for workflows

## User Interface

### macOS Native Experience
- **NavigationSplitView** - Adaptive 2/3-column layouts
- **Hidden title bar** - Clean, modern window chrome
- **Full-width status bar** - VS Code-style footer with sync status and memo count
- **Keyboard shortcuts** - Fast navigation and actions
- **Dark mode support** - Seamless light/dark theme switching

### Settings & Configuration
Organized settings with dedicated sections:

- **Workflows** - Create, edit, duplicate, and manage automation pipelines
- **Activity Log** - View execution history and debug workflow runs
- **Model Library** - Browse and configure AI models
- **API Settings** - Manage API keys for LLM providers
- **Allowed Commands** - Control which CLI tools workflows can execute
- **Output Directory** - Set default save location and path aliases

## Example Workflows

### Voice to Obsidian
1. **LLM** - Extract key insights as JSON
2. **Claude CLI** - Summarize with context from your MCP servers
3. **Save File** - Write to `@Obsidian/Voice Notes/{{DATE}}-{{TITLE}}.md`

### Meeting Notes to Tasks
1. **LLM** - Extract action items with priorities
2. **Transform** - Format as markdown checklist
3. **Webhook** - Send to Todoist/Linear/Notion API

### Daily Journal Builder
1. **LLM** - Summarize the day's thoughts
2. **Save File** - Append to `@Notes/journal-{{DATE}}.md` (append mode)

### Quick GitHub Issue
1. **LLM** - Structure memo as issue title + body
2. **Shell** - `gh issue create` with extracted content

## Security

- **Executable allowlist** - Only approved CLI tools can run
- **Content sanitization** - LLM outputs sanitized before use in commands
- **Injection detection** - Warnings logged for suspicious patterns
- **No shell expansion** - Arguments passed directly, preventing command injection
- **Local-first** - Your data stays on your devices with iCloud sync

## Platform Support

- **macOS** - Full-featured desktop app (macOS 13+)
- **iOS** - Mobile companion app (coming soon)
- **iCloud** - Seamless sync across devices
