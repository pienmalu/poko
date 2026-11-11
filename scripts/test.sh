#!/bin/zsh
# テストを実行する（SwiftPM を使わず、XCTest のバンドルを直接作って動かす）。
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
TMP="${TMPDIR:-/tmp}"
PLATFORM="$(xcrun --show-sdk-platform-path)"
BUNDLE="$ROOT/build/PokoTests.xctest"

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
# アプリの入口（PokoApp.swift）以外の部品とテストを、まとめて1つのバンドルにする。
swiftc -parse-as-library -swift-version 5 -target arm64-apple-macosx14.0 -module-name PokoTests \
  -module-cache-path "$TMP/poko-module-cache" \
  -F "$PLATFORM/Developer/Library/Frameworks" -I "$PLATFORM/Developer/usr/lib" \
  -L "$PLATFORM/Developer/usr/lib" -framework XCTest -lXCTestSwiftSupport \
  -Xlinker -rpath -Xlinker "$PLATFORM/Developer/Library/Frameworks" -Xlinker -rpath -Xlinker "$PLATFORM/Developer/usr/lib" \
  -emit-library -Xlinker -bundle \
  $(ls "$ROOT"/Sources/Poko/*.swift | grep -v PokoApp.swift) "$ROOT"/Tests/PokoTests/*.swift \
  -o "$BUNDLE/Contents/MacOS/PokoTests"
xcrun xctest "$BUNDLE"
