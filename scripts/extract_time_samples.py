#!/usr/bin/env python3
"""
extract_time_samples.py - Extract time-sample data from Instruments .trace files

Exports the time-sample table from a Time Profiler trace to XML format
for analysis by top_hotspots.py.

Usage:
    extract_time_samples.py --trace /tmp/App.trace --output /tmp/samples.xml
"""

import argparse
import subprocess
import sys
import os
from pathlib import Path


def list_tables(trace_path: str) -> list[str]:
    """List available tables in the trace file."""
    result = subprocess.run(
        ["xcrun", "xctrace", "export", "--input", trace_path, "--toc"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"Error listing tables: {result.stderr}", file=sys.stderr)
        return []

    tables = []
    for line in result.stdout.splitlines():
        # Look for table entries - they're usually indented with schema info
        line = line.strip()
        if line and not line.startswith("<?") and not line.startswith("<"):
            tables.append(line)
    return tables


def find_time_sample_schema(trace_path: str) -> str | None:
    """Find the time-sample schema in the trace."""
    result = subprocess.run(
        ["xcrun", "xctrace", "export", "--input", trace_path, "--toc"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return None

    # Parse the TOC output to find time-sample related schemas
    # Common names: time-sample, time-profile, cpu-profile
    for line in result.stdout.splitlines():
        lower = line.lower()
        if "time-sample" in lower or "time-profile" in lower:
            # Extract schema name from the line
            # Format varies, but usually contains the schema name
            parts = line.strip().split()
            for part in parts:
                if "time" in part.lower() and "sample" in part.lower():
                    return part.strip('",<>')
                if "time" in part.lower() and "profile" in part.lower():
                    return part.strip('",<>')

    return None


def export_time_samples(trace_path: str, output_path: str, schema: str | None = None) -> bool:
    """Export time samples from trace to XML."""

    # If no schema specified, try common ones
    schemas_to_try = []
    if schema:
        schemas_to_try.append(schema)
    else:
        # Try common Time Profiler schemas
        schemas_to_try = [
            "time-sample",
            "time-profile",
            "cpu-profile",
        ]

    for schema_name in schemas_to_try:
        print(f"Trying schema: {schema_name}")

        # First try with xpath for the specific table
        result = subprocess.run(
            [
                "xcrun", "xctrace", "export",
                "--input", trace_path,
                "--xpath", f'/trace-toc/run/data/table[@schema="{schema_name}"]',
                "--output", output_path,
            ],
            capture_output=True,
            text=True,
        )

        if result.returncode == 0 and os.path.exists(output_path):
            size = os.path.getsize(output_path)
            if size > 100:  # Sanity check - should have some content
                print(f"Successfully exported using schema: {schema_name}")
                return True

    # If specific schemas didn't work, try exporting all data
    print("Trying full export...")
    result = subprocess.run(
        [
            "xcrun", "xctrace", "export",
            "--input", trace_path,
            "--output", output_path,
        ],
        capture_output=True,
        text=True,
    )

    if result.returncode == 0 and os.path.exists(output_path):
        print("Exported full trace data")
        return True

    print(f"Export failed: {result.stderr}", file=sys.stderr)
    return False


def main():
    parser = argparse.ArgumentParser(
        description="Extract time-sample data from Instruments .trace files"
    )
    parser.add_argument(
        "--trace", "-t",
        required=True,
        help="Path to .trace file"
    )
    parser.add_argument(
        "--output", "-o",
        required=True,
        help="Output XML file path"
    )
    parser.add_argument(
        "--schema", "-s",
        help="Specific schema to export (default: auto-detect)"
    )
    parser.add_argument(
        "--list-tables",
        action="store_true",
        help="List available tables in the trace and exit"
    )

    args = parser.parse_args()

    trace_path = args.trace
    if not os.path.exists(trace_path):
        print(f"Error: Trace file not found: {trace_path}", file=sys.stderr)
        sys.exit(1)

    if args.list_tables:
        print("Trace table of contents:")
        result = subprocess.run(
            ["xcrun", "xctrace", "export", "--input", trace_path, "--toc"],
            capture_output=True,
            text=True,
        )
        print(result.stdout)
        if result.stderr:
            print(result.stderr, file=sys.stderr)
        sys.exit(0)

    # Ensure output directory exists
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"Extracting time samples from: {trace_path}")
    print(f"Output: {args.output}")
    print()

    if export_time_samples(trace_path, str(output_path), args.schema):
        size = output_path.stat().st_size
        print(f"\nSuccess! Wrote {size:,} bytes to {args.output}")
        print(f"\nNext: scripts/top_hotspots.py --samples '{args.output}' --binary <path> --load-address <addr>")
    else:
        print("\nFailed to export time samples", file=sys.stderr)
        print("\nTry listing available tables with: --list-tables", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
