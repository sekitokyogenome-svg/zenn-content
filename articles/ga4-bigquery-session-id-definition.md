---
title: "GA4×BigQueryでセッションIDを正しく定義する方法"
emoji: "🔗"
type: "tech"
topics: ["bigquery", "googleanalytics", "sql"]
published: true
---

## はじめに

GA4のBigQueryエクスポートデータを分析しようとしたとき、「セッションIDってどのカラムを使えばいいのか？」と迷っていませんか？

GA4のBigQueryテーブルには、`session_id` というカラムは存在しません。セッションを識別するには、`event_params` の中に格納されている `ga_session_id` をUNNESTで取り出し、`user_pseudo_id` と組み合わせる必要があります。

この記事では、セッションIDの正しい定義方法と、実務で使えるSQLパターンを解説します。

---

## ga_session_idはevent_paramsの中にある

GA4のBigQueryテーブルで最もよくある間違いが、トップレベルに `session_id` カラムがあると思い込むことです。

実際には、セッション識別子はネストされた `event_params` 配列の中に `ga_session_id` というキーで格納されています。

```sql
-- ga_session_idの取り出し方
SELECT
  user_pseudo_id,
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_id') AS ga_session_id
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'session_start'
LIMIT 10
```

:::message
`ga_session_id` は `int_value` で格納されています。`string_value` で取得しようとするとNULLが返るため注意してください。
:::

---

## ga_session_id単体では一意にならない

`ga_session_id` はユーザー単位のセッション識別子です。異なるユーザー間で同じ値が使われることがあります。

つまり、`ga_session_id` だけではテーブル全体でセッションを一意に識別できません。

```text
user_pseudo_id          | ga_session_id
------------------------|---------------
abc123.1234567890       | 1711234567
def456.9876543210       | 1711234567  ← 同じ値！
```

---

## user_pseudo_id + ga_session_idで一意なセッションIDを作る

セッションをテーブル全体で一意に識別するには、`user_pseudo_id` と `ga_session_id` を結合します。

```sql
SELECT
  CONCAT(
    user_pseudo_id, '.',
    CAST(
      (SELECT value.int_value
       FROM UNNEST(event_params)
       WHERE key = 'ga_session_id') AS STRING)
  ) AS session_id,
  user_pseudo_id,
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_id') AS ga_session_id,
  event_name,
  event_timestamp
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
ORDER BY session_id, event_timestamp
LIMIT 100
```

このSQLで生成される `session_id` は以下のような形式になります。

```text
abc123.1234567890.1711234567
```

これでテーブル全体でセッションを一意に識別できます。

---

## セッション単位の集計SQL

セッションIDを定義したら、セッション単位の集計が可能になります。

### セッション数のカウント

```sql
SELECT
  event_date,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    )
  ) AS session_count
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
GROUP BY event_date
ORDER BY event_date
```

### セッションごとのPV数

```sql
WITH sessions AS (
  SELECT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    event_name
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
)
SELECT
  session_id,
  COUNTIF(event_name = 'page_view') AS page_views
FROM sessions
GROUP BY session_id
ORDER BY page_views DESC
LIMIT 20
```

---

## セッション開始時刻と流入元を紐づける

セッション単位の分析では、流入元やランディングページの情報が重要です。`session_start` イベントを基準にこれらを取得します。

```sql
WITH session_starts AS (
  SELECT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    event_timestamp,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium,
    (SELECT value.string_value
     FROM UNNEST(event_params)
     WHERE key = 'page_location') AS landing_page
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
    AND event_name = 'session_start'
)
SELECT
  source,
  medium,
  COUNT(*) AS sessions,
  COUNT(DISTINCT session_id) AS unique_sessions
FROM session_starts
GROUP BY source, medium
ORDER BY sessions DESC
```

:::message
流入元の取得には `collected_traffic_source.manual_source` / `collected_traffic_source.manual_medium` を使ってください。`traffic_source.source` はユーザーの**初回訪問時**の情報であり、セッション単位の分析には不向きです。
:::

---

## ga_session_numberで新規・リピートを判定する

`event_params` には `ga_session_number`（そのユーザーの何回目のセッションか）も格納されています。

```sql
SELECT
  CONCAT(
    user_pseudo_id, '.',
    CAST(
      (SELECT value.int_value
       FROM UNNEST(event_params)
       WHERE key = 'ga_session_id') AS STRING)
  ) AS session_id,
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_number') AS session_number,
  CASE
    WHEN (SELECT value.int_value
          FROM UNNEST(event_params)
          WHERE key = 'ga_session_number') = 1
    THEN 'new'
    ELSE 'returning'
  END AS user_type
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'session_start'
```

`ga_session_number = 1` なら新規ユーザー、2以上ならリピーターとして分類できます。

---

## stagingビューとして定義する

毎回UNNESTを書くのは非効率です。セッションの基本情報をstagingビューとして定義しておくと、後続の分析が楽になります。

```sql
CREATE OR REPLACE VIEW `beeracle.beeracle_staging.stg_sessions` AS
SELECT
  event_date,
  CONCAT(
    user_pseudo_id, '.',
    CAST(
      (SELECT value.int_value
       FROM UNNEST(event_params)
       WHERE key = 'ga_session_id') AS STRING)
  ) AS session_id,
  user_pseudo_id,
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_id') AS ga_session_id,
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_number') AS ga_session_number,
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
  (SELECT value.string_value
   FROM UNNEST(event_params)
   WHERE key = 'page_location') AS landing_page,
  event_timestamp
FROM `beeracle.analytics_263425816.events_*`
WHERE event_name = 'session_start'
```

このビューを作っておけば、以降は `SELECT * FROM stg_sessions WHERE event_date = '20260330'` のように簡潔に書けます。

---

## まとめ

GA4のBigQueryデータでセッションを扱うには、`event_params` から `ga_session_id` をUNNESTで取り出し、`user_pseudo_id` と結合して一意なIDを作ることが基本です。このパターンを覚えておけば、セッション数・PV数・流入元分析・新規リピート判定など、多くの分析に応用できます。

---

:::message
「GA4のデータをBigQueryで分析したいが、設計や実装に不安がある」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
