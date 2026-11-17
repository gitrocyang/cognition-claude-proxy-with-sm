#!/usr/bin/env bash
set -euo pipefail
LABEL="com.gitrocyang.devin-proxy-manager.proxy"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
APP="$HOME/Applications/Devin Proxy Manager.app"
if [ -x "$APP/Contents/MacOS/DevinProxyManager" ]; then
  "$APP/Contents/MacOS/DevinProxyManager" --unregister-login-item || true
fi
if [ -e "$AGENT" ]; then
  OWNER="$(plutil -extract ManagedBy raw -o - "$AGENT" 2>/dev/null || true)"
  if [ "$OWNER" != "DevinProxyManager" ]; then
    echo "同名 LaunchAgent 不属于本项目，拒绝卸载：$AGENT" >&2
    exit 1
  fi
  SERVICE="gui/$(id -u)/$LABEL"
  if /bin/launchctl print "$SERVICE" >/dev/null 2>&1; then
    /bin/launchctl bootout "$SERVICE"
  fi
  if /bin/launchctl print "$SERVICE" >/dev/null 2>&1; then
    echo "LaunchAgent 仍在运行，已保留 plist；请先关闭管理器再重试。" >&2
    exit 1
  fi
  rm "$AGENT"
fi
if [ -e "$APP" ]; then rm -rf "$APP"; fi
defaults delete com.gitrocyang.devin-proxy-manager 2>/dev/null || true
echo "管理器及其 LaunchAgent 已卸载。日志留在 ~/Library/Logs/DevinProxyManager，可自行删除。"
