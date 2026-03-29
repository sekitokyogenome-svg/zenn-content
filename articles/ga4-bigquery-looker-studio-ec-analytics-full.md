---
title: "GA4 × BigQuery × Looker Studioで完全自動のEC分析基盤を0から構築する全手順"
emoji: "📈"
type: "tech"
topics: ["bigquery", "lookerstudio", "googleanalytics"]
published: false
---

## はじめに

「GA4は入れてある。BigQueryにもエクスポートしている。でも、そこから先がわからない。」

EC運営をしていると、売上やアクセスデータは日々蓄積されていきます。しかし、データが溜まっているだけでは意思決定には使えません。分析基盤を作りたいと思っても、何から手をつければいいのか、全体像が見えないまま手が止まってしまう方は多いのではないでしょうか。

この記事では、GA4のBigQueryエクスポートを起点に、staging/martの3層設計、Looker Studioでのダッシュボード構築、スケジュールクエリによる自動化まで、EC分析基盤を0から構築する全手順を解説します。

:::message
この記事は実際のEC案件で構築した基盤をベースにしています。プロジェクト名やデータセット名は適宜読み替えてください。
:::

---

## 全体アーキテクチャ

構築するパイプラインの全体像は以下の通りです。

```text
[GA4]  →  [BigQuery raw]  →  [staging ビュー]  →  [mart テーブル]  →  [Looker Studio]
           events_*            stg_events            mart_traffic         ダッシュボード
                               stg_sessions          mart_funnel
                               stg_purchases         mart_cohort
```

各レイヤーの役割を明確に分けることで、SQLの可読性・保守性が格段に上がります。3層設計の詳しい考え方は以下の記事で解説しています。

https://zenn.dev/web_benriya/articles/ga4-bigquery-3layer-design

---

## Step 1：GA4 → BigQueryエクスポートの設定

まずGA4の管理画面からBigQueryへのエクスポートを有効にします。

1. GA4管理画面 →「プロパティ設定」→「BigQueryのリンク設定」
2. GCPプロジェクトを選択
3. エクスポート頻度は「毎日」を選択（ストリーミングは追加コストがかかる）
4. リージョンは `asia-northeast1`（東京）を推奨

設定完了後、翌日から `analytics_XXXXXXXXX.events_YYYYMMDD` テーブルにデータが蓄積されます。

詳しい設定手順・注意点は以下の記事にまとめています。

https://zenn.dev/web_benriya/articles/ga4-bigquery-export-setup-guide-2026

---

## Step 2：stagingビューを作成する

raw層のデータはネスト構造になっており、そのままでは扱いにくい状態です。staging層でフラット化し、後続の集計で使いやすい形に整えます。

### stg_events（イベント単位のフラット化）

```sql
CREATE OR REPLACE VIEW `project.staging.stg_events` AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS event_date,
  event_timestamp,
  event_name,
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_title') AS page_title,
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
  device.category AS device_category,
  geo.country AS country,
  ecommerce.purchase_revenue AS purchase_revenue,
  ecommerce.transaction_id AS transaction_id
FROM `project.analytics_XXXXXXXXX.events_*`
```

:::message
`ga_session_id` は `event_params` の中にネストされているため、`UNNEST` で展開する必要があります。UNNESTのパターン詳細は[こちらの記事](https://zenn.dev/web_benriya/articles/ga4-bigquery-unnest-sql-patterns)を参照してください。
:::

### stg_sessions（セッション単位の集約）

```sql
CREATE OR REPLACE VIEW `project.staging.stg_sessions` AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS session_date,
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
  device.category AS device_category,
  MAX(IF(event_name = 'session_start', 1, 0)) AS is_session_start,
  MAX(IF(event_name = 'purchase', 1, 0)) AS has_purchase,
  MAX(IF(event_name = 'add_to_cart', 1, 0)) AS has_add_to_cart,
  MAX(IF(event_name = 'view_item', 1, 0)) AS has_view_item,
  SUM(ecommerce.purchase_revenue) AS session_revenue
FROM `project.analytics_XXXXXXXXX.events_*`
GROUP BY
  event_date, user_pseudo_id, ga_session_id,
  source, medium, device_category
```

### stg_purchases（購入イベントのみ抽出）

```sql
CREATE OR REPLACE VIEW `project.staging.stg_purchases` AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS purchase_date,
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  ecommerce.transaction_id,
  ecommerce.purchase_revenue,
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
  device.category AS device_category
FROM `project.analytics_XXXXXXXXX.events_*`
WHERE event_name = 'purchase'
  AND ecommerce.transaction_id IS NOT NULL
```

---

## Step 3：martテーブルを作成する

mart層ではビジネスロジックを適用し、Looker Studioから直接参照できる集計テーブルを作ります。

### mart_traffic（日別×チャネル別トラフィック）

```sql
CREATE OR REPLACE TABLE `project.mart.mart_traffic` AS
SELECT
  session_date,
  source,
  medium,
  device_category,
  COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING))) AS sessions,
  COUNT(DISTINCT IF(has_purchase = 1, CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING)), NULL)) AS converting_sessions,
  SUM(session_revenue) AS total_revenue
FROM `project.staging.stg_sessions`
GROUP BY session_date, source, medium, device_category
```

### mart_funnel（月次ファネル分析）

```sql
CREATE OR REPLACE TABLE `project.mart.mart_funnel` AS
SELECT
  FORMAT_DATE('%Y-%m', session_date) AS month,
  COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING))) AS total_sessions,
  COUNT(DISTINCT IF(has_view_item = 1, CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING)), NULL)) AS view_item_sessions,
  COUNT(DISTINCT IF(has_add_to_cart = 1, CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING)), NULL)) AS add_to_cart_sessions,
  COUNT(DISTINCT IF(has_purchase = 1, CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING)), NULL)) AS purchase_sessions
FROM `project.staging.stg_sessions`
GROUP BY month
```

### mart_cohort（月次コホート分析）

```sql
CREATE OR REPLACE TABLE `project.mart.mart_cohort` AS
WITH first_visit AS (
  SELECT
    user_pseudo_id,
    FORMAT_DATE('%Y-%m', MIN(session_date)) AS cohort_month
  FROM `project.staging.stg_sessions`
  GROUP BY user_pseudo_id
)
SELECT
  fv.cohort_month,
  FORMAT_DATE('%Y-%m', s.session_date) AS activity_month,
  DATE_DIFF(
    PARSE_DATE('%Y-%m', FORMAT_DATE('%Y-%m', s.session_date)),
    PARSE_DATE('%Y-%m', fv.cohort_month),
    MONTH
  ) AS months_since_first,
  COUNT(DISTINCT s.user_pseudo_id) AS returning_users
FROM `project.staging.stg_sessions` s
JOIN first_visit fv ON s.user_pseudo_id = fv.user_pseudo_id
GROUP BY cohort_month, activity_month, months_since_first
```

---

## Step 4：Looker StudioからBigQueryに接続する

martテーブルが揃ったら、Looker Studioから接続します。

1. [Looker Studio](https://lookerstudio.google.com/) を開く
2. 「空のレポート」を作成
3. データソース追加 →「BigQuery」→ プロジェクト → martデータセット → テーブルを選択
4. `mart_traffic`、`mart_funnel`、`mart_cohort` それぞれをデータソースとして追加

:::message alert
Looker Studioから直接raw層（`events_*`）に接続するのは避けてください。クエリコストが膨大になり、パフォーマンスも低下します。必ずmart層に接続しましょう。
:::

---

## Step 5：ダッシュボードを構築する

追加したデータソースを使って、以下のようなダッシュボードを構成します。

### ページ1：KPIサマリー

| コンポーネント | データソース | 表示内容 |
|------------|-----------|---------|
| スコアカード | mart_traffic | 合計セッション数 |
| スコアカード | mart_traffic | 合計売上 |
| スコアカード | mart_traffic | CVR（converting_sessions / sessions） |
| 時系列グラフ | mart_traffic | 日別セッション数・売上の推移 |

### ページ2：チャネル分析

| コンポーネント | データソース | 表示内容 |
|------------|-----------|---------|
| 棒グラフ | mart_traffic | チャネル別セッション数 |
| テーブル | mart_traffic | source/medium別のセッション・CV・売上 |
| 円グラフ | mart_traffic | デバイスカテゴリ別セッション割合 |

### ページ3：ファネル＆コホート

| コンポーネント | データソース | 表示内容 |
|------------|-----------|---------|
| 棒グラフ | mart_funnel | 月次ファネル（view_item → add_to_cart → purchase） |
| ヒートマップ | mart_cohort | コホート別リテンション |

日付フィルタやチャネルフィルタを配置しておくと、自由に切り口を変えて分析できます。

---

## Step 6：スケジュールクエリで自動化する

mart層をビューではなくテーブルとして運用する場合、定期的な再構築が必要です。BigQueryのスケジュールクエリを使って自動化します。

### BigQueryコンソールから設定する方法

1. BigQueryコンソールでmartテーブルを生成するSQLを開く
2. 「スケジュール」→「新しいスケジュールクエリ」を選択
3. 実行頻度を設定（毎日AM6:00 JSTなど）
4. 宛先テーブルの書き込み設定を「テーブルを上書き」にする

### bqコマンドで設定する方法

```bash
bq mk \
  --transfer_config \
  --project_id=project \
  --data_source=scheduled_query \
  --target_dataset=mart \
  --display_name="mart_traffic daily refresh" \
  --schedule="every day 06:00" \
  --params='{
    "query": "CREATE OR REPLACE TABLE `project.mart.mart_traffic` AS SELECT ... (省略)",
    "destination_table_name_template": "mart_traffic",
    "write_disposition": "WRITE_TRUNCATE"
  }'
```

:::message
mart層をビューで構成すれば、スケジュールクエリは不要です。ただし、データ量が増えるとクエリコストとパフォーマンスに影響するため、テーブル + 定期更新の構成を推奨します。
:::

---

## コスト見積もり

この構成にかかるGCPコストの目安です（月間PV 10万〜50万規模のECサイトを想定）。

| 項目 | 月額目安 |
|------|---------|
| BigQueryストレージ（GA4生データ） | $0.5〜$2 |
| BigQueryクエリ（スケジュールクエリ含む） | $1〜$5 |
| Looker Studio | 無料 |
| **合計** | **$1.5〜$7（約200〜1,000円）** |

BigQueryの無料枠（ストレージ10GB・クエリ1TB/月）の範囲内で収まるケースも多いです。GA4探索レポートの制約に悩むよりも、低コストで本格的な分析基盤が手に入ります。

---

## まとめ

本記事では、GA4 × BigQuery × Looker Studioを組み合わせたEC分析基盤の構築手順を、以下の流れで解説しました。

1. GA4 → BigQueryエクスポートの設定
2. staging層でデータをフラット化（stg_events / stg_sessions / stg_purchases）
3. mart層でビジネスロジックを適用した集計テーブルを作成
4. Looker Studioからmart層に接続してダッシュボードを構築
5. スケジュールクエリで毎日自動更新

3層設計の詳細は[こちら](https://zenn.dev/web_benriya/articles/ga4-bigquery-3layer-design)、UNNESTパターンの詳細は[こちら](https://zenn.dev/web_benriya/articles/ga4-bigquery-unnest-sql-patterns)も合わせてご覧ください。

「自社ECの分析基盤を構築したいが、設計から実装まで手が回らない」という方は、構築代行も承っています。お気軽にご相談ください。

https://coconala.com/services/1791205
