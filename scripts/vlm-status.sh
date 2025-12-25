#!/bin/bash
# Check VLM service status and configuration

# Load config if available
if [ -f .vlmrc ]; then
    source .vlmrc > /dev/null 2>&1
fi

VLM_HOST=${VLM_HOST:-127.0.0.1}
VLM_PORT=${VLM_PORT:-12346}
VLM_URL="http://${VLM_HOST}:${VLM_PORT}"

echo "🔍 VLM Service Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if service is running
if curl -s "${VLM_URL}/health" > /dev/null 2>&1; then
    echo "✅ VLM service is RUNNING and ready"
    echo ""
    echo "Configuration:"
    echo "  Host: ${VLM_HOST}"
    echo "  Port: ${VLM_PORT}"
    echo "  URL:  ${VLM_URL}"
    echo "  Model: mlx-community/Qwen2-VL-2B-Instruct-4bit"
    echo ""
    echo "Health endpoint: ${VLM_URL}/health"
    echo "Chat endpoint:   ${VLM_URL}/v1/chat/completions"
    echo ""

    # Check if process exists
    if pgrep -f "vlm:server" > /dev/null 2>&1; then
        PID=$(pgrep -f "vlm:server")
        echo "Process: PID $PID"
    fi

    echo ""
    echo "📊 Ready to analyze screenshots!"
else
    echo "❌ VLM service is NOT running"
    echo ""
    echo "Expected configuration:"
    echo "  Host: ${VLM_HOST}"
    echo "  Port: ${VLM_PORT}"
    echo "  URL:  ${VLM_URL}"
    echo ""
    echo "Start the service:"
    echo "  ./scripts/setup-vlm-analysis.sh"
    echo ""
    echo "Or manually:"
    echo "  cd ~/dev/agentloop"
    echo "  bun run vlm:server"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
