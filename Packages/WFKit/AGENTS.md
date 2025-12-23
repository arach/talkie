# AGENTS.md

This file provides context for AI coding assistants working with WFKit.

## What is WFKit?

WFKit is a Swift Package that provides a native workflow/node editor for macOS and iOS apps. Think React Flow, but for SwiftUI. No WebViews, no Electron - pure native performance.

## Critical Concept: Schema vs Instance

**This is the most important architectural concept to understand.**

WFKit separates two concerns:

### Schema (Type Definitions)
The **schema** describes *what kinds of nodes exist* and *what fields they have*. It's the application's type system - stable metadata that doesn't change per workflow.

- Defined once by the host app at initialization
- Describes node types (LLM, Notification, Condition, etc.)
- Defines field metadata (display names, types, ordering, help text)
- Passed via `WFSchemaProvider` protocol

### Instance (Runtime Data)
The **instance** is the actual workflow data - specific nodes, their positions, their field values, and their connections.

- Changes as users edit the workflow
- Contains node positions, titles, customFields values
- Stored in `CanvasState` and `WorkflowNode` models
- Serializable to JSON for persistence

### Why This Matters

The instance (`WorkflowNode.configuration.customFields`) stores raw key-value data like:
```json
{"_0.modelId": "gpt-4o", "_0.prompt": "Summarize...", "_0.temperature": "0.7"}
```

The schema tells WFKit *how to interpret and display* that data:
```swift
WFFieldSchema(id: "_0.modelId", displayName: "Model", type: .picker([...]), order: 0)
WFFieldSchema(id: "_0.prompt", displayName: "Prompt", type: .text, order: 1)
WFFieldSchema(id: "_0.temperature", displayName: "Temperature", type: .slider(min: 0, max: 2, step: 0.1), order: 2)
```

Without schema, WFKit falls back to auto-formatting keys (`_0.modelId` → "Model Id") and showing all fields alphabetically. With schema, the inspector shows properly labeled, ordered, grouped fields with appropriate controls.

### Integration Pattern

```swift
// Host app defines schema once
struct MyAppSchema: WFSchemaProvider {
    let nodeTypes: [WFNodeTypeSchema] = [
        WFNodeTypeSchema(
            id: "LLM",
            displayName: "AI Generation",
            category: "Processing",
            fields: [
                WFFieldSchema(id: "_0.modelId", displayName: "Model", type: .string, order: 0),
                WFFieldSchema(id: "_0.prompt", displayName: "Prompt", type: .text, order: 1),
            ]
        )
    ]
}

// Pass schema at initialization - it defines the world
WFWorkflowEditor(
    state: canvasState,      // Instance: changes per workflow
    schema: MyAppSchema(),   // Schema: stable type definitions
    isReadOnly: false
)
```

## Architecture Overview

```
Sources/WFKit/
├── Canvas/
│   ├── WorkflowCanvas.swift    # Main canvas with pan/zoom
│   └── NodeView.swift          # Individual node rendering
├── Models/
│   ├── CanvasState.swift       # @Observable state container
│   ├── WorkflowNode.swift      # Node model (instance data)
│   └── WFSchema.swift          # Schema types (type definitions)
├── Inspector/
│   └── InspectorView.swift     # Property inspector panel
├── Toolbar/
│   └── ToolbarView.swift       # Canvas toolbar
└── Theme/
    └── WFTheme.swift           # Theming system
```

## Key Patterns

### State Management
- `CanvasState` is an `@Observable` class
- Use `@State var canvas = CanvasState()` in your view
- Pass to `WFWorkflowEditor(state: canvas)`

### Node Types
Built-in types: `.trigger`, `.action`, `.condition`, `.output`, `.llm`

Extend with custom types:
```swift
extension NodeType {
    static let custom = NodeType(id: "custom", icon: "star", color: .blue)
}
```

### Connections
- Nodes have input/output ports
- Connections are directed (source → target)
- Use `canvas.connect(from:to:)` or `canvas.connect(from:port:to:)`

## Common Tasks

### Add a node programmatically
```swift
let node = WorkflowNode(type: .action, title: "My Node", position: .init(x: 100, y: 100))
canvas.addNode(node)
```

### Remove a node
```swift
canvas.removeNode(node)
```

### Get all nodes
```swift
canvas.nodes  // [WorkflowNode]
```

### Get connections
```swift
canvas.connections  // [Connection]
```

## Build Commands

```bash
swift build           # Build the package
swift test            # Run tests
swift build -c release # Release build
```

## Demo App

The package includes a demo app. Open `Package.swift` in Xcode and run the `WFKitDemo` target.

## Dependencies

None. WFKit is dependency-free, using only SwiftUI and Foundation.

## TWF (Talkie Workflow Format) Integration

WFKit can visualize workflows defined in TWF format - a JSON-based workflow definition format designed for voice memo processing pipelines.

### What is TWF?

TWF (Talkie Workflow Format) is a human-readable, LLM-friendly workflow format that uses:
- **Slug-based IDs** instead of UUIDs (git-friendly, portable)
- **14 step types** covering AI, integrations, logic, and outputs
- **Template variables** like `{{TRANSCRIPT}}`, `{{step-id.property}}`

### Sample Workflows

The `Sources/WFKit/Resources/SampleWorkflows/` directory contains:

| File | Complexity | Description |
|------|------------|-------------|
| `quick-summary.twf.json` | Simple | Single LLM step |
| `tweet-summary.twf.json` | Medium | LLM + clipboard + notification |
| `hq-transcribe.twf.json` | Medium | Local Whisper + LLM polish |
| `cloud-transcribe.twf.json` | Medium | Shell command + conditional branching |
| `feature-ideation.twf.json` | Complex | JSON extraction + conditional + reminders |
| `learning-capture.twf.json` | Complex | Multi-step with Obsidian integration |

### Full Specification

See `TWF_SPEC.md` in the SampleWorkflows directory for:
- Complete format specification
- All 14 step types with JSON examples
- Template variable syntax
- UUID generation algorithm

### Converting TWF to WFKit

TWF steps map to WFKit node types:

| TWF Step Type | WFKit NodeType | Category |
|---------------|----------------|----------|
| LLM Generation | `.llm` | AI |
| Transcribe Audio | `.llm` | AI |
| Transform Data | `.transform` | Logic |
| Conditional Branch | `.condition` | Logic |
| Send Notification | `.notification` | Output |
| Notify iPhone | `.notification` | Output |
| Copy to Clipboard | `.output` | Output |
| Save to File | `.output` | Output |
| Create Reminder | `.output` | Apple |
| Run Shell Command | `.action` | Integration |
| Trigger Detection | `.trigger` | Trigger |
| Extract Intents | `.trigger` | Trigger |
| Execute Workflows | `.trigger` | Trigger |

### Example: Loading TWF into WFKit

```swift
// 1. Parse TWF JSON
let twf = try JSONDecoder().decode(TWFWorkflow.self, from: data)

// 2. Convert to WFKit nodes
var nodes: [WorkflowNode] = []
for (index, step) in twf.steps.enumerated() {
    let node = WorkflowNode(
        id: UUID(slug: "\(twf.slug)/\(step.id)"),  // Deterministic UUID
        type: mapStepType(step.type),
        title: step.type,  // e.g., "LLM Generation"
        position: CGPoint(x: 100 + index * 280, y: 150),
        configuration: NodeConfiguration(
            customFields: flattenConfig(step.config)
        )
    )
    nodes.append(node)
}

// 3. Create connections (linear pipeline)
var connections: [WorkflowConnection] = []
for i in 0..<(nodes.count - 1) {
    connections.append(WorkflowConnection(
        sourceNodeId: nodes[i].id,
        targetNodeId: nodes[i + 1].id
    ))
}

// 4. Create canvas state
let canvas = CanvasState()
canvas.nodes = nodes
canvas.connections = connections
```

### TWF Custom Fields

TWF config is nested under type-specific keys. Flatten for WFKit:

```json
// TWF format
{
  "config": {
    "llm": {
      "prompt": "Summarize...",
      "temperature": 0.7
    }
  }
}

// Flattened for WFKit customFields
{
  "configType": "llm",
  "prompt": "Summarize...",
  "temperature": "0.7"
}
```

### Schema for TWF Step Types

Define schema to render TWF configs properly in the inspector:

```swift
WFNodeTypeSchema(
    id: "LLM Generation",
    displayName: "AI Generation",
    category: "AI",
    fields: [
        WFFieldSchema(id: "prompt", displayName: "Prompt", type: .text, order: 0),
        WFFieldSchema(id: "systemPrompt", displayName: "System Prompt", type: .text, order: 1),
        WFFieldSchema(id: "costTier", displayName: "Cost Tier", type: .picker(["budget", "balanced", "capable"]), order: 2),
        WFFieldSchema(id: "temperature", displayName: "Temperature", type: .slider(min: 0, max: 2, step: 0.1), order: 3),
        WFFieldSchema(id: "maxTokens", displayName: "Max Tokens", type: .number, order: 4),
    ]
)
```
