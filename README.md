# Poko

キーを押しながら話して離すと、いま使っているアプリのカーソル位置に文字が入る、日本語の音声入力。
macOS 14 以降の Apple Silicon の Mac で動く。

- アプリは 2.3 MB と軽く、macOS の部品だけで組んである（依存するライブラリはない）。
  待っている間はアプリ1つだけが動き、CPU は 0%、メモリは 10 時間動かしたあとで約 55 MB だった。
  認識の `speech asr` はキーを押したときだけ起動し、貼り終えたら終わる。
  長く話しても、離してから 0.1 秒ほどで貼れる（M4、推敲しないとき）。
- 認識はこの Mac の中で完結し、音声は外に送らない。
  要るのは speech.cpp（66 MB）と認識のモデル（0.66 GB）だけで、アカウントも API キーも要らない。
  ネットにつながるのは、最初にそれらを取ってくる `setup.sh` だけだ。
- 固有名詞や略語は、辞書に書き方と読みを足すと、その書き方で出る（合成音声で試すと、boc → PoC、mtg → MTG になった）。
- 認識した文から「えー」「あの」などを消して貼る推敲もできる（既定はしない）。
  Mac の中の Gemma 4（約 5 GB を足す）なら、文字も外に出ない。
  Claude や ChatGPT のサブスクでもでき、そのときだけ文字と辞書をその会社に送る。
  その場合も Poko は API キーもトークンも持たず、ログイン済みの公式 CLI に頼む。

名前は、話すと文字が「ぽこっ」と出ることから付けた。
メモ帳の [Mogu](https://github.com/pienmalu/mogu/tree/personal) と対になる。
認識には [speech.cpp](https://github.com/nyosegawa/speech.cpp) と Haas-ja-v1.0（Q8_0）を使う。

アプリは Dock とメニューバーに出る。
Dock のアイコンを押すと、話した文の履歴と辞書の窓が開く。

## 使い方

```bash
./scripts/setup.sh                        # 最初に1回。speech.cpp 0.10.1 と、モデル（0.66 GB）を取ってくる
./scripts/setup.sh --llm                  # 推敲を Mac の中でするときだけ。llama.cpp と Gemma 4 E4B（約 5 GB）も取ってくる
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
- Dock のアイコンを押すと、窓が開く（メニュー →「履歴を開く」「辞書を開く」でも開く）。
  Poko は起動したときと、窓を閉じたときに隠れて、前に使っていたアプリに戻る（前に残ると、話した文の貼り先がなくなるため）。
- 窓が前にある間に話した文は、貼らずに窓にだけ出す。

## 履歴と辞書の窓

上の切り替えで「履歴」と「辞書」を行き来する（⌘1、⌘2）。

- **履歴**: 話した文が新しい順に並ぶ。文は選んでコピーでき、右クリックで推敲する前の文もコピーできる。
  Poko を起動してからの 200 件まで。
  ディスクには書かないので、終了すると消える。
- **辞書**: 固有名詞や略語を、書き方と読みの組で足す（⌘N で足す、⌫ で消す）。
  変えたらすぐ保存し、次に話したときから効く。
  下の帯に最後の結果が出るので、語を足してそのまま話して試せる。
  ⚠︎ は、その語が効きにくそうな理由（指を載せると出る）。

## 固有名詞と略語の辞書

認識に使う Haas-ja-v1.0 には、書き方と読みを渡すと、その読みに聞こえた所をその書き方で書く機能がある（speech.cpp の `--keywords`）。
Poko の辞書はこれに渡す。

| 書き方 | 読み | 辞書なし → 辞書あり（合成音声で試した例） |
|---|---|---|
| PoC | ぴーおーしー | boc → PoC |
| MTG | えむてぃーじー | mtg → MTG |
| Silero | しれろ | シレロ → Silero |

- 読みはひらがなかカタカナで書く。いくつもあるときは「、」で区切る。
  読みがない語はほとんど効かず、別の所が置き換わることもあった。
- 読みが短い語や、読みが普通の言葉の一部になる語は、その言葉の中でも置き換わる。
  「もぐ」を Mogu にすると「もぐもぐ」が MoguMogu に、「はいく」を Haiku にすると「それはいくら」が「それHaikuら」に、「ろーら」を LoRA にすると「コントローラ」が「コントLoRA」になった。
  効かせる強さを下げても変わらなかった。
- 語を足したら、その語を含まない普段の文も話してみて、関係のない所が変わらないかを見る。
  語が多いほど、こうした化け方は増える（50 語ほどで試すと、強さ 3 では 15 文に 1 つほど、強さ 2 では 100 文に 1 つほど化けたので、強さを 2 にした）。
- 漢字の語は認識だけでは効きにくいことがある。
  鷲生（わしお）は「鷲尾」のままだった（試した漢字の語はこの1つだけ）。
  推敲を使うと、辞書を用語集として LLM にも渡すので、同じ読みの別の字はそこで直る（Mac の中の Gemma 4 で、鷲尾 → 鷲生 に直った）。
- 推敲に Claude か ChatGPT を選んでいると、辞書の全部を、話した文と一緒に毎回送る。
- ファイルは `~/Library/Application Support/Poko/dictionary.txt`。1行に1語、「書き方=読み,読み」で、手で直してもよい（窓を開くと読み直す）。
  辞書の画面の右下のフォルダのボタンで、Finder に出せる。
- 本人の声ではまだ試していない。
  上の例はどれも `say` の声で試したもの。

## 推敲

メニュー → 推敲 で、認識した文を貼る前に整えさせられる。
「えー」「あの」「えっと」などのフィラーと言い直しを消し、句読点を整える。
言いたいことと文体は変えない。

| 選ぶもの | どこで | 離してから貼るまで（M4 で測った値） | 要るもの |
|---|---|---|---|
| しない（既定） | ― | 0.1 秒ほど | ― |
| Mac の中の Gemma 4 | Mac の中。文字は外に出ない | 1 秒ほど | `./scripts/setup.sh --llm` |
| Claude | Anthropic に文字と辞書を送る | 3〜5 秒 | Claude Code（`claude`）に、サブスクでログインしておく |
| ChatGPT | OpenAI に文字と辞書を送る | 4〜5 秒 | Codex（`codex`）に `codex login` で、ChatGPT でログインしておく |

- Gemma は常には動かさない。キーを押して 0.3 秒経ったら読み込み始め（1〜4 秒）、話している間に用意する。
  2 分使わなければ止めて、メモリ（約 5 GB）を返す。
  そのため、しばらく使っていないときに 2 秒より短く話すと、読み込みを待つ分だけ遅れる。
  Mac で初めて動かすときは、Metal の準備で十数秒かかる。
- Claude と ChatGPT はログイン済みの公式 CLI（`claude -p`、`codex exec`）を1回ごとに起動して頼む。
  Poko は API キーもトークンも持たない。
  CLI の場所は、ターミナルと同じものを使うよう、起動したときにログインシェルに尋ねる。
  違うものを使わせたいときは `defaults write dev.haruka.poko codexPath /path/to/codex`（`claudePath` も同じ）。
  使うモデルは `LLM.swift` の `SubscriptionLLM` にある（Claude は Sonnet、ChatGPT は gpt-6-luna の推論なし）。
- このように CLI を自分のアプリから呼ぶ使い方が、各社のサブスクの規約で認められているかは確かめていない。
- 推敲が終わって貼るまでは、次の録音を始めない（貼る順番が入れ替わらないように）。
  その間にほかの場所をクリックすると、クリックした先に貼られる。
- 推敲が失敗したとき、時間内に終わらなかったとき（Gemma は 30 秒、サブスクは 10 秒）、答えが変なとき
  （元の文よりずっと長い、など。中身の質問に答えてしまったとみなす）は、元の文を貼り、理由をメニューの1行目に出す。
- 推敲する前の文はメニュー → 推敲する前の文をコピー で取り出せる。

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
Poko 自身がネットにつながるのは `setup.sh` だけだ（推敲に Claude か ChatGPT を選んだときは、その CLI がつながる）。
ネットワークを `sandbox-exec` で塞いだ中でも、アプリと同じ呼び方で認識できることを確かめてある。

推敲を選んでいると、行をつないだ文を貼る前に推敲に回す（`Polish.swift`）。
Gemma は `llama-server` を `127.0.0.1` だけで待ち受けさせて頼む。

## 構成

| ファイル | 役割 |
|---|---|
| `PokoApp.swift` | 起動し、部品をつなぐ（キー → 録音 → 認識 → 貼り付け）。許可の確認 |
| `PushToTalk.swift` | 押す、離す、ほかのキー、上限から、「録る、捨てる、認識する」を決める（副作用なし） |
| `HotKey.swift` | 右⌘ と fn の押し離しを、どのアプリを使っていても受け取る |
| `Recorder.swift` | マイクの音を 16 kHz、16 bit に変える。声の大きさも出す |
| `Transcription.swift` | 1 回の録音につき `speech asr` を1つ動かし、音を流して結果を受け取る |
| `Transcript.swift` | 区間ごとの行を1つの文にまとめる |
| `Polish.swift` | 推敲の選択、頼み方、返ってきた文の確かめ方。失敗したら元の文を返す |
| `LLM.swift` | 文字の LLM を呼ぶ口（Gemma の llama-server を必要なときだけ起動する部分と、claude と codex の CLI）。ほかのアプリからも使えるよう、単独で動く |
| `Paster.swift` | クリップボードを借りて ⌘V を送り、元に戻す |
| `StatusIcon.swift` | メニューバーのアイコン（ばねで動く5本のバー）の動きと描画 |
| `MenuBar.swift` | メニューバーの項目とメニュー |
| `MainWindow.swift` | 窓（履歴と辞書）。SwiftUI の標準の部品だけで組む |
| `Activity.swift` | 窓に出す、いまの状態と認識結果（メモリだけ） |
| `Vocabulary.swift` | 辞書の読み書きと、認識と推敲に渡す形への変換 |
| `Permissions.swift` | アクセシビリティとマイクの許可 |

すぐ変えたくなりそうな値は次のとおり。

| 値 | 場所 | 既定 |
|---|---|---|
| 押し間違いとみなす長さ | `PushToTalk.minimumHold` | 0.3 秒 |
| 1 回に録れる長さ | `Poko.longest` | 180 秒 |
| 離してから録り続ける長さ | `Poko.tail` | 0.2 秒 |
| クリップボードを戻すまで | `Paster.restoreDelay` | 0.5 秒 |
| 区間のつなぎ方 | `Transcript.join` | 句読点がなければ「、」 |
| Gemma を止めるまで | `LocalLLM.idleLimit` | 2 分 |
| 辞書を効かせる強さ | `Transcription.keywordsAlpha` | 2（speech.cpp の既定と同じ。50 語ほどの辞書では、普段の文が 3 で 15 文に 1 つほど、2 で 100 文に 1 つほど化けた） |
| 推敲を待つ上限 | `Polisher.localTimeout` / `subscriptionTimeout` | 30 秒 / 10 秒 |
| 推敲の指示 | `PolishPrompt.system` | フィラーと言い直しを消し、句読点を整える |
| VAD の閾値など | `Transcription` の `process.arguments` に `--threshold` `--min-silence-duration-ms` などを足す | speech.cpp の既定 |

## 開発

```bash
./scripts/test.sh                       # 単体テスト（押し離しの判定、行のつなぎ方、アイコンの動き）
POKO_HOME=$PWD POKO_TEST_WAV=voice.wav ./scripts/test.sh   # 本物の speech.cpp で認識するテストも走らせる（16 kHz、16 bit、モノラルの WAV）
POKO_HOME=$PWD POKO_TEST_WAV=voice.wav POKO_TEST_AUDIO=voice48k.wav ./scripts/test.sh  # マイクの形式からの変換も確かめる
POKO_HOME=$PWD POKO_TEST_WAV=voice.wav POKO_TEST_KEYWORDS=dictionary.txt ./scripts/test.sh  # 辞書を付けて認識する
./tools/render-window.sh                # 窓をライトとダーク、空と中身ありで build/window/ に PNG で描く（画面収録の許可がないと中身だけ）
POKO_HOME=$PWD POKO_TEST_LLM=local,claude,chatgpt ./scripts/test.sh   # 本物の LLM で推敲する（claude と chatgpt は文字を送る）
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
| [llama.cpp](https://github.com/ggml-org/llama.cpp)（`--llm` のとき） | MIT |
| [Gemma 4 E4B](https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF)（`--llm` のとき） | Apache-2.0 |
