#!/bin/zsh
# 窓の見た目を PNG に描く。使い方: ./tools/render-window.sh [出力フォルダ]
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="${TMPDIR:-/tmp}"
OUT="${1:-build/window}"
mkdir -p build
swiftc -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path "$TMP/poko-module-cache" \
  Sources/Poko/{MainWindow,Activity,Vocabulary,HotKey,PushToTalk}.swift tools/render-window/main.swift -o build/render-window
build/render-window "$OUT"
