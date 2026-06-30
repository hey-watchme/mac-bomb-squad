# BOMB SQUAD

メール・Slack などのコミュニケーションで、送る前に「ちょっと待って」と一拍おくためのアプリ。会話のサンドボックス。受信したメッセージにも適用できるフィルター。macOS ネイティブアプリ版。

実際の入力フォーム／受信画面の **手前に擬似的な中間レイヤー（ステージング）を物理的に挟み**、
AI レビューを通してから本番（ライブ）へ「デプロイ」する。システム開発の
「ステージングで確認してから本番投下」を、人間のコミュニケーションに持ち込む発想。

最終的には双方向（送信レビュー／受信翻訳）で、認知モデル・能力・発達特性・精神状態の
ギャップを越えてコミュニケーションするための共通レイヤーを目指す。

## 現在のスコープ（MVP）

**送信側レビュー**。**メニューバー常駐アプリ**（起動時はウィンドウなし／Dock アイコンなし）。

macOS の画面構成方針:
- 普段はメニューバーに常駐し、常設の大きな管理ウィンドウは出しっぱなしにしない。
- 右Shift 2回で出る入力補助は、軽い一時パネルとして扱う。
- アカウント、設定、履歴、料金プランは、メニューバーまたは入力補助パネル内の操作から必要な時だけ開く通常ウィンドウに分ける。
- 入力補助のたびに管理ウィンドウへ勝手にフォーカスを移さない。
- Google 認証やメールリンク認証の途中だけは、ブラウザやメールへ移動してもログイン画面を閉じない。

操作（右Shift 中心で完結）:
- **右Shift 2回タップ = 次へ**: 状態に応じて 呼び出し → レビュー → 送信確定。Esc でキャンセル。
- **右Shift 長押し = 喋る（ASR）**: 押している間だけ録音し、離すと Groq `whisper-large-v3` で文字起こしして原文欄に挿入（hold-to-talk）。
- **Enter = 送信**: カーソルがある側を直接送信（原文欄なら原文、レビュー欄ならレビュー結果）。Shift+Enter は改行。
- ⌘J は単純なパネル開閉。

> 喋る・次へを ⌘ から **右Shift に統一**したのは、⌘ が日常のショートカット（⌘C/⌘V 等）と衝突し、保持した瞬間に誤発火していたため。右Shift は単独で握ることが稀で、覚えやすいよう両ジェスチャを同じキーに揃えた。

フロー:
1. 任意のアプリのフォームにフォーカス → **右Shift2回** でパネルが画面中央に出現（入力欄に自動フォーカス）
2. 入力（手入力／ペースト／**右Shift長押しで音声**）。モデルは入力パネルのプルダウンで選択
3. 「レビュー」で ①誤字脱字 ②失礼・攻撃的 ③分かりにくさ の3観点を評価（結果右上に使用モデルと処理時間 ms）
4. 送信:
   - **左「送信」（紙飛行機）** = レビューを使わず原文のまま
   - **右「送信」（紙飛行機）** = レビュー結果（編集可）
   - いずれも**呼び出し元のフィールドへ自動入力（⌘V 合成）**。Gmail・Slack・Mail・Notion など汎用に動く。

> 自動送信はしない。最終判断は常に人間が行う。メニューバーアイコンから設定・終了。

### 受信側（読解支援）— 送信側の鏡像

同じインターフェースを、相手から届いたメッセージの「読みやすく整理」に使う。コミュニケーションの
中間レイヤーは本来双方向で、不快・難解な受信文もこのレイヤーを通すことで安全に読み取れる。
発達特性・言語・能力面で読み取りに課題がある人の社会適応を支える、というアプリの主目的の受信側。

- **取り込み**: 任意のアプリ（Slack・Gmail 等）で相手のメッセージを**マウスで選択（反転）**した状態で
  **右Shift2回**。選択テキストが ⌘C 合成（[`SelectionGrabber`](BombSquad/Services/SelectionGrabber.swift)）で
  原文ペインに入る。**選択が無ければ**従来どおり空の原文ペイン（送信モード）になる＝1ジェスチャで自動分岐。
- **変換**: 右Shift2回で、攻撃性・感情・皮肉を除き「相手が何を求めているか（依頼・期限・事実）」を
  **要点を箇条書きで構造化**して右側に表示（[`ReviewPrompt.transformSystem`](BombSquad/Resources/ReviewPrompt.swift)）。
- **出口**: 相手のメッセージは絶対に書き戻さない。受信モードの「送信」は**クリップボードへコピーのみ**
  （[`ClipboardDeployer`](BombSquad/Services/Deployer.swift)）。引用・転送・保存に使える。

> 入力と出力で**システム調整や行動変容を求めず**、中間地点を加工するだけで結果を変えるのが本アプリの肝。
> 送信も受信も「選択 or 入力 → 加工 → そのまま使える」という同じ操作で成立する。当面は UI も共通
> （`ReviewMode.compose` / `.transform` で分岐）。将来は受信専用 UI に分ける余地あり。

> **受信はワンストップ**: 選択して右Shift2回でパネルが立ち上がると同時に変換が走り、右ペインに整理済みが
> 出る（第2のジェスチャ不要）。処理中は右ペインにスピナーを表示。

### 出力言語（検討中・暫定実装）

成果物（`revised_text` = 送る文／読みやすくした文）の言語を、右ペイン上部のプルダウンで選択する
（[`OutputLanguage`](BombSquad/Models/OutputLanguage.swift)、既定=日本語。現状は日本語／English）。
プロンプトに明示注入（[`ReviewPrompt.languageInstruction`](BombSquad/Resources/ReviewPrompt.swift)）するので、
**入力が何語でも `revised_text` は選択言語**になる（例: 日本語で書いて英語で送る／中国語をスキャンして日本語で読む）。
`issues` の説明・`summary` はユーザー向けメタなので日本語のまま。言語を変えると `needsReReview` が立ち、
**次の右Shift2回で選択言語に再変換**される。

> 暫定実装。言語の扱い（既定値の永続化、受信時の自動言語判定など）は引き続き検討。
> 現状は言語選択がセッション単位（パネルを開くたび日本語に戻る）。

### 必要な権限
- **アクセシビリティ**: フィールド自動入力（⌘V 合成）と右Shiftジェスチャ検出に必要。
- **マイク**: 右Shift長押しの音声入力に必要。
（いずれもシステム設定 → プライバシーとセキュリティ で Bomb Squad を許可。未許可でもテキストはクリップボードに残り手動 ⌘V 可。）

## 技術スタック

- Swift / SwiftUI（macOS 14+）。**メニューバー常駐（`NSApp.setActivationPolicy(.accessory)` + `MenuBarExtra`）**、起動時ウィンドウなし。
- レビュー: OpenAI／Groq は OpenAI 互換 Chat Completions を [`OpenAICompatibleClient`](BombSquad/Services/OpenAICompatibleClient.swift) で共用、Anthropic は [`ClaudeClient`](BombSquad/Services/ClaudeClient.swift)。構造化出力は OpenAI=json_schema strict／Groq=json_object／Claude=Tool Use。`ReviewProvider` で抽象化。
- **音声入力（ASR）**: [`AudioRecorder`](BombSquad/Services/AudioRecorder.swift)（AVAudioRecorder, 16kHz mono m4a）＋ [`GroqTranscriber`](BombSquad/Services/GroqTranscriber.swift)（Groq `whisper-large-v3`, multipart）。⌘長押しで録音→離すと文字起こしして draft に挿入。
- **ジェスチャ**: [`ShiftGestureMonitor`](BombSquad/Services/ShiftGestureMonitor.swift) が右Shift の 2回タップ（=次へ）と長押し（=音声）を判定（⌘ はショートカットと衝突するため右Shift に統一）。⌘J は Carbon `RegisterEventHotKey`。
- **注入**: [`PasteDeployer`](BombSquad/Services/PasteDeployer.swift) がクリップボード＋⌘V 合成で元フィールドへ。`Deployer` で抽象化（将来 Accessibility 注入に差し替え可）。
- **クリップボード退避・復元（暫定）**: 送信の ⌘V（[`PasteDeployer`](BombSquad/Services/PasteDeployer.swift)）と受信取り込みの ⌘C（[`SelectionGrabber`](BombSquad/Services/SelectionGrabber.swift)）はシステムのクリップボードを一時的に借りる。ユーザーが元々コピーしていた内容を壊さないよう、操作の直前に全アイテム・全タイプを退避し、合成ペースト／コピーが処理された後に復元する（[`ClipboardBackup`](BombSquad/Services/Deployer.swift)）。これは TextExpander・Alfred・Raycast・Espanso 等の入力支援ツールで確立した定番パターン。ただし退避・復元も合成ペースト／コピーも遅延ベースのため原理的に 100% 完全ではない（重いアプリでの取りこぼし、一部アプリ独自形式、他のクリップボード管理ツールとの併用など）。**本筋はロードマップの「Accessibility API で実フォームへ直接注入」**で、それが入ればクリップボードを一切触らなくなりこの仕組みは不要になる。なお受信モードの出口（[`ClipboardDeployer`](BombSquad/Services/Deployer.swift)）は「クリップボードへコピー」自体が機能のため復元しない。
- 効果音: マイク ON/OFF の cue は AudioServices システムサウンド（`Tink`/`Pop`）。※終了音には既知のエコー問題あり（後述）。
- API キーは vendor 別に Keychain に保存（リポジトリには含めない）。署名は Apple Development 証明書で固定（Keychain の「常に許可」がリビルド後も持続）。
- プロジェクトは [XcodeGen](https://github.com/yonaskolb/XcodeGen) で生成。マイク権限は `INFOPLIST_KEY_NSMicrophoneUsageDescription`。

## レビューモデル

入力パネルのプルダウン、または設定（Cmd+,）から選択。カタログは
[`ReviewModel.catalog`](BombSquad/Models/AIProvider.swift) が単一の正本（追加は1行）。
モデル名と処理時間（ms）はレビュー結果の右上に表示される。

| モデル | 役割 | 速度の目安 (TPS) | 料金 (1M tokens) | メモ |
|---|---|---|---|---|
| **Groq · gpt-oss-120b**（推奨・既定） | 意味理解＋トゲ取り | 〜500 tok/s（体感1〜2秒） | in $0.15 / out $0.60 前後 | 意味内容まで理解できる。現状の本命 |
| Groq · gpt-oss-20b | 高速整形のみ | 〜1000 tok/s（1秒未満） | in $0.075 / out $0.30 | 速いが**意味は把握しきれない**。整形専用なら可 |
| OpenAI · gpt-4.1-nano | 高速・非推論 | 速い | in $0.10 / out $0.40 前後 | OpenAI 最速クラス |
| OpenAI · gpt-4.1-mini | バランス | 中 | in $0.40 / out $1.60 前後 | 速度と品質の中間 |
| Claude · Sonnet 4.6 | 品質 | 遅め | 中〜高 | ニュアンス重視 |
| Claude · Opus 4.8 | 最高品質 | 遅い | 高 | 重要メッセージ向け |

> TPS・料金は公開情報からの概算。正確な値は各社の料金ページを参照。コストが効くのは
> 高頻度ユースのため、既定は安価・高速な Groq 系。

## セットアップ

```bash
# プロジェクトを生成
xcodegen generate

# Xcode で開く
open BombSquad.xcodeproj

# もしくは CLI でビルド
xcodebuild -project BombSquad.xcodeproj -scheme BombSquad -configuration Debug build
```

ローカル認証設定は、リポジトリ直下の `BombSquad.local.plist` から読み込む。
読み取り順は `BombSquad.local.plist` → Xcode Scheme の環境変数 →
`Info.plist`。

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>BOMB_SQUAD_SUPABASE_URL</key>
  <string>https://skcsbcyivjcvevxntvqa.supabase.co</string>
  <key>BOMB_SQUAD_SUPABASE_ANON_KEY</key>
  <string>YOUR_SUPABASE_ANON_KEY</string>
  <key>BOMB_SQUAD_API_BASE_URL</key>
  <string></string>
</dict>
</plist>
```

初回起動後、設定（Cmd+,）で Claude API キーを登録する。

認証方式:
- Google 認証
- メールリンク認証

メール認証はコード入力ではなく、メール本文のリンクをこの Mac で開く方式。

### 現在の認証仕様

Bomb Squad のログイン方法は、現時点では次の 2 つだけ。

- Google OAuth
- メールリンク認証

ここでいう「メールリンク認証」は、メールアドレス宛てに届くリンクを開いて
ログインを完了する方式。アプリ内で認証コードを入力する方式ではない。

Supabase SDK ではメールリンク送信にも `signInWithOTP(...)` という API 名を使うが、
これは SDK 名称の都合であって、Bomb Squad のユーザー体験が OTP 入力であることを
意味しない。実際の挙動は、Supabase 側のメールテンプレートで
`{{ .ConfirmationURL }}` を使っているか `{{ .Token }}` を使っているかで決まる。

Bomb Squad では Web も macOS も `{{ .ConfirmationURL }}` 前提で揃える。

## Known issues（凍結中の残タスク）

### アプリ名リネーム完了

アプリ名・プロジェクト名・ターゲット名・Bundle ID は `Bomb Squad` / `BombSquad` /
`com.heywatchme.bombsquad` に統一済み。Bundle ID と Keychain service が変わったため、
リネーム後の初回起動ではアクセシビリティ／マイク権限の再許可と API キーの再登録が必要。

### 🧊 音声入力の「終了音」が3〜4回エコー（凍結）

**症状**: ⌘長押し→離した時の終了音（poko）が、残響のように3〜4回重なって鳴る（0.5秒ほどの間に連続）。開始音（pico）はクリーン。

**現状**: 終了音は有効（[`AppDelegate.swift`](BombSquad/AppDelegate.swift) の `stopDictationAndTranscribe` 内、`recorder.onFinish = { SoundFeedback.recordingStopped() }`）。必要ならこの1行をコメントアウトするとエコーは消える。

**これまでの切り分け（すべて効果なし）**:
- 再生方式: `NSSound` → `AudioServicesPlaySystemSound` に変更 → 変化なし。
- タイミング: 停止前 / 停止直後 / 0.2秒遅延 / 完了デリゲート `audioRecorderDidFinishRecording` → いずれも変化なし。
- 多重発火の計測: `calls:1 / plays:1`（こちらは1回しか再生していない）。`isDictating` ガードでも変化なし。
- **終了音の呼び出しを完全に無効化 → エコー消滅**（＝音源は当該再生呼び出しで確定）。

**わかっていること**: 「1回の再生呼び出し」なのに3〜4回聞こえる＝**単一再生がスタッターしている**。開始音（マイク静止状態）は綺麗で、終了音（録音直後）だけ割れる**非対称**。録音サブシステムの状態と関係する疑いが濃いが、再生方式・タイミングをどう変えても不変なのが不可解。

**未検証の仮説（次に試す候補）**:
- 出力デバイス依存（複数出力／Bluetooth／集約デバイスで多重出力になっている可能性）。別の出力構成で再現するか確認。
- システム側の音（macOS Dictation 等）が ⌘ ジェスチャで誤起動していないか。
- AudioServices/NSSound を捨て、専用 `AVAudioPlayer`（事前ロード・常駐）で再生。
- 録音を完全に別プロセス／別オーディオセッションに分離。
- 「ビルド後の初回だけ音が割れる」別現象あり（出力側コールドスタートの疑い、実害は初回のみ）。

## ロードマップ（MVP の先）

- グローバルホットキー＋前面オーバーレイ（押している間だけ擬似入力欄）
- Accessibility API で実フォームへテキスト自動注入（`Deployer` 実装の差し替え）
- 受信側翻訳（ScreenCaptureKit + OCR / アクセシビリティ読み取り）
- ローカル LLM 対応（`ReviewProvider` 実装の差し替え）

## これまでの経緯（覚書）

- **コンセプト**: 送受信の「物理的な中間ステージング層」。送信は下書きをレビューしてからデプロイ、
  受信は攻撃的メッセージを要件だけに翻訳。認知モデルのギャップを埋める共通レイヤー。
- **MVP は送信側レビューから**着手（独立ウィンドウ、ホットキー/注入は後フェーズ）。
- **モデル遍歴**:
  1. Claude Sonnet 4.6 から開始 → 品質は高いが**遅い**。中間レイヤーには摩擦が大きい。
  2. OpenAI `gpt-4.1-mini` を追加（速度重視）。
  3. Groq `gpt-oss` を追加 → **1秒未満**の応答で速度は理想形。
- **モデル選定の知見（重要）**:
  - `gpt-oss-20b`: 速いが**文章の意味を理解しきれていない**。トゲ取りはできず、テニヲハ／
    丁寧文化どまり。→ **高速スタイリング専用**ならパイプラインの一部に使えるが、単体では不可。
  - `gpt-oss-120b`: **意味内容まで理解**できる。現状はこれが本命（既定）。
  - → 将来は「120b で意味を理解 → 20b で高速整形」のような**役割分担パイプライン**も検討余地。
- **プロンプト**: 当初の「最小限の介入」方針だとテニヲハ修正止まりだったため、
  「トゲ取りを最優先ミッション」に全面改訂。攻撃性の7パターン定義＋before→after の few-shot を追加
  （[`ReviewPrompt.swift`](BombSquad/Resources/ReviewPrompt.swift)）。
- **署名**: アドホック署名だとビルドごとに Keychain が再確認してくるため、Apple Development
  証明書での固定署名に変更。

## フィードバック / TODO

- few-shot 例は**実際に使った before→after** を追加していくのが最も効く。良い実例が出たら追記する。
- 速度計測（ms）は結果右上に表示。ネットワーク往復が支配的で計測コストは無視できる。
