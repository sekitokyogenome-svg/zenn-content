---
title: "BigQueryでGA4のページ別滞在時間を正しく集計する方法"
emoji: "⏱"
type: "tech"
topics: ["bigquery", "googleanalytics", "sql"]
published: true
---

## はじめに

GA4の探索レポートで「平均エンゲージメント時間」を見て、「あれ、この数値おかしくないか？」と感じたことはないでしょうか。

GA4の滞在時間は、従来のユニバーサルアナリティクスとは計測方式がまったく異なります。UAの「直帰＝滞在時間0秒」問題はGA4では解消されましたが、BigQueryで正しく集計するにはいくつかのポイントを押さえる必要があります。

この記事では、BigQueryでGA4の `engagement_time_msec` を使い、ページ別の滞在時間を正しく集計する方法を解説します。

---

## GA4の滞在時間の仕組み

GA4では、ユーザーがページをフォアグラウンドで表示している時間を `engagement_time_msec` というパラメータで記録しています。

| 項目 | 内容 |
|------|------|
| パラメータ名 | `engagement_time_msec` |
| 記録単位 | ミリ秒 |
| 記録タイミング | `user_engagement` イベント発火時 |
| 計測対象 | ページがフォアグラウンドにある時間 |

UAでは「次のページビューとの差分」で滞在時間を計算していたため、最後のページの滞在時間が0秒になる問題がありました。GA4はフォアグラウンド時間を直接計測するため、この問題は原理的に解消されています。

ただし、BigQueryで集計する際にはいくつかの注意点があります。

---

## engagement_time_msecをBigQueryで取得する

`engagement_time_msec` は `event_params` のネスト構造に格納されているため、`UNNEST` で展開する必要があります。

```sql
SELECT
  event_name,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'engagement_time_msec') AS engagement_time_msec,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location
FROM `beeracle.analytics_263425816.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
  AND event_name = 'user_engagement'
```

:::message
`engagement_time_msec` は `int_value` で取得します。`string_value` で取得しようとすると `NULL` が返るので注意してください。
:::

---

## ページ別の平均滞在時間を集計するSQL

実用的なページ別滞在時間の集計クエリは以下のとおりです。

```sql
WITH engagement AS (
  SELECT
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'engagement_time_msec') AS engagement_time_msec
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
    AND event_name = 'user_engagement'
)
SELECT
  NET.REG_DOMAIN(page_location) AS domain,
  REGEXP_EXTRACT(page_location, r'^https?://[^/]+(/.*)') AS page_path,
  COUNT(*) AS engagement_events,
  ROUND(AVG(engagement_time_msec) / 1000, 1) AS avg_engagement_sec,
  ROUND(SUM(engagement_time_msec) / 1000, 1) AS total_engagement_sec
FROM engagement
WHERE engagement_time_msec IS NOT NULL
  AND engagement_time_msec > 0
GROUP BY domain, page_path
ORDER BY engagement_events DESC
LIMIT 50
```

### ポイント

- `engagement_time_msec > 0` のフィルタで、0ミリ秒のレコードを除外しています
- URLからパスを抽出することで、クエリパラメータ付きURLの統合が可能です
- ミリ秒を秒に変換するために `/ 1000` しています

---

## 最後のページ問題への対処

GA4では `user_engagement` イベントがページ離脱時に発火するため、UAに比べて最後のページの滞在時間も取得しやすくなっています。

ただし、以下のケースでは `user_engagement` が発火しない可能性があります。

- ブラウザが強制終了された場合
- ネットワーク接続が切れた場合
- ページ遷移が極端に速い場合（エンゲージメント判定に至らない）

これらのケースに対応するには、`page_view` イベントのタイムスタンプ差分を補助指標として併用する方法があります。

```sql
WITH page_views AS (
  SELECT
    user_pseudo_id,
    event_timestamp,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    LEAD(event_timestamp) OVER (
      PARTITION BY user_pseudo_id,
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
      ORDER BY event_timestamp
    ) AS next_event_timestamp
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
    AND event_name = 'page_view'
)
SELECT
  REGEXP_EXTRACT(page_location, r'^https?://[^/]+(/.*)') AS page_path,
  COUNT(*) AS page_views,
  ROUND(AVG(
    CASE
      WHEN next_event_timestamp IS NOT NULL
      THEN (next_event_timestamp - event_timestamp) / 1000000
    END
  ), 1) AS avg_time_on_page_sec
FROM page_views
GROUP BY page_path
ORDER BY page_views DESC
LIMIT 50
```

:::message
`LEAD` 関数で次のイベントのタイムスタンプを取得し、差分を計算しています。最後のページは `next_event_timestamp` が `NULL` になるため、`CASE` で除外しています。この方法はUA時代の計測ロジックに近い補助的な手法です。
:::

---

## engagement_time_msecとタイムスタンプ差分の使い分け

| 指標 | メリット | デメリット |
|------|----------|------------|
| `engagement_time_msec` | フォアグラウンド時間を正確に計測 | `user_engagement` 未発火時は取得不可 |
| タイムスタンプ差分（LEAD） | すべてのページビューで計算可能 | バックグラウンド時間も含まれる |

実務では、`engagement_time_msec` をメインの指標として使いつつ、タイムスタンプ差分は「最後のページの滞在時間を補完する参考値」として併用するのがバランスの良いアプローチです。

---

## セッション単位で滞在時間を集計する

ページ単位だけでなく、セッション全体の滞在時間を知りたい場合もあります。

```sql
WITH session_engagement AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    SUM(
      (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'engagement_time_msec')
    ) AS total_engagement_msec
  FROM `beeracle.analytics_263425816.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
    AND event_name = 'user_engagement'
  GROUP BY user_pseudo_id, ga_session_id
)
SELECT
  COUNT(*) AS sessions,
  ROUND(AVG(total_engagement_msec) / 1000, 1) AS avg_session_engagement_sec,
  ROUND(APPROX_QUANTILES(total_engagement_msec / 1000, 100)[OFFSET(50)], 1) AS median_session_engagement_sec
FROM session_engagement
WHERE total_engagement_msec > 0
```

中央値（`APPROX_QUANTILES`）を一緒に出すと、外れ値に引っ張られない実態に近い数値が把握できます。

---

## まとめ

GA4の滞在時間計測はUAから大きく変わりました。BigQueryで集計する際は、`engagement_time_msec` を正しく `UNNEST` で展開し、フィルタリングすることが重要です。

自分としては、`engagement_time_msec` と `LEAD` によるタイムスタンプ差分を両方出しておいて、ページの特性に応じて使い分けるのが実務では一番使いやすいと感じています。

皆さんはページ別の滞在時間、どのように集計していますか？コメントで教えていただけると嬉しいです。

---

:::message
「GA4のデータをBigQueryで分析したいが、設計や実装に不安がある」という方は、お気軽にご相談ください。
👉 [GA4×BigQuery基盤構築サービス](https://coconala.com/services/1791205)
:::
