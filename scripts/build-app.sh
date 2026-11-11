#!/bin/zsh
# Koe.app を作る。使い方: ./scripts/build-app.sh [--open]
# 署名する ID を KOE_SIGN_IDENTITY で渡せる（渡さなければ簡易署名。その場合、ビルドし直すたびに
# アクセシビリティの許可が効かなくなるので、README の「許可をやり直す」を見る）。
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/build/Koe.app"
TMP="${TMPDIR:-/tmp}"

mkdir -p "$ROOT/build"
swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macosx14.0 -module-name Koe \
  -module-cache-path "$TMP/koe-module-cache" \
  "$ROOT"/Sources/Koe/*.swift -o "$ROOT/build/Koe-bin"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mv "$ROOT/build/Koe-bin" "$APP/Contents/MacOS/Koe"
sed "s|__KOE_HOME__|$ROOT|" "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"
[[ -f "$ROOT/Resources/Koe.icns" ]] && cp "$ROOT/Resources/Koe.icns" "$APP/Contents/Resources/"
codesign --force --sign "${KOE_SIGN_IDENTITY:--}" "$APP"

echo "できました: $APP"
[[ -x "$ROOT/vendor/speech" ]] || echo "まだ speech.cpp がありません。先に ./scripts/setup.sh を実行してください"
if [[ "${1:-}" == "--open" ]]; then open "$APP"; fi
