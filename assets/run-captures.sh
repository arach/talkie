#!/bin/bash
# Talkie Capture Runner
# Executes active flows from capture-flows.yaml
#
# Usage: ./run-captures.sh [flow-name]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/captures"
SCHEME="talkie-dev"
APP="Talkie"
DELAY=0.5

mkdir -p "$OUTPUT_DIR"

echo "=== Talkie Capture Runner ==="
echo "Output: $OUTPUT_DIR"
echo ""

# Core Views Flow
run_core_views() {
    echo "--- Core Views Flow ---"

    echo "  Capturing: Memos"
    open "${SCHEME}://memos"
    sleep $DELAY
    npx @arach/vif shot --app "$APP" "$OUTPUT_DIR/01-memos-list.png"

    echo "  Capturing: Dictations"
    open "${SCHEME}://dictations"
    sleep $DELAY
    npx @arach/vif shot --app "$APP" "$OUTPUT_DIR/02-dictations.png"

    echo "  Capturing: Workflows"
    open "${SCHEME}://workflows"
    sleep $DELAY
    npx @arach/vif shot --app "$APP" "$OUTPUT_DIR/03-workflows.png"

    echo "  Capturing: Home"
    open "${SCHEME}://home"
    sleep $DELAY
    npx @arach/vif shot --app "$APP" "$OUTPUT_DIR/04-home-dashboard.png"

    echo "--- Core Views Complete ---"
    echo ""
}

# Workflow Showcase Flow
run_workflow_showcase() {
    echo "--- Workflow Showcase Flow ---"

    echo "  Capturing: Workflow List"
    open "${SCHEME}://workflows"
    sleep $DELAY
    npx @arach/vif shot --app "$APP" "$OUTPUT_DIR/workflows-01-list.png"

    echo "--- Workflow Showcase Complete ---"
    echo ""
}

# Run specific flow or all active flows
case "${1:-all}" in
    core)
        run_core_views
        ;;
    workflows)
        run_workflow_showcase
        ;;
    all)
        run_core_views
        run_workflow_showcase
        ;;
    *)
        echo "Unknown flow: $1"
        echo "Available: core, workflows, all"
        exit 1
        ;;
esac

echo "=== Capture Complete ==="
echo "Files:"
ls -la "$OUTPUT_DIR"/*.png 2>/dev/null || echo "  No captures found"

echo ""
echo "Opening gallery..."
open "$OUTPUT_DIR/index.html"
