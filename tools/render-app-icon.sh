#!/bin/zsh
# アプリのアイコン Resources/Koe.icns を作り直す。使い方: ./tools/render-app-icon.sh
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="${TMPDIR:-/tmp}"
mkdir -p build
swiftc -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path "$TMP/koe-module-cache" \
  tools/render-app-icon/main.swift -o build/render-app-icon
rm -rf build/Koe.iconset
build/render-app-icon build/Koe.iconset
iconutil -c icns build/Koe.iconset -o Resources/Koe.icns
echo "wrote Resources/Koe.icns"
