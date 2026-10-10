#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/.."
printf '喵伴开发环境\n'
for command in python3 docker; do
  if command -v "$command" >/dev/null; then "$command" --version; else printf '缺少 %s\n' "$command"; fi
done
docker info --format 'Docker server {{.ServerVersion}}' 2>/dev/null || true
if test -x .tools/flutter/bin/flutter; then .tools/flutter/bin/flutter doctor -v; else printf '缺少 Flutter SDK\n'; fi
if test -d /Applications/Xcode.app; then printf '完整 Xcode 已找到\n'; else printf '缺少完整 Xcode（当前只有 CommandLineTools）\n'; fi
printf '配置存在性（不输出密钥）\n'
for value in .env apps/mobile/android/key.properties; do
  if test -f "$value"; then printf '%s 已配置\n' "$value"; else printf '%s 待配置\n' "$value"; fi
done
