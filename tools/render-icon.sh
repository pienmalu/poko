#!/bin/zsh
# アイコンの各状態をコマ送りで PNG に描く。使い方: ./tools/render-icon.sh [出力.png]
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="${TMPDIR:-/tmp}"
OUT="${1:-build/icon-frames.png}"
mkdir -p build
swiftc -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path "$TMP/poko-module-cache" \
  Sources/Poko/StatusIcon.swift tools/render-icon/main.swift -o build/render-icon
build/render-icon "$OUT"
