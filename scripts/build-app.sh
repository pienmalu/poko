#!/bin/zsh
# Poko.app を作る。使い方: ./scripts/build-app.sh [--open]
# 署名する ID を POKO_SIGN_IDENTITY で渡せる（渡さなければ簡易署名。その場合、ビルドし直すたびに
# アクセシビリティの許可が効かなくなるので、README の「許可をやり直す」を見る）。
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/build/Poko.app"
TMP="${TMPDIR:-/tmp}"

mkdir -p "$ROOT/build"
swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macosx14.0 -module-name Poko \
  -module-cache-path "$TMP/poko-module-cache" \
  "$ROOT"/Sources/Poko/*.swift -o "$ROOT/build/Poko-bin"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mv "$ROOT/build/Poko-bin" "$APP/Contents/MacOS/Poko"
sed "s|__POKO_HOME__|$ROOT|" "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"
[[ -f "$ROOT/Resources/Poko.icns" ]] && cp "$ROOT/Resources/Poko.icns" "$APP/Contents/Resources/"
codesign --force --sign "${POKO_SIGN_IDENTITY:--}" "$APP"

echo "できました: $APP"
[[ -x "$ROOT/vendor/speech" ]] || echo "まだ speech.cpp がありません。先に ./scripts/setup.sh を実行してください"
if [[ "${1:-}" == "--open" ]]; then open "$APP"; fi
