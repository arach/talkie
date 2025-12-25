# VLM Visual Analysis Workflow

Automated visual analysis of Talkie UI using local vision-language models.

## Two-Step Workflow

### Step 1: Run Design Audit
Captures screenshots and generates baseline code analysis report.

```bash
# Build and run audit (all screens)
./scripts/run.sh --build
Talkie.app/Contents/MacOS/Talkie --debug=audit

# Output: ~/Desktop/talkie-audit/run-XXX/
#   - report.html (baseline report)
#   - screenshots/ (all screen captures)
```

### Step 2: Add VLM Visual Analysis (Async)
After audit completes, run VLM analysis to inject visual feedback into report.

```bash
# Start VLM service (one-time setup)
./scripts/setup-vlm-analysis.sh

# Add VLM analysis to latest audit
python3 scripts/audit-add-vlm.py

# Output: ~/Desktop/talkie-audit/run-XXX/
#   - report-with-vlm.html (enhanced with visual analysis)
#   - vlm-summary.txt (VLM-only summary)
#   - vlm-results.json (structured results)
```

This opens the enhanced report automatically in your browser.

## Tools

### `audit-add-vlm.py` ⭐ - Inject VLM into audit reports

**Primary workflow tool** - Adds visual analysis to existing design audit reports.

```bash
# Add VLM to latest audit
python3 scripts/audit-add-vlm.py

# Specific audit run
python3 scripts/audit-add-vlm.py ~/Desktop/talkie-audit/run-042

# Custom prompt
python3 scripts/audit-add-vlm.py --prompt "Check accessibility"

# Specific screens
python3 scripts/audit-add-vlm.py --screens "settings-*,memos-*"
```

**Output:**
- `report-with-vlm.html` - Original report enhanced with VLM feedback
- `vlm-summary.txt` - Text summary of all visual issues
- `vlm-results.json` - Structured JSON results

### `analyze-ui.py` - General-purpose screenshot analysis

Analyze any screenshot with any prompt.

```bash
# Analyze with custom prompt
python3 scripts/analyze-ui.py screenshot.png "Check for accessibility issues"

# Analyze with default light mode prompt
python3 scripts/analyze-ui.py screenshot.png

# Capture and analyze interactively
python3 scripts/analyze-ui.py --capture "Describe the status bar layout"

# Use prompt from file
python3 scripts/analyze-ui.py screenshot.png --prompt-file prompts/contrast.txt
```

### `vlm-audit-screens.py` - Batch analysis of audit screenshots

Analyzes all screenshots from a design audit run and generates summary reports.

```bash
# Analyze latest audit run
python3 scripts/vlm-audit-screens.py

# Analyze specific audit run
python3 scripts/vlm-audit-screens.py ~/Desktop/talkie-audit/run-042

# Analyze only settings screens
python3 scripts/vlm-audit-screens.py --screens "settings-*"

# Use custom prompt
python3 scripts/vlm-audit-screens.py --prompt "Identify spacing inconsistencies"
```

**Output:**
- `vlm-analysis/summary.txt` - Summary of all issues found
- `vlm-analysis/results.json` - Structured JSON results
- `vlm-analysis/*.vlm-analysis.txt` - Individual screen analyses

### `setup-vlm-analysis.sh` - VLM service setup

Installs and starts the local VLM service.

```bash
./scripts/setup-vlm-analysis.sh
```

## Workflow Examples

### Light Mode Audit

1. Set Talkie to light mode (Settings > Appearance)
2. Run full audit with screenshots:
   ```bash
   Talkie.app/Contents/MacOS/Talkie --debug=audit
   ```
3. Analyze all screens for light mode issues:
   ```bash
   python3 scripts/vlm-audit-screens.py
   ```
4. Review `vlm-analysis/summary.txt` for issues

### Specific Screen Analysis

1. Capture screenshots of specific screens:
   ```bash
   Talkie.app/Contents/MacOS/Talkie --debug=settings-screenshots
   ```
2. Analyze just those screens:
   ```bash
   python3 scripts/vlm-audit-screens.py --screens "settings-*"
   ```

### Custom Analysis

1. Create a custom prompt file:
   ```bash
   echo "Identify any buttons or controls that are hard to see" > prompts/visibility.txt
   ```
2. Run analysis with custom prompt:
   ```bash
   python3 scripts/vlm-audit-screens.py --prompt-file prompts/visibility.txt
   ```

## Analysis Prompts

Default prompt focuses on light mode issues:
- Dark backgrounds in light mode
- Poor contrast/readability
- UI elements not adapting properly
- Inconsistent colors
- Status bars/sidebars visibility

Custom prompts can check for:
- Accessibility (WCAG compliance, keyboard navigation hints)
- Spacing consistency
- Typography hierarchy
- Color palette adherence
- Component alignment

## VLM Service

**Model:** `mlx-community/Qwen2-VL-2B-Instruct-4bit`
**URL:** `http://127.0.0.1:12346`
**Source:** `~/dev/agentloop`

Start/stop:
```bash
# Start
cd ~/dev/agentloop && bun run vlm:server

# Stop
pkill -f 'bun.*vlm:server'

# Check status
curl http://127.0.0.1:12346/health
```

## Output Format

VLM returns structured JSON:
```json
{
  "issues": [
    {
      "location": "Status bar in top-right",
      "issue": "Dark background visible in light mode",
      "severity": "High",
      "suggestion": "Replace with Theme.current.background"
    }
  ],
  "overall_assessment": "Generally good, but needs fixes..."
}
```

## Tips

- **Batch analysis:** Run overnight for large audit runs
- **Specific screens:** Use `--screens` to focus on problem areas
- **Multiple prompts:** Run analysis multiple times with different prompts
- **Compare runs:** Keep results from different commits to track improvements
- **Custom prompts:** Tailor prompts to specific design system rules

## Dependencies

- Python 3.x with `requests` module
- VLM service running (auto-setup via `setup-vlm-analysis.sh`)
- Design audit screenshots (from `--debug=audit`)
