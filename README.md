# just a moment

メール・Slack などのコミュニケーションで、送る前に「ちょっと待って」と一拍おくための macOS ネイティブアプリ。

実際の入力フォーム／受信画面の **手前に擬似的な中間レイヤー（ステージング）を物理的に挟み**、
AI レビューを通してから本番（ライブ）へ「デプロイ」する。システム開発の
「ステージングで確認してから本番投下」を、人間のコミュニケーションに持ち込む発想。

最終的には双方向（送信レビュー／受信翻訳）で、認知モデル・能力・発達特性・精神状態の
ギャップを越えてコミュニケーションするための共通レイヤーを目指す。

## 現在のスコープ（MVP）

**送信側レビュー**。**メニューバー常駐アプリ**（起動時はウィンドウなし／Dock アイコンなし）。

操作（Command 中心で完結）:
- **⌘⌘（2回タップ）= 次へ**: 状態に応じて 呼び出し → レビュー → デプロイ。Enter も同義。Esc でキャンセル。
- **⌘ 長押し = 喋る（ASR）**: 押している間だけ録音し、離すと Groq `whisper-large-v3` で文字起こししてステージングに挿入（hold-to-talk）。
- ⌘J は単純なパネル開閉。

フロー:
1. 任意のアプリのフォームにフォーカス → **⌘⌘** でパネルが画面中央に出現（入力欄に自動フォーカス）
2. 入力（手入力／ペースト／**⌘長押しで音声**）。モデルは入力パネルのプルダウンで選択
3. 「レビュー」で ①誤字脱字 ②失礼・攻撃的 ③分かりにくさ の3観点を評価（結果右上に使用モデルと処理時間 ms）
4. デプロイ:
   - **左「原文をデプロイ」** = レビューを使わず原文のまま
   - **右「レビュー結果をデプロイ」** = 修正後（編集可）
   - いずれも**呼び出し元のフィールドへ自動入力（⌘V 合成）**。Gmail・Slack・Mail・Notion など汎用に動く。

> 自動送信はしない。最終判断は常に人間が行う。メニューバーアイコンから設定・終了。

### 必要な権限
- **アクセシビリティ**: フィールド自動入力（⌘V 合成）と ⌘ ジェスチャ検出に必要。
- **マイク**: ⌘ 長押しの音声入力に必要。
（いずれもシステム設定 → プライバシーとセキュリティ で just a moment を許可。未許可でもテキストはクリップボードに残り手動 ⌘V 可。）

## 技術スタック

- Swift / SwiftUI（macOS 14+）。**メニューバー常駐（`NSApp.setActivationPolicy(.accessory)` + `MenuBarExtra`）**、起動時ウィンドウなし。
- レビュー: OpenAI／Groq は OpenAI 互換 Chat Completions を [`OpenAICompatibleClient`](JustAMoment/Services/OpenAICompatibleClient.swift) で共用、Anthropic は [`ClaudeClient`](JustAMoment/Services/ClaudeClient.swift)。構造化出力は OpenAI=json_schema strict／Groq=json_object／Claude=Tool Use。`ReviewProvider` で抽象化。
- **音声入力（ASR）**: [`AudioRecorder`](JustAMoment/Services/AudioRecorder.swift)（AVAudioRecorder, 16kHz mono m4a）＋ [`GroqTranscriber`](JustAMoment/Services/GroqTranscriber.swift)（Groq `whisper-large-v3`, multipart）。⌘長押しで録音→離すと文字起こしして draft に挿入。
- **ジェスチャ**: [`CommandGestureMonitor`](JustAMoment/Services/CommandGestureMonitor.swift) が ⌘ の 2回タップ（=次へ）と長押し（=音声）を判定。⌘J は Carbon `RegisterEventHotKey`。
- **注入**: [`PasteDeployer`](JustAMoment/Services/PasteDeployer.swift) がクリップボード＋⌘V 合成で元フィールドへ。`Deployer` で抽象化（将来 Accessibility 注入に差し替え可）。
- 効果音: マイク ON/OFF の cue は AudioServices システムサウンド（`Tink`/`Pop`）。※終了音は既知の不具合により現在無効化（後述）。
- API キーは vendor 別に Keychain に保存（リポジトリには含めない）。署名は Apple Development 証明書で固定（Keychain の「常に許可」がリビルド後も持続）。
- プロジェクトは [XcodeGen](https://github.com/yonaskolb/XcodeGen) で生成。マイク権限は `INFOPLIST_KEY_NSMicrophoneUsageDescription`。

## レビューモデル

入力パネルのプルダウン、または設定（Cmd+,）から選択。カタログは
[`ReviewModel.catalog`](JustAMoment/Models/AIProvider.swift) が単一の正本（追加は1行）。
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
open JustAMoment.xcodeproj

# もしくは CLI でビルド
xcodebuild -project JustAMoment.xcodeproj -scheme JustAMoment -configuration Debug build
```

初回起動後、設定（Cmd+,）で Claude API キーを登録する。

## Known issues（凍結中の残タスク）

### 🧊 音声入力の「終了音」が3〜4回エコー（凍結）

**症状**: ⌘長押し→離した時の終了音（poko）が、残響のように3〜4回重なって鳴る（0.5秒ほどの間に連続）。開始音（pico）はクリーン。

**現状の対処**: 終了音を**無効化**（[`AppDelegate.swift`](JustAMoment/AppDelegate.swift) の `stopDictationAndTranscribe` 内、`recorder.onFinish = { SoundFeedback.recordingStopped() }` をコメントアウト）。開始音は有効。1行戻せば再現する。

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
  （[`ReviewPrompt.swift`](JustAMoment/Resources/ReviewPrompt.swift)）。
- **署名**: アドホック署名だとビルドごとに Keychain が再確認してくるため、Apple Development
  証明書での固定署名に変更。

## フィードバック / TODO

- few-shot 例は**実際に使った before→after** を追加していくのが最も効く。良い実例が出たら追記する。
- 速度計測（ms）は結果右上に表示。ネットワーク往復が支配的で計測コストは無視できる。
