#!/bin/bash
# Build and launch a tiny windowed app so you can Cmd+Tab preview without rebuilding.
# Usage: bash scripts/preview-macos-switcher.sh [AppIcon.appiconset] [app_path] [--rebuild]
set -euo pipefail

ICONSET="${1:-apps/macos/Talkie/Assets.xcassets/AppIcon.appiconset}"
APP_DIR="${2:-/tmp/TalkieIconPreview.app}"
REBUILD="${3:-}"
APP_NAME="$(basename "$APP_DIR" .app)"

if [ ! -d "$ICONSET" ]; then
  echo "Iconset not found: $ICONSET" >&2
  exit 1
fi

if ! command -v iconutil >/dev/null 2>&1; then
  echo "iconutil not found. Install Xcode CLT to use this preview." >&2
  exit 1
fi

if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc not found. Install Xcode CLT to use this preview." >&2
  exit 1
fi

tmpdir="$(mktemp -d /tmp/talkie-icon-preview.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

if [ ! -d "$APP_DIR" ] || [ "$REBUILD" = "--rebuild" ]; then
  mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

  cat > "$tmpdir/main.swift" <<'SWIFT'
import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let size = NSSize(width: 520, height: 360)
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Icon Preview"
        window.center()

        let content = NSView(frame: NSRect(origin: .zero, size: size))
        let label = NSTextField(labelWithString: "Cmd+Tab icon preview")
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor)
        ])
        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
SWIFT

  swiftc "$tmpdir/main.swift" -framework Cocoa -o "$APP_DIR/Contents/MacOS/$APP_NAME"

  cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>dev.talkie.$APP_NAME</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST
fi

iconutil -c icns "$ICONSET" -o "$tmpdir/AppIcon.icns"
cp "$tmpdir/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
open "$APP_DIR"
echo "Launched $APP_DIR. Use Cmd+Tab to preview, then Quit from the Dock."
