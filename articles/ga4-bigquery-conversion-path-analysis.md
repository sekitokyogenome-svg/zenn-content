---
title: "GA4×BigQueryでコンバージョン経路を分析するSQL"
emoji: "🛤️"
type: "tech"
topics: ["bigquery", "googleanalytics", "marketing"]
published: false
---

## はじめに

「コンバージョンしたユーザーがどんなページを経由しているのか知りたい」と思ったことはありませんか？

GA4のUI上でもパス分析は可能ですが、サンプリングの影響を受けやすく、柔軟なカスタマイズにも限界があります。BigQueryを使えば、全データに基づいたコンバージョン経路分析をSQLで自由に構築できます。

この記事では、STRING_AGGによるページ遷移パスの生成と、ファーストタッチ・ラストタッチのアトリビューション比較SQLを解説します。

---

## コンバージョン経路分析とは

コンバージョン経路分析とは、ユーザーがコンバージョン（購入・問い合わせ等）に至るまでにどのページを、どの順番で閲覧したかを可視化する分析です。

これにより以下のことがわかります。

- コンバージョンに貢献しているページ（意外なページが寄与していることも）
- 離脱が多いポイント
- 想定通りの導線でユーザーが回遊しているかの検証

---

## セッション内のページ遷移パスをSQLで生成する

BigQueryの `STRING_AGG` 関数を使って、セッション内のページ閲覧順序を1つの文字列にまとめます。

```sql
WITH session_pages AS (
  SELECT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    event_timestamp,
    REGEXP_EXTRACT(
      (SELECT value.string_value
       FROM UNNEST(event_params)
       WHERE key = 'page_location'),
      r'https?://[^/]+(/.*)') AS page_path
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
    AND event_name = 'page_view'
)
SELECT
  session_id,
  STRING_AGG(page_path, ' → ' ORDER BY event_timestamp) AS page_path_sequence,
  COUNT(*) AS page_views
FROM session_pages
GROUP BY session_id
ORDER BY page_views DESC
LIMIT 20
```

結果は以下のような形式になります。

```text
session_id              | page_path_sequence                          | page_views
------------------------|---------------------------------------------|----------
abc123.xxx.171123       | / → /products → /products/item-1 → /cart   | 4
def456.yyy.171456       | /blog/seo-tips → /services → /contact      | 3
```

:::message
`REGEXP_EXTRACT` でドメイン部分を除去し、パス部分だけを抽出しています。ドメインが複数ある場合やクエリパラメータを除去したい場合は正規表現を調整してください。
:::

---

## コンバージョンしたセッションの経路だけを抽出する

purchaseイベントが発生したセッションに絞り込むことで、コンバージョン経路だけを取得できます。

```sql
WITH all_events AS (
  SELECT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    event_name,
    event_timestamp,
    REGEXP_EXTRACT(
      (SELECT value.string_value
       FROM UNNEST(event_params)
       WHERE key = 'page_location'),
      r'https?://[^/]+(/.*)') AS page_path
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
),
cv_sessions AS (
  SELECT DISTINCT session_id
  FROM all_events
  WHERE event_name = 'purchase'
),
cv_pages AS (
  SELECT
    a.session_id,
    a.event_timestamp,
    a.page_path
  FROM all_events a
  INNER JOIN cv_sessions c ON a.session_id = c.session_id
  WHERE a.event_name = 'page_view'
)
SELECT
  session_id,
  STRING_AGG(page_path, ' → ' ORDER BY event_timestamp) AS cv_path
FROM cv_pages
GROUP BY session_id
ORDER BY session_id
```

---

## よく通るコンバージョン経路をランキングする

個別セッションではなく、パターンとして多い経路を集計します。

```sql
WITH all_events AS (
  SELECT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    event_name,
    event_timestamp,
    REGEXP_EXTRACT(
      (SELECT value.string_value
       FROM UNNEST(event_params)
       WHERE key = 'page_location'),
      r'https?://[^/]+(/.*)') AS page_path
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
),
cv_sessions AS (
  SELECT DISTINCT session_id
  FROM all_events
  WHERE event_name = 'purchase'
),
cv_paths AS (
  SELECT
    a.session_id,
    STRING_AGG(a.page_path, ' → ' ORDER BY a.event_timestamp) AS path
  FROM all_events a
  INNER JOIN cv_sessions c ON a.session_id = c.session_id
  WHERE a.event_name = 'page_view'
  GROUP BY a.session_id
)
SELECT
  path,
  COUNT(*) AS session_count
FROM cv_paths
GROUP BY path
ORDER BY session_count DESC
LIMIT 20
```

上位に来る経路パターンが、サイトの「黄金ルート」です。この導線を強化することでコンバージョン率の改善が期待できます。

---

## ファーストタッチ分析：最初に見たページ

ユーザーが最初に閲覧したページ（ランディングページ）をコンバージョンの功績とする分析です。

```sql
WITH session_first_page AS (
  SELECT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    event_name,
    REGEXP_EXTRACT(
      (SELECT value.string_value
       FROM UNNEST(event_params)
       WHERE key = 'page_location'),
      r'https?://[^/]+(/.*)') AS page_path,
    ROW_NUMBER() OVER (
      PARTITION BY
        CONCAT(
          user_pseudo_id, '.',
          CAST(
            (SELECT value.int_value
             FROM UNNEST(event_params)
             WHERE key = 'ga_session_id') AS STRING))
      ORDER BY event_timestamp
    ) AS rn
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
    AND event_name = 'page_view'
),
cv_sessions AS (
  SELECT DISTINCT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
    AND event_name = 'purchase'
)
SELECT
  f.page_path AS first_touch_page,
  COUNT(*) AS cv_sessions
FROM session_first_page f
INNER JOIN cv_sessions c ON f.session_id = c.session_id
WHERE f.rn = 1
GROUP BY first_touch_page
ORDER BY cv_sessions DESC
LIMIT 20
```

---

## ラストタッチ分析：コンバージョン直前のページ

purchaseイベントの直前に閲覧されたページを特定します。

```sql
WITH session_last_page AS (
  SELECT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    event_name,
    REGEXP_EXTRACT(
      (SELECT value.string_value
       FROM UNNEST(event_params)
       WHERE key = 'page_location'),
      r'https?://[^/]+(/.*)') AS page_path,
    ROW_NUMBER() OVER (
      PARTITION BY
        CONCAT(
          user_pseudo_id, '.',
          CAST(
            (SELECT value.int_value
             FROM UNNEST(event_params)
             WHERE key = 'ga_session_id') AS STRING))
      ORDER BY event_timestamp DESC
    ) AS rn
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
    AND event_name = 'page_view'
),
cv_sessions AS (
  SELECT DISTINCT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
    AND event_name = 'purchase'
)
SELECT
  l.page_path AS last_touch_page,
  COUNT(*) AS cv_sessions
FROM session_last_page l
INNER JOIN cv_sessions c ON l.session_id = c.session_id
WHERE l.rn = 1
GROUP BY last_touch_page
ORDER BY cv_sessions DESC
LIMIT 20
```

---

## ファーストタッチとラストタッチを比較する

両方の結果を並べて見ると、ページの役割が見えてきます。

```text
ページ              | ファーストタッチCV | ラストタッチCV | 役割
--------------------|-------------------|---------------|------
/blog/how-to-choose | 15                | 3             | 集客ページ
/products           | 8                 | 5             | 中間ページ
/products/item-1    | 3                 | 12            | クロージングページ
/cart               | 0                 | 18            | 購入直前ページ
```

- ファーストタッチが多いページ → 集客に強い
- ラストタッチが多いページ → 意思決定の後押しに強い
- 両方多いページ → サイトの中核コンテンツ

:::message
チャネル別のアトリビューション分析も同様のロジックで構築できます。`page_path` の代わりに `collected_traffic_source.manual_source` / `collected_traffic_source.manual_medium` を使ってください。
:::

---

## まとめ

BigQueryを使えば、GA4のコンバージョン経路をSQLで自由に分析できます。STRING_AGGでページ遷移パスを可視化し、ファーストタッチ・ラストタッチの比較でページの役割を特定することで、サイト改善のヒントが得られます。

---

:::message
「GA4のデータをBigQueryで分析したいが、設計や実装に不安がある」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
