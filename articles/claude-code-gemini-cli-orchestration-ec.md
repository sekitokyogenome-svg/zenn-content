---
title: "Claude Code × Gemini CLIをオーケストレーションしてEC分析を多角的に回す方法"
emoji: "✨"
type: "tech"
topics: ["bigquery","claude","gemini","ai","ec"]
published: false
---

## はじめに

「売上データは毎月Excelで集計しているが、どこに問題があるのかよくわからない」「GA4のレポートを見ても、次に何をすべきかピンとこない」——そう感じているEC担当者の方は少なくないのではないでしょうか。

近年、Claude CodeやGemini CLIといったAIアシスタントをコマンドラインから直接呼び出せるツールが登場し、データ分析の現場に大きな変化をもたらしています。それぞれのAIは得意な役割が異なるため、「複数のAIを組み合わせて使う」という発想が、分析の質とスピードを大きく引き上げてくれます。

本記事では、Claude CodeとGemini CLIを連携させた「オーケストレーション」の考え方を紹介します。GA4のBigQueryエクスポートデータをベースに、EC特有の購買分析・流入分析を多角的に実施する方法を、SQL例やスクリプト例を交えながら解説します。エンジニア以外の方にも理解いただけるよう、概念から順を追って説明していきます。

---

## Claude CodeとGemini CLIのオーケストレーションとは

「オーケストレーション」とは、複数のツールやサービスを指揮者のように束ねて協調動作させることを指します。ここでは、**Claude Code**（Anthropic社のCLI対話型AIエージェント）と**Gemini CLI**（Google DeepMind提供の対話型AIツール）を、それぞれの強みに応じて役割分担させることを意味します。

具体的には次のような役割分担が考えられます。

| 役割 | 担当AI |
|------|--------|
| SQLクエリの設計・修正・デバッグ | Claude Code |
| クエリ結果の自然言語での解釈・施策提案 | Gemini CLI |
| スクリプトのオーケストレーション制御 | bashまたはPython |

Claude Codeはコード生成・修正の精度が高く、複雑なSQLロジックの構築に向いています。一方、Gemini CLIはGoogleエコシステムとの親和性が高く、GA4・BigQueryの結果を自然な日本語で解釈・要約する用途に使いやすい側面があります。両者を使い分けることで、「分析の設計」と「ビジネス解釈」を分業できます。

---

## GA4 BigQueryエクスポートでEC分析に必要なSQL基礎

GA4のデータをBigQueryで扱う際には、テーブル構造への理解が欠かせません。特に以下の点は非エンジニアがつまずきやすい箇所です。

- `ga_session_id` はイベントパラメータのネスト構造の中にあるため、`UNNEST(event_params)` で展開して取得する必要があります
- 流入元（参照元・メディア）は `collected_traffic_source.manual_medium` および `collected_traffic_source.manual_source` カラムを参照します

以下は、セッションごとの流入元と購買有無を集計するSQLの例です。

```sql
-- GA4 BigQuery: セッション別流入元×購買フラグ集計
WITH session_base AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS ga_session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    MAX(IF(event_name = 'purchase', 1, 0)) AS has_purchase,
    SUM(IF(event_name = 'purchase',
      (SELECT value.double_value
       FROM UNNEST(event_params)
       WHERE key = 'value'), 0)) AS purchase_value
  FROM
    `your_project.analytics_XXXXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  GROUP BY
    user_pseudo_id,
    ga_session_id,
    medium,
    source
)
SELECT
  source,
  medium,
  COUNT(DISTINCT ga_session_id) AS sessions,
  SUM(has_purchase) AS purchases,
  ROUND(SUM(purchase_value), 0) AS total_revenue,
  ROUND(SAFE_DIVIDE(SUM(has_purchase), COUNT(DISTINCT ga_session_id)) * 100, 2) AS cvr_pct
FROM session_base
GROUP BY source, medium
ORDER BY total_revenue DESC
LIMIT 20;
```

このSQLをClaude Codeに「修正・拡張してほしい」と依頼すれば、商品カテゴリ別や日次トレンド別に素早くバリエーションを生成してもらえます。

---

## Claude Codeでクエリ設計、Gemini CLIで解釈を分担する

クエリの実行結果をCSVとして出力したあと、その内容をGemini CLIに渡して「ビジネス的な示唆」を導き出す流れが有効です。

以下はbashスクリプトでの連携イメージです。

```bash
#!/bin/bash
# 1. BigQueryでクエリを実行してCSVに保存
bq query \
  --use_legacy_sql=false \
  --format=csv \
  --max_rows=100 \
  'SELECT source, medium, sessions, purchases, cvr_pct
   FROM `your_project.analytics_XXXXXXXXX.session_summary`
   ORDER BY cvr_pct DESC LIMIT 20' \
  > /tmp/cvr_by_source.csv

# 2. Claude Codeにクエリ改善を依頼（例: 標準入力経由）
echo "以下のクエリ結果に対して、購買率が低い流入元を特定するためのSQLを追加提案してください" \
  | claude -p "$(cat /tmp/cvr_by_source.csv)" > /tmp/claude_suggestion.txt

# 3. Gemini CLIに解釈・施策提案を依頼
cat /tmp/cvr_by_source.csv \
  | gemini -p "このEC流入元別CVRデータをビジネス視点で解釈し、改善施策を3点提案してください（日本語で）" \
  > /tmp/gemini_insights.txt

echo "=== Claude Codeの提案 ===" && cat /tmp/claude_suggestion.txt
echo "=== Gemini CLIの解釈 ===" && cat /tmp/gemini_insights.txt
```

このように、**分析設計はClaude Code・ビジネス解釈はGemini CLI**という役割を明示的に分けることで、それぞれのAIの回答品質を引き出しやすくなります。

---

## Pythonで組むオーケストレーションの実践例

bashよりも複雑な制御が必要な場合は、Pythonでオーケストレーターを組むことも検討できます。以下はシンプルな例です。

```python
import subprocess
import json

def run_bq_query(sql: str) -> str:
    """BigQueryクエリを実行してJSON文字列で返す"""
    result = subprocess.run(
        ["bq", "query", "--use_legacy_sql=false", "--format=json", sql],
        capture_output=True, text=True
    )
    return result.stdout

def ask_claude(prompt: str, context: str) -> str:
    """Claude Codeにプロンプトを送って回答を取得"""
    full_prompt = f"{prompt}\n\nデータ:\n{context}"
    result = subprocess.run(
        ["claude", "-p", full_prompt],
        capture_output=True, text=True
    )
    return result.stdout.strip()

def ask_gemini(prompt: str, context: str) -> str:
    """Gemini CLIにプロンプトを送って回答を取得"""
    full_prompt = f"{prompt}\n\nデータ:\n{context}"
    result = subprocess.run(
        ["gemini", "-p", full_prompt],
        capture_output=True, text=True
    )
    return result.stdout.strip()

if __name__ == "__main__":
    sql = """
    SELECT
      source, medium,
      COUNT(DISTINCT ga_session_id) AS sessions,
      SUM(has_purchase) AS purchases
    FROM `your_project.analytics_XXXXXXXXX.session_summary`
    GROUP BY source, medium
    ORDER BY sessions DESC
    LIMIT 10
    """
    data = run_bq_query(sql)

    claude_resp = ask_claude(
        "このデータに対して、購買数を増やすための追加分析クエリを1つ提案してください",
        data
    )

    gemini_resp = ask_gemini(
        "このEC流入元データを見て、注力すべき施策を日本語で簡潔に教えてください",
        data
    )

    print("【Claude Codeの提案】")
    print(claude_resp)
    print("\n【Gemini CLIの解釈】")
    print(gemini_resp)
```

:::message
上記スクリプトはあくまで構成イメージです。実際の運用では、BigQuery接続情報・APIキーの管理や、エラーハンドリングを適切に追加してください。
:::

このスクリプトを定期実行（例: Cloud Schedulerやcron）に組み込むと、毎朝の分析レポート生成を自動化することも視野に入ってきます。

---

## 分析テーマの広げ方：EC特有のユースケース

Claude Code × Gemini CLIのオーケストレーションは、以下のようなEC特有の分析にも応用できます。

**カゴ落ち分析**
`add_to_cart` イベントはあるが `purchase` イベントがないセッションを抽出し、流入元・デバイスカテゴリ別にカゴ落ち率を比較します。Claude Codeにクエリを生成させ、Gemini CLIに「離脱しやすい属性の傾向と対策」を回答させます。

**リピート購買分析**
`user_pseudo_id` ごとに購買回数を集計し、初回購買から2回目購買までの平均日数を算出します。LTV向上施策の検討にそのまま使える洞察をGemini CLIに引き出すことができます。

**商品ページのCV貢献度分析**
`view_item` → `purchase` の遷移率を商品単位で集計し、CVに貢献している商品ページとそうでないページを可視化します。Claude Codeは集計SQLを、Gemini CLIは商品ページ改善の方向性をそれぞれ担います。

これらをテンプレート化しておくことで、月次・週次レポートのほぼ全工程をスクリプト一本に集約できるようになります。

---

## まとめ

本記事では、Claude CodeとGemini CLIを組み合わせたオーケストレーションによるEC分析の進め方を紹介しました。要点を整理します。

- **役割分担が鍵**：SQLの設計・修正はClaude Code、ビジネス解釈・施策提案はGemini CLIが向いている
- **GA4 BigQueryのSQL作法**：`ga_session_id` は `UNNEST(event_params)` 経由、流入元は `collected_traffic_source` カラムを使用する
- **bashまたはPythonでつなぐ**：シェルスクリプトやPythonで両AIへの問い合わせを順序制御することで、分析フローを自動化できる
- **ECの頻出テーマに適用**：カゴ落ち・リピート・商品貢献度など、EC固有の分析ニーズにそのまま転用できる

まずは手元のBigQueryに対してSQLを1本投げ、その結果をコピーして両AIに解釈させてみるところから始めてみてください。小さな自動化の積み重ねが、データドリブンな意思決定の土台になっていきます。

## 関連記事

- [ChatGPT・Claude・GeminiのデータAI分析能力を実データで徹底比較した](https://zenn.dev/web_benriya/articles/chatgpt-claude-gemini-data-analysis-comparison)
- [Claude CodeにGA4の異常値を検知させて原因仮説まで出力させるプロンプト設計](https://zenn.dev/web_benriya/articles/claude-code-ga4-anomaly-detection-prompt)
- [Claude Codeに月次KPIレポートの「考察」まで書かせるプロンプト設計術](https://zenn.dev/web_benriya/articles/claude-code-monthly-kpi-insight-prompt-design)
- [BigQueryのGeminiアシスタントで非エンジニアが自力でSQL分析できるか検証した](https://zenn.dev/web_benriya/articles/bigquery-gemini-assistant-noneng-sql-validation)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
