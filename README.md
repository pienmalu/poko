# Poko

キーを押しながら話して離すと、いま使っているアプリのカーソル位置に文字が入る、日本語の音声入力。
macOS 14 以降の Apple Silicon の Mac で動く。
名前は、話すと文字が「ぽこっ」と出ることから付けた。
メモ帳の [Mogu](../mogu) と対になる。
認識には [speech.cpp](https://github.com/nyosegawa/speech.cpp) と Haas-ja-v1.0（Q8_0）を使い、Mac の中だけで行う。
音声も文字も外には送らない。

アプリは Dock とメニューバーに出る。
窓は出さない。

## 使い方

```bash
./scripts/setup.sh                        # 最初に1回。speech.cpp 0.10.1 と、モデル（0.66 GB）を取ってくる
./scripts/build-app.sh --install --open   # アプリを作って ~/Applications に入れ、開く
```

`--install` を付けると、`~/Applications/Poko.app` に入る。
動いている Poko は先に終了させてから入れ替える。
Dock に置くには、開いている間に Dock のアイコンを右クリックし、オプション → Dock に追加 を選ぶ。
同じメニューの「ログイン時に開く」で、Mac を起動したときに開くようにもできる。

1. 初回は「アクセシビリティ」と「マイク」の許可を求められるので、両方許可する。
   アクセシビリティは システム設定 → プライバシーとセキュリティ → アクセシビリティ で Poko をオンにする。
2. **右⌘ を押している間に話し、離す**。
   認識した文がカーソルの位置に貼り付けられる。
3. キーは メニュー → キー で `fn` にも変えられる。
   ただし、システム設定 → キーボード の「🌐キーを押して」が「何もしない」以外だと、絵文字の窓や macOS の音声入力も同時に動く。
   そのため既定は右⌘にしている。

- 押してすぐ（0.3 秒未満で）離したときと、押している間にほかのキーが入ったとき（右⌘+C など）は、録った音を捨てる。
- 言い終わりと同時に離しても語尾が切れないよう、離してからも 0.2 秒だけ録り続ける。
- 1 回に録れるのは 3 分まで。3 分経つと、離すのを待たずに認識して貼る。
- 貼り付けにはクリップボードを一瞬借りる。元の中身は 0.5 秒後に戻す。
- 文字を入れられる場所がなかったときなど、貼れなかったときは、メニュー → 最後の結果をコピー で取り出せる。
- Dock のアイコンを押すと、メニューバーと同じメニューが開く。
  Poko は起動したときと、このメニューを閉じたときに隠れて、前に使っていたアプリに戻る（前に残ると、話した文の貼り先がなくなるため）。

## メニューバーのアイコン

| 形 | 意味 |
|---|---|
| 静かな波形 | 待っている |
| 薄い波形 | 準備ができていない（許可かモデルが足りない。理由はメニューの1行目） |
| 点が並ぶ → 声に合わせて伸びる | 聴いている |
| 点の上を波が渡る | 文字にしている |
| 一瞬跳ねて波形に戻る | 貼り終えた |
| 真ん中が「!」 | 失敗した（理由はメニューの1行目。4 秒で元に戻る） |

## モデルの置き場所

モデルは speech.cpp の既定のフォルダ `~/Library/Caches/speech.cpp/models` に置く。
環境変数 `SPEECH_MODEL_DIR` があれば、そのフォルダに置く。
Poko のほかに speech.cpp を使うアプリやコマンドも、同じモデルを取り直さずに使える。

```bash
speech asr haas-ja-v1.0 voice.wav   # ほかの場所から使う例
```

Poko はリポジトリの `models/` に張ったリンクを通して、このファイルを読む。
リンクは `setup.sh` が張る。
`~/Library/Caches` の中身が消えたときは、`setup.sh` を実行し直す。

## 許可をやり直す

`build-app.sh` は簡易署名（ad-hoc）でアプリを作る。
macOS はこの署名を「別のアプリ」とみなすので、**ビルドし直すとアクセシビリティの許可が効かなくなる**。
システム設定の一覧ではオンのままでも、キーに反応しない。
そのときは、次を実行してから Poko を起動し直し、もう一度許可する。

```bash
tccutil reset Accessibility dev.haruka.poko
```

ビルドし直すたびにこれをするのが面倒なら、自己署名のコード署名用の証明書を1つ作り、その名前を渡してビルドする。
証明書は キーチェーンアクセス → 証明書アシスタント → 証明書を作成 で、種類を「コード署名」にして作る。
署名が変わらないので、許可は1回で済む。

```bash
POKO_SIGN_IDENTITY="Poko Local" ./scripts/build-app.sh --install --open
```

## 仕組み

```
右⌘を押す ─→ マイク（AVAudioEngine）─→ 16 kHz・16 bit ─→ speech asr Haas --vad Silero -（標準入力）
                                                              │ 話している区間ごとに認識して1行ずつ返す
右⌘を離す ─→ 標準入力を閉じる ─→ 最後の区間だけ認識 ─→ 行をつなぐ ─→ ⌘V で貼る
```

右⌘を押した時点で `speech asr` を起動し、録りながら音を流す。
speech.cpp は Silero VAD で区間（最長 10 秒）を見つけるたびに、その区間を認識する。
そのため、離したときに残っているのは最後の区間だけになる。
長く話しても、離してから貼るまでは 0.1 秒ほど（M4）。

Haas（FastConformer）は、複数の文を一度に渡すと文がまるごと抜けることがあり、計算量も長さの2乗で増える。
区間に分けて認識するのはそのためだ。

区間の終わりに句読点がないときは、「、」でつなぐ（`Transcript.swift`）。
区間は 0.5 秒の無音で切れ、言いよどみでも切れるので、「。」にはしない。

起動時に一度、短い雑音を VAD なしで認識させ、最初に話す前に Metal の準備を済ませる。
初めての Mac や OS の更新後は、この準備に十数秒かかる。

モデルはファイルの場所で渡すので、speech.cpp がネットからモデルを取りに行くことはない。
ネットにつながるのは `setup.sh` だけだ。
ネットワークを `sandbox-exec` で塞いだ中でも、アプリと同じ呼び方で認識できることを確かめてある。

## 構成

| ファイル | 役割 |
|---|---|
| `PokoApp.swift` | 起動し、部品をつなぐ（キー → 録音 → 認識 → 貼り付け）。許可の確認 |
| `PushToTalk.swift` | 押す、離す、ほかのキー、上限から、「録る、捨てる、認識する」を決める（副作用なし） |
| `HotKey.swift` | 右⌘ と fn の押し離しを、どのアプリを使っていても受け取る |
| `Recorder.swift` | マイクの音を 16 kHz、16 bit に変える。声の大きさも出す |
| `Transcription.swift` | 1 回の録音につき `speech asr` を1つ動かし、音を流して結果を受け取る |
| `Transcript.swift` | 区間ごとの行を1つの文にまとめる |
| `Paster.swift` | クリップボードを借りて ⌘V を送り、元に戻す |
| `StatusIcon.swift` | メニューバーのアイコン（ばねで動く5本のバー）の動きと描画 |
| `MenuBar.swift` | メニューバーの項目とメニュー |
| `Permissions.swift` | アクセシビリティとマイクの許可 |

すぐ変えたくなりそうな値は次のとおり。

| 値 | 場所 | 既定 |
|---|---|---|
| 押し間違いとみなす長さ | `PushToTalk.minimumHold` | 0.3 秒 |
| 1 回に録れる長さ | `Poko.longest` | 180 秒 |
| 離してから録り続ける長さ | `Poko.tail` | 0.2 秒 |
| クリップボードを戻すまで | `Paster.restoreDelay` | 0.5 秒 |
| 区間のつなぎ方 | `Transcript.join` | 句読点がなければ「、」 |
| VAD の閾値など | `Transcription` の `process.arguments` に `--threshold` `--min-silence-duration-ms` などを足す | speech.cpp の既定 |

## 開発

```bash
./scripts/test.sh                       # 単体テスト（押し離しの判定、行のつなぎ方、アイコンの動き）
POKO_HOME=$PWD POKO_TEST_WAV=voice.wav ./scripts/test.sh   # 本物の speech.cpp で認識するテストも走らせる（16 kHz、16 bit、モノラルの WAV）
POKO_HOME=$PWD POKO_TEST_WAV=voice.wav POKO_TEST_AUDIO=voice48k.wav ./scripts/test.sh  # マイクの形式からの変換も確かめる
./tools/render-icon.sh                  # メニューバーのアイコンの全状態をコマ送りで build/icon-frames.png に描く（明暗、1x と 2x）
./tools/render-app-icon.sh              # アプリのアイコン Resources/AppIcon.icns を、正方形の絵 Resources/AppIcon.png から作り直す
```

- ビルドは SwiftPM を使わず、`swiftc` で直接行う。`Package.swift` は Xcode で開くためのもの。
- アプリはビルドしたフォルダ（`Info.plist` の `PokoHome`）の `vendor/speech` と `models/` を使う。
  `~/Applications` に入れたアプリも同じで、フォルダを動かしたらビルドし直す。
  `POKO_HOME=<フォルダ>` を付けて起動すると、別の場所を使える。
- speech.cpp を上げるときは、`scripts/setup.sh` の `VERSION` を変えて実行し直す。
- アプリのアイコンの絵は自作アプリで共通の黒いスライム（`~/workspace/dev/brand/black-slime`）から描いた。描き方とほかの案はそちらの README にある。

## ライセンス

Poko は MIT License で公開している（[LICENSE](LICENSE)）。

`setup.sh` が取ってくるものは Poko に含まれず、それぞれのライセンスに従う。

| もの | ライセンス |
|---|---|
| [speech.cpp](https://github.com/nyosegawa/speech.cpp) | MIT |
| [Haas-ja-v1.0](https://huggingface.co/sakasegawa/Haas-ja-v1.0-GGUF) | Apache-2.0 |
| [Silero VAD](https://huggingface.co/sakasegawa/silero-vad-GGUF) | MIT |
