# CLAUDE.md

Instructions for AI agents working with WFKit.

## What This Is

WFKit is a visual workflow editor component library for macOS SwiftUI apps. It provides a canvas-based node editor where users can create, connect, and configure workflow steps visually.

## Build & Run

```bash
# Build
swift build

# Run demo app
swift run Workflow

# Or use the dev script
./dev.sh
```

## Project Structure

```
Sources/
├── WFKit/                    # Library (importable by other projects)
│   ├── Models/
│   │   ├── WorkflowNode.swift      # Node model (id, type, position, ports, config)
│   │   ├── WorkflowConnection.swift # Edge model (source/target node+port)
│   │   └── CanvasState.swift       # Observable state container
│   ├── Canvas/
│   │   ├── WorkflowCanvas.swift    # Main canvas view with pan/zoom
│   │   ├── NodeView.swift          # Individual node rendering
│   │   ├── ConnectionView.swift    # Bezier curve connections
│   │   └── MinimapView.swift       # Overview minimap
│   ├── Inspector/
│   │   └── InspectorView.swift     # Node property editor
│   ├── Toolbar/
│   │   └── ToolbarView.swift       # Top toolbar
│   ├── Theme/
│   │   └── WFTheme.swift           # Unified theming
│   ├── Components/
│   │   └── DebugKit/               # Debug toolbar (local copy)
│   └── WFWorkflowEditor.swift      # Main entry point
│
└── WorkflowApp/              # Demo app
    └── WorkflowApp.swift     # Window shell
```

## Key Models

### WorkflowNode
- `id: UUID` - Unique identifier
- `type: String` - Node type (Trigger, LLM, Condition, Action, Output)
- `title: String` - Display name
- `position: CGPoint` - Canvas position
- `size: CGSize` - Node dimensions
- `inputs: [NodePort]` - Input ports
- `outputs: [NodePort]` - Output ports
- `configuration: [String: AnyCodable]` - Type-specific config

### WorkflowConnection
- `id: UUID`
- `sourceNodeId: UUID` + `sourcePortId: UUID`
- `targetNodeId: UUID` + `targetPortId: UUID`

### CanvasState
Observable class holding:
- `nodes: [WorkflowNode]`
- `connections: [WorkflowConnection]`
- `scale: CGFloat` - Zoom level
- `offset: CGSize` - Pan offset
- `selectedNodeIds: Set<UUID>`

## Debug Features

The debug toolbar (bottom-right, ant icon) provides:
- Canvas state display (zoom, offset, node count)
- Reset zoom action
- **Snapshot** - Captures JSON state + PNG screenshot to `~/Documents/WFKit-Snapshots/`

## JSON Export Format

```json
{
  "nodes": [
    {
      "id": "UUID",
      "type": "LLM",
      "title": "Summarize",
      "position": [400, 100],
      "size": [200, 120],
      "inputs": [{ "id": "UUID", "label": "In", "isInput": true }],
      "outputs": [{ "id": "UUID", "label": "Out", "isInput": false }],
      "configuration": {
        "model": "gemini-2.0-flash",
        "prompt": "...",
        "temperature": 0.7
      }
    }
  ],
  "connections": [
    {
      "id": "UUID",
      "sourceNodeId": "UUID",
      "sourcePortId": "UUID",
      "targetNodeId": "UUID",
      "targetPortId": "UUID"
    }
  ]
}
```

## Talkie Integration

WFKit is designed to visualize and eventually edit workflows from Talkie.

### Talkie Workflow Model (in `../talkie/MacOS/`)

Talkie uses `WorkflowDefinition` with a **linear step array**:

```swift
WorkflowDefinition
├── id, name, description, icon, color
├── steps: [WorkflowStep]      // Ordered, linear execution
├── isEnabled, isPinned, autoRun
└── createdAt, modifiedAt

WorkflowStep
├── id: UUID
├── type: StepType             // 18 types (llm, shell, webhook, etc.)
├── config: StepConfig         // Union type with step-specific config
├── outputKey: String          // Named output for template vars
└── condition: StepCondition?  // Optional gating
```

### Step Types (18 total)
- **AI**: `.llm`, `.transcribe`
- **Communication**: `.email`, `.notification`, `.iOSPush`
- **Apple Apps**: `.appleNotes`, `.appleReminders`, `.appleCalendar`
- **Integration**: `.shell`, `.webhook`
- **Output**: `.clipboard`, `.saveFile`
- **Logic**: `.conditional`, `.transform`, `.trigger`, `.intentExtract`, `.executeWorkflows`

### Storage
- Location: `UserDefaults` key `"workflows_v2"`
- Format: JSON (Codable)
- All models fully serializable

### Mapping: Talkie → WFKit

| Talkie | WFKit |
|--------|-------|
| `WorkflowDefinition` | Canvas (nodes + connections) |
| `WorkflowStep` | `WorkflowNode` |
| `step.type` | `node.type` |
| `step.config` | `node.configuration` |
| `step.outputKey` | Port label |
| *implicit linear flow* | *explicit connections* |

### Conversion Strategy

**Talkie → WFKit (one-way visualization):**
1. Each `WorkflowStep` → `WorkflowNode`
2. Generate connections: step[n].output → step[n+1].input
3. Auto-layout positions (horizontal flow)
4. Map 18 step types to node types

**Round-trip challenges:**
- Branching: WFKit allows arbitrary graphs, Talkie is linear
- Port IDs: WFKit uses UUIDs, Talkie uses `outputKey` strings
- Node types: Need to expand WFKit's generic types to match Talkie's 18 specific types

## Planned: Talkie Integration (v1)

WFKit will be imported as a library into Talkie, not run as a separate app.

### Architecture
```
Talkie (macOS app)
├── Package.swift: .package(path: "../WFKit")
├── imports WFKit
└── WorkflowViews.swift
    └── "View Workflow" button → shows sheet with WFWorkflowEditor
```

### v1 Scope: Read-Only Visualization
1. **Button in Talkie** - "View Workflow" in workflow editor UI
2. **Converter** - `WorkflowDefinition` → `CanvasState` (nodes + connections)
3. **Read-only mode** - Pan/zoom only, no editing
4. **Auto-layout** - Position nodes in horizontal flow

### Implementation Steps

**In WFKit:**
1. Add `isReadOnly` flag to `CanvasState` or `WFWorkflowEditor`
2. When read-only: disable drag, hide inspector, disable connection creation
3. Create converter: `TalkieWorkflowConverter.convert(workflow: WorkflowDefinition) -> CanvasState`

**In Talkie:**
1. Add WFKit as local package dependency
2. Add "View Workflow" button (eye icon?) in WorkflowViews.swift
3. On tap: convert current workflow, show sheet with WFWorkflowEditor

### Converter Logic
```swift
func convert(workflow: WorkflowDefinition) -> CanvasState {
    var nodes: [WorkflowNode] = []
    var connections: [WorkflowConnection] = []

    for (index, step) in workflow.steps.enumerated() {
        // Create node at horizontal position
        let node = WorkflowNode(
            id: step.id,
            type: step.type.rawValue,  // "llm", "shell", etc.
            title: step.displayName,
            position: CGPoint(x: 100 + index * 250, y: 100),
            inputs: [NodePort(...)],
            outputs: [NodePort(...)],
            configuration: step.config.toDictionary()
        )
        nodes.append(node)

        // Connect to previous node
        if index > 0 {
            connections.append(WorkflowConnection(
                sourceNodeId: nodes[index-1].id,
                sourcePortId: nodes[index-1].outputs[0].id,
                targetNodeId: node.id,
                targetPortId: node.inputs[0].id
            ))
        }
    }

    return CanvasState(nodes: nodes, connections: connections)
}
```

## Common Tasks

### Adding a new node type
1. Add type to `WorkflowNode.swift` type enum/validation
2. Create config structure for the type
3. Add inspector fields in `InspectorView.swift`
4. Add node color/styling in `NodeView.swift`

### Testing changes
```bash
swift build && ./dev.sh
```

### Taking a snapshot for debugging
1. Open debug toolbar (ant icon, bottom-right)
2. Click "Snapshot" (camera icon)
3. Find files in `~/Documents/WFKit-Snapshots/`

---

## Next Steps

### Immediate: Talkie v1 Integration (Read-Only Viewer)

The goal is to add a "View Workflow" button in Talkie that opens a WFKit canvas showing the current workflow visually.

**In WFKit (do first):**
1. Add `isReadOnly: Bool` parameter to `WFWorkflowEditor`
2. When read-only: disable node dragging, hide inspector, disable connection creation
3. Ensure WFKit builds as a clean library with no demo-app dependencies

**In Talkie (`../talkie/MacOS/`):**
1. Add WFKit as local package dependency in `Package.swift`:
   ```swift
   .package(path: "../WFKit")
   ```
2. Create `TalkieWorkflowConverter.swift` - converts `WorkflowDefinition` → `CanvasState`
   - Each `WorkflowStep` → `WorkflowNode`
   - Generate connections between sequential steps
   - Auto-layout: horizontal positions at `x = 100 + index * 250`
3. Add "View Workflow" button (eye icon) in workflow editor UI
4. On tap: convert workflow, present sheet with `WFWorkflowEditor(state: converted, isReadOnly: true)`

**Key files in Talkie:**
- `Workflow/WorkflowDefinition.swift` - Source models
- `Workflow/WorkflowViews.swift` - Add button here
- Storage: `UserDefaults` key `"workflows_v2"`

### Future: Editing Support
After read-only works, consider:
- Two-way sync between Talkie linear model and WFKit graph
- Handle branching (WFKit allows, Talkie doesn't)
- Extend Talkie to support non-linear workflows
