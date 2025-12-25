#!/usr/bin/env python3
"""
Add VLM visual analysis to an existing design audit report.

This script runs as a separate async step after the design audit completes.
It analyzes screenshots and injects VLM feedback into the HTML report.

Workflow:
1. Run design audit: Talkie --debug=audit
2. Run VLM analysis: python3 scripts/audit-add-vlm.py [audit-dir]
3. Open updated report: open ~/Desktop/talkie-audit/run-XXX/report-with-vlm.html

Usage:
    # Add VLM to latest audit
    python3 scripts/audit-add-vlm.py

    # Add VLM to specific audit
    python3 scripts/audit-add-vlm.py ~/Desktop/talkie-audit/run-042

    # Use custom prompt
    python3 scripts/audit-add-vlm.py --prompt "Focus on accessibility issues"

    # Specific screens only
    python3 scripts/audit-add-vlm.py --screens "settings-*"
"""

import sys
import json
from pathlib import Path
from typing import List, Optional, Dict
import re

# Import analyze_ui functions
sys.path.insert(0, str(Path(__file__).parent))
try:
    from analyze_ui import (
        analyze_image_with_vlm,
        check_vlm_health,
        parse_json_from_response,
        DEFAULT_PROMPT
    )
except ImportError:
    print("Error: analyze_ui.py not found in scripts/")
    sys.exit(1)

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

def analyze_with_vlm(screenshots: List[Path], prompt: str) -> Dict[str, dict]:
    """Run VLM analysis on screenshots, return results keyed by filename."""
    results = {}
    total = len(screenshots)

    print(f"\n🔍 Analyzing {total} screenshots with VLM...")
    print(f"📝 Prompt: {prompt[:80]}...\n" if len(prompt) > 80 else f"📝 Prompt: {prompt}\n")

    for i, screenshot in enumerate(screenshots, 1):
        filename = screenshot.stem
        print(f"[{i}/{total}] {filename}")

        result = analyze_image_with_vlm(screenshot, prompt)

        if result["success"]:
            parsed = parse_json_from_response(result["analysis"])
            results[filename] = {
                "success": True,
                "analysis": result["analysis"],
                "parsed": parsed,
                "screenshot": screenshot.name
            }

            if parsed and "issues" in parsed:
                issue_count = len(parsed["issues"])
                print(f"   {'⚠️ ' if issue_count > 0 else '✅'} {issue_count} issue(s)")
            else:
                print(f"   ✅ Complete")
        else:
            results[filename] = {
                "success": False,
                "error": result["error"],
                "screenshot": screenshot.name
            }
            print(f"   ❌ Failed: {result['error']}")

    return results

def inject_vlm_into_html(html_path: Path, vlm_results: Dict[str, dict], output_path: Path) -> bool:
    """Inject VLM analysis into existing HTML report."""
    if not html_path.exists():
        print(f"❌ HTML report not found: {html_path}")
        return False

    html = html_path.read_text()

    # Add VLM CSS styles
    vlm_css = """
    <style>
        .vlm-section {
            margin-top: 30px;
            padding: 20px;
            background: #f8f9fa;
            border-radius: 8px;
            border-left: 4px solid #6366f1;
        }
        .vlm-header {
            font-size: 18px;
            font-weight: 600;
            color: #1e293b;
            margin-bottom: 15px;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .vlm-badge {
            background: #6366f1;
            color: white;
            padding: 4px 10px;
            border-radius: 4px;
            font-size: 11px;
            font-weight: 700;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        .vlm-issue {
            background: white;
            padding: 15px;
            margin-bottom: 12px;
            border-radius: 6px;
            border-left: 3px solid #e5e7eb;
        }
        .vlm-issue.severity-high {
            border-left-color: #ef4444;
        }
        .vlm-issue.severity-medium {
            border-left-color: #f59e0b;
        }
        .vlm-issue.severity-low {
            border-left-color: #3b82f6;
        }
        .vlm-issue-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            margin-bottom: 8px;
        }
        .vlm-issue-location {
            font-weight: 600;
            color: #1e293b;
        }
        .vlm-issue-severity {
            font-size: 11px;
            padding: 3px 8px;
            border-radius: 3px;
            font-weight: 600;
            text-transform: uppercase;
        }
        .severity-high {
            background: #fee2e2;
            color: #991b1b;
        }
        .severity-medium {
            background: #fef3c7;
            color: #92400e;
        }
        .severity-low {
            background: #dbeafe;
            color: #1e40af;
        }
        .vlm-issue-description {
            color: #64748b;
            font-size: 14px;
            margin-bottom: 10px;
        }
        .vlm-issue-fix {
            background: #f1f5f9;
            padding: 10px;
            border-radius: 4px;
            font-size: 13px;
            color: #475569;
            font-family: 'Monaco', 'Menlo', monospace;
        }
        .vlm-no-issues {
            color: #059669;
            font-weight: 500;
            display: flex;
            align-items: center;
            gap: 6px;
        }
    </style>
    """

    # Insert CSS before </head>
    html = html.replace("</head>", vlm_css + "\n</head>")

    # For each screenshot section in HTML, add VLM analysis
    for filename, vlm_data in vlm_results.items():
        if not vlm_data["success"]:
            continue

        parsed = vlm_data.get("parsed")
        if not parsed or "issues" not in parsed:
            continue

        issues = parsed["issues"]

        # Count issues by severity
        high_count = sum(1 for i in issues if i.get("severity", "").lower() == "high")
        medium_count = sum(1 for i in issues if i.get("severity", "").lower() == "medium")
        low_count = sum(1 for i in issues if i.get("severity", "").lower() == "low")

        # Build VLM section HTML (matching compiler output structure)
        vlm_html = f"""
            <div class="dossier-issues" style="margin-bottom: 20px;">
                <h3>Visual Analysis</h3>
                <div class="compiler-output">
                    <div class="compiler-summary">
                        <span class="error-count" style="background: #fee2e2; color: #991b1b;">{high_count} high severity</span>
                        <span class="warning-count" style="background: #fef3c7; color: #92400e;">{medium_count} medium</span>
                        <span style="background: #dbeafe; color: #1e40af; padding: 4px 12px; border-radius: 4px; font-size: 12px; font-weight: 600;">{low_count} low</span>
                    </div>
"""

        if issues:
            for issue in issues:
                location = issue.get("location", "Unknown location")
                description = issue.get("issue", "No description")
                severity = issue.get("severity", "Unknown").lower()
                suggestion = issue.get("suggestion", "")

                severity_color = {
                    "high": "#991b1b",
                    "medium": "#92400e",
                    "low": "#1e40af"
                }.get(severity, "#6b7280")

                severity_bg = {
                    "high": "#fee2e2",
                    "medium": "#fef3c7",
                    "low": "#dbeafe"
                }.get(severity, "#f3f4f6")

                vlm_html += f"""
                    <div class="issue-category">
                        <div class="category-header">
                            <span class="category-code" style="background: {severity_bg}; color: {severity_color};">VLM-{severity.upper()}</span>
                            <span class="category-title">{location}</span>
                        </div>
                        <div class="category-issues">
                            <div class="compiler-line">
                                <code class="line-pattern">{description}</code>
                                {f'<span class="line-fix">→ {suggestion}</span>' if suggestion else ''}
                            </div>
                        </div>
                    </div>
"""
        else:
            vlm_html += """
                    <div style="padding: 20px; text-align: center; color: #059669; font-weight: 500;">
                        ✅ No visual issues detected
                    </div>
"""

        vlm_html += """
                </div>
            </div>
"""

        # Find the dossier for this screen and inject VLM section BEFORE compiler output
        dossier_pattern = f'<div class="dossier" id="dossier-{filename}">'
        dossier_match = re.search(re.escape(dossier_pattern), html)

        if dossier_match:
            # Find the first occurrence of <div class="dossier-issues"> after this dossier
            search_start = dossier_match.end()
            issues_pattern = '<div class="dossier-issues">'
            issues_pos = html.find(issues_pattern, search_start)

            if issues_pos > 0:
                # Insert VLM section before the compiler output section
                html = html[:issues_pos] + vlm_html + html[issues_pos:]

    # Update title
    html = html.replace("<title>Design Audit Report</title>", "<title>Design Audit Report (with VLM)</title>")

    # Save updated HTML
    output_path.write_text(html)
    return True

def generate_vlm_summary(vlm_results: Dict[str, dict], output_path: Path):
    """Generate a VLM-only summary report."""
    total = len(vlm_results)
    successful = sum(1 for r in vlm_results.values() if r["success"])
    total_issues = 0
    high_count = 0
    medium_count = 0
    low_count = 0

    summary = "="*80 + "\n"
    summary += "VLM Visual Analysis Summary\n"
    summary += "="*80 + "\n\n"

    summary += f"Screens analyzed: {total}\n"
    summary += f"Successful analyses: {successful}\n\n"

    for filename, data in vlm_results.items():
        if not data["success"]:
            continue

        parsed = data.get("parsed")
        if not parsed or "issues" not in parsed:
            continue

        issues = parsed["issues"]
        if not issues:
            continue

        total_issues += len(issues)

        for issue in issues:
            severity = issue.get("severity", "").lower()
            if "high" in severity:
                high_count += 1
            elif "medium" in severity:
                medium_count += 1
            elif "low" in severity:
                low_count += 1

    summary += f"Total issues found: {total_issues}\n"
    summary += f"  - High severity: {high_count}\n"
    summary += f"  - Medium severity: {medium_count}\n"
    summary += f"  - Low severity: {low_count}\n"
    summary += "\n" + "-"*80 + "\n\n"

    # List issues by screen
    for filename, data in vlm_results.items():
        if not data["success"]:
            continue

        parsed = data.get("parsed")
        if not parsed or "issues" not in parsed:
            continue

        issues = parsed["issues"]
        if not issues:
            continue

        summary += f"📸 {filename}\n"
        for i, issue in enumerate(issues, 1):
            severity = issue.get("severity", "Unknown")
            location = issue.get("location", "Unknown")
            description = issue.get("issue", "No description")
            summary += f"   {i}. [{severity}] {location}\n"
            summary += f"      {description}\n"
        summary += "\n"

    summary += "="*80 + "\n"
    output_path.write_text(summary)

def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Add VLM visual analysis to existing design audit",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument("audit_dir", nargs="?", type=Path, help="Audit run directory (default: latest)")
    parser.add_argument("--prompt", help="Custom VLM analysis prompt (default: light mode check)")
    parser.add_argument("--screens", help="Screen patterns to analyze (comma-separated, e.g. 'settings-*')")

    args = parser.parse_args()

    # Check VLM health
    if not check_vlm_health():
        print("❌ VLM service is not running!")
        print("\nStart it with:")
        print("  ./scripts/setup-vlm-analysis.sh")
        sys.exit(1)

    # Find audit directory
    audit_dir = args.audit_dir or find_latest_audit_run()
    if not audit_dir or not audit_dir.exists():
        print("❌ No audit directory found!")
        print("\nRun a design audit first:")
        print("  Talkie.app/Contents/MacOS/Talkie --debug=audit")
        sys.exit(1)

    print(f"📁 Audit run: {audit_dir.name}")

    # Get screenshots
    if args.screens:
        patterns = args.screens.split(",")
        screenshots = []
        for p in patterns:
            screenshots.extend(get_screenshots(audit_dir, p.strip() + (".png" if not p.endswith(".png") else "")))
    else:
        screenshots = get_screenshots(audit_dir)

    if not screenshots:
        print(f"❌ No screenshots found in {audit_dir / 'screenshots'}")
        sys.exit(1)

    print(f"📸 Found {len(screenshots)} screenshot(s)")

    # Run VLM analysis
    prompt = args.prompt or DEFAULT_PROMPT
    vlm_results = analyze_with_vlm(screenshots, prompt)

    # Inject into HTML report
    html_path = audit_dir / "report.html"
    output_path = audit_dir / "report-with-vlm.html"

    if html_path.exists():
        print(f"\n📄 Injecting VLM analysis into HTML report...")
        if inject_vlm_into_html(html_path, vlm_results, output_path):
            print(f"✅ Updated report: {output_path}")
        else:
            print(f"⚠️  Could not update HTML report")
    else:
        print(f"⚠️  Original HTML report not found: {html_path}")

    # Generate VLM summary
    summary_path = audit_dir / "vlm-summary.txt"
    generate_vlm_summary(vlm_results, summary_path)
    print(f"✅ VLM summary: {summary_path}")

    # Save JSON
    json_path = audit_dir / "vlm-results.json"
    json_path.write_text(json.dumps({
        "audit_dir": str(audit_dir),
        "prompt": prompt,
        "results": vlm_results
    }, indent=2, default=str))
    print(f"✅ VLM JSON: {json_path}")

    # Open updated report
    import subprocess
    if output_path.exists():
        subprocess.run(["open", str(output_path)])

if __name__ == "__main__":
    main()
