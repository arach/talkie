# Settings UI Storyboards

Iteration tracking for Settings UI redesign.

## Versions

### v1-baseline (Dec 22, 2024)
**Status:** Captured
**Screenshots:** 13 pages
**Issues identified:**
- Font inconsistencies (Theme.current vs SettingsManager.shared vs hardcoded)
- Color system fragmentation (midnightX vs Theme.current)
- Hardcoded spacing (numbers instead of Spacing enum)
- Hardcoded opacity values

**Files:**
- `settings-v1-baseline/` - Individual page screenshots
- `settings-v1-baseline/storyboard-all-pages.png` - Combined storyboard

---

## How to Generate New Iterations

```bash
# Individual screenshots
Talkie.app --debug=settings-screenshots ~/path/to/output-dir

# Combined storyboard
Talkie.app --debug=settings-storyboard ~/path/to/output.png
```

## Comparison Workflow

1. Capture baseline before changes
2. Make styling updates
3. Capture new version
4. Compare side-by-side using Preview or ImageMagick:
   ```bash
   # Side-by-side comparison
   magick montage v1-baseline/settings-00-appearance.png v2/settings-00-appearance.png -tile 2x1 -geometry +10+10 compare-appearance.png
   ```
