# Codebase Analysis Plan

Multi-phase recursive analysis of the Talkie codebase to identify complexity, performance opportunities, and architectural improvements.

## Analysis Tiers

| Phase | Model | Purpose | Cost |
|-------|-------|---------|------|
| 1. Inventory | haiku | Fast file/structure mapping | Low |
| 2. Module Analysis | haiku | Extract APIs, dependencies | Low |
| 3. Complexity Analysis | sonnet | Identify hotspots, patterns | Medium |
| 4. Deep Architecture | opus | Strategic recommendations | High |

---

## Phase 1: Inventory (Haiku)

### 1.1 Directory Structure Mapping
```
Prompt: Map the directory structure of {path}. For each directory, list:
- Purpose (inferred from name/contents)
- File count by extension
- Estimated lines of code
- Key files (entry points, configs)

Output as structured markdown with hierarchy.
```

### 1.2 File Classification
```
Prompt: Classify files in {path} into categories:
- Entry points (main, app delegates)
- Models/Data structures
- Views/UI components
- Services/Business logic
- Utilities/Helpers
- Tests
- Configuration

List each file with its category and a 1-line description.
```

---

## Phase 2: Module Analysis (Haiku)

### 2.1 Public API Extraction
```
Prompt: For the module at {path}, extract all public APIs:
- Public classes/structs/enums
- Public functions with signatures
- Public properties
- Protocols defined
- Extensions provided

Format as a module interface document.
```

### 2.2 Dependency Mapping
```
Prompt: Analyze imports/dependencies in {path}:
- Internal dependencies (other modules in codebase)
- External dependencies (frameworks, packages)
- Circular dependency risks
- Coupling assessment (tight/loose)

Create a dependency matrix.
```

### 2.3 Data Flow Tracing
```
Prompt: Trace data flow in {module}:
- Entry points (where data comes in)
- Transformations (how data changes)
- Exit points (where data goes out)
- State storage (where data persists)

Document as a flow diagram description.
```

---

## Phase 3: Complexity Analysis (Sonnet)

### 3.1 Cyclomatic Complexity Hotspots
```
Prompt: Analyze {file} for complexity:
- Functions with high cyclomatic complexity (many branches)
- Deeply nested code (>3 levels)
- Long functions (>50 lines)
- God classes (>500 lines, too many responsibilities)

For each hotspot, explain:
1. Why it's complex
2. Risk level (low/medium/high)
3. Refactoring suggestion
```

### 3.2 Pattern Recognition
```
Prompt: Identify design patterns in {module}:
- Patterns in use (singleton, observer, factory, etc.)
- Anti-patterns present
- Missing patterns that could help
- Inconsistent pattern usage

Provide examples and recommendations.
```

### 3.3 Error Handling Audit
```
Prompt: Audit error handling in {path}:
- Try/catch coverage
- Error propagation patterns
- Silent failures (caught but ignored)
- User-facing error messages
- Logging of errors

Rate error handling quality and suggest improvements.
```

### 3.4 Concurrency Analysis
```
Prompt: Analyze concurrency in {module}:
- Async/await usage patterns
- Actor isolation
- Potential race conditions
- Main thread blocking risks
- Dispatch queue usage

Identify thread safety issues.
```

---

## Phase 4: Deep Architecture Review (Opus)

### 4.1 Module Boundary Assessment
```
Prompt: Evaluate module boundaries in the codebase:
- Are responsibilities clearly separated?
- Which modules are doing too much?
- Which modules are too fragmented?
- Where should code be moved?

Propose an ideal module structure with migration path.
```

### 4.2 Performance Architecture
```
Prompt: Analyze performance architecture:
- Startup path critical analysis
- Memory management patterns
- Caching strategies in use
- Database query patterns
- Network call patterns
- UI rendering bottlenecks

Prioritize performance improvements by impact.
```

### 4.3 Testability Assessment
```
Prompt: Evaluate testability:
- Dependency injection usage
- Protocol-based abstractions
- Mocking boundaries
- Integration test seams
- Current test coverage gaps

Recommend testability improvements.
```

### 4.4 Strategic Recommendations
```
Prompt: Based on the full analysis, provide:
1. Top 5 technical debt items to address
2. Top 5 performance optimizations
3. Top 5 architectural improvements
4. Estimated effort for each (small/medium/large)
5. Recommended prioritization

Consider both short-term fixes and long-term refactors.
```

---

## Execution Strategy

### Parallel Execution Plan

```
┌─────────────────────────────────────────────────────────────┐
│                    PHASE 1: INVENTORY                        │
│                      (5 haiku agents)                        │
├─────────────┬─────────────┬─────────────┬─────────────┬─────┤
│   Talkie    │  TalkieLive │ TalkieEngine│  TalkieKit  │ iOS │
│   macOS/    │   macOS/    │   macOS/    │  Packages/  │     │
└─────────────┴─────────────┴─────────────┴─────────────┴─────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                 PHASE 2: MODULE ANALYSIS                     │
│                     (haiku per module)                       │
├─────────────────────────────────────────────────────────────┤
│  Run in parallel: API extraction, dependency mapping,        │
│  data flow for each major module                            │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                PHASE 3: COMPLEXITY ANALYSIS                  │
│                    (sonnet, sequential)                      │
├─────────────────────────────────────────────────────────────┤
│  Analyze hotspots identified in Phase 2                      │
│  Deep dive on largest/most complex files                     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              PHASE 4: ARCHITECTURE REVIEW                    │
│                      (opus, final)                           │
├─────────────────────────────────────────────────────────────┤
│  Synthesize all findings into strategic recommendations      │
└─────────────────────────────────────────────────────────────┘
```

---

## Output Structure

All analysis should be saved to `docs/analysis/`:

```
docs/analysis/
├── inventory/
│   ├── talkie-structure.md
│   ├── talkielive-structure.md
│   ├── talkiekit-structure.md
│   └── file-classification.md
├── modules/
│   ├── {module}-api.md
│   ├── {module}-dependencies.md
│   └── {module}-dataflow.md
├── complexity/
│   ├── hotspots.md
│   ├── patterns.md
│   ├── error-handling.md
│   └── concurrency.md
├── architecture/
│   ├── module-boundaries.md
│   ├── performance.md
│   ├── testability.md
│   └── recommendations.md
└── SUMMARY.md
```
