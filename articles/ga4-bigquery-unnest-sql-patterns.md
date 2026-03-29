---
title: "GA4イベントパラメータをUNNESTで展開するSQLパターン集"
emoji: "🔍"
type: "tech"
topics: ["bigquery", "googleanalytics", "sql"]
published: false
---

## はじめに

GA4のBigQueryエクスポートデータは、イベントパラメータが `RECORD` 型（配列）でネストされています。

分析のたびに `UNNEST` を書く必要があり、慣れないうちは構文エラーやNULLの扱いに悩まされがちです。

この記事では、GA4×BigQueryで頻出する `UNNEST` パターンをユースケース別にまとめました。コピペで使えるSQLテンプレートとして活用してください。

---

## GA4のネスト構造をおさらい

GA4のBigQueryエクスポートテーブル `events_YYYYMMDD` には、以下のネストされたカラムがあります。

| カラム | 型 | 内容 |
|--------|-----|------|
| `event_params` | RECORD (REPEATED) | イベントパラメータ（page_location, ga_session_id 等） |
| `user_properties` | RECORD (REPEATED) | ユーザープロパティ |
| `items` | RECORD (REPEATED) | eコマース商品情報 |

これらを取り出すには、`UNNEST` を使ってフラット化する必要があります。

---

## パターン1：サブクエリで単一パラメータを取り出す

最も基本的なパターンです。`SELECT` 句内でサブクエリを使い、特定のキーの値を取得します。

```sql
SELECT
  event_date,
  user_pseudo_id,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id
FROM `project.analytics_XXXXXXXXX.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
  AND event_name = 'page_view'
```

:::message
`event_params` の値は型ごとに別フィールドに格納されています。取り出したいパラメータの型に合わせて `value.string_value`、`value.int_value`、`value.double_value` を使い分けてください。
:::

---

## パターン2：複数パラメータを一度に展開する

分析に必要なパラメータが複数ある場合、同じパターンを並べて書きます。

```sql
SELECT
  event_date,
  event_timestamp,
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_title') AS page_title,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_referrer') AS page_referrer,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'engagement_time_msec') AS engagement_time_msec
FROM `project.analytics_XXXXXXXXX.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
```

冗長に見えますが、BigQueryはこのパターンを効率的に処理します。パフォーマンスの心配は不要です。

---

## パターン3：セッションIDを構築する

GA4のBigQueryデータにはセッション単位の一意なIDがそのままでは存在しません。`user_pseudo_id` と `ga_session_id` を結合して作ります。

```sql
SELECT
  CONCAT(
    user_pseudo_id,
    '-',
    CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
  ) AS session_id,
  event_date,
  event_name
FROM `project.analytics_XXXXXXXXX.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
```

:::message alert
`ga_session_id` は `event_params` の中にネストされています。トップレベルに `session_id` というカラムは存在しないため、直接 `session_id` と書くとエラーになります。
:::

---

## パターン4：CROSS JOINでitemを展開する

eコマースイベント（`purchase`、`add_to_cart` など）に含まれる `items` 配列を展開するには、`CROSS JOIN UNNEST` を使います。

```sql
SELECT
  event_date,
  user_pseudo_id,
  item.item_id,
  item.item_name,
  item.item_category,
  item.price,
  item.quantity
FROM `project.analytics_XXXXXXXXX.events_*`
CROSS JOIN UNNEST(items) AS item
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
  AND event_name = 'purchase'
```

`items` が空（NULLまたは0件）の行は `CROSS JOIN` では除外されます。空の行も残したい場合は `LEFT JOIN UNNEST` を使います。

```sql
FROM `project.analytics_XXXXXXXXX.events_*`
LEFT JOIN UNNEST(items) AS item
```

---

## パターン5：user_propertiesを展開する

ユーザープロパティも `event_params` と同じ構造です。

```sql
SELECT
  user_pseudo_id,
  (SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'first_open_time') AS first_open_time,
  (SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'user_tier') AS user_tier
FROM `project.analytics_XXXXXXXXX.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
```

---

## パターン6：トラフィックソースを正しく取得する

GA4のBigQueryスキーマでは、トラフィックソース情報の取得先がバージョンによって異なります。

```sql
SELECT
  event_date,
  user_pseudo_id,
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_campaign_name AS campaign
FROM `project.analytics_XXXXXXXXX.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
  AND event_name = 'session_start'
```

:::message alert
`traffic_source.medium` や `traffic_source.source` は非推奨になっています。新しいスキーマでは `collected_traffic_source.manual_medium`、`collected_traffic_source.manual_source` を使用してください。
:::

---

## パターン7：stagingビューにまとめる

毎回 `UNNEST` を書くのは非効率です。よく使うパラメータはstagingビューとして定義しておくと、以降のクエリがシンプルになります。

```sql
CREATE OR REPLACE VIEW `project.staging.stg_events` AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS event_date,
  event_timestamp,
  event_name,
  user_pseudo_id,
  CONCAT(
    user_pseudo_id,
    '-',
    CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
  ) AS session_id,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_title') AS page_title,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_referrer') AS page_referrer,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'engagement_time_msec') AS engagement_time_msec,
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
  device.category AS device_category,
  geo.country AS country,
  geo.city AS city
FROM `project.analytics_XXXXXXXXX.events_*`
```

staging層の設計については、以下の記事で詳しく解説しています。

https://zenn.dev/web_benriya/articles/ga4-bigquery-3layer-design

---

## よくあるエラーと対処法

### エラー：Cannot access field on a value with type ARRAY

`UNNEST` せずに `event_params.key` のように直接アクセスしようとすると発生します。サブクエリパターンを使ってください。

### エラー：No matching signature for function UNNEST

`UNNEST` に渡すカラムが配列型でない場合に発生します。テーブル名やカラム名のタイポを確認してください。

### 値がNULLになる

パラメータの型が合っていない可能性があります。`string_value` で取得できない場合は `int_value` や `double_value` を試してください。BigQueryコンソールのスキーマタブで型を確認するのが確実です。

---

## まとめ

| パターン | 用途 | ポイント |
|----------|------|----------|
| サブクエリ UNNEST | 単一パラメータ取得 | 型に注意（string/int/double） |
| 複数サブクエリ | 複数パラメータ一括取得 | パフォーマンスの心配は不要 |
| セッションID構築 | セッション分析 | user_pseudo_id + ga_session_id |
| CROSS JOIN UNNEST | items展開 | 空配列は行が消える点に注意 |
| stagingビュー化 | 再利用性向上 | UNNEST処理を一箇所に集約 |

`UNNEST` はGA4×BigQueryの最初の壁ですが、パターンを覚えてしまえば怖くありません。staging層にまとめておくことで、分析SQLがすっきりします。

GA4×BigQueryの基盤構築やデータマート設計のご相談はこちらからどうぞ。

https://coconala.com/services/1791205
