#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE="$ROOT/macos/DevinProxyManager"
OUTPUT="$ROOT/dist/Devin Proxy Manager.app"

swift build --package-path "$PACKAGE" -c release
BIN="$(swift build --package-path "$PACKAGE" -c release --show-bin-path)/DevinProxyManager"
mkdir -p "$OUTPUT/Contents/MacOS"
cp "$BIN" "$OUTPUT/Contents/MacOS/DevinProxyManager"
cat > "$OUTPUT/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.gitrocyang.devin-proxy-manager</string>
<key>CFBundleName</key><string>Devin Proxy Manager</string>
<key>CFBundleExecutable</key><string>DevinProxyManager</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$OUTPUT"
echo "$OUTPUT"
