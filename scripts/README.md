# Talkie Scripts

Utility scripts for building, auditing, and analyzing the Talkie macOS app.

## Quick Reference

### Build & Run
```bash
# Run without building (fast)
./scripts/run.sh

# Build then run
./scripts/run.sh --build
```

### Design Audit + VLM Analysis

**Two-step workflow:**

```bash
# Step 1: Run design audit (code analysis + screenshots)
./scripts/run.sh --build
Talkie.app/Contents/MacOS/Talkie --debug=audit

# Step 2: Add VLM visual analysis (async, separate step)
python3 scripts/audit-add-vlm.py
```

**Output:** `~/Desktop/talkie-audit/run-XXX/report-with-vlm.html`

See [VLM-ANALYSIS.md](./VLM-ANALYSIS.md) for details.

### Light Mode Fixes

```bash
# Automated color token migration
python3 scripts/fix-light-mode.py --dry-run  # Preview
python3 scripts/fix-light-mode.py            # Apply
```

## Scripts

### Build & Launch

**`run.sh`** - Smart launcher with optional build
- Finds DerivedData for current worktree
- Caches location for fast launches
- Optional build step with `--build` flag
- Shows app and binary paths

```bash
./scripts/run.sh          # Quick launch
./scripts/run.sh --build  # Build then launch
```

### Design Audit

**`audit-add-vlm.py`** ⭐ - Inject VLM into audit reports
- Primary workflow tool for visual analysis
- Analyzes screenshots from design audit
- Injects visual feedback into HTML report
- Auto-opens enhanced report

```bash
python3 scripts/audit-add-vlm.py              # Latest audit
python3 scripts/audit-add-vlm.py run-042      # Specific run
python3 scripts/audit-add-vlm.py --screens "settings-*"
```

**`vlm-audit-screens.py`** - Batch VLM analysis
- Analyzes all screenshots from audit run
- Generates summary reports
- Alternative to audit-add-vlm.py (doesn't modify HTML)

```bash
python3 scripts/vlm-audit-screens.py         # Latest audit
python3 scripts/vlm-audit-screens.py --screens "memos-*"
```

### Visual Analysis

**`analyze-ui.py`** - General-purpose screenshot analyzer
- Feed any screenshot + any prompt
- Not audit-specific, works standalone
- Supports capture mode

```bash
python3 scripts/analyze-ui.py screenshot.png "Your prompt"
python3 scripts/analyze-ui.py --capture "Check spacing"
```

**`setup-vlm-analysis.sh`** - VLM service setup
- One-time setup for VLM service
- Installs from ~/dev/agentloop if needed
- Starts service with health check

```bash
./scripts/setup-vlm-analysis.sh
```

### Code Fixes

**`fix-light-mode.py`** - Automated light mode fixes
- Replaces hardcoded colors with semantic tokens
- Maps opacity values to design system tokens
- Dry-run mode to preview changes

```bash
python3 scripts/fix-light-mode.py --dry-run  # Preview
python3 scripts/fix-light-mode.py            # Apply
```

**`sync-xcode-files.py`** - Xcode project sync
- Adds missing Swift files to Xcode project
- Preserves folder structure
- Creates backup before changes

```bash
./scripts/sync-xcode-files.py --check  # Check only
./scripts/sync-xcode-files.py --diff   # Show diff
./scripts/sync-xcode-files.py          # Apply
```

## Workflows

### Full Light Mode Audit

```bash
# 1. Fix colors automatically
python3 scripts/fix-light-mode.py

# 2. Build and run audit
./scripts/run.sh --build
Talkie.app/Contents/MacOS/Talkie --debug=audit

# 3. Add visual analysis
python3 scripts/audit-add-vlm.py

# 4. Review report (opens automatically)
open ~/Desktop/talkie-audit/run-XXX/report-with-vlm.html
```

### Quick Visual Check

```bash
# Capture and analyze any screen
python3 scripts/analyze-ui.py --capture "Check this screen"
```

### Settings-Only Audit

```bash
# 1. Run audit (captures all screens)
Talkie.app/Contents/MacOS/Talkie --debug=audit

# 2. Analyze only settings screens
python3 scripts/audit-add-vlm.py --screens "settings-*"
```

## Dependencies

- **Python 3.x** with `requests` module
- **VLM service** for visual analysis (auto-setup via setup-vlm-analysis.sh)
- **Xcode** for building Talkie

## Documentation

- [VLM-ANALYSIS.md](./VLM-ANALYSIS.md) - Complete VLM workflow guide
- Individual script `--help` for detailed options
