#!/bin/bash
#
# Setup Apple Containerization Framework for TalkieGateway
#
# Usage:
#   ./setup-containerization.sh          # Auto-setup (installs if needed)
#   ./setup-containerization.sh clone    # Step 1: Clone repo
#   ./setup-containerization.sh sdk      # Step 2: Install Swift Static Linux SDK
#   ./setup-containerization.sh kernel   # Step 3: Fetch Kata kernel
#   ./setup-containerization.sh build    # Step 4: Build tools
#   ./setup-containerization.sh status   # Check current status
#
# Prerequisites: macOS 26, Xcode 26, Apple Silicon

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
EXTERNAL_DIR="$PROJECT_ROOT/external"
CONTAINER_REPO="$EXTERNAL_DIR/containerization"

# Source Swift environment if available
if [ -f "$HOME/.swiftly/env.sh" ]; then
    source "$HOME/.swiftly/env.sh"
fi

get_cctl_path() {
    if [ -f "$CONTAINER_REPO/bin/TalkieGateway" ]; then
        echo "$CONTAINER_REPO/bin/TalkieGateway"
    elif command -v cctl &> /dev/null; then
        which cctl
    elif [ -f "$CONTAINER_REPO/bin/cctl" ]; then
        echo "$CONTAINER_REPO/bin/cctl"
    elif [ -f "$CONTAINER_REPO/.build/arm64-apple-macosx/release/cctl" ]; then
        echo "$CONTAINER_REPO/.build/arm64-apple-macosx/release/cctl"
    elif [ -f "$CONTAINER_REPO/.build/arm64-apple-macosx/debug/cctl" ]; then
        echo "$CONTAINER_REPO/.build/arm64-apple-macosx/debug/cctl"
    else
        echo ""
    fi
}

step_clone() {
    echo "=== Step 1: Clone Containerization Repo ==="
    if [ -d "$CONTAINER_REPO" ]; then
        echo "Already exists at $CONTAINER_REPO"
    else
        mkdir -p "$EXTERNAL_DIR"
        git clone https://github.com/apple/containerization.git "$CONTAINER_REPO"
        echo "Done. Cloned to $CONTAINER_REPO"
    fi
}

step_sdk() {
    echo "=== Step 2: Install Swift Static Linux SDK ==="
    if [ ! -d "$CONTAINER_REPO" ]; then
        echo "Error: Run 'clone' step first"
        exit 1
    fi
    if [ -f "$HOME/.swiftly/env.sh" ]; then
        echo "Swiftly already installed, skipping..."
        return 0
    fi
    cd "$CONTAINER_REPO"
    echo "This installs Swiftly + Swift + Static Linux SDK for cross-compilation"
    echo "May take several minutes..."
    make cross-prep
    echo ""
    echo "Done. Add this to your shell profile:"
    echo "  source ~/.swiftly/env.sh"
}

step_kernel() {
    echo "=== Step 3: Fetch Kata Kernel ==="
    if [ ! -d "$CONTAINER_REPO" ]; then
        echo "Error: Run 'clone' step first"
        exit 1
    fi
    cd "$CONTAINER_REPO"
    echo "Downloading ~5MB Linux kernel optimized for container VMs..."
    make fetch-default-kernel
    echo "Done."
}

step_build() {
    echo "=== Step 4: Build Containerization Tools ==="
    if [ ! -d "$CONTAINER_REPO" ]; then
        echo "Error: Run 'clone' step first"
        exit 1
    fi

    # Re-source in case sdk step just installed it
    if [ -f "$HOME/.swiftly/env.sh" ]; then
        source "$HOME/.swiftly/env.sh"
    fi

    cd "$CONTAINER_REPO"
    make all

    # Create TalkieGateway symlink for friendly process name
    if [ -f "$CONTAINER_REPO/bin/cctl" ] && [ ! -f "$CONTAINER_REPO/bin/TalkieGateway" ]; then
        ln -sf cctl "$CONTAINER_REPO/bin/TalkieGateway"
        echo "Created TalkieGateway symlink"
    fi

    echo ""
    echo "Done. Tools built."
}

step_status() {
    echo "=== Containerization Setup Status ==="
    echo ""

    # Repo
    if [ -d "$CONTAINER_REPO" ]; then
        echo "[x] Repo cloned: $CONTAINER_REPO"
    else
        echo "[ ] Repo not cloned"
    fi

    # Swift SDK
    if [ -f "$HOME/.swiftly/env.sh" ]; then
        echo "[x] Swiftly installed"
    else
        echo "[ ] Swiftly not installed"
    fi

    # Kernel
    if [ -f "$CONTAINER_REPO/kernel/linux-kernel" ] || [ -d "$CONTAINER_REPO/.build" ]; then
        echo "[x] Kernel fetched (or build exists)"
    else
        echo "[ ] Kernel not fetched"
    fi

    # cctl
    local cctl_path=$(get_cctl_path)
    if [ -n "$cctl_path" ]; then
        echo "[x] cctl available: $cctl_path"
    else
        echo "[ ] cctl not built"
    fi

    echo ""
}

step_auto() {
    local cctl_path=$(get_cctl_path)

    if [ -n "$cctl_path" ]; then
        echo "=== cctl already available ==="
        echo "Path: $cctl_path"
        echo ""
        echo "Ready to build containers. Example:"
        echo "  cd $PROJECT_ROOT/macOS/TalkieGateway"
        echo "  $cctl_path build -t talkie-gateway:latest ."
        exit 0
    fi

    echo "=== cctl not found, running full setup ==="
    echo ""

    step_clone
    echo ""
    step_sdk
    echo ""
    step_kernel
    echo ""
    step_build
    echo ""

    cctl_path=$(get_cctl_path)
    if [ -n "$cctl_path" ]; then
        echo "=== Setup Complete ==="
        echo "cctl available at: $cctl_path"
        echo ""
        echo "Next: Build the Gateway image:"
        echo "  cd $PROJECT_ROOT/macOS/TalkieGateway"
        echo "  $cctl_path build -t talkie-gateway:latest ."
    else
        echo "=== Setup may have failed ==="
        echo "Run './setup-containerization.sh status' to check"
    fi
}

# Main
case "${1:-auto}" in
    clone)  step_clone ;;
    sdk)    step_sdk ;;
    kernel) step_kernel ;;
    build)  step_build ;;
    status) step_status ;;
    auto)   step_auto ;;
    all)    step_auto ;;
    *)
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  (none)  - Auto-setup: installs everything if cctl not found"
        echo "  clone   - Clone Apple containerization repo"
        echo "  sdk     - Install Swift Static Linux SDK"
        echo "  kernel  - Fetch Kata kernel"
        echo "  build   - Build containerization tools"
        echo "  status  - Check current setup status"
        exit 1
        ;;
esac
