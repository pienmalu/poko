#!/bin/zsh
# speech.cpp とモデルを取ってくる（最初に1回だけ）。使い方: ./scripts/setup.sh
# ここだけがネットにつながる。アプリは取ってきたファイルを読むだけで、外には何も送らない。
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
VERSION=0.10.1
ZIP="speech-$VERSION-macos-arm64-metal.zip"
URL="https://github.com/nyosegawa/speech.cpp/releases/download/v$VERSION"

# 1. speech.cpp（コマンド1つ）を vendor/ に置く。リリースの SHA-256 と照らし合わせる。
mkdir -p vendor
if [[ "$(vendor/speech --version 2>/dev/null)" != "speech.cpp $VERSION"* ]]; then
  echo "speech.cpp $VERSION を取ってきます"
  curl -fsSL -o "vendor/$ZIP" "$URL/$ZIP"
  curl -fsSL -o vendor/SHA256SUMS "$URL/SHA256SUMS"
  (cd vendor && grep " $ZIP\$" SHA256SUMS | shasum -a 256 -c -)
  unzip -q -o "vendor/$ZIP" -d vendor
fi
vendor/speech --version

# 2. モデルを取ってくる（Haas-ja-v1.0 の Q8_0 が 0.66 GB、Silero VAD が 1 MB）。
#    置き場所は speech.cpp の既定のフォルダ（~/Library/Caches/speech.cpp/models。SPEECH_MODEL_DIR があればそこ）。
#    ほかのアプリやコマンドから speech.cpp を使うときも、同じモデルをそのまま使える。
# 3. アプリが読む名前で、models/ にリンクを張る。speech pull は取ってきたファイルの場所を出力する。
mkdir -p models
ln -sf "$(vendor/speech pull haas-ja-v1.0:q8_0)" models/haas-ja-v1.0-q8_0.gguf
ln -sf "$(vendor/speech pull silero-vad)" models/silero-vad.gguf
ls -l models/*.gguf
echo "準備できました。次は ./scripts/build-app.sh --open"
