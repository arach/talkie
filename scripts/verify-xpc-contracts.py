#!/usr/bin/env python3
"""
XPC Contract Verification Script

Uses Xcode's swift-symbolgraph-extract to get authoritative protocol definitions,
then verifies implementations match across the codebase.

Usage:
    ./scripts/verify-xpc-contracts.py           # Verify contracts
    ./scripts/verify-xpc-contracts.py --rebuild # Rebuild symbolgraphs first
"""

import os
import re
import sys
import json
import hashlib
import subprocess
from pathlib import Path
from typing import Optional

# ANSI colors
RED = "\033[91m"
GREEN = "\033[92m"
YELLOW = "\033[93m"
BLUE = "\033[94m"
CYAN = "\033[96m"
RESET = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[2m"

def get_repo_root() -> Path:
    """Get the repository root directory."""
    script_dir = Path(__file__).parent
    return script_dir.parent

def find_derived_data(project_name: str) -> Optional[Path]:
    """Find DerivedData directory for a project."""
    derived_base = Path.home() / "Library/Developer/Xcode/DerivedData"
    for d in derived_base.iterdir():
        if d.name.startswith(project_name + "-"):
            products = d / "Build/Products/Debug"
            if products.exists():
                return products
    return None

def find_all_derived_data() -> list[Path]:
    """Find all Talkie-related DerivedData directories."""
    derived_base = Path.home() / "Library/Developer/Xcode/DerivedData"
    results = []

    prefixes = ["TalkieSuite-", "Talkie-", "TalkieEngine-", "TalkieLive-"]

    for d in derived_base.iterdir():
        if any(d.name.startswith(p) for p in prefixes):
            products = d / "Build/Products/Debug"
            if products.exists():
                results.append(products)

    return results

def extract_symbolgraph(module_name: str, derived_data_paths: list[Path], output_dir: Path) -> Optional[Path]:
    """Extract symbol graph for a module using Xcode tools.

    Tries multiple DerivedData paths until one succeeds.
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    output_file = output_dir / f"{module_name}.symbols.json"

    # Get SDK path
    sdk_result = subprocess.run(["xcrun", "--show-sdk-path"], capture_output=True, text=True)
    sdk_path = sdk_result.stdout.strip()

    # Build -I flags for all derived data paths
    include_flags = []
    for path in derived_data_paths:
        include_flags.extend(["-I", str(path)])

    cmd = [
        "xcrun", "swift-symbolgraph-extract",
        "-module-name", module_name,
        "-target", "arm64-apple-macosx14.0",
        "-sdk", sdk_path,
        *include_flags,
        "-output-dir", str(output_dir)
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        return None

    return output_file if output_file.exists() else None

def parse_protocol_methods(symbolgraph_path: Path, protocol_name: str) -> list[dict]:
    """Extract method signatures from a protocol in the symbol graph."""
    with open(symbolgraph_path) as f:
        data = json.load(f)

    symbols = data.get('symbols', [])
    methods = []

    for sym in symbols:
        path = sym.get('pathComponents', [])
        if protocol_name in path and sym.get('kind', {}).get('identifier') == 'swift.method':
            name = sym['names']['title']
            # Get full declaration
            decl_frags = sym.get('declarationFragments', [])
            decl = ''.join([f['spelling'] for f in decl_frags])
            methods.append({
                'name': name,
                'declaration': decl,
                'identifier': sym.get('identifier', {}).get('precise', '')
            })

    return sorted(methods, key=lambda m: m['name'])

def find_protocol_usages(repo_root: Path, protocol_name: str) -> dict:
    """Find all usages of a protocol in the codebase."""
    usages = {
        'definitions': [],      # Where protocol is defined
        'conformances': [],     # Types that conform to protocol
        'interface_uses': [],   # NSXPCInterface uses
        'proxy_types': [],      # Variables typed as protocol
    }

    swift_files = list(repo_root.glob("macOS/**/*.swift"))

    for file in swift_files:
        try:
            content = file.read_text()
            rel_path = file.relative_to(repo_root)

            # Find protocol definition
            if re.search(rf'protocol\s+{protocol_name}\s*[{{:]', content):
                usages['definitions'].append(str(rel_path))

            # Find conformances (class/struct : Protocol)
            if re.search(rf':\s*.*{protocol_name}', content) and 'protocol ' not in content.split(protocol_name)[0][-50:]:
                for i, line in enumerate(content.split('\n'), 1):
                    if re.search(rf'(class|struct|final class)\s+\w+.*:\s*.*{protocol_name}', line):
                        usages['conformances'].append(f"{rel_path}:{i}")

            # Find NSXPCInterface uses
            for i, line in enumerate(content.split('\n'), 1):
                if f'NSXPCInterface(with: {protocol_name}.self)' in line:
                    usages['interface_uses'].append(f"{rel_path}:{i}")

            # Find proxy variables
            for i, line in enumerate(content.split('\n'), 1):
                if re.search(rf':\s*{protocol_name}\??', line) and 'protocol' not in line:
                    usages['proxy_types'].append(f"{rel_path}:{i}")

        except Exception:
            continue

    return usages

def compute_method_hash(methods: list[dict]) -> str:
    """Compute a hash of method signatures for comparison."""
    sig = "\n".join(m['name'] for m in methods)
    return hashlib.sha256(sig.encode()).hexdigest()[:12]


def extract_methods_from_source(file_path: Path, protocol_name: str) -> list[dict]:
    """Extract method signatures from Swift source file.

    Fallback when symbol graph extraction isn't available.
    Returns method names in Swift selector format (e.g., "transcribe(audioPath:modelId:...)").
    """
    content = file_path.read_text()
    methods = []

    # Find protocol block
    pattern = rf'@objc\s+public\s+protocol\s+{protocol_name}\s*\{{'
    match = re.search(pattern, content)
    if not match:
        pattern = rf'protocol\s+{protocol_name}\s*\{{'
        match = re.search(pattern, content)

    if not match:
        return methods

    # Extract content between braces
    start = match.end()
    brace_count = 1
    end = start

    for i, char in enumerate(content[start:], start):
        if char == '{':
            brace_count += 1
        elif char == '}':
            brace_count -= 1
            if brace_count == 0:
                end = i
                break

    protocol_body = content[start:end]

    # Parse func declarations with full parameter list
    # Match: func name(param1: Type, param2: Type, ...)
    func_pattern = r'func\s+(\w+)\s*\(([^)]*)\)'
    for match in re.finditer(func_pattern, protocol_body):
        func_name = match.group(1)
        params_str = match.group(2)

        # Parse parameters to build selector
        selector_parts = []
        if params_str.strip():
            # Split by comma, handling nested generics
            params = []
            depth = 0
            current = ""
            for char in params_str:
                if char in '<([':
                    depth += 1
                elif char in '>)]':
                    depth -= 1
                if char == ',' and depth == 0:
                    params.append(current.strip())
                    current = ""
                else:
                    current += char
            if current.strip():
                params.append(current.strip())

            for param in params:
                # Extract external parameter name (before internal name or colon)
                # e.g., "audioPath: String" -> "audioPath"
                # e.g., "_ modelId: String" -> "_"
                param = param.strip()
                if ':' in param:
                    before_colon = param.split(':')[0].strip()
                    # Handle "external internal: Type" or just "name: Type"
                    parts = before_colon.split()
                    if len(parts) >= 1:
                        external_name = parts[0]
                        selector_parts.append(external_name + ':')

        if selector_parts:
            selector = f"{func_name}({' '.join(selector_parts)})"
            # Remove spaces for canonical form
            selector = selector.replace(' ', '')
        else:
            selector = func_name

        # Get full line for context
        line_start = protocol_body.rfind('\n', 0, match.start()) + 1
        line_end = protocol_body.find('\n', match.end())
        if line_end == -1:
            line_end = len(protocol_body)
        full_line = protocol_body[line_start:line_end].strip()

        methods.append({
            'name': selector,
            'declaration': full_line,
            'source': 'parsed'
        })

    return sorted(methods, key=lambda m: m['name'])

def main():
    repo_root = get_repo_root()
    rebuild = "--rebuild" in sys.argv

    print(f"{BOLD}XPC Contract Verification (Xcode Toolchain){RESET}")
    print("=" * 60)

    # Find all DerivedData directories
    derived_paths = find_all_derived_data()

    if not derived_paths:
        print(f"{YELLOW}WARN{RESET}: No DerivedData found. Run xcodebuild first.")
        print("      Falling back to source-based analysis...")
    else:
        print(f"{DIM}Found {len(derived_paths)} DerivedData location(s):{RESET}")
        for p in derived_paths:
            print(f"{DIM}  • {p.parent.parent.name}{RESET}")

    # Extract symbol graphs if available
    symbolgraph_dir = Path("/tmp/talkie-symbolgraph")
    protocol_methods = {}

    if derived_paths:
        print(f"\n{BLUE}Extracting symbol graphs...{RESET}")
        for module in ["TalkieKit", "TalkieEngine"]:
            sg_file = extract_symbolgraph(module, derived_paths, symbolgraph_dir)
            if sg_file:
                methods = parse_protocol_methods(sg_file, "TalkieEngineProtocol")
                if methods:
                    protocol_methods[module] = methods
                    print(f"  {GREEN}✓{RESET} {module}: {len(methods)} methods")
            else:
                print(f"  {YELLOW}⚠{RESET} {module}: extraction failed")

    # Find usages in source
    print(f"\n{BLUE}Analyzing source code...{RESET}")
    usages = find_protocol_usages(repo_root, "TalkieEngineProtocol")

    print(f"\n{BOLD}Protocol: TalkieEngineProtocol{RESET}")
    print("-" * 60)

    # Show definitions
    print(f"\n{CYAN}Definitions:{RESET}")
    for d in usages['definitions']:
        print(f"  📄 {d}")

    # Show conformances
    print(f"\n{CYAN}Conforming Types:{RESET}")
    for c in usages['conformances']:
        print(f"  🔧 {c}")

    # Show XPC interface uses
    print(f"\n{CYAN}XPC Interface Uses:{RESET}")
    for u in usages['interface_uses']:
        print(f"  🔌 {u}")

    # Source-based extraction for all definitions (fallback/complement to symbolgraph)
    source_methods = {}
    for def_path in usages['definitions']:
        full_path = repo_root / def_path
        methods = extract_methods_from_source(full_path, "TalkieEngineProtocol")
        if methods:
            # Use short name for display
            short_name = def_path.split('/')[-1].replace('.swift', '')
            source_methods[short_name] = methods

    # Merge with symbolgraph methods (symbolgraph takes precedence)
    all_methods = {**source_methods}
    for module, methods in protocol_methods.items():
        # Symbolgraph overrides source parsing for same module
        all_methods[module] = methods

    # Contract Verification
    print(f"\n{BOLD}Contract Verification{RESET}")
    print("-" * 60)

    if len(all_methods) >= 2:
        hashes = {name: compute_method_hash(methods) for name, methods in all_methods.items()}
        unique_hashes = set(hashes.values())

        if len(unique_hashes) == 1:
            print(f"{GREEN}✓{RESET} All protocol definitions match ({list(unique_hashes)[0]})")
            first_methods = list(all_methods.values())[0]
            print(f"\n{BOLD}Methods ({len(first_methods)}):{RESET}")
            for m in first_methods:
                print(f"  • {m['name']}")
            return 0
        else:
            print(f"{RED}✗{RESET} MISMATCH DETECTED!")
            for name, h in hashes.items():
                source_type = "symbolgraph" if name in protocol_methods else "source"
                print(f"  {name} ({source_type}): {h}")

            # Show differences
            all_method_names = set()
            for methods in all_methods.values():
                all_method_names.update(m['name'] for m in methods)

            print(f"\n{YELLOW}Method comparison:{RESET}")
            for method in sorted(all_method_names):
                status = []
                for module, methods in all_methods.items():
                    has_it = any(m['name'] == method for m in methods)
                    status.append(f"{module}:{'✓' if has_it else '✗'}")
                print(f"  {method}: {', '.join(status)}")

            return 1
    elif len(all_methods) == 1:
        name, methods = list(all_methods.items())[0]
        print(f"{GREEN}✓{RESET} Single definition found: {name}")
        print(f"\n{BOLD}Methods ({len(methods)}):{RESET}")
        for m in methods:
            print(f"  • {m['name']}")
        return 0
    else:
        print(f"{YELLOW}⚠{RESET} No protocol methods extracted")
        return 1

if __name__ == "__main__":
    sys.exit(main())
