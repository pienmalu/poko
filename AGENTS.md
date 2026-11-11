# Poko

押しながら話す音声入力（メニューバー常駐、macOS 14+、Apple Silicon）。使い方と構成は README.md。

- ビルド `./scripts/build-app.sh`、テスト `./scripts/test.sh`、アイコンの確認 `./tools/render-icon.sh`（PNG を見る）
- SwiftPM は使わず `swiftc` で直接ビルドする。`-target arm64-apple-macosx14.0` を保ち、14 にない API を使わない
- 認識は speech.cpp の `speech asr <Haas> --vad <Silero> -` を録音ごとに起動して PCM を流す。worker は VAD を扱えず、serve は常駐が要るので使わない
- モデルは speech.cpp の既定のフォルダ（`~/Library/Caches/speech.cpp/models`）に置き、ほかの用途と共有する。リポジトリの `models/` には `setup.sh` が張るリンクだけを置く
- 音声も文字も Mac の外に送らない。ネットにつながるのは `scripts/setup.sh` だけにする
- 要る許可はアクセシビリティとマイクの2つだけ。通知センターなど、許可を増やすものは足さない
- コメントとメッセージは日本語。ユーザーが後から自分で少し弄れる単純さを保つ
- サンドボックスの中では Metal、`say`、`iconutil` が動かない。本物の認識を試すときはサンドボックスの外で動かす
