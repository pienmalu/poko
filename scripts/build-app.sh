#!/bin/zsh
# Poko.app を作る。使い方: ./scripts/build-app.sh [--install] [--open]
#   --install  ~/Applications/Poko.app に入れる（Dock や Launchpad から開けるようになる）。動いていれば先に終了させる
#   --open     作ったアプリを開く（--install と一緒なら、入れた方を開く）
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
[[ -f "$ROOT/Resources/AppIcon.icns" ]] && cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
codesign --force --sign "${POKO_SIGN_IDENTITY:--}" "$APP"

echo "できました: $APP"
[[ -x "$ROOT/vendor/speech" ]] || echo "まだ speech.cpp がありません。先に ./scripts/setup.sh を実行してください"

if (( ${@[(Ie)--install]} )); then
  DEST="$HOME/Applications/Poko.app"
  osascript -e 'quit app "Poko"' 2>/dev/null || true
  mkdir -p "$HOME/Applications"
  rm -rf "$DEST"
  ditto "$APP" "$DEST"
  APP="$DEST"
  echo "入れました: $DEST"
fi
if (( ${@[(Ie)--open]} )); then open "$APP"; fi
