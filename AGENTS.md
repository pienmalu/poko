# Poko

押しながら話す音声入力（Dock とメニューバーに出る。窓はない。macOS 14+、Apple Silicon）。使い方と構成は README.md。

- ビルド `./scripts/build-app.sh`（`--install` で `~/Applications` に入れる）、テスト `./scripts/test.sh`、メニューバーのアイコンの確認 `./tools/render-icon.sh`（PNG を見る）
- SwiftPM は使わず `swiftc` で直接ビルドする。`-target arm64-apple-macosx14.0` を保ち、14 にない API を使わない
- 認識は speech.cpp の `speech asr <Haas> --vad <Silero> -` を録音ごとに起動して PCM を流す。worker は VAD を扱えず、serve は常駐が要るので使わない
- モデルは speech.cpp の既定のフォルダ（`~/Library/Caches/speech.cpp/models`）に置き、ほかの用途と共有する。リポジトリの `models/` には `setup.sh` が張るリンクだけを置く
- 音声は Mac の外に送らない。文字を送るのは、推敲（メニュー → 推敲）に Claude か ChatGPT を選んだときだけで、既定は「しない」。外に送る選択肢には、メニューの名前に送り先を書く
- サブスクはログイン済みの公式 CLI（`claude -p`、`codex exec`）を1回ごとに起動して使い、アプリは API キーもトークンも持たない。CLI の場所はログインシェルに尋ねる（Dock から開いたアプリには PATH が渡らない）
- 推敲の Gemma（llama-server）は常駐させない。押してから `minimumHold` を過ぎたら起動し、2 分使わなければ止める。llama.cpp やモデルがなくても認識と貼り付けは今までどおり動くようにし、推敲が失敗したら元の文を貼る
- `Sources/Poko/LLM.swift` は別のアプリも持ち込んで使う。Poko のほかのファイルに頼らせず、Poko 固有のことも書かない
- 要る許可はアクセシビリティとマイクの2つだけ。通知センターなど、許可を増やすものは足さない
- Poko が前に出たまま残らないようにする。残ると、話した文の貼り先がなくなる（起動したときと、Dock から開いたメニューを閉じたときに隠す）
- アプリのアイコンは `Resources/AppIcon.png` から `./tools/render-app-icon.sh` で作る。絵を変えるときは、自作アプリで共通の黒いスライム（`~/workspace/dev/brand/black-slime`）からそろえて描き、勝手に差し替えない
- コメントとメッセージは日本語。ユーザーが後から自分で少し弄れる単純さを保つ
- サンドボックスの中では Metal、`say`、`iconutil` が動かない。本物の認識を試すときと、アイコンを作るときはサンドボックスの外で動かす
