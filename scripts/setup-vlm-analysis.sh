#!/bin/bash
# Setup and run VLM-based light mode analysis for Talkie

set -e

echo "🔧 Setting up VLM-based light mode analysis"
echo ""

# Check if agentloop exists
AGENTLOOP_DIR=~/dev/agentloop
if [ ! -d "$AGENTLOOP_DIR" ]; then
    echo "❌ AgentLoop not found at $AGENTLOOP_DIR"
    exit 1
fi

# Check if VLM is installed
if [ ! -d "$AGENTLOOP_DIR/external/vlm" ]; then
    echo "📦 VLM not installed. Installing..."
    cd "$AGENTLOOP_DIR"
    bun run vlm:install -- --yes
    echo "✅ VLM installed"
    echo ""
fi

# Check if VLM service is running
if curl -s http://127.0.0.1:12346/health > /dev/null 2>&1; then
    echo "✅ VLM service is already running"
else
    echo "🚀 Starting VLM service..."
    echo "   This will run in the background and may take a moment to load the model..."
    cd "$AGENTLOOP_DIR"
    bun run vlm:server > /tmp/vlm-server.log 2>&1 &
    VLM_PID=$!
    echo "   PID: $VLM_PID"

    # Wait for service to be ready
    echo "   Waiting for VLM to start..."
    for i in {1..30}; do
        if curl -s http://127.0.0.1:12346/health > /dev/null 2>&1; then
            echo "✅ VLM service is ready!"
            break
        fi
        sleep 1
        echo -n "."
    done
    echo ""
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 VLM Configuration"
echo ""
echo "Service is running with stable defaults:"
echo "  Host: 127.0.0.1"
echo "  Port: 12346"
echo "  URL:  http://127.0.0.1:12346"
echo ""
echo "To customize, edit .vlmrc or set environment variables:"
echo "  export VLM_HOST=127.0.0.1"
echo "  export VLM_PORT=12346"
echo ""
echo "Check status anytime:"
echo "  ./scripts/vlm-status.sh"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Usage Instructions:"
echo ""
echo "1. Make sure Talkie is running and set to LIGHT MODE:"
echo "   - Open Talkie"
echo "   - Go to Settings > Appearance"
echo "   - Select 'Light' appearance mode"
echo ""
echo "2. Navigate to the screen you want to analyze (e.g., Status Bar, All Memos, etc.)"
echo ""
echo "3. Run the analysis:"
echo "   python3 scripts/analyze-light-mode.py --capture-and-analyze"
echo ""
echo "4. When prompted, click on the Talkie window to capture it"
echo ""
echo "5. The VLM will analyze the screenshot and report any light mode issues"
echo ""
echo "To stop the VLM service:"
echo "   pkill -f 'bun.*vlm:server'"
echo ""
