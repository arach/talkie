#!/usr/bin/env python3
"""
General-purpose UI screenshot analysis using local VLM.
Feed any screenshot and prompt for visual analysis.

Prerequisites:
1. Install and start the VLM service from ~/dev/agentloop:
   cd ~/dev/agentloop
   bun run vlm:install -- --yes
   bun run vlm:server

Usage:
    # Analyze with custom prompt
    python3 scripts/analyze-ui.py path/to/screenshot.png "Describe the layout"

    # Analyze with default light mode prompt
    python3 scripts/analyze-ui.py path/to/screenshot.png

    # Capture and analyze with custom prompt
    python3 scripts/analyze-ui.py --capture "Check for accessibility issues"

    # Use a prompt from a file
    python3 scripts/analyze-ui.py screenshot.png --prompt-file prompts/light-mode.txt
"""

import base64
import json
import os
import sys
from pathlib import Path
from typing import Optional
import subprocess

try:
    import requests
except ImportError:
    print("Error: requests module not found. Install with: pip3 install requests")
    sys.exit(1)

# VLM Service Configuration
# Supports both DNS names (talkie-vlm.local) and IP addresses (127.0.0.1)
# Run ./scripts/setup-vlm-dns.sh to configure local DNS
VLM_HOST = os.environ.get("VLM_HOST", "talkie-vlm.local")
VLM_PORT = os.environ.get("VLM_PORT", "12346")
VLM_BASE_URL = os.environ.get("VLM_URL", f"http://{VLM_HOST}:{VLM_PORT}")

VLM_URL = f"{VLM_BASE_URL}/v1/chat/completions"
VLM_HEALTH_URL = f"{VLM_BASE_URL}/health"

DEFAULT_PROMPT = """Analyze this screenshot of a macOS app in light mode and identify any visual issues.

Focus on:
1. Dark backgrounds that should be light in light mode
2. Text that's hard to read due to poor contrast
3. UI elements that don't adapt to light mode properly
4. Inconsistent color usage across sections
5. Status bars, sidebars, or navigation elements with dark backgrounds

For each issue found, provide:
- Location (describe where it appears)
- Issue (what's wrong)
- Severity (High/Medium/Low)
- Suggestion (how to fix it)

Format your response as JSON:
{
  "issues": [
    {
      "location": "...",
      "issue": "...",
      "severity": "...",
      "suggestion": "..."
    }
  ],
  "overall_assessment": "..."
}
"""

def encode_image_to_data_url(image_path: Path) -> str:
    """Encode an image file to a base64 data URL."""
    with open(image_path, "rb") as f:
        image_data = f.read()

    # Detect image format from extension
    ext = image_path.suffix.lower()
    mime_type = {
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".gif": "image/gif",
        ".webp": "image/webp"
    }.get(ext, "image/png")

    b64_data = base64.b64encode(image_data).decode('utf-8')
    return f"data:{mime_type};base64,{b64_data}"

def check_vlm_health() -> bool:
    """Check if VLM service is running."""
    try:
        response = requests.get(VLM_HEALTH_URL, timeout=2)
        return response.status_code == 200
    except requests.exceptions.RequestException:
        return False

def analyze_image_with_vlm(image_path: Path, prompt: str) -> dict:
    """Send an image to VLM for analysis."""
    if not check_vlm_health():
        print("❌ VLM service is not running!")
        print("\nStart it with:")
        print("  cd ~/dev/agentloop")
        print("  bun run vlm:server")
        print("\nOr run the setup script:")
        print("  ./scripts/setup-vlm-analysis.sh")
        sys.exit(1)

    print(f"🔍 Analyzing {image_path.name}...")
    print(f"📝 Prompt: {prompt[:100]}..." if len(prompt) > 100 else f"📝 Prompt: {prompt}")

    # Encode image
    data_url = encode_image_to_data_url(image_path)

    # Prepare request
    payload = {
        "model": "mlx-community/Qwen2-VL-2B-Instruct-4bit",
        "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": prompt
                    },
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": data_url
                        }
                    }
                ]
            }
        ],
        "max_tokens": 1500,
        "temperature": 0.1  # Low temperature for consistent analysis
    }

    # Send request
    try:
        response = requests.post(VLM_URL, json=payload, timeout=90)
        response.raise_for_status()

        result = response.json()
        content = result["choices"][0]["message"]["content"]

        return {
            "success": True,
            "analysis": content,
            "raw_response": result
        }
    except requests.exceptions.RequestException as e:
        error_details = str(e)
        try:
            # Try to extract error details from response body
            if hasattr(e, 'response') and e.response is not None:
                error_json = e.response.json()
                if "error" in error_json:
                    error_details = f"{str(e)} - {error_json['error']}"
        except:
            pass
        return {
            "success": False,
            "error": error_details
        }

def capture_screenshot(output_path: Path) -> bool:
    """Capture a screenshot using macOS screencapture."""
    print(f"📸 Capturing screenshot to {output_path}...")
    print("Click on the window to capture...")

    cmd = ["screencapture", "-w", "-o", str(output_path)]

    try:
        subprocess.run(cmd, check=True)
        return output_path.exists()
    except subprocess.CalledProcessError:
        print("❌ Screenshot capture failed")
        return False

def parse_json_from_response(analysis: str) -> Optional[dict]:
    """Try to extract JSON from the VLM response."""
    # Handle GenerationResult wrapper: GenerationResult(text='...', ...)
    if analysis.startswith("GenerationResult(text="):
        try:
            # Extract the text value from GenerationResult
            start = analysis.find("text='") + 6
            end = analysis.find("', token=")
            if start > 5 and end > start:
                json_str = analysis[start:end]
                # Unescape the string
                json_str = json_str.replace('\\"', '"').replace('\\n', '\n')
                return json.loads(json_str)
        except (ValueError, json.JSONDecodeError):
            pass

    # Look for JSON code block
    if "```json" in analysis:
        start = analysis.find("```json") + 7
        end = analysis.find("```", start)
        if end > start:
            json_str = analysis[start:end].strip()
            try:
                return json.loads(json_str)
            except json.JSONDecodeError:
                pass

    # Try direct JSON parsing
    try:
        return json.loads(analysis)
    except json.JSONDecodeError:
        return None

def format_analysis_report(analysis_text: str, screenshot_name: str, prompt: str) -> str:
    """Format the VLM analysis into a readable report."""
    report = f"\n{'='*80}\n"
    report += f"UI Analysis: {screenshot_name}\n"
    report += f"{'='*80}\n\n"
    report += f"Prompt: {prompt[:200]}...\n" if len(prompt) > 200 else f"Prompt: {prompt}\n"
    report += "-" * 80 + "\n\n"

    # Try to parse as JSON
    parsed = parse_json_from_response(analysis_text)

    if parsed and "issues" in parsed:
        issues = parsed["issues"]
        if issues:
            report += f"Found {len(issues)} issue(s):\n\n"
            for i, issue in enumerate(issues, 1):
                report += f"{i}. {issue.get('location', 'Unknown location')}\n"
                report += f"   Issue: {issue.get('issue', 'No description')}\n"
                report += f"   Severity: {issue.get('severity', 'Unknown')}\n"
                report += f"   Fix: {issue.get('suggestion', 'No suggestion')}\n\n"
        else:
            report += "✅ No issues found!\n\n"

        if "overall_assessment" in parsed:
            report += f"Overall: {parsed['overall_assessment']}\n"
    else:
        # Fallback to raw text
        report += "VLM Analysis:\n"
        report += "-" * 80 + "\n"
        report += analysis_text + "\n"

    report += "\n" + "="*80 + "\n"
    return report

def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Analyze UI screenshots using local VLM",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Analyze screenshot with custom prompt
  %(prog)s screenshot.png "Identify any accessibility issues"

  # Analyze with default light mode prompt
  %(prog)s screenshot.png

  # Capture and analyze
  %(prog)s --capture "Check for inconsistent spacing"

  # Use prompt from file
  %(prog)s screenshot.png --prompt-file prompts/contrast-check.txt
        """
    )

    parser.add_argument("screenshot", nargs="?", type=Path, help="Path to screenshot to analyze")
    parser.add_argument("prompt", nargs="?", help="Analysis prompt (default: light mode check)")
    parser.add_argument("--capture", metavar="PROMPT", help="Capture screenshot then analyze with given prompt")
    parser.add_argument("--prompt-file", type=Path, help="Read prompt from file")
    parser.add_argument("--output", type=Path, help="Output path for captured screenshot (default: screenshots/ui-analysis-<timestamp>.png)")
    parser.add_argument("--save-response", action="store_true", help="Save raw VLM response as JSON")

    args = parser.parse_args()

    # Determine prompt
    if args.prompt_file:
        if not args.prompt_file.exists():
            print(f"❌ Prompt file not found: {args.prompt_file}")
            sys.exit(1)
        prompt = args.prompt_file.read_text()
    elif args.prompt:
        prompt = args.prompt
    elif args.capture:
        prompt = args.capture
    else:
        prompt = DEFAULT_PROMPT

    # Determine screenshot path
    if args.capture:
        # Capture mode
        from datetime import datetime
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        output_path = args.output or Path(f"screenshots/ui-analysis-{timestamp}.png")
        output_path.parent.mkdir(parents=True, exist_ok=True)

        if not capture_screenshot(output_path):
            sys.exit(1)

        screenshot_path = output_path
    else:
        # Analyze existing screenshot
        if not args.screenshot:
            parser.print_help()
            sys.exit(1)

        screenshot_path = args.screenshot
        if not screenshot_path.exists():
            print(f"❌ Screenshot not found: {screenshot_path}")
            sys.exit(1)

    # Analyze
    result = analyze_image_with_vlm(screenshot_path, prompt)

    if not result["success"]:
        print(f"❌ Analysis failed: {result['error']}")
        sys.exit(1)

    # Print report
    report = format_analysis_report(result["analysis"], screenshot_path.name, prompt)
    print(report)

    # Save report
    report_path = screenshot_path.with_suffix(".analysis.txt")
    report_path.write_text(report)
    print(f"📝 Report saved to: {report_path}")

    # Save raw response if requested
    if args.save_response:
        json_path = screenshot_path.with_suffix(".response.json")
        json_path.write_text(json.dumps(result["raw_response"], indent=2))
        print(f"💾 Raw response saved to: {json_path}")

if __name__ == "__main__":
    main()
