#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Devin Proxy Manager.app"
"$ROOT/scripts/build-macos.sh"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ARCH="$(/usr/bin/lipo -archs "$APP/Contents/MacOS/DevinProxyManager" | tr ' ' '-')"
DMG="$ROOT/dist/Devin Proxy Manager-$VERSION-macOS-$ARCH.dmg"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/devin-proxy-dmg.XXXXXX")"
trap 'if [ -d "$STAGING" ] && [ -x /usr/bin/trash ]; then /usr/bin/trash "$STAGING"; fi' EXIT

/usr/bin/ditto "$APP" "$STAGING/Devin Proxy Manager.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/安装说明.txt" <<'NOTE'
Devin Proxy Manager（第三方工具）

将 Devin Proxy Manager.app 拖到 Applications 文件夹。
首次打开后，在菜单中选择 cognition-claude-proxy-with-sm 仓库目录，
检查 Node.js 和 Devin CLI 凭据，再点击“启动”。

此 DMG 只包含菜单栏应用，不包含 Node.js、Devin CLI 或代理源码。
仓库地址：https://github.com/gitrocyang/cognition-claude-proxy-with-sm
本地构建版本未经过 Apple 公证，仅供自行构建和本机使用。
NOTE

/usr/bin/hdiutil create -volname "Devin Proxy Manager" -srcfolder "$STAGING" \
  -format UDZO -imagekey zlib-level=9 -ov "$DMG"
/usr/bin/hdiutil verify "$DMG"
echo "$DMG"
