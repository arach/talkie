#!/bin/bash
# Setup local DNS for VLM service

set -e

HOSTNAME="agentloop.dev"
IP="127.0.0.1"
HOSTS_FILE="/etc/hosts"

echo "🌐 Setting up local DNS for VLM service"
echo ""

# Check if entry already exists
if grep -q "$HOSTNAME" "$HOSTS_FILE" 2>/dev/null; then
    echo "✅ DNS entry already exists in $HOSTS_FILE"
    grep "$HOSTNAME" "$HOSTS_FILE"
else
    echo "📝 Adding DNS entry to $HOSTS_FILE"
    echo "   $IP $HOSTNAME"
    echo ""
    echo "This requires sudo access..."

    # Add entry to /etc/hosts
    echo "$IP $HOSTNAME" | sudo tee -a "$HOSTS_FILE" > /dev/null

    echo "✅ DNS entry added!"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🎯 VLM Service DNS"
echo ""
echo "  Hostname: $HOSTNAME"
echo "  IP:       $IP"
echo "  Port:     12346"
echo ""
echo "  Full URL: http://$HOSTNAME:12346"
echo ""
echo "Test it:"
echo "  curl http://$HOSTNAME:12346/health"
echo "  ping $HOSTNAME"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
