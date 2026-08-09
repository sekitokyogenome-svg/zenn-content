# GA4 × BigQuery 分析SQL 50本パック

GA4 の BigQuery エクスポートを前提にした、実務で使う分析SQLを 50 本まとめたものです。
**全てのSQLは BigQuery の方言でパース検証済み**で、コピーして `${PROJECT}` と `${DATASET}` を自社の値に置き換えればそのまま動きます。

GA4 の BigQuery スキーマは、実際に叩くと細部で動きません。`event_params` の型、`collected_traffic_source` の有無、パーティションの指定。この 50 本は、その「動かない」を先に潰してあります。

## 収録内容

- EC向けデータ分析: 25 本
- データ基盤設計・運用Tips: 25 本

## 使い方

各SQLの `${PROJECT}` を GCP プロジェクトID、`${DATASET}` を GA4 のデータセット（`analytics_XXXXXXXXX`）に置き換えてください。
実行前に必ずドライランでスキャン量を確認することをおすすめします。

```bash
bq query --dry_run --use_legacy_sql=false '<SQLをここに貼る>'
```

---

## サンプル（3本を無料公開）

### 01. ユーザーの閲覧から購入までの日数分布をBigQueryで可視化する（リマーケティング期間の設定根拠）

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

### 02. BigQueryで1回しか買わない顧客と2回以上買う顧客の行動差を分析した（流入元の違いを確認する）

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

### 03. BigQueryでEC商品別の粗利×CVR×流入数をまとめた利益ダッシュボードを作った

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

---

## ここから先は購入者限定

### 04. ECの季節変動をBigQueryで前年比分析して仕入れ計画に活かす方法（月別売上の前年比SQL）

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

### 05. ECの季節変動をBigQueryで前年比分析して仕入れ計画に活かす方法（週別売上の前年比SQL）

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

### 06. GA4×BigQueryでモバイルとPCの購買行動の違いを分析した（デバイス別の基本指標を比較する）

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

### 07. BigQueryで売上上位20%の商品が生み出す収益構造をパレート分析した（Step 1: 商品別売上集計SQL）

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

### 08. BigQueryで売上上位20%の商品が生み出す収益構造をパレート分析した（Step 2: 累積比率を算出してパレート曲線を描く）

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

### 09. BigQueryでEC顧客をRFM分析してセグメント別メルマガ戦略を立てた

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

### 10. BigQueryでGA4データからEC顧客の年齢・性別推定精度を検証した（Step 2: デモグラフィック別のセグメント分析）

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

### 11. BigQueryでGA4データからEC顧客の年齢・性別推定精度を検証した（Step 3: デモグラフィック別の購買行動比較）

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

### 12. ユーザーの閲覧から購入までの日数分布をBigQueryで可視化する（初回訪問日と初回購入日を取得するSQL）

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

### 13. BigQueryで1回しか買わない顧客と2回以上買う顧客の行動差を分析した（初回セッションの行動指標を比較する）

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

### 14. GA4×BigQueryでEC新規顧客獲得コスト（CAC）を媒体別に正確計算する（チャネル別の新規購入者数を算出するSQL）

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

### 15. GA4×BigQueryでEC新規顧客獲得コスト（CAC）を媒体別に正確計算する（方法1: 手動でCTEに記述する）

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

### 16. GA4×BigQueryでカート放棄率を正確に計測・改善する方法（デバイス別のカート放棄率）

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

### 17. GA4×BigQueryでカート放棄率を正確に計測・改善する方法（流入元別のカート放棄率）

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

### 18. GA4×BigQueryでメルマガのROIを正確に測定する（セッションをまたいだアトリビューション）

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

### 19. GA4×BigQueryでメルマガのROIを正確に測定する（ROIを算出する）

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

### 20. GA4×BigQueryでGoogle広告のキーワード別CVRを正確に測定する

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

### 21. GA4×BigQueryでモバイルとPCの購買行動の違いを分析した（モバイルの離脱ポイントを深掘りする）

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

### 22. GA4×BigQueryでポイント還元施策の効果をコホート分析で検証した（Step 2: コホート別の月次購入回数）

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

### 23. GA4×BigQueryでポイント還元施策の効果をコホート分析で検証した（Step 3: コホート別LTVの比較）

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

### 24. EC商品ページの離脱率をGA4×BigQueryで分析して改善につなげた事例

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

### 25. ECサイトのサイト内検索キーワードをGA4×BigQueryで分析して品揃えを改善した

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

### 26. BigQueryのSTRUCT・ARRAY型を活用してGA4データを効率的にモデリングする（セッションテーブルをデータマートとして整形する）

**用途**: セッションテーブルをデータマートとして整形する

**必要なテーブル**: `${DATASET}.events_*`, `${DATASET}.session_mart`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.session_mart` AS

WITH base AS (
  SELECT
    event_date,
    user_pseudo_id,
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id,
    event_name,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium,
    device.category AS device_category,
    geo.country AS country
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240801' AND '20240831'
)

SELECT
  event_date,
  user_pseudo_id,
  ga_session_id,
  MAX(source) AS source,
  MAX(medium) AS medium,
  MAX(device_category) AS device_category,
  MAX(country) AS country,
  COUNTIF(event_name = 'page_view') AS page_view_count,
  COUNTIF(event_name = 'purchase') AS purchase_count
FROM
  base
WHERE
  ga_session_id IS NOT NULL
GROUP BY
  event_date,
  user_pseudo_id,
  ga_session_id
```

### 27. dbt × BigQueryで再現可能なデータパイプラインを構築する入門【GA4データ編】

**用途**: GA4イベントデータからセッション・流入元を抽出するモデルを作る

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です / `SELECT *` を含みます。必要な列だけに絞るとコストが下がります

```sql
WITH raw_events AS (
  SELECT
    user_pseudo_id,
    event_date,
    event_timestamp,
    event_name,
    -- ga_session_idはevent_paramsをUNNESTして取得する
    (
      SELECT value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id,
    -- 流入元はcollected_traffic_sourceから取得する
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source
  FROM
    `your-gcp-project-id.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
    AND event_name = 'session_start'
),

sessions AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    MIN(event_date) AS session_date,
    MIN(event_timestamp) AS session_start_ts,
    MAX(medium) AS medium,
    MAX(source) AS source
  FROM raw_events
  WHERE ga_session_id IS NOT NULL
  GROUP BY
    user_pseudo_id,
    ga_session_id
)

SELECT * FROM sessions
```

### 28. BigQueryのデータリネージ機能でデータマートの依存関係を可視化する

**用途**: GA4データを使ったビューの依存関係を実際に確認する

**必要なテーブル**: `${DATASET}.events_*`, `${DATASET}.stg_sessions`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
CREATE OR REPLACE VIEW `${PROJECT}.${DATASET}.stg_sessions` AS
SELECT
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  SUM(ecommerce.purchase_revenue) AS revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
  AND event_name = 'purchase'
GROUP BY
  user_pseudo_id,
  ga_session_id,
  medium,
  source
;
```

### 29. BigQueryのエクスポート上限に引っかかったときの回避策まとめ

**用途**: 回避策②：日付パーティションを活用してクエリ・エクスポート対象を絞り込む

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(*) AS event_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'purchase'
GROUP BY
  1, 2, 3, 4
ORDER BY
  event_count DESC
```

### 30. BigQueryのアクセス制御をIAMで適切に設計する【チーム運用編】

**用途**: GA4データへの閲覧権限を安全に設計する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id,
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING
      )
    )
  ) AS session_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'session_start'
GROUP BY
  medium, source
ORDER BY
  session_count DESC
LIMIT 20;
```

### 31. BigQueryのラベル機能でプロジェクト横断のコスト配分を自動管理する（クエリジョブへのラベル付与方法）

**用途**: クエリジョブへのラベル付与方法

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')
  ) AS sessions
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240601' AND '20240630'
  AND event_name = 'session_start'
GROUP BY
  medium, source
ORDER BY
  sessions DESC
```

### 32. BigQueryのマテリアライズドビューでGA4集計クエリを高速化した（マテリアライズドビューの作成手順） その1

**用途**: マテリアライズドビューの作成手順

**必要なテーブル**: `${DATASET}.events_*`, `${DATASET}.mv_ga4_session_summary`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
CREATE MATERIALIZED VIEW `${PROJECT}.${DATASET}.mv_ga4_session_summary`
OPTIONS (
  enable_refresh = true,
  refresh_interval_minutes = 60
)
AS
SELECT
  event_date,
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  COUNTIF(event_name = 'purchase') AS purchase_count,
  SUM(
    CASE
      WHEN event_name = 'purchase'
      THEN (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'value')
      ELSE 0
    END
  ) AS total_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
GROUP BY
  event_date,
  source,
  medium,
  user_pseudo_id,
  ga_session_id
```

### 33. BigQueryのクエリキャッシュの仕組みを理解してコスト効率を最大化する

**用途**: GA4データを活用するクエリでのキャッシュ設計

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_date,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')
  ) AS sessions
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
  AND event_name = 'session_start'
GROUP BY
  event_date, medium, source
ORDER BY
  event_date
```

### 34. BigQueryのクエリコストを月1万円以下に抑える7つの実践テクニック（テクニック7：不要なテーブルと期限切れポリシーを活用する）

**用途**: テクニック7：不要なテーブルと期限切れポリシーを活用する

**必要なテーブル**: `${DATASET}.events_*`, `${DATASET}.temp_session_summary`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
CREATE TABLE `${PROJECT}.${DATASET}.temp_session_summary`
OPTIONS (
  expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
)
AS
SELECT
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  MIN(event_timestamp) AS session_start_ts
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY
  user_pseudo_id, ga_session_id
```

### 35. BigQueryのクエリ結果をCloud Storageに自動エクスポートして外部ツール連携する

**用途**: GA4データをBigQueryで集計するSQLの書き方

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT ep.value.int_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
GROUP BY
  medium,
  source
ORDER BY
  sessions DESC
;
```

### 36. BigQueryのスケジュールクエリでデータマートを毎朝自動更新する設定と監視方法

**用途**: データマート用SQLの書き方（GA4エクスポートテーブル使用）

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS date,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id,
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING
      )
    )
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 7 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 1 DAY))
GROUP BY
  date, medium, source
ORDER BY
  date DESC, sessions DESC
```

### 37. BigQueryからGoogleスプレッドシートに自動出力して非エンジニアとデータ共有する

**用途**: GA4データをコネクテッドシートで参照するカスタムクエリ例

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.string_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY
  1, 2
ORDER BY
  sessions DESC
LIMIT 100
```

### 38. BigQueryのSTRUCT・ARRAY型を活用してGA4データを効率的にモデリングする（流入元データをcollected_traffic_sourceから取得する）

**用途**: 流入元データをcollected_traffic_sourceから取得する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_date,
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
  COUNT(*) AS page_view_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240801' AND '20240831'
  AND event_name = 'page_view'
GROUP BY
  event_date,
  source,
  medium
ORDER BY
  event_date,
  page_view_count DESC
```

### 39. BigQueryのタイムトラベル機能で誤削除・誤更新からデータを復旧する方法（過去時点のデータをSELECTで確認する）

**用途**: 過去時点のデータをSELECTで確認する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_date,
  event_name,
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_id'
  ) AS ga_session_id,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(*) AS event_count
FROM
  `${PROJECT}.${DATASET}.events_*`
  FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20250131'
GROUP BY
  event_date, event_name, ga_session_id, medium, source
ORDER BY
  event_date DESC
LIMIT 100;
```

### 40. BigQueryのタイムトラベル機能で誤削除・誤更新からデータを復旧する方法（GA4集計テーブルの復旧シナリオ例）

**用途**: GA4集計テーブルの復旧シナリオ例

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_date,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
  ) AS sessions
FROM
  `${PROJECT}.${DATASET}.events_*`
  FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 HOUR)
WHERE
  _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
GROUP BY
  event_date, medium, source
ORDER BY
  event_date, sessions DESC;
```

### 41. GA4 BigQueryエクスポートのストリーミング vs 日次の違いと使い分け（日次テーブルを対象にしたクエリ例）

**用途**: 日次テーブルを対象にしたクエリ例

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_name,
  (
    SELECT value.string_value
    FROM UNNEST(event_params)
    WHERE key = 'page_location'
  ) AS page_location,
  COUNT(*) AS event_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 7 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 1 DAY))
GROUP BY
  event_name,
  page_location
ORDER BY
  event_count DESC
LIMIT 50;
```

### 42. GA4 BigQueryエクスポートのストリーミング vs 日次の違いと使い分け（流入元の取得方法）

**用途**: 流入元の取得方法

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNT(*) AS sessions
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
  AND event_name = 'session_start'
GROUP BY
  medium,
  source
ORDER BY
  sessions DESC;
```

### 43. 小規模EC事業者がBigQueryを無料枠内で運用し続けるための設計戦略（GA4データを活用する際のSQL設計パターン）

**用途**: GA4データを活用する際のSQL設計パターン

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT ep.value.string_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS session_count,
  COUNT(*) AS purchase_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'purchase'
GROUP BY
  medium, source
ORDER BY
  purchase_count DESC;
```

### 44. 小規模EC事業者がBigQueryを無料枠内で運用し続けるための設計戦略（ストレージコストを抑えるテーブル管理の工夫）

**用途**: ストレージコストを抑えるテーブル管理の工夫

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
CREATE OR REPLACE TABLE `your_project.ec_summary.monthly_revenue_202506` AS
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(*) AS purchase_count,
  SUM(
    (SELECT ep.value.double_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'value')
  ) AS total_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'purchase'
GROUP BY
  medium, source;
```

### 45. BigQueryのCOLUMN_FIELD_PATHSでGA4のネストされたスキーマを効率的に探索する

**用途**: 実際の分析クエリへの応用

**必要なテーブル**: `${DATASET}.events_20250101`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT ep.value.int_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS sessions
FROM
  `${PROJECT}.${DATASET}.events_20250101`
WHERE
  event_name = 'session_start'
GROUP BY
  medium,
  source
ORDER BY
  sessions DESC;
```

### 46. BigQueryのINFORMATION_SCHEMAでクエリコスト・実行履歴を自動監視する（ユーザー別・日別のコスト集計でチーム内の利用傾向を掴む）

**用途**: ユーザー別・日別のコスト集計でチーム内の利用傾向を掴む

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  DATE(creation_time, 'Asia/Tokyo') AS query_date,
  user_email,
  COUNT(*) AS job_count,
  ROUND(SUM(total_bytes_processed) / POW(1024, 4), 4) AS total_processed_tb,
  ROUND(SUM(total_bytes_processed) / POW(1024, 4) * 6.25, 2) AS estimated_cost_usd
FROM
  `region-asia-northeast1`.INFORMATION_SCHEMA.JOBS
WHERE
  creation_time BETWEEN TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND CURRENT_TIMESTAMP()
  AND job_type = 'QUERY'
  AND state = 'DONE'
  AND error_result IS NULL
GROUP BY
  query_date,
  user_email
ORDER BY
  query_date DESC,
  total_processed_tb DESC;
```

### 47. BigQueryのINFORMATION_SCHEMAでクエリコスト・実行履歴を自動監視する（定期監視の仕組みをBigQueryスケジュールクエリで構築する）

**用途**: 定期監視の仕組みをBigQueryスケジュールクエリで構築する

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  DATE(creation_time, 'Asia/Tokyo') AS job_date,
  user_email,
  COUNT(*) AS job_count,
  COUNTIF(error_result IS NOT NULL) AS error_count,
  ROUND(SUM(total_bytes_processed) / POW(1024, 4), 6) AS total_processed_tb,
  ROUND(SUM(total_bytes_processed) / POW(1024, 4) * 6.25, 4) AS estimated_cost_usd,
  ROUND(AVG(TIMESTAMP_DIFF(end_time, start_time, SECOND)), 1) AS avg_duration_sec
FROM
  `region-asia-northeast1`.INFORMATION_SCHEMA.JOBS
WHERE
  DATE(creation_time, 'Asia/Tokyo') = DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 1 DAY)
  AND job_type = 'QUERY'
GROUP BY
  job_date,
  user_email;
```

### 48. BigQueryのラベル機能でプロジェクト横断のコスト配分を自動管理する（ラベル別コストを集計するSQL）

**用途**: ラベル別コストを集計するSQL

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  (SELECT value FROM UNNEST(labels) WHERE key = 'team') AS team,
  (SELECT value FROM UNNEST(labels) WHERE key = 'purpose') AS purpose,
  SUM(cost) AS total_cost_usd,
  SUM(cost) * 150 AS total_cost_jpy_approx  -- 概算換算（為替レートは適宜変更）
FROM
  `your_billing_project.billing_dataset.gcp_billing_export_v1_XXXXXX_XXXXXX_XXXXXX`
WHERE
  service.description = 'BigQuery'
  AND DATE(_PARTITIONTIME) BETWEEN '2024-06-01' AND '2024-06-30'
GROUP BY
  team, purpose
ORDER BY
  total_cost_usd DESC
```

### 49. BigQueryのマテリアライズドビューでGA4集計クエリを高速化した（マテリアライズドビューの作成手順） その2

**用途**: マテリアライズドビューの作成手順

**必要なテーブル**: `${DATASET}.mv_ga4_session_summary`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  event_date,
  source,
  medium,
  COUNT(DISTINCT ga_session_id) AS sessions,
  SUM(purchase_count) AS purchases,
  SUM(total_revenue) AS revenue
FROM
  `${PROJECT}.${DATASET}.mv_ga4_session_summary`
WHERE
  event_date BETWEEN '2025-06-01' AND '2025-06-30'
GROUP BY
  event_date,
  source,
  medium
ORDER BY
  event_date DESC
```

### 50. BigQueryのクエリコストを月1万円以下に抑える7つの実践テクニック（テクニック4：マテリアライズドビューで集計コストを自動化する）

**用途**: テクニック4：マテリアライズドビューで集計コストを自動化する

**必要なテーブル**: `${DATASET}.events_*`, `${DATASET}.mv_session_traffic`

**コストの注意**: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください

```sql
CREATE MATERIALIZED VIEW `${PROJECT}.${DATASET}.mv_session_traffic`
AS
SELECT
  DATE(TIMESTAMP_MICROS(event_timestamp)) AS event_date,
  collected_traffic_source.manual_medium AS traffic_medium,
  collected_traffic_source.manual_source AS traffic_source,
  COUNT(DISTINCT user_pseudo_id) AS unique_users
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  event_name = 'session_start'
GROUP BY
  event_date,
  traffic_medium,
  traffic_source
```
