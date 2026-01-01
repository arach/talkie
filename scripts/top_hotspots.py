#!/usr/bin/env python3
"""
top_hotspots.py - Symbolicate and rank hotspots from Time Profiler samples

Parses the XML output from extract_time_samples.py, symbolicates addresses
using atos, and ranks functions by sample count.

Usage:
    top_hotspots.py --samples /tmp/samples.xml --binary /path/to/App --load-address 0x100000000 --top 30
"""

import argparse
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Sample:
    """A single time sample with backtrace addresses."""
    addresses: list[int]
    weight: int = 1


def parse_samples_xml(xml_path: str) -> list[Sample]:
    """Parse time samples from exported XML."""
    samples = []

    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
    except ET.ParseError as e:
        print(f"Error parsing XML: {e}", file=sys.stderr)
        return samples

    # Look for sample/backtrace data in various possible formats
    # xctrace export format can vary

    # Try to find rows with backtrace data
    for row in root.iter("row"):
        addresses = []
        weight = 1

        for child in row:
            # Look for address/backtrace fields
            tag = child.tag.lower()
            text = child.text or ""

            if "backtrace" in tag or "stack" in tag or "address" in tag:
                # Parse addresses from the field
                # Could be hex addresses separated by spaces/commas
                for match in re.findall(r"0x[0-9a-fA-F]+", text):
                    try:
                        addresses.append(int(match, 16))
                    except ValueError:
                        pass

            if "weight" in tag or "count" in tag or "sample" in tag:
                try:
                    weight = int(text)
                except ValueError:
                    pass

        if addresses:
            samples.append(Sample(addresses=addresses, weight=weight))

    # Also try looking for frame elements directly
    if not samples:
        for frame in root.iter("frame"):
            addr_text = frame.get("addr") or frame.get("address") or frame.text or ""
            for match in re.findall(r"0x[0-9a-fA-F]+", addr_text):
                try:
                    samples.append(Sample(addresses=[int(match, 16)], weight=1))
                except ValueError:
                    pass

    return samples


def symbolicate_addresses(
    addresses: set[int],
    binary_path: str,
    load_address: int
) -> dict[int, str]:
    """Symbolicate addresses using atos."""
    if not addresses:
        return {}

    # Filter addresses to those likely in our binary
    # (within reasonable range of load address)
    MAX_OFFSET = 0x10000000  # 256MB - reasonable for most apps
    filtered = [
        addr for addr in addresses
        if load_address <= addr < load_address + MAX_OFFSET
    ]

    if not filtered:
        print(f"Warning: No addresses in range of load address {hex(load_address)}", file=sys.stderr)
        return {}

    # Run atos in batch mode
    addr_args = [hex(a) for a in filtered]

    result = subprocess.run(
        ["atos", "-o", binary_path, "-l", hex(load_address)] + addr_args,
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        print(f"atos error: {result.stderr}", file=sys.stderr)
        return {}

    # Parse atos output - one line per address
    symbols = {}
    lines = result.stdout.strip().split("\n")
    for addr, line in zip(filtered, lines):
        # Clean up the symbol name
        symbol = line.strip()
        if symbol and symbol != hex(addr):
            symbols[addr] = symbol
        else:
            symbols[addr] = f"<unknown {hex(addr)}>"

    return symbols


def extract_function_name(symbol: str) -> str:
    """Extract just the function name from a full symbol."""
    # Handle Swift-style: "FunctionName (in Module) + offset"
    # Handle C-style: "function_name (in library) (file.c:123)"

    # Remove file/line info in parentheses at the end
    symbol = re.sub(r"\s+\([^)]+:\d+\)$", "", symbol)

    # Remove offset
    symbol = re.sub(r"\s+\+\s+\d+$", "", symbol)

    # Remove module info like "(in ModuleName)"
    symbol = re.sub(r"\s+\(in [^)]+\)$", "", symbol)

    return symbol.strip()


def analyze_hotspots(
    samples: list[Sample],
    symbols: dict[int, str],
    binary_name: str,
    top_n: int = 30
) -> list[tuple[str, int]]:
    """Analyze samples and return top hotspots."""
    function_counts: Counter[str] = Counter()

    for sample in samples:
        for addr in sample.addresses:
            if addr in symbols:
                symbol = symbols[addr]
                # Only count our app's symbols (not system frameworks)
                if binary_name.lower() in symbol.lower() or "(in " not in symbol:
                    func_name = extract_function_name(symbol)
                    function_counts[func_name] += sample.weight

    return function_counts.most_common(top_n)


def main():
    parser = argparse.ArgumentParser(
        description="Symbolicate and rank hotspots from Time Profiler samples"
    )
    parser.add_argument(
        "--samples", "-s",
        required=True,
        help="Path to samples XML file from extract_time_samples.py"
    )
    parser.add_argument(
        "--binary", "-b",
        required=True,
        help="Path to binary for symbolication"
    )
    parser.add_argument(
        "--load-address", "-l",
        required=True,
        help="Runtime load address of __TEXT segment (from vmmap)"
    )
    parser.add_argument(
        "--top", "-t",
        type=int,
        default=30,
        help="Number of top hotspots to show (default: 30)"
    )
    parser.add_argument(
        "--raw",
        action="store_true",
        help="Show raw addresses without symbolication"
    )

    args = parser.parse_args()

    # Parse load address
    try:
        if args.load_address.startswith("0x"):
            load_address = int(args.load_address, 16)
        else:
            load_address = int(args.load_address)
    except ValueError:
        print(f"Error: Invalid load address: {args.load_address}", file=sys.stderr)
        sys.exit(1)

    # Verify paths
    if not Path(args.samples).exists():
        print(f"Error: Samples file not found: {args.samples}", file=sys.stderr)
        sys.exit(1)

    if not Path(args.binary).exists():
        print(f"Error: Binary not found: {args.binary}", file=sys.stderr)
        sys.exit(1)

    binary_name = Path(args.binary).stem

    print(f"Parsing samples from: {args.samples}")
    samples = parse_samples_xml(args.samples)

    if not samples:
        print("No samples found in file. The XML format may not be supported.")
        print("\nTry opening the .trace in Instruments and manually exporting.")
        sys.exit(1)

    print(f"Found {len(samples)} samples")

    # Collect all unique addresses
    all_addresses: set[int] = set()
    for sample in samples:
        all_addresses.update(sample.addresses)

    print(f"Found {len(all_addresses)} unique addresses")

    if args.raw:
        # Just show raw address counts
        addr_counts: Counter[int] = Counter()
        for sample in samples:
            for addr in sample.addresses:
                addr_counts[addr] += sample.weight

        print(f"\nTop {args.top} addresses by sample count:")
        print("-" * 60)
        for addr, count in addr_counts.most_common(args.top):
            print(f"  {hex(addr):20}  {count:>6} samples")
        return

    print(f"\nSymbolicating with binary: {args.binary}")
    print(f"Load address: {hex(load_address)}")

    symbols = symbolicate_addresses(all_addresses, args.binary, load_address)
    print(f"Symbolicated {len(symbols)} addresses")

    hotspots = analyze_hotspots(samples, symbols, binary_name, args.top)

    if not hotspots:
        print("\nNo hotspots found in your app's code.")
        print("This could mean:")
        print("  - The load address is wrong (check vmmap output)")
        print("  - The binary doesn't match the trace")
        print("  - Most time was spent in system frameworks")
        sys.exit(1)

    print(f"\nTop {len(hotspots)} hotspots in {binary_name}:")
    print("=" * 80)

    total_samples = sum(count for _, count in hotspots)
    for i, (func, count) in enumerate(hotspots, 1):
        pct = (count / total_samples) * 100 if total_samples > 0 else 0
        bar = "█" * int(pct / 2)
        print(f"{i:3}. {count:>6} ({pct:5.1f}%) {bar}")
        print(f"     {func}")
        print()


if __name__ == "__main__":
    main()
