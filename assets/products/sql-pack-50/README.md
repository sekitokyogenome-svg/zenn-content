# GA4 × BigQuery 分析SQL 50本パック

GA4 の BigQuery エクスポートを前提にした、実務で使う分析SQLを 50 本まとめたものです。
**全てのSQLは BigQuery の方言でパース検証済み**で、コピーして `${PROJECT}` と `${DATASET}` を自社の値に置き換えればそのまま動きます。

GA4 の BigQuery スキーマは、実際に叩くと細部で動きません。`event_params` の型、`collected_traffic_source` の有無、パーティションの指定。収録したSQLは、その「動かない」を先に潰してあります。

## 収録内容

- BigQuery×GA4: 25 本
- EC向けデータ分析: 25 本

## 使い方

各SQLの `${PROJECT}` を GCP プロジェクトID、`${DATASET}` を GA4 のデータセット（`analytics_XXXXXXXXX`）に置き換えてください。
実行前に必ずドライランでスキャン量を確認することをおすすめします。

```bash
bq query --dry_run --use_legacy_sql=false '<SQLをここに貼る>'
```

---

## サンプル（3本を無料公開）

### 01. GA4×BigQueryでコンバージョン経路を分析するSQL（ファーストタッチ分析：最初に見たページ）

**用途**: ファーストタッチ分析：最初に見たページ

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

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
  FROM `${PROJECT}.${DATASET}.events_*`
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
  FROM `${PROJECT}.${DATASET}.events_*`
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

### 02. GA4×BigQueryでコンバージョン経路を分析するSQL（ラストタッチ分析：コンバージョン直前のページ）

**用途**: ラストタッチ分析：コンバージョン直前のページ

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

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
  FROM `${PROJECT}.${DATASET}.events_*`
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
  FROM `${PROJECT}.${DATASET}.events_*`
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

### 03. GA4×BigQueryでユーザーのファーストタッチ・ラストタッチを取得する（ラストタッチを取得するSQL）

**用途**: ラストタッチを取得するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH sessions AS (
  SELECT
    user_pseudo_id,
    event_timestamp,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    collected_traffic_source.manual_source AS session_source,
    collected_traffic_source.manual_medium AS session_medium
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'session_start'
    AND collected_traffic_source.manual_source IS NOT NULL
),

converters AS (
  SELECT DISTINCT
    user_pseudo_id
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
),

last_touch AS (
  SELECT DISTINCT
    s.user_pseudo_id,
    LAST_VALUE(s.session_source) OVER (
      PARTITION BY s.user_pseudo_id
      ORDER BY s.event_timestamp
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS last_touch_source,
    LAST_VALUE(s.session_medium) OVER (
      PARTITION BY s.user_pseudo_id
      ORDER BY s.event_timestamp
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS last_touch_medium
  FROM sessions s
  INNER JOIN converters c ON s.user_pseudo_id = c.user_pseudo_id
)

SELECT
  last_touch_source,
  last_touch_medium,
  COUNT(DISTINCT user_pseudo_id) AS converting_users
FROM last_touch
GROUP BY last_touch_source, last_touch_medium
ORDER BY converting_users DESC
LIMIT 20
```

---

## ここから先は購入者限定

### 04. BigQueryでGA4のeコマースイベントを完全解析する【purchase/add_to_cart】（ファネル分析：view_item → add_to_cart → purchase の転換率）

**用途**: ファネル分析：view_item → add_to_cart → purchase の転換率

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH funnel AS (
  SELECT
    event_name,
    COUNT(DISTINCT CONCAT(
      user_pseudo_id,
      (SELECT CAST(value.int_value AS STRING) FROM UNNEST(event_params) WHERE key = 'ga_session_id')
    )) AS unique_sessions
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20260101' AND '20260331'
    AND event_name IN ('view_item', 'add_to_cart', 'begin_checkout', 'purchase')
  GROUP BY
    event_name
)

SELECT
  event_name,
  unique_sessions,
  ROUND(
    SAFE_DIVIDE(
      unique_sessions,
      MAX(unique_sessions) OVER ()
    ) * 100, 1
  ) AS rate_from_top
FROM funnel
ORDER BY
  CASE event_name
    WHEN 'view_item' THEN 1
    WHEN 'add_to_cart' THEN 2
    WHEN 'begin_checkout' THEN 3
    WHEN 'purchase' THEN 4
  END
```

### 05. GA4×BigQueryでリピーターと新規ユーザーを分離して分析する（新規/リピーター別のセッション指標を比較する）

**用途**: 新規/リピーター別のセッション指標を比較する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH first_visit_date AS (
  SELECT
    user_pseudo_id,
    MIN(PARSE_DATE('%Y%m%d', event_date)) AS first_visit_date
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20250331'
    AND event_name = 'first_visit'
  GROUP BY user_pseudo_id
),

sessions AS (
  SELECT
    e.user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(e.event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    CASE
      WHEN f.first_visit_date BETWEEN '2025-03-01' AND '2025-03-31'
      THEN '新規'
      ELSE 'リピーター'
    END AS user_type,
    e.event_name
  FROM `${PROJECT}.${DATASET}.events_*` e
  LEFT JOIN first_visit_date f ON e.user_pseudo_id = f.user_pseudo_id
  WHERE e._TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
)

SELECT
  user_type,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))) AS sessions,
  ROUND(
    COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING)))
    / COUNT(DISTINCT user_pseudo_id), 2
  ) AS sessions_per_user,
  COUNTIF(event_name = 'purchase') AS purchases,
  ROUND(
    SAFE_DIVIDE(
      COUNTIF(event_name = 'purchase'),
      COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING)))
    ) * 100, 2
  ) AS purchase_rate_pct
FROM sessions
GROUP BY user_type
ORDER BY user_type
```

### 06. GA4×BigQueryでSearch Consoleデータを結合してオーガニック分析する（GA4 × Search Console結合クエリ）

**用途**: GA4 × Search Console結合クエリ

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH ga4_landing AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    REGEXP_EXTRACT(
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location'),
      r'^https?://[^/]+(/.*)$'
    ) AS page_path,
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'entrances') AS is_entrance,
    event_name
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
),

ga4_by_page AS (
  SELECT
    event_date,
    page_path,
    COUNT(DISTINCT CASE WHEN is_entrance = 1
      THEN CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))
    END) AS organic_sessions,
    COUNT(DISTINCT user_pseudo_id) AS users,
    COUNTIF(event_name = 'purchase') AS purchases
  FROM ga4_landing
  GROUP BY event_date, page_path
),

gsc AS (
  SELECT
    data_date AS event_date,
    REGEXP_EXTRACT(url, r'^https?://[^/]+(/.*)') AS page_path,
    SUM(impressions) AS impressions,
    SUM(clicks) AS clicks,
    ROUND(SAFE_DIVIDE(SUM(sum_position), SUM(impressions)), 1) AS avg_position
  FROM `your-project.searchconsole.searchdata_url_impression`
  WHERE data_date BETWEEN '2025-03-01' AND '2025-03-31'
  GROUP BY event_date, page_path
)

SELECT
  COALESCE(ga.page_path, gsc.page_path) AS page_path,
  SUM(gsc.impressions) AS search_impressions,
  SUM(gsc.clicks) AS search_clicks,
  ROUND(SAFE_DIVIDE(SUM(gsc.clicks), SUM(gsc.impressions)) * 100, 2) AS ctr_pct,
  ROUND(AVG(gsc.avg_position), 1) AS avg_position,
  SUM(ga.organic_sessions) AS site_sessions,
  SUM(ga.purchases) AS purchases,
  ROUND(SAFE_DIVIDE(SUM(ga.purchases), SUM(ga.organic_sessions)) * 100, 2) AS cvr_pct
FROM gsc
LEFT JOIN ga4_by_page ga
  ON gsc.event_date = ga.event_date
  AND gsc.page_path = ga.page_path
GROUP BY page_path
HAVING search_clicks >= 5
ORDER BY search_clicks DESC
LIMIT 30
```

### 07. BigQueryでGA4のページ別滞在時間を正しく集計する方法（最後のページ問題への対処）

**用途**: 最後のページ問題への対処

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

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
  FROM `${PROJECT}.${DATASET}.events_*`
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

### 08. GA4×BigQueryでカスタムディメンションを活用した分析（実践例2：会員ランク別の行動分析）

**用途**: 実践例2：会員ランク別の行動分析

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH user_tier AS (
  SELECT
    user_pseudo_id,
    (SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'membership_tier') AS membership_tier
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
    AND event_name = 'session_start'
    AND (SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'membership_tier') IS NOT NULL
),

user_events AS (
  SELECT
    e.user_pseudo_id,
    t.membership_tier,
    e.event_name,
    (SELECT value.int_value FROM UNNEST(e.event_params) WHERE key = 'ga_session_id') AS ga_session_id
  FROM `${PROJECT}.${DATASET}.events_*` e
  INNER JOIN user_tier t ON e.user_pseudo_id = t.user_pseudo_id
  WHERE e._TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
)

SELECT
  membership_tier,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))) AS sessions,
  COUNTIF(event_name = 'page_view') AS page_views,
  COUNTIF(event_name = 'add_to_cart') AS add_to_carts,
  COUNTIF(event_name = 'purchase') AS purchases
FROM user_events
GROUP BY membership_tier
ORDER BY users DESC
```

### 09. GA4×BigQueryでユーザーのファーストタッチ・ラストタッチを取得する（ファーストタッチを取得するSQL）

**用途**: ファーストタッチを取得するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH sessions AS (
  SELECT
    user_pseudo_id,
    event_timestamp,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    collected_traffic_source.manual_source AS session_source,
    collected_traffic_source.manual_medium AS session_medium
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'session_start'
),

first_touch AS (
  SELECT DISTINCT
    user_pseudo_id,
    FIRST_VALUE(session_source) OVER (
      PARTITION BY user_pseudo_id
      ORDER BY event_timestamp
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS first_touch_source,
    FIRST_VALUE(session_medium) OVER (
      PARTITION BY user_pseudo_id
      ORDER BY event_timestamp
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS first_touch_medium
  FROM sessions
  WHERE session_source IS NOT NULL
)

SELECT
  IFNULL(first_touch_source, '(direct)') AS first_touch_source,
  IFNULL(first_touch_medium, '(none)') AS first_touch_medium,
  COUNT(DISTINCT user_pseudo_id) AS users
FROM first_touch
GROUP BY first_touch_source, first_touch_medium
ORDER BY users DESC
LIMIT 20
```

### 10. GA4×BigQueryでリピーターと新規ユーザーを分離して分析する（応用パターン：初回訪問日を特定して分類する）

**用途**: 応用パターン：初回訪問日を特定して分類する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH first_visit_date AS (
  SELECT
    user_pseudo_id,
    MIN(PARSE_DATE('%Y%m%d', event_date)) AS first_visit_date
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20250331'
    AND event_name = 'first_visit'
  GROUP BY user_pseudo_id
),

target_users AS (
  SELECT DISTINCT
    user_pseudo_id
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
)

SELECT
  CASE
    WHEN f.first_visit_date BETWEEN '2025-03-01' AND '2025-03-31'
    THEN '新規'
    ELSE 'リピーター'
  END AS user_type,
  COUNT(DISTINCT t.user_pseudo_id) AS users
FROM target_users t
LEFT JOIN first_visit_date f ON t.user_pseudo_id = f.user_pseudo_id
GROUP BY user_type
```

### 11. GA4×BigQueryでカスタムディメンションを活用した分析（実践例1：ABテストのバリアント別コンバージョン分析）

**用途**: 実践例1：ABテストのバリアント別コンバージョン分析

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH ab_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ab_variant') AS ab_variant,
    event_name
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
)

SELECT
  ab_variant,
  COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases,
  ROUND(
    SAFE_DIVIDE(
      COUNTIF(event_name = 'purchase'),
      COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING)))
    ) * 100, 2
  ) AS cvr_pct
FROM ab_sessions
WHERE ab_variant IS NOT NULL
GROUP BY ab_variant
ORDER BY cvr_pct DESC
```

### 12. BigQueryでGA4のeコマースイベントを完全解析する【purchase/add_to_cart】（add_to_cart分析：カートに入れたが購入されなかった商品）

**用途**: add_to_cart分析：カートに入れたが購入されなかった商品

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH cart_items AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    item.item_id,
    item.item_name
  FROM
    `${PROJECT}.${DATASET}.events_*`,
    UNNEST(items) AS item
  WHERE
    _TABLE_SUFFIX BETWEEN '20260101' AND '20260331'
    AND event_name = 'add_to_cart'
),

purchased_items AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    item.item_id
  FROM
    `${PROJECT}.${DATASET}.events_*`,
    UNNEST(items) AS item
  WHERE
    _TABLE_SUFFIX BETWEEN '20260101' AND '20260331'
    AND event_name = 'purchase'
)

SELECT
  c.item_id,
  c.item_name,
  COUNT(*) AS cart_add_count,
  COUNTIF(p.item_id IS NOT NULL) AS purchase_count,
  COUNTIF(p.item_id IS NULL) AS abandoned_count,
  ROUND(
    SAFE_DIVIDE(COUNTIF(p.item_id IS NULL), COUNT(*)) * 100, 1
  ) AS abandonment_rate
FROM
  cart_items c
LEFT JOIN
  purchased_items p
  ON c.user_pseudo_id = p.user_pseudo_id
  AND c.ga_session_id = p.ga_session_id
  AND c.item_id = p.item_id
GROUP BY
  c.item_id, c.item_name
ORDER BY
  abandoned_count DESC
```

### 13. BigQueryでGA4のページ別滞在時間を正しく集計する方法（ページ別の平均滞在時間を集計するSQL）

**用途**: ページ別の平均滞在時間を集計するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH engagement AS (
  SELECT
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'engagement_time_msec') AS engagement_time_msec
  FROM `${PROJECT}.${DATASET}.events_*`
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

### 14. BigQueryでGA4の直帰率を正確に計算する方法（GA4に直帰率はない問題）（方法1：session_engagedを使う（推奨））

**用途**: 方法1：session_engagedを使う（推奨）

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH session_engagement AS (
  SELECT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    MAX(
      (SELECT value.string_value
       FROM UNNEST(event_params)
       WHERE key = 'session_engaged')
    ) AS session_engaged
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  GROUP BY session_id
)
SELECT
  COUNT(*) AS total_sessions,
  COUNTIF(session_engaged != '1' OR session_engaged IS NULL) AS bounced_sessions,
  ROUND(
    COUNTIF(session_engaged != '1' OR session_engaged IS NULL)
    / COUNT(*) * 100, 2
  ) AS bounce_rate_percent
FROM session_engagement
```

### 15. BigQueryでGA4の直帰率を正確に計算する方法（GA4に直帰率はない問題）（方法2：engagement_time_msecを使う）

**用途**: 方法2：engagement_time_msecを使う

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH session_metrics AS (
  SELECT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    SUM(
      IFNULL(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'engagement_time_msec'), 0)
    ) AS total_engagement_time_msec,
    COUNTIF(event_name = 'page_view') AS page_views
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  GROUP BY session_id
)
SELECT
  COUNT(*) AS total_sessions,
  COUNTIF(
    total_engagement_time_msec < 10000
    AND page_views <= 1
  ) AS bounced_sessions,
  ROUND(
    COUNTIF(
      total_engagement_time_msec < 10000
      AND page_views <= 1
    ) / COUNT(*) * 100, 2
  ) AS bounce_rate_percent
FROM session_metrics
```

### 16. GA4×BigQueryでデバイス別・地域別セグメント分析をする（デバイス別セッション数・コンバージョン率）

**用途**: デバイス別セッション数・コンバージョン率

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

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
    device.category AS device_category,
    event_name
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
),
session_summary AS (
  SELECT
    session_id,
    device_category,
    MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) AS has_purchase
  FROM sessions
  GROUP BY session_id, device_category
)
SELECT
  device_category,
  COUNT(*) AS sessions,
  SUM(has_purchase) AS cv_sessions,
  ROUND(SUM(has_purchase) / COUNT(*) * 100, 2) AS cv_rate_percent
FROM session_summary
GROUP BY device_category
ORDER BY sessions DESC
```

### 17. GA4×BigQueryでデバイス別・地域別セグメント分析をする（デバイス別×チャネル別のクロス集計）

**用途**: デバイス別×チャネル別のクロス集計

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

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
    device.category AS device_category,
    collected_traffic_source.manual_medium AS medium
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
    AND event_name = 'session_start'
)
SELECT
  device_category,
  IFNULL(medium, '(none)') AS medium,
  COUNT(DISTINCT session_id) AS sessions
FROM sessions
GROUP BY device_category, medium
ORDER BY device_category, sessions DESC
```

### 18. GA4×BigQueryでSearch Consoleデータを結合してオーガニック分析する（結合のためのGA4側の準備）

**用途**: 結合のためのGA4側の準備

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です / `SELECT *` を含みます。必要な列だけに絞るとコストが下がります

```sql
WITH ga4_landing AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    REGEXP_EXTRACT(
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location'),
      r'^https?://[^/]+(/.*)$'
    ) AS page_path,
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'entrances') AS is_entrance
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
    AND event_name = 'page_view'
),

ga4_sessions AS (
  SELECT
    event_date,
    page_path,
    COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))) AS sessions,
    COUNT(DISTINCT user_pseudo_id) AS users
  FROM ga4_landing
  WHERE is_entrance = 1
  GROUP BY event_date, page_path
)

SELECT * FROM ga4_sessions
```

### 19. GA4×BigQueryでセッションIDを正しく定義する方法（セッションごとのPV数）

**用途**: セッションごとのPV数

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

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
  FROM `${PROJECT}.${DATASET}.events_*`
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

### 20. GA4×BigQueryでセッションIDを正しく定義する方法（セッション開始時刻と流入元を紐づける）

**用途**: セッション開始時刻と流入元を紐づける

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

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
  FROM `${PROJECT}.${DATASET}.events_*`
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

### 21. GA4のデータをBigQueryに繋ぐと何が変わるのか【3層設計まで解説】

**用途**: mart層

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
CREATE OR REPLACE TABLE `project.mart.channel_summary` AS
SELECT
  event_date,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    CONCAT(user_pseudo_id, CAST(
      (SELECT value.int_value FROM UNNEST(event_params)
       WHERE key = 'ga_session_id') AS STRING))
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS conversions
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN
  FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
  AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY 1, 2, 3
```

### 22. BigQueryでGA4のサンプリングを回避して正確な数値を出す（BigQueryなら100%のデータで分析できる）

**用途**: BigQueryなら100%のデータで分析できる

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_date,
  collected_traffic_source.manual_medium AS medium,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    )
  ) AS sessions
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'session_start'
GROUP BY event_date, medium
ORDER BY event_date, sessions DESC
```

### 23. BigQueryでGA4のサンプリングを回避して正確な数値を出す（GA4 UIとBigQueryの数値を比較してみる）

**用途**: GA4 UIとBigQueryの数値を比較してみる

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  FORMAT_DATE('%Y%m%d',
    DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo')
  ) AS event_date_jst,
  COUNT(*) AS event_count
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
GROUP BY event_date_jst
ORDER BY event_date_jst
```

### 24. BigQueryでGA4データのコスト管理・クエリ最適化入門（テクニック3：中間テーブルやビューを活用する）

**用途**: テクニック3：中間テーブルやビューを活用する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
CREATE OR REPLACE TABLE `your-project.staging.sessions_202603` AS
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
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'session_start'
```

### 25. BigQueryでGA4データのコスト管理・クエリ最適化入門（パーティション）

**用途**: パーティション

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
CREATE OR REPLACE TABLE `your-project.staging.sessions_partitioned`
PARTITION BY event_date_parsed
CLUSTER BY medium
AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS event_date_parsed,
  CONCAT(
    user_pseudo_id, '.',
    CAST(
      (SELECT value.int_value
       FROM UNNEST(event_params)
       WHERE key = 'ga_session_id') AS STRING)
  ) AS session_id,
  collected_traffic_source.manual_medium AS medium,
  user_pseudo_id
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260101' AND '20260330'
  AND event_name = 'session_start'
```

### 26. ユーザーの閲覧から購入までの日数分布をBigQueryで可視化する（リマーケティング期間の設定根拠）

**用途**: リマーケティング期間の設定根拠

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH first_visits AS (
  SELECT
    user_pseudo_id,
    MIN(DATE(TIMESTAMP_MICROS(event_timestamp))) AS first_visit_date
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'first_visit'
  GROUP BY user_pseudo_id
),

first_purchases AS (
  SELECT
    user_pseudo_id,
    MIN(DATE(TIMESTAMP_MICROS(event_timestamp))) AS first_purchase_date
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
),

days_calc AS (
  SELECT
    DATE_DIFF(fp.first_purchase_date, fv.first_visit_date, DAY) AS days_to_purchase
  FROM first_visits fv
  INNER JOIN first_purchases fp ON fv.user_pseudo_id = fp.user_pseudo_id
)

SELECT
  days_to_purchase,
  COUNT(*) AS users,
  SUM(COUNT(*)) OVER(ORDER BY days_to_purchase) AS cumulative_users,
  ROUND(SUM(COUNT(*)) OVER(ORDER BY days_to_purchase) / SUM(COUNT(*)) OVER() * 100, 1) AS cumulative_pct
FROM days_calc
WHERE days_to_purchase <= 30
GROUP BY days_to_purchase
ORDER BY days_to_purchase
```

### 27. BigQueryで1回しか買わない顧客と2回以上買う顧客の行動差を分析した（流入元の違いを確認する）

**用途**: 流入元の違いを確認する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH purchase_counts AS (
  SELECT
    user_pseudo_id,
    COUNT(*) AS purchase_count
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
),

buyer_type AS (
  SELECT
    user_pseudo_id,
    CASE WHEN purchase_count = 1 THEN 'one_time' ELSE 'repeat' END AS buyer_type
  FROM purchase_counts
),

first_touch AS (
  SELECT
    e.user_pseudo_id,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium,
    ROW_NUMBER() OVER(PARTITION BY e.user_pseudo_id ORDER BY e.event_timestamp) AS rn
  FROM `${PROJECT}.${DATASET}.events_*` e
  INNER JOIN buyer_type bt ON e.user_pseudo_id = bt.user_pseudo_id
  WHERE e._TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND e.event_name = 'session_start'
)

SELECT
  bt.buyer_type,
  ft.source,
  ft.medium,
  COUNT(*) AS users
FROM first_touch ft
INNER JOIN buyer_type bt ON ft.user_pseudo_id = bt.user_pseudo_id
WHERE ft.rn = 1
GROUP BY bt.buyer_type, ft.source, ft.medium
ORDER BY bt.buyer_type, users DESC
```

### 28. BigQueryでEC商品別の粗利×CVR×流入数をまとめた利益ダッシュボードを作った

**用途**: 商品別の流入数とCVRを算出するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH product_views AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_id') AS item_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_name') AS item_name
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'view_item'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
),
product_purchases AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_id') AS item_id,
    ecommerce.purchase_revenue AS revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
    AND ecommerce.purchase_revenue > 0
)
SELECT
  v.item_id,
  v.item_name,
  COUNT(DISTINCT CONCAT(v.user_pseudo_id, '-', CAST(v.ga_session_id AS STRING))) AS view_sessions,
  COUNT(DISTINCT CONCAT(p.user_pseudo_id, '-', CAST(p.ga_session_id AS STRING))) AS purchase_sessions,
  ROUND(
    SAFE_DIVIDE(
      COUNT(DISTINCT CONCAT(p.user_pseudo_id, '-', CAST(p.ga_session_id AS STRING))),
      COUNT(DISTINCT CONCAT(v.user_pseudo_id, '-', CAST(v.ga_session_id AS STRING)))
    ) * 100, 2
  ) AS cvr,
  SUM(p.revenue) AS total_revenue
FROM product_views v
LEFT JOIN product_purchases p
  ON v.user_pseudo_id = p.user_pseudo_id
  AND v.ga_session_id = p.ga_session_id
  AND v.item_id = p.item_id
GROUP BY v.item_id, v.item_name
HAVING view_sessions >= 10
ORDER BY total_revenue DESC;
```

### 29. ECの季節変動をBigQueryで前年比分析して仕入れ計画に活かす方法（月別売上の前年比SQL）

**用途**: 月別売上の前年比SQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH monthly_revenue AS (
  SELECT
    FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m%d', event_date)) AS year_month,
    EXTRACT(YEAR FROM PARSE_DATE('%Y%m%d', event_date)) AS year,
    EXTRACT(MONTH FROM PARSE_DATE('%Y%m%d', event_date)) AS month,
    SUM(ecommerce.purchase_revenue) AS revenue,
    COUNT(DISTINCT user_pseudo_id) AS purchasers
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'purchase'
    AND ecommerce.purchase_revenue > 0
    AND _TABLE_SUFFIX BETWEEN '20250101' AND '20260331'
  GROUP BY year_month, year, month
)
SELECT
  curr.month,
  curr.year_month AS current_period,
  curr.revenue AS current_revenue,
  prev.revenue AS prev_revenue,
  curr.purchasers AS current_purchasers,
  prev.purchasers AS prev_purchasers,
  ROUND(SAFE_DIVIDE(curr.revenue - prev.revenue, prev.revenue) * 100, 1) AS revenue_yoy_pct,
  ROUND(SAFE_DIVIDE(curr.purchasers - prev.purchasers, prev.purchasers) * 100, 1) AS purchasers_yoy_pct
FROM monthly_revenue curr
LEFT JOIN monthly_revenue prev
  ON curr.month = prev.month
  AND curr.year = prev.year + 1
WHERE curr.year = 2026
ORDER BY curr.month;
```

### 30. ECの季節変動をBigQueryで前年比分析して仕入れ計画に活かす方法（週別売上の前年比SQL）

**用途**: 週別売上の前年比SQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH weekly_revenue AS (
  SELECT
    EXTRACT(ISOYEAR FROM PARSE_DATE('%Y%m%d', event_date)) AS iso_year,
    EXTRACT(ISOWEEK FROM PARSE_DATE('%Y%m%d', event_date)) AS iso_week,
    SUM(ecommerce.purchase_revenue) AS revenue,
    COUNT(DISTINCT
      CONCAT(
        user_pseudo_id, '-',
        CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
      )
    ) AS purchase_sessions
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'purchase'
    AND ecommerce.purchase_revenue > 0
    AND _TABLE_SUFFIX BETWEEN '20250101' AND '20260331'
  GROUP BY iso_year, iso_week
)
SELECT
  curr.iso_week,
  curr.revenue AS current_revenue,
  prev.revenue AS prev_revenue,
  ROUND(SAFE_DIVIDE(curr.revenue - prev.revenue, prev.revenue) * 100, 1) AS revenue_yoy_pct,
  curr.purchase_sessions AS current_sessions,
  prev.purchase_sessions AS prev_sessions
FROM weekly_revenue curr
LEFT JOIN weekly_revenue prev
  ON curr.iso_week = prev.iso_week
  AND curr.iso_year = prev.iso_year + 1
WHERE curr.iso_year = 2026
ORDER BY curr.iso_week;
```

### 31. GA4×BigQueryでモバイルとPCの購買行動の違いを分析した（デバイス別の基本指標を比較する）

**用途**: デバイス別の基本指標を比較する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    device.category AS device_category
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'session_start'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
),
purchases AS (
  SELECT DISTINCT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
)
SELECT
  s.device_category,
  COUNT(DISTINCT CONCAT(s.user_pseudo_id, '-', CAST(s.ga_session_id AS STRING))) AS sessions,
  COUNT(DISTINCT CONCAT(p.user_pseudo_id, '-', CAST(p.ga_session_id AS STRING))) AS purchase_sessions,
  ROUND(
    SAFE_DIVIDE(
      COUNT(DISTINCT CONCAT(p.user_pseudo_id, '-', CAST(p.ga_session_id AS STRING))),
      COUNT(DISTINCT CONCAT(s.user_pseudo_id, '-', CAST(s.ga_session_id AS STRING)))
    ) * 100, 2
  ) AS cvr
FROM sessions s
LEFT JOIN purchases p
  ON s.user_pseudo_id = p.user_pseudo_id
  AND s.ga_session_id = p.ga_session_id
GROUP BY s.device_category
ORDER BY sessions DESC;
```

### 32. BigQueryで売上上位20%の商品が生み出す収益構造をパレート分析した（Step 1: 商品別売上集計SQL）

**用途**: Step 1: 商品別売上集計SQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH item_revenue AS (
  SELECT
    items.item_name,
    items.item_id,
    SUM(items.item_revenue) AS total_revenue,
    COUNT(DISTINCT event_bundle_sequence_id) AS purchase_count
  FROM
    `${PROJECT}.${DATASET}.events_*`,
    UNNEST(items) AS items
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
    AND items.item_revenue > 0
  GROUP BY
    items.item_name, items.item_id
)
SELECT
  item_name,
  item_id,
  total_revenue,
  purchase_count,
  ROUND(total_revenue / SUM(total_revenue) OVER () * 100, 2) AS revenue_pct
FROM item_revenue
ORDER BY total_revenue DESC
```

### 33. BigQueryで売上上位20%の商品が生み出す収益構造をパレート分析した（Step 2: 累積比率を算出してパレート曲線を描く）

**用途**: Step 2: 累積比率を算出してパレート曲線を描く

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です / `SELECT *` を含みます。必要な列だけに絞るとコストが下がります

```sql
WITH item_revenue AS (
  SELECT
    items.item_name,
    items.item_id,
    SUM(items.item_revenue) AS total_revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`,
    UNNEST(items) AS items
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
    AND items.item_revenue > 0
  GROUP BY
    items.item_name, items.item_id
),
ranked AS (
  SELECT
    item_name,
    item_id,
    total_revenue,
    ROW_NUMBER() OVER (ORDER BY total_revenue DESC) AS rank,
    COUNT(*) OVER () AS total_items,
    SUM(total_revenue) OVER () AS grand_total
  FROM item_revenue
),
cumulative AS (
  SELECT
    *,
    SUM(total_revenue) OVER (ORDER BY rank) AS cumulative_revenue,
    ROUND(rank / total_items * 100, 2) AS item_pct,
    ROUND(SUM(total_revenue) OVER (ORDER BY rank) / grand_total * 100, 2) AS cumulative_revenue_pct
  FROM ranked
)
SELECT
  rank,
  item_name,
  total_revenue,
  item_pct,
  cumulative_revenue_pct,
  CASE
    WHEN cumulative_revenue_pct <= 80 THEN 'A'
    WHEN cumulative_revenue_pct <= 95 THEN 'B'
    ELSE 'C'
  END AS abc_rank
FROM cumulative
ORDER BY rank
```

### 34. BigQueryでEC顧客をRFM分析してセグメント別メルマガ戦略を立てた

**用途**: RFMスコアを算出するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH purchases AS (
  SELECT
    user_pseudo_id,
    PARSE_DATE('%Y%m%d', event_date) AS purchase_date,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    ecommerce.purchase_revenue AS revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20250401' AND '20260331'
    AND ecommerce.purchase_revenue > 0
),
user_rfm AS (
  SELECT
    user_pseudo_id,
    DATE_DIFF(CURRENT_DATE(), MAX(purchase_date), DAY) AS recency,
    COUNT(DISTINCT CONCAT(CAST(purchase_date AS STRING), '-', CAST(ga_session_id AS STRING))) AS frequency,
    SUM(revenue) AS monetary
  FROM purchases
  GROUP BY user_pseudo_id
)
SELECT
  user_pseudo_id,
  recency,
  frequency,
  monetary,
  NTILE(5) OVER (ORDER BY recency ASC) AS r_score,
  NTILE(5) OVER (ORDER BY frequency DESC) AS f_score,
  NTILE(5) OVER (ORDER BY monetary DESC) AS m_score
FROM user_rfm;
```

### 35. BigQueryでGA4データからEC顧客の年齢・性別推定精度を検証した（Step 2: デモグラフィック別のセグメント分析）

**用途**: Step 2: デモグラフィック別のセグメント分析

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH user_demo AS (
  SELECT
    user_pseudo_id,
    MAX((SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'age')) AS age_bracket,
    MAX((SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'gender')) AS gender
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
  GROUP BY user_pseudo_id
)
SELECT
  age_bracket,
  gender,
  COUNT(*) AS user_count,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER () * 100, 1) AS pct
FROM user_demo
WHERE age_bracket IS NOT NULL
  AND gender IS NOT NULL
GROUP BY age_bracket, gender
ORDER BY user_count DESC
```

### 36. BigQueryでGA4データからEC顧客の年齢・性別推定精度を検証した（Step 3: デモグラフィック別の購買行動比較）

**用途**: Step 3: デモグラフィック別の購買行動比較

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH user_demo AS (
  SELECT
    user_pseudo_id,
    MAX((SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'age')) AS age_bracket,
    MAX((SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'gender')) AS gender
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
  GROUP BY user_pseudo_id
),
user_purchases AS (
  SELECT
    user_pseudo_id,
    COUNT(*) AS purchase_count,
    SUM(ecommerce.purchase_revenue) AS total_revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
)
SELECT
  CASE
    WHEN ud.age_bracket IS NOT NULL THEN 'デモグラ取得済み'
    ELSE 'デモグラ未取得'
  END AS demo_status,
  COUNT(DISTINCT up.user_pseudo_id) AS purchasers,
  ROUND(AVG(up.purchase_count), 2) AS avg_purchases,
  ROUND(AVG(up.total_revenue), 0) AS avg_revenue
FROM user_purchases up
LEFT JOIN user_demo ud
  ON up.user_pseudo_id = ud.user_pseudo_id
GROUP BY demo_status
```

### 37. ユーザーの閲覧から購入までの日数分布をBigQueryで可視化する（初回訪問日と初回購入日を取得するSQL）

**用途**: 初回訪問日と初回購入日を取得するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH first_visits AS (
  SELECT
    user_pseudo_id,
    MIN(DATE(TIMESTAMP_MICROS(event_timestamp))) AS first_visit_date
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'first_visit'
  GROUP BY user_pseudo_id
),

first_purchases AS (
  SELECT
    user_pseudo_id,
    MIN(DATE(TIMESTAMP_MICROS(event_timestamp))) AS first_purchase_date
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
)

SELECT
  fv.user_pseudo_id,
  fv.first_visit_date,
  fp.first_purchase_date,
  DATE_DIFF(fp.first_purchase_date, fv.first_visit_date, DAY) AS days_to_purchase
FROM first_visits fv
INNER JOIN first_purchases fp ON fv.user_pseudo_id = fp.user_pseudo_id
```

### 38. BigQueryで1回しか買わない顧客と2回以上買う顧客の行動差を分析した（初回セッションの行動指標を比較する）

**用途**: 初回セッションの行動指標を比較する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH purchase_counts AS (
  SELECT
    user_pseudo_id,
    COUNT(*) AS purchase_count
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
),

buyer_type AS (
  SELECT
    user_pseudo_id,
    CASE WHEN purchase_count = 1 THEN 'one_time' ELSE 'repeat' END AS buyer_type
  FROM purchase_counts
),

first_sessions AS (
  SELECT
    e.user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(e.event_params) WHERE key = 'ga_session_id') AS session_id,
    e.event_name,
    (SELECT value.int_value FROM UNNEST(e.event_params) WHERE key = 'engagement_time_msec') AS engagement_time_msec,
    ROW_NUMBER() OVER(
      PARTITION BY e.user_pseudo_id
      ORDER BY e.event_timestamp
    ) AS event_seq
  FROM `${PROJECT}.${DATASET}.events_*` e
  INNER JOIN buyer_type bt ON e.user_pseudo_id = bt.user_pseudo_id
  WHERE e._TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
),

first_session_ids AS (
  SELECT DISTINCT user_pseudo_id, session_id
  FROM first_sessions
  WHERE event_seq = 1
),

first_session_metrics AS (
  SELECT
    fs.user_pseudo_id,
    fsi.session_id,
    COUNTIF(fs.event_name = 'page_view') AS page_views,
    SUM(fs.engagement_time_msec) / 1000 AS engagement_sec,
    MAX(IF(fs.event_name = 'add_to_cart', 1, 0)) AS has_add_to_cart,
    MAX(IF(fs.event_name = 'view_item', 1, 0)) AS has_view_item
  FROM first_sessions fs
  INNER JOIN first_session_ids fsi
    ON fs.user_pseudo_id = fsi.user_pseudo_id
    AND fs.session_id = fsi.session_id
  GROUP BY fs.user_pseudo_id, fsi.session_id
)

SELECT
  bt.buyer_type,
  COUNT(*) AS users,
  ROUND(AVG(fsm.page_views), 1) AS avg_page_views,
  ROUND(AVG(fsm.engagement_sec), 1) AS avg_engagement_sec,
  ROUND(COUNTIF(fsm.has_view_item = 1) / COUNT(*) * 100, 1) AS view_item_rate,
  ROUND(COUNTIF(fsm.has_add_to_cart = 1) / COUNT(*) * 100, 1) AS add_to_cart_rate
FROM first_session_metrics fsm
INNER JOIN buyer_type bt ON fsm.user_pseudo_id = bt.user_pseudo_id
GROUP BY bt.buyer_type
```

### 39. GA4×BigQueryでEC新規顧客獲得コスト（CAC）を媒体別に正確計算する（チャネル別の新規購入者数を算出するSQL）

**用途**: チャネル別の新規購入者数を算出するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH first_purchase AS (
  SELECT
    user_pseudo_id,
    MIN(event_timestamp) AS first_purchase_timestamp
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
),

first_purchase_detail AS (
  SELECT
    e.user_pseudo_id,
    CASE
      WHEN e.collected_traffic_source.manual_medium = 'cpc' THEN 'Paid Search'
      WHEN e.collected_traffic_source.manual_medium = 'organic' THEN 'Organic Search'
      WHEN e.collected_traffic_source.manual_medium = 'social' THEN 'Social'
      WHEN e.collected_traffic_source.manual_medium = 'email' THEN 'Email'
      WHEN e.collected_traffic_source.manual_medium = 'referral' THEN 'Referral'
      WHEN e.collected_traffic_source.manual_medium IS NULL
        OR e.collected_traffic_source.manual_medium = '(none)' THEN 'Direct'
      ELSE 'Other'
    END AS channel,
    e.collected_traffic_source.manual_source AS source,
    e.ecommerce.purchase_revenue AS revenue
  FROM `${PROJECT}.${DATASET}.events_*` e
  INNER JOIN first_purchase fp
    ON e.user_pseudo_id = fp.user_pseudo_id
    AND e.event_timestamp = fp.first_purchase_timestamp
  WHERE e._TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND e.event_name = 'purchase'
)

SELECT
  channel,
  source,
  COUNT(DISTINCT user_pseudo_id) AS new_customers,
  ROUND(SUM(revenue), 0) AS first_purchase_revenue,
  ROUND(AVG(revenue), 0) AS avg_first_purchase_value
FROM first_purchase_detail
GROUP BY channel, source
ORDER BY new_customers DESC
```

### 40. GA4×BigQueryでEC新規顧客獲得コスト（CAC）を媒体別に正確計算する（方法1: 手動でCTEに記述する）

**用途**: 方法1: 手動でCTEに記述する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH ad_costs AS (
  SELECT 'Paid Search' AS channel, 'google' AS source, 350000 AS monthly_cost UNION ALL
  SELECT 'Paid Search', 'yahoo', 150000 UNION ALL
  SELECT 'Social', 'instagram', 80000 UNION ALL
  SELECT 'Social', 'tiktok', 120000
),

first_purchase AS (
  SELECT
    user_pseudo_id,
    MIN(event_timestamp) AS first_purchase_timestamp
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
),

first_purchase_channel AS (
  SELECT
    e.user_pseudo_id,
    CASE
      WHEN e.collected_traffic_source.manual_medium = 'cpc' THEN 'Paid Search'
      WHEN e.collected_traffic_source.manual_medium = 'social' THEN 'Social'
      ELSE 'Other'
    END AS channel,
    e.collected_traffic_source.manual_source AS source
  FROM `${PROJECT}.${DATASET}.events_*` e
  INNER JOIN first_purchase fp
    ON e.user_pseudo_id = fp.user_pseudo_id
    AND e.event_timestamp = fp.first_purchase_timestamp
  WHERE e._TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND e.event_name = 'purchase'
    AND e.collected_traffic_source.manual_medium IN ('cpc', 'social')
),

new_customers_by_source AS (
  SELECT
    channel,
    source,
    COUNT(DISTINCT user_pseudo_id) AS new_customers
  FROM first_purchase_channel
  GROUP BY channel, source
)

SELECT
  nc.channel,
  nc.source,
  nc.new_customers,
  ac.monthly_cost,
  ROUND(ac.monthly_cost / NULLIF(nc.new_customers, 0), 0) AS cac
FROM new_customers_by_source nc
INNER JOIN ad_costs ac ON nc.channel = ac.channel AND nc.source = ac.source
ORDER BY cac
```

### 41. GA4×BigQueryでカート放棄率を正確に計測・改善する方法（デバイス別のカート放棄率）

**用途**: デバイス別のカート放棄率

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH add_to_cart_users AS (
  SELECT DISTINCT
    user_pseudo_id,
    device.category AS device_category
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'add_to_cart'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
),
purchase_users AS (
  SELECT DISTINCT user_pseudo_id
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
)
SELECT
  a.device_category,
  COUNT(*) AS total_add_to_cart_users,
  COUNTIF(p.user_pseudo_id IS NULL) AS abandoned_users,
  ROUND(
    COUNTIF(p.user_pseudo_id IS NULL) / COUNT(*) * 100, 1
  ) AS cart_abandonment_rate
FROM add_to_cart_users a
LEFT JOIN purchase_users p
  ON a.user_pseudo_id = p.user_pseudo_id
GROUP BY a.device_category
ORDER BY cart_abandonment_rate DESC;
```

### 42. GA4×BigQueryでカート放棄率を正確に計測・改善する方法（流入元別のカート放棄率）

**用途**: 流入元別のカート放棄率

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH add_to_cart_users AS (
  SELECT DISTINCT
    user_pseudo_id,
    collected_traffic_source.manual_source AS traffic_source,
    collected_traffic_source.manual_medium AS traffic_medium
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'add_to_cart'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
),
purchase_users AS (
  SELECT DISTINCT user_pseudo_id
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
)
SELECT
  a.traffic_source,
  a.traffic_medium,
  COUNT(*) AS total_add_to_cart_users,
  COUNTIF(p.user_pseudo_id IS NULL) AS abandoned_users,
  ROUND(
    COUNTIF(p.user_pseudo_id IS NULL) / COUNT(*) * 100, 1
  ) AS cart_abandonment_rate
FROM add_to_cart_users a
LEFT JOIN purchase_users p
  ON a.user_pseudo_id = p.user_pseudo_id
GROUP BY a.traffic_source, a.traffic_medium
HAVING COUNT(*) >= 10
ORDER BY cart_abandonment_rate DESC;
```

### 43. GA4×BigQueryでメルマガのROIを正確に測定する（セッションをまたいだアトリビューション）

**用途**: セッションをまたいだアトリビューション

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH email_clicks AS (
  -- メルマガ経由で訪問したユーザーとその日時
  SELECT
    user_pseudo_id,
    collected_traffic_source.manual_campaign AS campaign,
    MIN(TIMESTAMP_MICROS(event_timestamp)) AS email_click_time
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND collected_traffic_source.manual_medium = 'email'
    AND event_name = 'session_start'
  GROUP BY user_pseudo_id, campaign
),

purchases AS (
  SELECT
    user_pseudo_id,
    TIMESTAMP_MICROS(event_timestamp) AS purchase_time,
    ecommerce.purchase_revenue AS revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
)

SELECT
  ec.campaign,
  COUNT(DISTINCT ec.user_pseudo_id) AS email_visitors,
  -- 直接CV（同日購入）
  COUNT(DISTINCT IF(
    DATE(p.purchase_time) = DATE(ec.email_click_time),
    ec.user_pseudo_id, NULL
  )) AS same_day_purchasers,
  -- 間接CV（7日以内に購入）
  COUNT(DISTINCT IF(
    p.purchase_time BETWEEN ec.email_click_time AND TIMESTAMP_ADD(ec.email_click_time, INTERVAL 7 DAY),
    ec.user_pseudo_id, NULL
  )) AS purchasers_within_7d,
  -- 7日以内の売上合計
  ROUND(SUM(IF(
    p.purchase_time BETWEEN ec.email_click_time AND TIMESTAMP_ADD(ec.email_click_time, INTERVAL 7 DAY),
    p.revenue, 0
  )), 0) AS revenue_within_7d
FROM email_clicks ec
LEFT JOIN purchases p ON ec.user_pseudo_id = p.user_pseudo_id
  AND p.purchase_time >= ec.email_click_time
GROUP BY ec.campaign
ORDER BY revenue_within_7d DESC
```

### 44. GA4×BigQueryでメルマガのROIを正確に測定する（ROIを算出する）

**用途**: ROIを算出する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH campaign_costs AS (
  SELECT 'spring_sale_2025' AS campaign, 15000 AS cost UNION ALL
  SELECT 'weekly_20250301', 5000 UNION ALL
  SELECT 'weekly_20250308', 5000 UNION ALL
  SELECT 'weekly_20250315', 5000
),

email_revenue AS (
  SELECT
    collected_traffic_source.manual_campaign AS campaign,
    SUM(ecommerce.purchase_revenue) AS revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND collected_traffic_source.manual_medium = 'email'
    AND event_name = 'purchase'
  GROUP BY campaign
)

SELECT
  er.campaign,
  cc.cost,
  ROUND(er.revenue, 0) AS revenue,
  ROUND((er.revenue - cc.cost) / cc.cost * 100, 1) AS roi_pct
FROM email_revenue er
INNER JOIN campaign_costs cc ON er.campaign = cc.campaign
ORDER BY roi_pct DESC
```

### 45. GA4×BigQueryでGoogle広告のキーワード別CVRを正確に測定する

**用途**: キーワード別CVRを算出するSQL

**必要なテーブル**: `${DATASET}.ads_click_keyword`, `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH ga4_gclid AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    REGEXP_EXTRACT(
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location'),
      r'gclid=([^&]+)'
    ) AS gclid,
    event_name
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
    AND collected_traffic_source.manual_medium = 'cpc'
    AND collected_traffic_source.manual_source = 'google'
),
sessions AS (
  SELECT DISTINCT
    user_pseudo_id,
    ga_session_id,
    gclid
  FROM ga4_gclid
  WHERE gclid IS NOT NULL
),
conversions AS (
  SELECT DISTINCT
    user_pseudo_id,
    ga_session_id
  FROM ga4_gclid
  WHERE event_name = 'purchase'
),
keyword_sessions AS (
  SELECT
    ak.keyword,
    ak.match_type,
    ak.campaign_name,
    s.user_pseudo_id,
    s.ga_session_id,
    CASE WHEN c.ga_session_id IS NOT NULL THEN 1 ELSE 0 END AS is_cv
  FROM sessions s
  JOIN `${PROJECT}.${DATASET}.ads_click_keyword` ak
    ON s.gclid = ak.gclid
  LEFT JOIN conversions c
    ON s.user_pseudo_id = c.user_pseudo_id
    AND s.ga_session_id = c.ga_session_id
)
SELECT
  keyword,
  match_type,
  campaign_name,
  COUNT(*) AS sessions,
  SUM(is_cv) AS conversions,
  ROUND(SUM(is_cv) / COUNT(*) * 100, 2) AS cvr
FROM keyword_sessions
GROUP BY keyword, match_type, campaign_name
HAVING sessions >= 5
ORDER BY sessions DESC;
```

### 46. GA4×BigQueryでモバイルとPCの購買行動の違いを分析した（モバイルの離脱ポイントを深掘りする）

**用途**: モバイルの離脱ポイントを深掘りする

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH cart_users AS (
  SELECT
    user_pseudo_id,
    MIN(event_timestamp) AS cart_time
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'add_to_cart'
    AND device.category = 'mobile'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
  GROUP BY user_pseudo_id
),
purchase_users AS (
  SELECT
    user_pseudo_id,
    MIN(event_timestamp) AS purchase_time
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
  GROUP BY user_pseudo_id
)
SELECT
  CASE
    WHEN p.user_pseudo_id IS NULL THEN '未購入'
    WHEN TIMESTAMP_DIFF(
      TIMESTAMP_MICROS(p.purchase_time),
      TIMESTAMP_MICROS(c.cart_time),
      HOUR
    ) <= 1 THEN '1時間以内'
    WHEN TIMESTAMP_DIFF(
      TIMESTAMP_MICROS(p.purchase_time),
      TIMESTAMP_MICROS(c.cart_time),
      HOUR
    ) <= 24 THEN '24時間以内'
    WHEN TIMESTAMP_DIFF(
      TIMESTAMP_MICROS(p.purchase_time),
      TIMESTAMP_MICROS(c.cart_time),
      HOUR
    ) <= 168 THEN '1週間以内'
    ELSE '1週間以上'
  END AS purchase_timing,
  COUNT(*) AS user_count
FROM cart_users c
LEFT JOIN purchase_users p
  ON c.user_pseudo_id = p.user_pseudo_id
GROUP BY purchase_timing
ORDER BY
  CASE purchase_timing
    WHEN '1時間以内' THEN 1
    WHEN '24時間以内' THEN 2
    WHEN '1週間以内' THEN 3
    WHEN '1週間以上' THEN 4
    WHEN '未購入' THEN 5
  END;
```

### 47. GA4×BigQueryでポイント還元施策の効果をコホート分析で検証した（Step 2: コホート別の月次購入回数）

**用途**: Step 2: コホート別の月次購入回数

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH first_purchase AS (
  SELECT
    user_pseudo_id,
    DATE(TIMESTAMP_MICROS(MIN(event_timestamp)), 'Asia/Tokyo') AS first_purchase_date,
    FORMAT_DATE('%Y-%m',
      DATE(TIMESTAMP_MICROS(MIN(event_timestamp)), 'Asia/Tokyo')
    ) AS cohort_month
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250301' AND '20250430'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
),
subsequent_purchases AS (
  SELECT
    e.user_pseudo_id,
    fp.cohort_month,
    DATE_DIFF(
      DATE(TIMESTAMP_MICROS(e.event_timestamp), 'Asia/Tokyo'),
      fp.first_purchase_date,
      MONTH
    ) AS months_after
  FROM
    `${PROJECT}.${DATASET}.events_*` e
  INNER JOIN first_purchase fp
    ON e.user_pseudo_id = fp.user_pseudo_id
  WHERE
    e._TABLE_SUFFIX BETWEEN '20250301' AND '20251231'
    AND e.event_name = 'purchase'
    AND fp.cohort_month IN ('2025-03', '2025-04')
)
SELECT
  cohort_month,
  CASE
    WHEN cohort_month = '2025-03' THEN '施策前'
    WHEN cohort_month = '2025-04' THEN '施策後'
  END AS cohort_label,
  months_after,
  COUNT(DISTINCT user_pseudo_id) AS active_users,
  COUNT(*) AS total_purchases
FROM subsequent_purchases
WHERE months_after BETWEEN 0 AND 6
GROUP BY cohort_month, cohort_label, months_after
ORDER BY cohort_month, months_after
```

### 48. GA4×BigQueryでポイント還元施策の効果をコホート分析で検証した（Step 3: コホート別LTVの比較）

**用途**: Step 3: コホート別LTVの比較

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH first_purchase AS (
  SELECT
    user_pseudo_id,
    DATE(TIMESTAMP_MICROS(MIN(event_timestamp)), 'Asia/Tokyo') AS first_purchase_date,
    FORMAT_DATE('%Y-%m',
      DATE(TIMESTAMP_MICROS(MIN(event_timestamp)), 'Asia/Tokyo')
    ) AS cohort_month
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250301' AND '20250430'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
),
user_ltv AS (
  SELECT
    fp.user_pseudo_id,
    fp.cohort_month,
    COUNT(*) AS purchase_count,
    SUM(e.ecommerce.purchase_revenue) AS total_revenue
  FROM
    `${PROJECT}.${DATASET}.events_*` e
  INNER JOIN first_purchase fp
    ON e.user_pseudo_id = fp.user_pseudo_id
  WHERE
    e._TABLE_SUFFIX BETWEEN '20250301' AND '20251231'
    AND e.event_name = 'purchase'
    AND fp.cohort_month IN ('2025-03', '2025-04')
    AND DATE_DIFF(
      DATE(TIMESTAMP_MICROS(e.event_timestamp), 'Asia/Tokyo'),
      fp.first_purchase_date,
      DAY
    ) <= 180
  GROUP BY fp.user_pseudo_id, fp.cohort_month
)
SELECT
  cohort_month,
  CASE
    WHEN cohort_month = '2025-03' THEN '施策前'
    WHEN cohort_month = '2025-04' THEN '施策後'
  END AS cohort_label,
  COUNT(*) AS customers,
  ROUND(AVG(purchase_count), 2) AS avg_purchases,
  ROUND(AVG(total_revenue), 0) AS avg_ltv_180d,
  ROUND(STDDEV(total_revenue), 0) AS stddev_ltv
FROM user_ltv
GROUP BY cohort_month, cohort_label
ORDER BY cohort_month
```

### 49. EC商品ページの離脱率をGA4×BigQueryで分析して改善につなげた事例

**用途**: 基本SQL：商品ページ別の離脱率を算出する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH session_pages AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
    event_timestamp
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'page_view'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
),
last_page_per_session AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    ARRAY_AGG(page_location ORDER BY event_timestamp DESC LIMIT 1)[OFFSET(0)] AS exit_page
  FROM session_pages
  GROUP BY user_pseudo_id, ga_session_id
),
product_page_views AS (
  SELECT
    sp.user_pseudo_id,
    sp.ga_session_id,
    sp.page_location,
    CASE WHEN lp.exit_page = sp.page_location THEN 1 ELSE 0 END AS is_exit
  FROM session_pages sp
  JOIN last_page_per_session lp
    ON sp.user_pseudo_id = lp.user_pseudo_id
    AND sp.ga_session_id = lp.ga_session_id
  WHERE sp.page_location LIKE '%/products/%'
)
SELECT
  page_location,
  COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))) AS total_sessions,
  SUM(is_exit) AS exit_sessions,
  ROUND(SUM(is_exit) / COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))) * 100, 1) AS exit_rate
FROM product_page_views
GROUP BY page_location
HAVING total_sessions >= 10
ORDER BY exit_rate DESC;
```

### 50. ECサイトのサイト内検索キーワードをGA4×BigQueryで分析して品揃えを改善した

**用途**: 検索キーワードごとの購入転換率を算出する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH search_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'search_term') AS search_term
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'view_search_results'
),

purchase_sessions AS (
  SELECT DISTINCT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
)

SELECT
  ss.search_term,
  COUNT(DISTINCT CONCAT(ss.user_pseudo_id, '-', CAST(ss.session_id AS STRING))) AS search_sessions,
  COUNT(DISTINCT CONCAT(ps.user_pseudo_id, '-', CAST(ps.session_id AS STRING))) AS purchase_sessions,
  ROUND(
    COUNT(DISTINCT CONCAT(ps.user_pseudo_id, '-', CAST(ps.session_id AS STRING)))
    / COUNT(DISTINCT CONCAT(ss.user_pseudo_id, '-', CAST(ss.session_id AS STRING))) * 100,
    2
  ) AS search_to_purchase_rate
FROM search_sessions ss
LEFT JOIN purchase_sessions ps
  ON ss.user_pseudo_id = ps.user_pseudo_id
  AND ss.session_id = ps.session_id
WHERE ss.search_term IS NOT NULL
GROUP BY ss.search_term
HAVING search_sessions >= 5
ORDER BY search_sessions DESC
```
