#!/bin/zsh
# speech.cpp とモデルを取ってくる（最初に1回だけ）。使い方: ./scripts/setup.sh [--llm]
#   --llm  推敲を Mac の中でするための llama.cpp と Gemma 4 E4B（約 5 GB）も取ってくる
# ここだけがネットにつながる。アプリは取ってきたファイルを読むだけ（推敲に Claude か ChatGPT を選んだときは、
# その CLI が文字を送る）。
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

# 4. --llm のときだけ、推敲に使う llama.cpp と Gemma 4 E4B を取ってくる。
#    Gemma は Mogu などとも共有するフォルダ（LLAMA_MODEL_DIR、既定は ~/models/llama.cpp）に置き、リンクを張る。
if (( ${@[(Ie)--llm]} )); then
  LLAMA_TAG="b12110"   # Gemma 4 が動くことを確かめた版
  if [[ ! -x "vendor/llama-$LLAMA_TAG/llama-server" ]]; then
    echo "llama.cpp $LLAMA_TAG を取ってきます"
    curl -fL --progress-bar -o vendor/llama.tgz \
      "https://github.com/ggml-org/llama.cpp/releases/download/$LLAMA_TAG/llama-$LLAMA_TAG-bin-macos-arm64.tar.gz"
    tar xzf vendor/llama.tgz -C vendor
    rm vendor/llama.tgz
    xattr -dr com.apple.quarantine "vendor/llama-$LLAMA_TAG" 2>/dev/null || true
  fi
  ln -sfn "llama-$LLAMA_TAG" vendor/llama

  SHARED="${LLAMA_MODEL_DIR:-$HOME/models/llama.cpp}"
  GEMMA="gemma-4-E4B-it-Q4_K_M.gguf"
  mkdir -p "$SHARED"
  if [[ ! -f "$SHARED/$GEMMA" ]]; then
    echo "$GEMMA を取ってきます"
    curl -fL --progress-bar -o "$SHARED/$GEMMA.part" "https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/main/$GEMMA"
    mv "$SHARED/$GEMMA.part" "$SHARED/$GEMMA"
  fi
  ln -sf "$SHARED/$GEMMA" "models/$GEMMA"
fi

ls -l models/*.gguf
echo "準備できました。次は ./scripts/build-app.sh --open"
