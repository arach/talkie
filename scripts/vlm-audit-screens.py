#!/usr/bin/env python3
"""
Add VLM visual analysis to existing design audit screenshots.

This script processes screenshots from the design audit tool
(~/Desktop/talkie-audit/run-XXX/screenshots/) and adds visual analysis
from a local VLM model.

Usage:
    # Analyze latest audit run
    python3 scripts/vlm-audit-screens.py

    # Analyze specific audit run
    python3 scripts/vlm-audit-screens.py ~/Desktop/talkie-audit/run-042

    # Use custom analysis prompt
    python3 scripts/vlm-audit-screens.py --prompt "Check for accessibility issues"

    # Analyze specific screens only
    python3 scripts/vlm-audit-screens.py --screens "settings-*,memos-*"
"""

import sys
from pathlib import Path
import json
from typing import List, Optional
import subprocess

# Import analyze_ui functions
sys.path.insert(0, str(Path(__file__).parent))
from analyze_ui import (
    analyze_image_with_vlm,
    check_vlm_health,
    parse_json_from_response,
    DEFAULT_PROMPT
)

AUDIT_BASE = Path.home() / "Desktop" / "talkie-audit"

def find_latest_audit_run() -> Optional[Path]:
    """Find the latest audit run directory."""
    if not AUDIT_BASE.exists():
        return None

    runs = sorted(AUDIT_BASE.glob("run-*"), reverse=True)
    return runs[0] if runs else None

def get_screenshots(audit_dir: Path, pattern: str = "*.png") -> List[Path]:
    """Get all screenshots from audit directory."""
    screenshots_dir = audit_dir / "screenshots"
    if not screenshots_dir.exists():
        return []

    return sorted(screenshots_dir.glob(pattern))

def analyze_screenshots(screenshots: List[Path], prompt: str, output_dir: Path):
    """Analyze multiple screenshots with VLM."""
    results = []
    total = len(screenshots)

    print(f"\n🔍 Analyzing {total} screenshots with VLM...")
    print(f"📝 Using prompt: {prompt[:100]}...\n" if len(prompt) > 100 else f"📝 Using prompt: {prompt}\n")

    for i, screenshot in enumerate(screenshots, 1):
        print(f"[{i}/{total}] {screenshot.name}")

        # Analyze with VLM
        result = analyze_image_with_vlm(screenshot, prompt)

        if result["success"]:
            analysis = result["analysis"]
            parsed = parse_json_from_response(analysis)

            # Save individual analysis
            analysis_file = output_dir / f"{screenshot.stem}.vlm-analysis.txt"
            analysis_file.write_text(analysis)

            # Collect for summary
            results.append({
                "screenshot": screenshot.name,
                "analysis": analysis,
                "parsed": parsed,
                "success": True
            })

            # Quick summary
            if parsed and "issues" in parsed:
                issue_count = len(parsed["issues"])
                if issue_count > 0:
                    print(f"   ⚠️  Found {issue_count} issue(s)")
                else:
                    print(f"   ✅ No issues")
            else:
                print(f"   ✅ Analysis complete")
        else:
            print(f"   ❌ Failed: {result['error']}")
            results.append({
                "screenshot": screenshot.name,
                "error": result["error"],
                "success": False
            })

        print()

    return results

def generate_summary_report(results: List[dict], output_path: Path):
    """Generate a summary report of all VLM analyses."""
    report = "="*80 + "\n"
    report += "VLM Visual Analysis Summary\n"
    report += "="*80 + "\n\n"

    total_issues = 0
    screens_with_issues = 0
    high_severity = 0
    medium_severity = 0
    low_severity = 0

    for result in results:
        if not result["success"]:
            continue

        parsed = result.get("parsed")
        if not parsed or "issues" not in parsed:
            continue

        issues = parsed["issues"]
        if not issues:
            continue

        screens_with_issues += 1
        total_issues += len(issues)

        # Count severity
        for issue in issues:
            severity = issue.get("severity", "").lower()
            if "high" in severity:
                high_severity += 1
            elif "medium" in severity:
                medium_severity += 1
            elif "low" in severity:
                low_severity += 1

    # Summary stats
    report += f"Screens analyzed: {len(results)}\n"
    report += f"Screens with issues: {screens_with_issues}\n"
    report += f"Total issues: {total_issues}\n"
    report += f"  - High severity: {high_severity}\n"
    report += f"  - Medium severity: {medium_severity}\n"
    report += f"  - Low severity: {low_severity}\n"
    report += "\n" + "-"*80 + "\n\n"

    # Detailed issues by screen
    report += "Issues by Screen:\n\n"

    for result in results:
        if not result["success"]:
            report += f"❌ {result['screenshot']}: Analysis failed\n"
            continue

        parsed = result.get("parsed")
        if not parsed or "issues" not in parsed:
            report += f"✅ {result['screenshot']}: No structured issues found\n"
            continue

        issues = parsed["issues"]
        if not issues:
            report += f"✅ {result['screenshot']}: No issues\n"
            continue

        report += f"⚠️  {result['screenshot']}: {len(issues)} issue(s)\n"
        for i, issue in enumerate(issues, 1):
            location = issue.get("location", "Unknown")
            severity = issue.get("severity", "Unknown")
            description = issue.get("issue", "No description")
            report += f"   {i}. [{severity}] {location}\n"
            report += f"      {description}\n"
        report += "\n"

    report += "="*80 + "\n"

    # Save report
    output_path.write_text(report)
    return report

def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Add VLM visual analysis to design audit screenshots",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument("audit_dir", nargs="?", type=Path, help="Path to audit run directory (default: latest)")
    parser.add_argument("--prompt", help=f"Custom analysis prompt (default: light mode check)")
    parser.add_argument("--screens", help="Screen name patterns to analyze (comma-separated, e.g. 'settings-*,memos-*')")
    parser.add_argument("--output-dir", type=Path, help="Output directory for analyses (default: same as screenshots)")

    args = parser.parse_args()

    # Check VLM health
    if not check_vlm_health():
        print("❌ VLM service is not running!")
        print("\nStart it with:")
        print("  cd ~/dev/agentloop")
        print("  bun run vlm:server")
        print("\nOr run the setup script:")
        print("  ./scripts/setup-vlm-analysis.sh")
        sys.exit(1)

    # Find audit directory
    if args.audit_dir:
        audit_dir = args.audit_dir
    else:
        audit_dir = find_latest_audit_run()

    if not audit_dir or not audit_dir.exists():
        print("❌ No audit directory found!")
        print(f"\nLooked in: {AUDIT_BASE}")
        print("\nRun a design audit first:")
        print("  Talkie.app/Contents/MacOS/Talkie --debug=audit")
        sys.exit(1)

    print(f"📁 Using audit run: {audit_dir.name}")

    # Get screenshots
    pattern = "*.png"
    if args.screens:
        # User can specify patterns like "settings-*" or specific files
        patterns = args.screens.split(",")
        screenshots = []
        for p in patterns:
            screenshots.extend(get_screenshots(audit_dir, p.strip() + ".png" if not p.endswith(".png") else p.strip()))
    else:
        screenshots = get_screenshots(audit_dir, pattern)

    if not screenshots:
        print(f"❌ No screenshots found in {audit_dir / 'screenshots'}")
        sys.exit(1)

    print(f"📸 Found {len(screenshots)} screenshot(s)")

    # Determine output directory
    output_dir = args.output_dir or (audit_dir / "vlm-analysis")
    output_dir.mkdir(parents=True, exist_ok=True)

    # Determine prompt
    prompt = args.prompt or DEFAULT_PROMPT

    # Analyze
    results = analyze_screenshots(screenshots, prompt, output_dir)

    # Generate summary
    summary_path = output_dir / "summary.txt"
    summary = generate_summary_report(results, summary_path)
    print(summary)

    # Save detailed JSON
    json_path = output_dir / "results.json"
    json_path.write_text(json.dumps({
        "audit_dir": str(audit_dir),
        "prompt": prompt,
        "results": results
    }, indent=2))

    print(f"\n✅ Analysis complete!")
    print(f"📝 Summary: {summary_path}")
    print(f"💾 Detailed results: {json_path}")
    print(f"📁 Individual analyses: {output_dir}/")

if __name__ == "__main__":
    main()
