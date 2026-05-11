#!/bin/bash
#
# TalkieSync launchd setup script
# Installs the XPC service for development
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PLIST_SRC="$PROJECT_DIR/jdi.talkie.sync.xpc.dev.plist"
PLIST_DST="$HOME/Library/LaunchAgents/jdi.talkie.sync.xpc.dev.plist"

echo "TalkieSync launchd setup"
echo "========================"

# Find the TalkieSync app in DerivedData
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
TALKIESYNC_APP=$(find "$DERIVED_DATA" -name "TalkieSync.app" -path "*/Debug/*" 2>/dev/null | head -1)

if [ -z "$TALKIESYNC_APP" ]; then
    echo "ERROR: TalkieSync.app not found in DerivedData"
    echo "Please build TalkieSync in Xcode first."
    exit 1
fi

TALKIESYNC_BIN="$TALKIESYNC_APP/Contents/MacOS/TalkieSync"
echo "Found TalkieSync: $TALKIESYNC_BIN"

# Create plist with correct path
cat > "$PLIST_DST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>jdi.talkie.sync.xpc.dev</string>
    <key>ProgramArguments</key>
    <array>
        <string>$TALKIESYNC_BIN</string>
    </array>
    <key>MachServices</key>
    <dict>
        <key>jdi.talkie.sync.xpc.dev</key>
        <true/>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>StandardOutPath</key>
    <string>/tmp/jdi.talkie.sync.xpc.dev.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/jdi.talkie.sync.xpc.dev.stderr.log</string>
</dict>
</plist>
EOF

echo "Created plist: $PLIST_DST"

# Unload existing if present
if launchctl list | grep -q "jdi.talkie.sync.xpc.dev"; then
    echo "Unloading existing service..."
    launchctl unload "$PLIST_DST" 2>/dev/null || true
fi

# Load the service
echo "Loading service..."
launchctl load "$PLIST_DST"

echo ""
echo "TalkieSync XPC service installed!"
echo ""
echo "View logs:"
echo "  tail -f /tmp/jdi.talkie.sync.xpc.dev.stdout.log"
echo ""
echo "Restart service:"
echo "  launchctl unload ~/Library/LaunchAgents/jdi.talkie.sync.xpc.dev.plist"
echo "  launchctl load ~/Library/LaunchAgents/jdi.talkie.sync.xpc.dev.plist"
