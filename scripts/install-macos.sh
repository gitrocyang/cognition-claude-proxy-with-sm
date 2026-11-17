#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Devin Proxy Manager.app"
TARGET="$HOME/Applications/Devin Proxy Manager.app"
[ -d "$APP" ] || "$ROOT/scripts/build-macos.sh"
mkdir -p "$HOME/Applications"
if [ -e "$TARGET" ]; then
  echo "已有安装：$TARGET；请先退出管理器，再手动移走旧应用。" >&2
  exit 1
fi
cp -R "$APP" "$TARGET"
if ! defaults read com.gitrocyang.devin-proxy-manager projectPath >/dev/null 2>&1; then
  defaults write com.gitrocyang.devin-proxy-manager projectPath "$ROOT"
fi
echo "已安装：$TARGET"
echo "执行 open \"$TARGET\" 启动。若端口由旧代理占用，先在旧终端安全停止旧代理。"
