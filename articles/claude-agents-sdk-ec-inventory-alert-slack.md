---
title: "Claude CodeのAgents SDKでEC在庫アラート→発注提案→Slack通知を全自動化した"
emoji: "🔔"
type: "tech"
topics: ["claude","bigquery","ec","slack","ai"]
published: false
---

## はじめに

「在庫が切れていた商品に広告費を使い続けていた」「売れ筋商品が欠品してそのまま機会損失が発生した」——中小ECを運営していると、こうした事態は珍しくありません。商品数が数十点を超えてくると、日々の在庫確認だけで相当な時間を取られてしまいます。

在庫管理システムからCSVを取り出して、スプレッドシートで確認して、Slackに手作業で投稿して……といった手順を毎朝繰り返しているなら、その作業はAIエージェントに任せられます。

本記事では、**Anthropic の Claude Code に組み込まれた Agents SDK** を使って、BigQuery 上の在庫データを監視し、アラートと発注提案を Slack へ自動通知するパイプラインを構築した事例を紹介します。エンジニアでなくても全体の流れを把握できるよう、概念と実装の両面から説明します。

---

## 全体アーキテクチャと処理の流れ

今回構築したシステムは、以下の 4 ステップで動作します。

1. **BigQuery でリアルタイム在庫 + 直近売上を集計**（SQL）
2. **Claude Agents SDK が集計結果を受け取り、発注提案を生成**（Python）
3. **生成した提案を Slack の Incoming Webhook で通知**（HTTP POST）
4. **Cloud Scheduler で毎朝 8 時に自動実行**

在庫データは EC システム（Shopify / カラーミーショップ等）から BigQuery にエクスポートしたテーブルを前提としています。GA4 の購買イベントと突き合わせることで「売れているのに在庫が薄い商品」を優先的にアラート対象にできます。

```
[BigQuery] ──SQL集計──▶ [Python スクリプト]
                              │
                    [Claude Agents SDK]
                              │
                         発注提案テキスト生成
                              │
                       [Slack Webhook]
                              ▼
                        #在庫アラート チャンネル
```

---

## BigQuery での在庫 × 売上集計 SQL

まず、在庫テーブルと GA4 の購買データを組み合わせて「在庫残日数」を算出するクエリを用意します。GA4 の BigQuery エクスポートテーブルでは `ga_session_id` を直接参照できないため、`UNNEST(event_params)` 経由で取得する点に注意してください。また、流入元の判定には `collected_traffic_source.manual_medium` / `manual_source` を使用します。

```sql
WITH
-- GA4 から直近 7 日間の商品別注文数を集計
ga4_sales AS (
  SELECT
    ep_item.value.string_value AS item_id,
    COUNT(DISTINCT
      (SELECT ep.value.int_value
       FROM UNNEST(event_params) AS ep
       WHERE ep.key = 'ga_session_id')
    ) AS session_count,
    SUM(ecommerce.purchase_revenue) AS revenue_7d,
    -- 流入元の確認
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source
  FROM
    `your_project.analytics_XXXXXXX.events_*`,
    UNNEST(items) AS ep_item
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    AND event_name = 'purchase'
  GROUP BY
    item_id, medium, source
),

-- 在庫テーブル（例: Shopify エクスポート or 自社 DB を BQ に同期）
inventory AS (
  SELECT
    product_id,
    product_name,
    stock_quantity,
    reorder_point,
    lead_time_days
  FROM
    `your_project.ec_data.inventory_snapshot`
  WHERE
    snapshot_date = CURRENT_DATE()
)

SELECT
  i.product_id,
  i.product_name,
  i.stock_quantity,
  i.reorder_point,
  i.lead_time_days,
  COALESCE(s.session_count, 0)             AS sessions_7d,
  COALESCE(s.revenue_7d, 0)               AS revenue_7d,
  -- 1日平均販売数（セッション数を粗い代理変数として使用）
  ROUND(COALESCE(s.session_count, 0) / 7, 1) AS avg_daily_sales,
  -- 在庫残日数の推定
  CASE
    WHEN COALESCE(s.session_count, 0) = 0 THEN 999
    ELSE ROUND(i.stock_quantity / (s.session_count / 7), 0)
  END AS estimated_days_remaining
FROM
  inventory AS i
LEFT JOIN
  ga4_sales AS s
  ON i.product_id = s.item_id
WHERE
  -- 在庫残日数がリードタイム以下の商品のみ抽出
  CASE
    WHEN COALESCE(s.session_count, 0) = 0 THEN 999
    ELSE ROUND(i.stock_quantity / (s.session_count / 7), 0)
  END <= i.lead_time_days
ORDER BY
  estimated_days_remaining ASC
LIMIT 20
```

このクエリを Python から実行し、結果を Claude Agents SDK に渡します。

---

## Claude Agents SDK で発注提案を生成する

Agents SDK では、外部ツール（BigQuery クエリ実行・Slack 投稿）を定義しておき、Claude に「在庫アラートを確認して発注提案を Slack に送る」という目的だけを与えます。Claude が自律的にツールを呼び出して一連のフローを実行します。

```python
import anthropic
import json
from google.cloud import bigquery

client = anthropic.Anthropic()
bq_client = bigquery.Client(project="your_project")

# ---- ツール定義 ----

tools = [
    {
        "name": "get_low_stock_items",
        "description": "BigQueryから在庫残日数がリードタイム以下の商品一覧を取得する",
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "post_slack_alert",
        "description": "在庫アラートと発注提案をSlackに投稿する",
        "input_schema": {
            "type": "object",
            "properties": {
                "message": {
                    "type": "string",
                    "description": "Slackに投稿するメッセージ本文（Markdown形式）"
                }
            },
            "required": ["message"]
        }
    }
]

# ---- ツール実装 ----

def get_low_stock_items():
    """BigQueryのクエリを実行して低在庫商品を返す"""
    query = """
    -- 上記SQLを文字列として埋め込む
    SELECT product_name, stock_quantity, estimated_days_remaining, avg_daily_sales
    FROM `your_project.ec_data.low_stock_view`
    ORDER BY estimated_days_remaining ASC
    LIMIT 10
    """
    rows = bq_client.query(query).result()
    return [dict(row) for row in rows]

def post_slack_alert(message: str):
    """Slack Incoming Webhookにメッセージを送信する"""
    import urllib.request
    webhook_url = "https://hooks.slack.com/services/XXX/YYY/ZZZ"
    payload = json.dumps({"text": message}).encode("utf-8")
    req = urllib.request.Request(
        webhook_url,
        data=payload,
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req) as res:
        return res.read().decode("utf-8")

# ---- エージェントループ ----

def run_inventory_agent():
    messages = [
        {
            "role": "user",
            "content": (
                "今日の在庫状況を確認してください。"
                "在庫残日数がリードタイム以下の商品を抽出し、"
                "各商品への発注推奨数量と優先度をビジネス担当者向けにわかりやすくまとめ、"
                "Slackの#在庫アラートチャンネルに日本語で投稿してください。"
            )
        }
    ]

    while True:
        response = client.messages.create(
            model="claude-sonnet-4-5",
            max_tokens=2048,
            tools=tools,
            messages=messages
        )

        if response.stop_reason == "end_turn":
            print("エージェント処理完了")
            break

        if response.stop_reason == "tool_use":
            tool_results = []
            for block in response.content:
                if block.type == "tool_use":
                    if block.name == "get_low_stock_items":
                        result = get_low_stock_items()
                    elif block.name == "post_slack_alert":
                        result = post_slack_alert(block.input["message"])
                    else:
                        result = {"error": "unknown tool"}

                    tool_results.append({
                        "type": "tool_result",
                        "tool_use_id": block.id,
                        "content": json.dumps(result, ensure_ascii=False)
                    })

            messages.append({"role": "assistant", "content": response.content})
            messages.append({"role": "user", "content": tool_results})

if __name__ == "__main__":
    run_inventory_agent()
```

エージェントループは `stop_reason` が `"tool_use"` の間は繰り返し動作し、`"end_turn"` になったら終了します。Claude が「まず在庫データを取得して、次に Slack に投稿する」という判断を自律的に行います。

---

## Cloud Scheduler で毎朝自動実行する

上記スクリプトを Cloud Run Jobs としてデプロイし、Cloud Scheduler で毎朝 8 時（JST）に実行します。

```bash
# Cloud Run Jobs にデプロイ
gcloud run jobs create inventory-alert-job \
  --image asia-northeast1-docker.pkg.dev/your_project/repo/inventory-agent:latest \
  --region asia-northeast1 \
  --set-env-vars ANTHROPIC_API_KEY=your_key \
  --service-account inventory-agent-sa@your_project.iam.gserviceaccount.com

# Cloud Scheduler でスケジュール設定（毎朝 8:00 JST）
gcloud scheduler jobs create http inventory-alert-schedule \
  --location asia-northeast1 \
  --schedule "0 8 * * *" \
  --time-zone "Asia/Tokyo" \
  --uri "https://asia-northeast1-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/your_project/jobs/inventory-alert-job:run" \
  --oauth-service-account-email scheduler-sa@your_project.iam.gserviceaccount.com \
  --http-method POST
```

:::message
サービスアカウントには `roles/bigquery.dataViewer`、`roles/run.invoker` の IAM ロールを付与してください。Slack の Webhook URL は Secret Manager に格納し、環境変数として渡すとセキュリティ面で安心です。
:::

---

## 実際に届く Slack 通知の例

Claude が生成する Slack メッセージは、単なるデータの羅列ではなく、担当者がすぐに行動できる形式で出力されます。以下は実際に受信したメッセージの例です。

```
📦 *本日の在庫アラート（2026-08-02 08:00 JST）*

⚠️ *発注優先度：高*
• 【商品A】在庫残 3 日分 / リードタイム 7 日
  → 推奨発注数：50 個（直近 7 日の平均販売ペース × 2 週間分）

⚠️ *発注優先度：中*
• 【商品B】在庫残 5 日分 / リードタイム 5 日（ギリギリです）
  → 推奨発注数：30 個

ℹ️ 詳細は BigQuery ダッシュボードをご確認ください。
```

担当者はこの通知を見て、仕入先にメールを送るだけで完結します。毎朝の在庫確認作業が不要になり、他の業務に集中できます。

---

## まとめ

本記事では、Claude Code の Agents SDK を活用した EC 在庫アラート自動化の全体像を紹介しました。要点を整理します。

- **BigQuery × GA4** で「売れ筋かつ在庫薄」な商品を SQL で特定できる
- **Agents SDK のツール定義**により、BigQuery 取得 → 発注提案生成 → Slack 投稿を Claude が自律的に実行する
- **Cloud Scheduler + Cloud Run Jobs** の組み合わせでノーコードに近い形で定期自動化できる

導入の第一歩としては、まず BigQuery に在庫スナップショットを取り込む仕組みを作ることをお勧めします。データ基盤が整えば、今回のような AI エージェント活用の幅が一気に広がります。自社の EC システムとの接続方法や、GA4 のイベント設計についてご不明な点があれば、下記よりお気軽にご相談ください。

## 関連記事

- [Claude CodeにGA4の異常値を検知させて原因仮説まで出力させるプロンプト設計](https://zenn.dev/web_benriya/articles/claude-code-ga4-anomaly-detection-prompt)
- [Claude Codeに月次KPIレポートの「考察」まで書かせるプロンプト設計術](https://zenn.dev/web_benriya/articles/claude-code-monthly-kpi-insight-prompt-design)
- [ChatGPT・Claude・GeminiのデータAI分析能力を実データで徹底比較した](https://zenn.dev/web_benriya/articles/chatgpt-claude-gemini-data-analysis-comparison)
- [BigQueryのGeminiアシスタントで非エンジニアが自力でSQL分析できるか検証した](https://zenn.dev/web_benriya/articles/bigquery-gemini-assistant-noneng-sql-validation)

---

:::message
GA4・BigQuery・LookerStudio・AI自動化の構築や設定代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
👉 [ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
