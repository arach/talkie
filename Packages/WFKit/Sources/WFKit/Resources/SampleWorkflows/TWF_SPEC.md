# TWF (Talkie Workflow Format) Specification

**Version:** 1.0
**File Extension:** `.twf.json`

TWF is a human-readable, LLM-friendly workflow definition format designed for voice memo processing pipelines. It uses slug-based IDs (not UUIDs) for portability and git-friendliness.

---

## Format Overview

```json
{
  "slug": "workflow-slug",
  "name": "Display Name",
  "description": "What this workflow does",
  "icon": "sf.symbol.name",
  "color": "purple",
  "isEnabled": true,
  "isPinned": false,
  "autoRun": false,
  "steps": [...]
}
```

### Root Properties

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `slug` | string | Yes | Unique identifier (kebab-case). Used to generate stable UUIDs. |
| `name` | string | Yes | Display name shown in UI |
| `description` | string | Yes | Brief description of workflow purpose |
| `icon` | string | Yes | SF Symbol name (e.g., "waveform", "doc.text") |
| `color` | string | Yes | Theme color: `blue`, `purple`, `pink`, `red`, `orange`, `yellow`, `green`, `mint`, `teal`, `cyan`, `indigo`, `gray` |
| `isEnabled` | bool | Yes | Whether workflow can be run |
| `isPinned` | bool | Yes | Shows in quick access / iOS widget |
| `autoRun` | bool | Yes | Runs automatically after recording |
| `steps` | array | Yes | Ordered list of workflow steps |

---

## Step Structure

```json
{
  "id": "step-slug",
  "type": "Step Type Name",
  "config": {
    "<configKey>": { ... }
  }
}
```

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `id` | string | Yes | Unique step identifier within workflow (kebab-case) |
| `type` | string | Yes | One of the 14 step types (see below) |
| `config` | object | Yes | Configuration nested under a type-specific key |

---

## Step Types & Configurations

### 1. LLM Generation
AI text generation using various providers.

```json
{
  "id": "summarize",
  "type": "LLM Generation",
  "config": {
    "llm": {
      "costTier": "budget",
      "prompt": "Summarize this: {{TRANSCRIPT}}",
      "systemPrompt": "You are a helpful assistant.",
      "temperature": 0.7,
      "maxTokens": 1024
    }
  }
}
```

**Config properties:**
- `costTier`: `"budget"` | `"balanced"` | `"capable"` (auto-routes to appropriate model)
- `provider`: Optional. `"gemini"` | `"openai"` | `"anthropic"` | `"groq"` | `"mlx"`
- `modelId`: Optional. Specific model ID (e.g., `"gpt-4o-mini"`)
- `prompt`: Required. The prompt template with variables
- `systemPrompt`: Optional. System message for the LLM
- `temperature`: 0.0-2.0, default 0.7
- `maxTokens`: Max output tokens, default 1024
- `topP`: 0.0-1.0, default 0.9

---

### 2. Transcribe Audio
Local transcription using WhisperKit (MLX-optimized).

```json
{
  "id": "transcribe",
  "type": "Transcribe Audio",
  "config": {
    "transcribe": {
      "model": "openai_whisper-small",
      "overwriteExisting": false,
      "saveAsVersion": true
    }
  }
}
```

**Config properties:**
- `model`: Whisper model identifier
  - `"openai_whisper-tiny"` - Fastest, least accurate
  - `"openai_whisper-base"` - Fast
  - `"openai_whisper-small"` - Default, good balance
  - `"distil-whisper_distil-large-v3"` - Highest quality (MLX)
- `overwriteExisting`: Replace existing transcript
- `saveAsVersion`: Save as new version (preserves history)

---

### 3. Transform Data
Data manipulation and extraction operations.

```json
{
  "id": "parse",
  "type": "Transform Data",
  "config": {
    "transform": {
      "operation": "Extract JSON",
      "parameters": {
        "path": "$.text",
        "fallback": ""
      }
    }
  }
}
```

**Operations:**
- `"Extract JSON"` - Parse JSON from text, optionally extract path
- `"Extract List"` - Extract bullet points/numbered items
- `"Format Template"` - Apply string template
- `"Regex Match"` - Extract via regex pattern
- `"Split Text"` - Split by delimiter

**Parameters vary by operation:**
- `path`: JSONPath expression (for Extract JSON)
- `fallback`: Default value if extraction fails
- `pattern`: Regex pattern (for Regex Match)
- `delimiter`: Split character (for Split Text)

---

### 4. Conditional Branch
Control flow based on conditions.

```json
{
  "id": "check-length",
  "type": "Conditional Branch",
  "config": {
    "conditional": {
      "condition": "{{parse-response}}.length > 0",
      "thenSteps": ["format-output", "notify-success"],
      "elseSteps": ["notify-failure"]
    }
  }
}
```

**Config properties:**
- `condition`: JavaScript-like expression evaluated at runtime
- `thenSteps`: Array of step IDs to execute if true
- `elseSteps`: Array of step IDs to execute if false

---

### 5. Send Notification
Local macOS notification.

```json
{
  "id": "notify",
  "type": "Send Notification",
  "config": {
    "notification": {
      "title": "Processing complete",
      "body": "{{TITLE}} has been processed",
      "sound": true
    }
  }
}
```

---

### 6. Notify iPhone
Push notification to paired iOS device.

```json
{
  "id": "push-ios",
  "type": "Notify iPhone",
  "config": {
    "iOSPush": {
      "title": "{{TITLE}}",
      "body": "{{summarize}}",
      "sound": true,
      "includeOutput": false
    }
  }
}
```

---

### 7. Copy to Clipboard
Copy text to system clipboard.

```json
{
  "id": "copy",
  "type": "Copy to Clipboard",
  "config": {
    "clipboard": {
      "content": "{{polish}}"
    }
  }
}
```

---

### 8. Save to File
Write content to a file.

```json
{
  "id": "save",
  "type": "Save to File",
  "config": {
    "saveFile": {
      "filename": "{{DATE}}-{{TITLE}}.md",
      "directory": "@Obsidian/Notes",
      "content": "# {{TITLE}}\n\n{{summarize}}",
      "appendIfExists": false
    }
  }
}
```

**Special directories:**
- `@Obsidian/` - User's configured Obsidian vault
- `@Documents/` - User's Documents folder
- `@Desktop/` - User's Desktop

---

### 9. Create Reminder
Add to Apple Reminders.

```json
{
  "id": "remind",
  "type": "Create Reminder",
  "config": {
    "appleReminders": {
      "listName": "Inbox",
      "title": "Follow up: {{TITLE}}",
      "notes": "From voice memo on {{DATE}}",
      "dueDate": "{{NOW+1d}}",
      "priority": 5
    }
  }
}
```

**Priority values:** `1` (high), `5` (medium), `9` (low)

**Date expressions:**
- `{{NOW}}` - Current time
- `{{NOW+1d}}` - Tomorrow
- `{{NOW+3d}}` - 3 days from now
- `{{NOW+1w}}` - 1 week from now

---

### 10. Run Shell Command
Execute external commands.

```json
{
  "id": "curl-api",
  "type": "Run Shell Command",
  "config": {
    "shell": {
      "executable": "/usr/bin/curl",
      "arguments": ["-s", "https://api.example.com", "-d", "{{TRANSCRIPT}}"],
      "timeout": 30,
      "captureStderr": true
    }
  }
}
```

---

### 11. Trigger Detection
Detect activation phrases in transcript.

```json
{
  "id": "detect",
  "type": "Trigger Detection",
  "config": {
    "trigger": {
      "phrases": ["hey talkie", "okay talkie"],
      "caseSensitive": false,
      "searchLocation": "End",
      "contextWindowSize": 200,
      "stopIfNoMatch": true
    }
  }
}
```

**searchLocation:** `"Start"` | `"End"` | `"Anywhere"`

---

### 12. Extract Intents
Parse user intents from natural language.

```json
{
  "id": "parse-intent",
  "type": "Extract Intents",
  "config": {
    "intentExtract": {
      "inputKey": "{{PREVIOUS_OUTPUT}}",
      "extractionMethod": "Hybrid",
      "confidenceThreshold": 0.5
    }
  }
}
```

**extractionMethod:** `"LLM"` | `"Keywords"` | `"Hybrid"`

---

### 13. Execute Workflows
Run other workflows based on extracted intents.

```json
{
  "id": "dispatch",
  "type": "Execute Workflows",
  "config": {
    "executeWorkflows": {
      "intentsKey": "{{parse-intent}}",
      "stopOnError": false,
      "parallel": false
    }
  }
}
```

---

### 14. Additional Types

- **Add to Apple Notes** (`appleNotes`)
- **Create Calendar Event** (`appleCalendar`)
- **Webhook** (`webhook`)
- **Send Email** (`email`)

---

## Template Variables

Variables use double-brace syntax: `{{VARIABLE}}`

### Built-in Variables

| Variable | Description |
|----------|-------------|
| `{{TRANSCRIPT}}` | Full transcript text |
| `{{TITLE}}` | Voice memo title |
| `{{DATE}}` | Recording date (YYYY-MM-DD) |
| `{{DATETIME}}` | Full timestamp |
| `{{DURATION}}` | Recording duration |
| `{{AUDIO_PATH}}` | Path to audio file |
| `{{MEMO_ID}}` | Unique memo identifier |

### Step Output Variables

Reference previous step outputs by step ID:

```
{{step-id}}           → Full output of step
{{step-id.property}}  → Nested property (if JSON output)
```

**Example:**
```json
{
  "id": "extract",
  "type": "LLM Generation",
  "config": {
    "llm": {
      "prompt": "Extract JSON from: {{TRANSCRIPT}}"
    }
  }
},
{
  "id": "format",
  "type": "LLM Generation",
  "config": {
    "llm": {
      "prompt": "Format this data: {{extract.items}}"
    }
  }
}
```

---

## Example Workflows

### Simple: Quick Summary

```json
{
  "slug": "quick-summary",
  "name": "Quick Summary",
  "description": "One-sentence summary of the memo",
  "icon": "text.quote",
  "color": "blue",
  "isEnabled": true,
  "isPinned": true,
  "autoRun": false,
  "steps": [
    {
      "id": "summarize",
      "type": "LLM Generation",
      "config": {
        "llm": {
          "costTier": "budget",
          "prompt": "Summarize in one sentence: {{TRANSCRIPT}}",
          "temperature": 0.3,
          "maxTokens": 100
        }
      }
    }
  ]
}
```

### Medium: Tweet Summary with Copy

```json
{
  "slug": "tweet-summary",
  "name": "Tweet Summary",
  "description": "280-character summary, copied to clipboard",
  "icon": "text.bubble",
  "color": "cyan",
  "isEnabled": true,
  "isPinned": true,
  "autoRun": false,
  "steps": [
    {
      "id": "summarize",
      "type": "LLM Generation",
      "config": {
        "llm": {
          "costTier": "budget",
          "prompt": "Summarize in 280 characters or less. Output ONLY the summary:\n\n{{TRANSCRIPT}}",
          "temperature": 0.5,
          "maxTokens": 100
        }
      }
    },
    {
      "id": "copy",
      "type": "Copy to Clipboard",
      "config": {
        "clipboard": {
          "content": "{{summarize}}"
        }
      }
    },
    {
      "id": "notify",
      "type": "Send Notification",
      "config": {
        "notification": {
          "title": "Copied!",
          "body": "{{summarize}}",
          "sound": true
        }
      }
    }
  ]
}
```

### Complex: Feature Ideation Pipeline

```json
{
  "slug": "feature-ideation",
  "name": "Feature Ideation",
  "description": "Brainstorm features, categorize by effort/impact, save to backlog",
  "icon": "lightbulb.max",
  "color": "yellow",
  "isEnabled": true,
  "isPinned": false,
  "autoRun": false,
  "steps": [
    {
      "id": "extract-features",
      "type": "LLM Generation",
      "config": {
        "llm": {
          "costTier": "balanced",
          "prompt": "Analyze this feature brainstorm:\n\n{{TRANSCRIPT}}\n\nReturn JSON:\n{\n  \"project\": \"project name or 'General'\",\n  \"features\": [\n    {\n      \"title\": \"short title\",\n      \"description\": \"1-2 sentences\",\n      \"impact\": \"high|medium|low\",\n      \"effort\": \"high|medium|low\"\n    }\n  ],\n  \"quickWins\": [\"high impact + low effort features\"]\n}",
          "systemPrompt": "You help with product thinking. Be honest about effort estimates.",
          "temperature": 0.4,
          "maxTokens": 2048
        }
      }
    },
    {
      "id": "parse-json",
      "type": "Transform Data",
      "config": {
        "transform": {
          "operation": "Extract JSON",
          "parameters": {
            "fallback": "{\"project\": \"General\", \"features\": []}"
          }
        }
      }
    },
    {
      "id": "check-quick-wins",
      "type": "Conditional Branch",
      "config": {
        "conditional": {
          "condition": "{{parse-json.quickWins.length}} > 0",
          "thenSteps": ["create-reminder"],
          "elseSteps": []
        }
      }
    },
    {
      "id": "create-reminder",
      "type": "Create Reminder",
      "config": {
        "appleReminders": {
          "listName": "Inbox",
          "title": "Quick win: {{parse-json.quickWins[0]}}",
          "notes": "From {{parse-json.project}} ideation",
          "dueDate": "{{NOW+1d}}",
          "priority": 5
        }
      }
    },
    {
      "id": "notify",
      "type": "Send Notification",
      "config": {
        "notification": {
          "title": "Ideas captured",
          "body": "{{parse-json.features.length}} features for {{parse-json.project}}",
          "sound": true
        }
      }
    }
  ]
}
```

---

## UUID Generation

TWF uses deterministic UUID generation from slugs:

```
UUID = SHA256("talkie.twf:{workflow-slug}")[:16]  // with version 4 bits set
Step UUID = SHA256("talkie.twf:{workflow-slug}/{step-id}")[:16]
```

This ensures:
- Same slug always produces same UUID
- Workflows can be safely re-imported without duplication
- Git-friendly (no random UUIDs in diffs)

---

## Validation Rules

1. `slug` must be unique, kebab-case, no spaces
2. Step `id` must be unique within workflow
3. `thenSteps`/`elseSteps` must reference valid step IDs
4. Template variables must reference existing steps or built-ins
5. At least one step required

---

## File Naming Convention

```
{slug}.twf.json
```

Examples:
- `quick-summary.twf.json`
- `feature-ideation.twf.json`
- `hq-transcribe.twf.json`
