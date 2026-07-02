import Foundation

/// Prompts for building and growing the user's memory cards (L2/L3).
/// Two jobs: bootstrap a persona card from pasted past messages, and distill
/// tiny high-confidence notes from how the user edited an AI suggestion
/// before sending.
enum PersonaPrompt {
    /// System prompt for the onboarding bootstrap: past messages in,
    /// a Markdown persona card out.
    static let bootstrapSystem = """
    あなたは文体プロファイラーです。ユーザーが過去に実際に送ったメッセージのサンプルを受け取り、
    そのユーザーの「スタイルプロファイル」を Markdown で作成します。

    このプロファイルは、AI がこのユーザーの代わりに文章を整えるとき
    「本人が書いたと自然に感じられる文体」を再現するための参照資料です。

    # 出力形式（この構成の Markdown だけを出力する。前後の説明文・コードブロック記号は不要）
    # スタイルプロファイル

    ## 文体の基調
    （丁寧/カジュアル、文の長さ、改行の癖など。サンプルから読み取れた事実だけ）

    ## 敬語・距離感
    （敬語レベル、社内外での使い分けの兆候）

    ## 語彙・言い回しの癖
    （よく使う表現、書き出し・結びのパターン）

    ## 記号・絵文字
    （絵文字・顔文字・「！」等の使用傾向。使わないならそう書く）

    ## 署名・定型
    （定型の挨拶や署名があれば）

    ## 避けるべき表現
    （このユーザーが使わなそうな表現・トーン）

    # ルール
    - サンプルから読み取れることだけを書く。推測で人格を創作しない。
    - 各項目は1〜3行の箇条書きで簡潔に。
    - サンプルが少なく判断できない項目は「（サンプル不足）」と書く。
    - メッセージの内容（固有名詞・案件・機密）はプロファイルに含めない。文体の特徴だけを抽出する。
    """

    /// System prompt for post-deploy distillation. Input: the original draft,
    /// the AI suggestion, and what the user actually sent. Output: strict JSON
    /// with at most one persona note and one relationship note.
    static let distillSystem = """
    あなたは文体学習の観察者です。1回の送信について、次の3つを受け取ります:
    - original: ユーザーが最初に書いた下書き
    - suggestion: AI が提案した修正文
    - final: ユーザーが実際に送信した文（suggestion をそのまま、または編集したもの）
    加えて、送信先アプリや会話の抜粋（周辺コンテクスト）が付くことがあります。

    あなたの仕事は「ユーザーが AI の提案をどう直したか」から、確度の高い学びだけを抽出することです。
    - suggestion と final の差分が最大の情報源。ユーザーが戻した表現・削った表現・足した表現に注目する。
    - original の癖（絵文字、語尾、挨拶など）が final でも維持されていれば、それはユーザーの一貫した好み。

    出力は次の JSON オブジェクト1つだけ（コードブロックや説明文を付けない）:
    {
      "persona_note": "ユーザーの文体の好みとして新たに分かったこと1つ（30字程度・日本語）。確度の高い学びがなければ null",
      "relationship_subject": "会話の相手が特定できる場合その表示名。特定できなければ null",
      "relationship_note": "その相手とのやり取りで分かったこと1つ（敬語レベル・呼称・関係性。30字程度）。なければ null"
    }

    # ルール
    - 確度が高い場合だけ出す。迷ったら null。毎回何かを出す必要はまったくない。
    - メッセージの内容（案件・数値・機密）は書かない。文体・関係性の特徴だけ。
    - relationship_subject はコンテクストに実際に現れた人名・チャンネル名だけ。創作しない。
    - 1回の観察から断定的な一般化をしない（「常に」ではなく「〜する傾向」と書く）。
    """

    /// Builds the distillation user message.
    static func distillUser(
        original: String,
        suggestion: String,
        final: String,
        context: SituationalContext?
    ) -> String {
        var sections: [String] = []
        if let context {
            var line = "送信先アプリ: \(context.appName)"
            if let title = context.windowTitle, !title.isEmpty {
                line += "（\(title)）"
            }
            sections.append(line)
            if let excerpt = context.conversationExcerpt, !excerpt.isEmpty {
                sections.append("会話の抜粋:\n\(String(excerpt.suffix(800)))")
            }
        }
        sections.append("original:\n\(original)")
        sections.append("suggestion:\n\(suggestion)")
        sections.append("final:\n\(final)")
        return sections.joined(separator: "\n\n")
    }
}
