---
title: "Data Engineering Agentで自然言語からパイプラインを作る"
emoji: "🔧"
type: "tech"
topics: ["bigquery", "googlecloud", "ai", "データエンジニアリング", "エージェント"]
published: true
---

## この記事で解決する課題

データパイプラインの構築に時間がかかっていませんか。「GA4のrawデータを毎日集計してマートテーブルに書き込みたい」という要件を実装するとします。SQLクエリ設計・テスト・スケジュール設定まで含めると、半日以上かかることは珍しくありません。

BigQueryのData Engineering Agentを使うと、自然言語でパイプラインの要件を伝えるだけで、SQLの生成からスケジュール設定の提案まで一気に進められます。本記事では、実務で使えるレベルの操作手順とポイントを解説します。

:::message
本記事は2026年10月時点の情報に基づいています。Data Engineering AgentはPreview段階の機能を含むため、採用前に公式ドキュメントをご確認ください。
:::

---

## Data Engineering Agentとは

Data Engineering AgentはBigQueryに組み込まれたAIエージェント機能の一つで、自然言語の指示に基づいてデータパイプラインの設計・実装を支援します。Geminiモデルを活用し、以下の作業を会話ベースで進められます。

- テーブルスキーマの自動探索と変換ロジックの提案
- ELT（Extract-Load-Transform）クエリの生成
- スケジュールクエリ・マテリアライズドビューの設定案の提示
- 既存パイプラインのリファクタリング提案

Conversational Analyticsは「問いに答えるエージェント」です。Data Engineering Agentは「パイプラインを作るエージェント」と位置付けると分かりやすいです。

---

## 事前準備

### 必要な権限

Data Engineering Agentを利用するには、以下のIAMロールが必要です。

```text
roles/bigquery.dataEditor     -- データセット・テーブルの操作
roles/bigquery.jobUser        -- クエリジョブの実行
roles/bigquery.resourceViewer -- スキーマの参照
```

Vertex AIのGeminiモデルを利用するため、プロジェクトでVertex AIのAPIが有効になっていることも確認してください。

```bash
gcloud services enable aiplatform.googleapis.com --project=YOUR_PROJECT_ID
```

### Knowledge Catalogの整備

Data Engineering Agentはテーブルとカラムのメタデータを参照して変換ロジックを提案します。変換元テーブルには最低限の説明を付与しておきます。

```sql
ALTER TABLE `your-project.raw.ga4_events`
SET OPTIONS (
  description = 'GA4の日次エクスポートテーブル。1行が1イベントに対応する。'
);

ALTER TABLE `your-project.raw.ga4_events`
ALTER COLUMN event_name SET OPTIONS (
  description = 'イベント名。purchase/add_to_cart/page_view/session_startなど。'
);
```

---

## 基本的な使い方：BigQuery Studioから

BigQuery Studioを開き、左ペインの「Gemini」アイコンから「Data Engineering Agent」を選択します。チャット形式でパイプラインの要件を入力します。

### 例1：GA4の日次集計パイプラインを作る

入力：
```text
analytics_YOUR_ID.events_* から、毎日の商品別売上（purchase イベントの revenue パラメータの合計）を集計して、ec_mart.daily_product_revenue テーブルに書き込むパイプラインを作ってください。
```

エージェントの応答例（要約）：
1. `events_*` のスキーマを探索し、`revenue` パラメータの取得方法（UNNEST）を確認
2. 集計SQLの草稿を提示
3. スケジュールクエリの設定手順を案内

提示されるSQL例：

```sql
-- Data Engineering Agentが生成するSQL例
INSERT INTO `your-project.ec_mart.daily_product_revenue`
SELECT
  DATE(_TABLE_SUFFIX) AS event_date,
  ep_item.value.string_value AS item_id,
  ep_item_name.value.string_value AS item_name,
  SUM(ep_revenue.value.double_value) AS revenue
FROM `your-project.analytics_XXXXXXXXX.events_*`
  CROSS JOIN UNNEST(event_params) AS ep_revenue
  CROSS JOIN UNNEST(items) AS item_row
  LEFT JOIN UNNEST(item_row.item_params) AS ep_item
    ON ep_item.key = 'item_id'
  LEFT JOIN UNNEST(item_row.item_params) AS ep_item_name
    ON ep_item_name.key = 'item_name'
WHERE
  event_name = 'purchase'
  AND ep_revenue.key = 'revenue'
  AND _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY 1, 2, 3
```

生成されたSQLを確認し、誤りがあればチャットで修正を指示します。

---

## 例2：3層設計（raw → staging → mart）に沿ったパイプライン

入力：
```text
raw.orders テーブルから staging.orders_cleaned を作るクエリを書いてください。
条件は：
- status = 'cancelled' の行を除外
- total_amount が NULL の行を除外
- created_at を DATE 型に変換して order_date カラムを追加
- 重複する order_id があれば created_at が最新の行を残す
```

エージェントは要件を読み解いてSQL草稿を出力します。QUALIFY句や ROW_NUMBER を使った重複排除など、ベストプラクティスに沿った書き方を提案します。

```sql
CREATE OR REPLACE TABLE `your-project.staging.orders_cleaned` AS
SELECT * EXCEPT(rn)
FROM (
  SELECT
    *,
    DATE(created_at) AS order_date,
    ROW_NUMBER() OVER (
      PARTITION BY order_id
      ORDER BY created_at DESC
    ) AS rn
  FROM `your-project.raw.orders`
  WHERE
    status != 'cancelled'
    AND total_amount IS NOT NULL
)
WHERE rn = 1
```

---

## スケジュールクエリへの変換

生成したSQLをスケジュールクエリとして登録する手順もエージェントに任せられます。

入力：
```text
上記のクエリを毎日 JST 3:00 に実行するスケジュールクエリとして登録してください。
```

エージェントはBigQueryのスケジュールクエリ設定手順を案内します。GUIでの設定手順に加えて、`bq` CLIを使った登録コマンドも提示します。

```bash
bq query \
  --use_legacy_sql=false \
  --destination_table='your-project:staging.orders_cleaned' \
  --replace=true \
  --schedule='every 24 hours' \
  --display_name='staging_orders_cleaned_daily' \
  'CREATE OR REPLACE TABLE ...'
```

:::message
スケジュールクエリの時刻指定はUTC基準です。JSTの午前3時はUTCの前日18:00になります。`--schedule='every 24 hours'` に加えて開始時刻の調整が必要な場合は、Cloud Schedulerとの組み合わせを検討してください。
:::

---

## GA4データを扱う際の注意点

Data Engineering AgentにGA4のパイプラインを依頼するとき、以下のポイントを指示に含めると精度が上がります。

```text
GA4データを処理する際は以下のルールに従ってください：
- ga_session_id は UNNEST(event_params) でキー 'ga_session_id' の int_value を取得すること
- 流入元の取得には collected_traffic_source.manual_medium を使うこと
  （trafficSource.medium は旧仕様のため使用禁止）
- events_* のワイルドカードテーブルを参照し、_TABLE_SUFFIX で日付を絞ること
```

:::message
`ga_session_id` は `UNNEST(event_params)` 経由でのみ正しく取得できます。`collected_traffic_source.manual_medium` は流入元の標準カラムであり、旧来の `trafficSource.medium` より精度が高いです。
:::

---

## APIからの呼び出し

Data Engineering AgentはREST APIから呼び出すことができ、CI/CDパイプラインへの組み込みも可能です。

```python
import google.auth
import google.auth.transport.requests
import requests

def call_data_engineering_agent(
    instruction: str,
    project_id: str,
    location: str = "us-central1",
) -> dict:
    credentials, _ = google.auth.default()
    credentials.refresh(google.auth.transport.requests.Request())

    endpoint = (
        f"https://bigquery.googleapis.com/v2/projects/{project_id}"
        f"/locations/{location}:generateSql"
    )
    headers = {
        "Authorization": f"Bearer {credentials.token}",
        "Content-Type": "application/json",
    }
    payload = {
        "naturalLanguageQuery": instruction,
        "outputTable": f"{project_id}.staging.orders_cleaned",
    }

    response = requests.post(endpoint, headers=headers, json=payload)
    response.raise_for_status()
    return response.json()


result = call_data_engineering_agent(
    instruction="""
    raw.orders から staging.orders_cleaned を作ってください。
    cancelled と NULL の total_amount を除外し、
    order_id の重複は最新行のみ残してください。
    """,
    project_id="your-project-id",
)
print(result.get("sql"))
```

返却された SQL を確認・修正してからジョブとして実行する、というフローを自動化できます。

---

## よくある質問と対処法

| 質問 | 回答 |
|---|---|
| 生成されたSQLが間違っている | チャットで「〇〇の条件が抜けています」と修正指示を送る |
| スキーマが複雑でエージェントが迷っている | Knowledge Catalogにカラム説明を追記してから再試行する |
| GA4のUNNESTが正しく生成されない | 指示にUNNESTのルールを明示的に記載する |
| コストが心配 | 生成されたSQLを `LIMIT 100` で動作確認してから本番実行する |

---

## まとめ

- Data Engineering Agentは自然言語の要件からSQLパイプラインを生成するBigQueryの組み込みエージェント機能
- BigQuery Studioのチャットから使え、スケジュールクエリの設定手順も案内してくれる
- Knowledge Catalogでテーブルメタデータを整備しておくと生成精度が向上する
- GA4データを扱う場合はUNNESTのルールと `collected_traffic_source.manual_medium` の指定を明示する
- APIから呼び出せるため、CI/CDへの組み込みも可能

次回（第22回）は Data Engineering Agentで既存パイプラインを改修・移行する を解説します。

---

:::message
GA4・BigQuery・Looker Studio・AIエージェント構築の設計支援・実装代行を承っています（中小EC・個人事業主向け／スポット相談1万円〜）。「自社の場合はどうすれば？」のご相談も歓迎です。
[ウェブの便利屋（ろじかる）](https://logical-web.jp/?utm_source=zenn&utm_medium=article&utm_campaign=footer_cta)
:::

ココナラからのご依頼はこちら → [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
