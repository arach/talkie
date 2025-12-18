# Performance Monitor V2 - Comprehensive Design

## Overview

The Performance Monitor has been completely redesigned from a basic list view into a production-quality performance analysis tool. It now provides deep inspection capabilities with interactive visualizations, advanced filtering, statistical analysis, and operation-level drill-down.

## Key Features

### 1. Expandable Action Rows
**What it does**: Click any action to see all individual operations that occurred during that action.

**Visual Design**:
- Chevron indicator (right → down when expanded)
- Highlighted background when expanded (accent color with opacity)
- Smooth transition animation
- Operations shown only when action has operations (empty actions have no chevron)

**Information Shown**:
- Main row: Action type badge, name, processing time, operation count, category breakdown
- Expanded view: Timeline visualization + detailed operations table

### 2. Operation Timeline Visualization
**What it does**: Visual timeline showing when each operation occurred within the action and how long it took.

**Visual Design**:
- Horizontal timeline bar (20px height)
- Colored bars for each operation category
- Bar width represents operation duration
- Bar position represents when it started (relative to action start)
- Hover shows operation name and duration

**Color Coding**:
- **Blue**: Database operations
- **Orange**: Network operations
- **Purple**: LLM calls
- **Pink**: Inference operations
- **Cyan**: Engine tasks
- **Green**: Processing/general
- **Gray**: Other/uncategorized

### 3. Operation Details Table
**What it shows**: When action is expanded, shows table with all operations.

**Columns**:
- **OPERATION**: Category badge + operation name
- **DURATION**: Time taken (color-coded: red >1s, orange >100ms, default otherwise)
- **START**: Relative time from action start (e.g., "+16ms")
- **% OF TOTAL**: Percentage of action's total processing time + mini progress bar

**Visual Elements**:
- Color-coded category dots (6px circles)
- Category labels (8px, uppercase)
- Progress bars showing operation percentage
- Monospaced fonts for all timing data

### 4. Advanced Filtering

**Search Box** (200px width):
- Magnifying glass icon
- Placeholder: "Search actions..."
- Clear button (X) appears when text entered
- Filters by action name or action type
- Case-insensitive matching

**Filter by Action Type** (dropdown menu):
- "All Actions" (default)
- Dynamically populated from existing action types
- Shows: Load, Click, Sort, Search, Filter, etc.
- Menu style: borderless button

**Filter by Operation Category** (dropdown menu):
- "All Categories" (default)
- Fixed options: Database, Network, LLM, Inference, Engine, Processing
- Shows color dot indicator when category selected
- Filters to actions containing at least one operation of that category

**Action Counter**: Shows "X actions" based on current filters

### 5. Comprehensive Statistics Panel

**Toggle**: "Show Stats" / "Hide Stats" button (collapses entire panel)

**Primary Metrics** (top row, 5 stat cards):
- **TOTAL ACTIONS**: All actions since app launch
- **RECENT**: Last 50 actions (current view limit)
- **AVG TIME**: Average processing time
- **MIN**: Fastest processing time
- **MAX**: Slowest processing time

**Percentile Metrics** (second row, 3 stat cards):
- **P50 (MEDIAN)**: 50th percentile
- **P95**: 95th percentile (performance target)
- **P99**: 99th percentile (outliers)

**Category Breakdown** (third row):
- "TIME BY CATEGORY" section
- Shows total time spent in each operation category across all actions
- Sorted by most time to least time
- Visual chips with:
  - Color dot indicator
  - Category name (uppercase)
  - Total duration

**Stat Card Design**:
- Color-coded borders and backgrounds
- 10% opacity fill
- 30% opacity border
- Bold monospaced values
- Small uppercase labels (8px)
- Padding: 10px horizontal, 6px vertical
- Rounded corners (6px)

### 6. Sorting Options

**Sort Menu** (dropdown):
- Icon: "arrow.up.arrow.down"
- Checkmark indicates active sort
- Menu style: borderless button

**Sort Modes**:
1. **Newest First** (default): Most recent actions at top
2. **Oldest First**: Reverse chronological
3. **Slowest First**: Longest processing time first
4. **Fastest First**: Shortest processing time first
5. **Most Operations**: Actions with most operations first

### 7. Enhanced Breakdown View

**Mini Category Pills** (in main action row):
- Show count + category abbreviation + total time
- Example: "2 DAT (13ms)" = 2 database operations, 13ms total
- Sorted by total time within category (most expensive first)
- Color-coded backgrounds (15% opacity)
- Compact design: 5px horizontal, 2px vertical padding

**Breakdown Elements**:
- 5px color dots
- Operation count (monospaced, 9px)
- 3-letter category abbreviation (uppercase, 8px, bold)
- Duration in parentheses (monospaced, 9px, secondary color)

### 8. Header & Controls

**Header Design**:
- Left: "PERFORMANCE MONITOR" title + "INSTRUMENTED" status (green dot)
- Right: "Show/Hide Stats" toggle + "Clear All" button
- Full width: 1200px
- Background: window background color
- Padding: 16px

**Controls Row** (under stats):
- Search box (left)
- Action type filter
- Category filter
- Spacer
- Sort menu
- Action count label (right)
- Background: slightly darker than window
- Padding: 16px horizontal, 8px vertical

### 9. Actions List Table

**Column Headers**:
- **Chevron**: (12px, for expand indicator)
- **#**: Index number
- **ACTION**: Type badge + name + context
- **TIME**: Processing duration
- **OPS**: Operation count
- **BREAKDOWN**: Category pills

**Column Widths**:
- Chevron: 12px
- Index: 30px
- Action: 200px
- Time: 80px
- Ops: 40px
- Breakdown: flexible (maxWidth: .infinity)

**Visual Design**:
- Header: control background color
- Rows: 8px vertical padding, 16px horizontal
- Dividers between rows
- Hover-able (click to expand)
- Expanded rows have colored background (accent 5% opacity)

### 10. Empty State

**Shown when**: No actions recorded OR all actions filtered out

**Design**:
- Centered vertically and horizontally
- "No actions yet" (12px, secondary color)
- "Navigate between sections to see performance data" (10px, secondary color)
- Spacer top and bottom

## Technical Implementation

### State Management
- `@State expandedActions: Set<UUID>`: Tracks which actions are expanded
- `@State filterActionType: String?`: Current action type filter
- `@State filterCategory: OperationCategory?`: Current category filter
- `@State searchText: String`: Search query
- `@State sortMode: SortMode`: Current sorting mode
- `@State showStats: Bool`: Stats panel visibility

### Computed Properties
- `filteredActions`: Applies all filters and sorting to monitor.actions
- `stats`: Calculates all statistics on-the-fly from current actions

### Helper Functions
- `percentile(_ values: [TimeInterval], _ p: Double)`: Calculates percentiles
- `calculateCategoryBreakdown()`: Aggregates time by category across all actions
- `actionTypeColor()`: Maps action types to colors
- `categoryColor()`: Maps operation categories to colors
- `processingTimeColor()`: Color-codes processing times (red/orange/default)

### Performance Optimizations
- Stats calculated lazily (only when needed)
- Filtering happens in computed property (reactive)
- Expandable sections use Set for O(1) lookup
- Timeline uses GeometryReader for responsive width calculations

## Usage Examples

### Basic Usage
1. Press **Cmd+Shift+P** to open Performance Monitor
2. Navigate between sections to see "LOAD" actions
3. Click buttons to see "CLICK" actions
4. Click any action row to expand and see operations

### Finding Slow Operations
1. Click **Sort** → **Slowest First**
2. Expand the slowest action
3. Look at timeline to see operation distribution
4. Check operations table to find bottleneck (highest %)

### Analyzing Database Performance
1. Click **Category filter** → **Database**
2. See only actions with DB operations
3. Check stats panel "TIME BY CATEGORY" → DATABASE total
4. Expand actions to see individual query times

### Tracking LLM Usage
1. Click **Category filter** → **LLM**
2. Stats panel shows total LLM time
3. Expand actions to see which LLM calls took longest
4. Check P95/P99 to understand outliers

### Finding UI Lag
1. Click **Action Type filter** → **Click**
2. Sort by **Slowest First**
3. See which button clicks are slowest
4. Expand to see what operations make them slow

## Visual Hierarchy

1. **Stats Panel** (top): High-level overview
2. **Controls** (below stats): Filtering and sorting
3. **Action List** (main area): Scannable table
4. **Expanded Details** (when clicked): Deep dive into single action

## Color Palette

**Action Types**:
- Load: Blue
- Click: Green
- Sort: Orange
- Search: Purple
- Filter: Pink
- Default: Gray

**Operation Categories**:
- Database: Blue
- Network: Orange
- LLM: Purple
- Inference: Pink
- Engine: Cyan
- Processing: Green
- Other: Gray

**Processing Time**:
- Fast (<100ms): Default
- Medium (100ms-1s): Orange
- Slow (>1s): Red

**UI Elements**:
- Primary text: Default (adapts to light/dark mode)
- Secondary text: .secondary
- Backgrounds: .controlBackgroundColor
- Accents: .accentColor (5% opacity when expanded)

## Window Dimensions

- **Width**: 1200px (increased from 900px)
- **Height**: 700px (increased from 600px)
- Provides space for:
  - Stats panel (when shown)
  - Filters row
  - ~10-12 actions visible
  - Expanded action details

## Future Enhancements (Not Implemented)

Possible additions for future iterations:
- Export actions to CSV/JSON
- Trend charts (processing time over time)
- Real-time streaming updates
- Alert thresholds (notify when action >Xms)
- Comparative analysis (compare two actions)
- Flame graph visualization
- Custom grouping (by context, by hour, etc.)
- Performance budgets ("warn if DB >50ms")

## Integration Points

**Used By**:
- NavigationView: Cmd+Shift+P keyboard shortcut opens monitor
- Every TalkieSection: Creates LOAD actions automatically
- Every TalkieButton: Creates CLICK actions automatically
- GRDBRepository: Adds DB operations to active action

**Consumes**:
- PerformanceMonitor.shared: Singleton with all performance data
- PerformanceAction: Action model with operations
- PerformanceOperation: Individual operation model
- OperationCategory: Enum for operation types

## Testing Workflow

1. **Generate test data**: Navigate between sections (creates LOAD actions)
2. **Click buttons**: Use instrumented buttons (creates CLICK actions with DB ops)
3. **Verify stats**: Check that avg/min/max/percentiles make sense
4. **Test filtering**: Try each filter to ensure correct subset shown
5. **Test sorting**: Verify each sort mode orders correctly
6. **Test expansion**: Click actions to see operations and timeline
7. **Test search**: Type action names and verify filtering
8. **Check colors**: Verify category colors match between pills, timeline, and table

## Known Limitations

1. **50 action limit**: Only keeps last 50 actions in memory
2. **No persistence**: Actions lost on app restart
3. **MainActor only**: All instrumentation must happen on main thread
4. **No export**: Can't save data for later analysis
5. **No grouping**: Can't group related actions (e.g., all Loads together)

## Conclusion

This redesigned Performance Monitor transforms raw performance data into actionable insights. It provides multiple levels of detail (stats → actions → operations → individual operation timing) with powerful filtering and sorting to help developers understand where time is spent in the application.
