# GA4 × BigQuery 実務SQL 全集

GA4 の BigQuery エクスポートを前提にした、実務で使う分析SQLを 456 本まとめたものです。
**全てのSQLは BigQuery の方言でパース検証済み**で、コピーして `${PROJECT}` と `${DATASET}` を自社の値に置き換えればそのまま動きます。

GA4 の BigQuery スキーマは、実際に叩くと細部で動きません。`event_params` の型、`collected_traffic_source` の有無、パーティションの指定。収録したSQLは、その「動かない」を先に潰してあります。

## 収録内容

- EC向けデータ分析: 92 本
- BigQuery×GA4: 90 本
- EC実務×データ活用: 66 本
- データ基盤設計・運用Tips: 59 本
- AI×データ分析: 49 本
- ClaudeCode×自動化: 30 本
- 広告運用×データ基盤: 30 本
- LookerStudio: 26 本
- フリーランス・ビジネス: 8 本
- GTM×GA4: 6 本

## 使い方

各SQLの `${PROJECT}` を GCP プロジェクトID、`${DATASET}` を GA4 のデータセット（`analytics_XXXXXXXXX`）に置き換えてください。
実行前に必ずドライランでスキャン量を確認することをおすすめします。

```bash
bq query --dry_run --use_legacy_sql=false '<SQLをここに貼る>'
```

### 01. Claude CodeにGA4の異常値を検知させて原因仮説まで出力させるプロンプト設計

**用途**: 異常値を取得するBigQueryクエリの設計

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH session_base AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS date,
    user_pseudo_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    event_name
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
),
sessions AS (
  SELECT
    date,
    medium,
    source,
    COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING))) AS sessions
  FROM session_base
  GROUP BY 1, 2, 3
),
purchases AS (
  SELECT
    date,
    medium,
    source,
    COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING))) AS conversions
  FROM session_base
  WHERE event_name = 'purchase'
  GROUP BY 1, 2, 3
)
SELECT
  s.date,
  s.medium,
  s.source,
  s.sessions,
  COALESCE(p.conversions, 0) AS conversions,
  SAFE_DIVIDE(COALESCE(p.conversions, 0), s.sessions) AS cvr
FROM sessions s
LEFT JOIN purchases p
  ON s.date = p.date AND s.medium = p.medium AND s.source = p.source
ORDER BY s.date DESC, s.sessions DESC
```

### 02. Claude Codeに月次KPIレポートの「考察」まで書かせるプロンプト設計術

**用途**: BigQueryでGA4データを集計するSQL設計

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH session_base AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    event_name,
    FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m%d', event_date)) AS month
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
),

sessions AS (
  SELECT
    month,
    medium,
    source,
    COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING))) AS sessions
  FROM session_base
  GROUP BY 1, 2, 3
),

conversions AS (
  SELECT
    month,
    medium,
    source,
    COUNT(*) AS cv_count
  FROM session_base
  WHERE event_name = 'purchase'
  GROUP BY 1, 2, 3
)

SELECT
  s.month,
  s.medium,
  s.source,
  s.sessions,
  COALESCE(c.cv_count, 0) AS cv_count,
  ROUND(SAFE_DIVIDE(COALESCE(c.cv_count, 0), s.sessions) * 100, 2) AS cvr
FROM sessions s
LEFT JOIN conversions c
  ON s.month = c.month AND s.medium = c.medium AND s.source = c.source
ORDER BY s.sessions DESC
```

### 03. Claude Code × Gemini CLIをオーケストレーションしてEC分析を多角的に回す方法

**用途**: GA4 BigQueryエクスポートでEC分析に必要なSQL基礎

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
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
    `${PROJECT}.${DATASET}.events_*`
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

### 04. BigQuery ML × Gemini でEC顧客の購買予測モデルを構築する（特徴量テーブルを作成する（GA4エクスポートデータの加工））

**用途**: 特徴量テーブルを作成する（GA4エクスポートデータの加工）

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です / `SELECT *` を含みます。必要な列だけに絞るとコストが下がります

```sql
WITH base AS (
  SELECT
    user_pseudo_id,
    -- ga_session_idはevent_paramsをUNNESTして取得
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    event_name,
    event_timestamp,
    -- 流入元はcollected_traffic_sourceから取得
    collected_traffic_source.manual_medium AS traffic_medium,
    collected_traffic_source.manual_source  AS traffic_source
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
),
features AS (
  SELECT
    user_pseudo_id,
    COUNT(DISTINCT ga_session_id)                             AS session_count,
    COUNTIF(event_name = 'page_view')                        AS page_view_count,
    COUNTIF(event_name = 'view_item')                        AS view_item_count,
    COUNTIF(event_name = 'add_to_cart')                      AS add_to_cart_count,
    COUNTIF(event_name = 'begin_checkout')                   AS begin_checkout_count,
    MAX(CASE WHEN traffic_medium = 'email'   THEN 1 ELSE 0 END) AS has_email_session,
    MAX(CASE WHEN traffic_medium = 'cpc'     THEN 1 ELSE 0 END) AS has_paid_search_session,
    MAX(CASE WHEN event_name = 'purchase'    THEN 1 ELSE 0 END) AS label
  FROM base
  GROUP BY user_pseudo_id
)
SELECT * FROM features;
```

### 05. BigQuery × Vertex AIでEC商品レコメンドエンジンを自作した話（Step 1: GA4の閲覧・購入ログをBigQueryで整形する）

**用途**: Step 1: GA4の閲覧・購入ログをBigQueryで整形する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH session_base AS (
  SELECT
    user_pseudo_id,
    -- ga_session_idはevent_paramsからUNNESTして取得
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id,
    event_name,
    -- eコマースアイテム情報
    item.item_id,
    item.item_name,
    item.item_category,
    -- 流入元はcollected_traffic_sourceから取得
    collected_traffic_source.manual_medium AS traffic_medium,
    collected_traffic_source.manual_source AS traffic_source,
    event_timestamp
  FROM
    `${PROJECT}.${DATASET}.events_*`,
    UNNEST(items) AS item
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20240731'
    AND event_name IN ('view_item', 'purchase')
    AND item.item_id IS NOT NULL
)
SELECT
  user_pseudo_id,
  ga_session_id,
  item_id,
  item_name,
  item_category,
  traffic_medium,
  traffic_source,
  COUNTIF(event_name = 'view_item') AS view_count,
  COUNTIF(event_name = 'purchase') AS purchase_count
FROM session_base
GROUP BY 1, 2, 3, 4, 5, 6, 7
```

### 06. ChatGPT・Claude・GeminiのデータAI分析能力を実データで徹底比較した（Claudeの回答傾向：仕様理解と説明の深さが際立つ）

**用途**: Claudeの回答傾向：仕様理解と説明の深さが際立つ

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH session_base AS (
  SELECT
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    (SELECT ep.value.int_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id') AS session_id,
    MAX(IF(event_name = 'purchase', 1, 0)) AS has_purchase
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
  GROUP BY
    medium, source, session_id
)
SELECT
  medium,
  source,
  COUNT(*) AS sessions,
  SUM(has_purchase) AS purchases,
  ROUND(SUM(has_purchase) / COUNT(*) * 100, 2) AS purchase_rate_pct
FROM
  session_base
GROUP BY
  medium, source
ORDER BY
  sessions DESC
```

### 07. Claude Codeで競合ECサイトのSEO戦略をGA4×Search Consoleデータから逆算する（GA4 BigQueryデータで流入セッションとコンバージョンを紐づけるSQL）

**用途**: GA4 BigQueryデータで流入セッションとコンバージョンを紐づけるSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH session_params AS (
  SELECT
    user_pseudo_id,
    -- ga_session_id は event_params を UNNEST して取得
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')              AS session_id,
    collected_traffic_source.manual_medium     AS medium,
    collected_traffic_source.manual_source     AS source,
    event_name
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
                      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
),
session_summary AS (
  SELECT
    user_pseudo_id,
    session_id,
    medium,
    source,
    COUNTIF(event_name = 'purchase') AS purchase_count
  FROM session_params
  WHERE medium = 'organic'   -- オーガニック検索のみ
  GROUP BY 1, 2, 3, 4
)
SELECT
  source,
  COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(session_id AS STRING))) AS sessions,
  SUM(purchase_count)                                                  AS purchases,
  ROUND(SUM(purchase_count) /
        COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(session_id AS STRING))) * 100, 2) AS cvr_pct
FROM session_summary
GROUP BY source
ORDER BY sessions DESC;
```

### 08. Gemini in BigQueryの料金体系を完全解説【思わぬ課金を防ぐ設定】

**用途**: データを絞り込んでからモデルに渡す

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH session_data AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    COUNT(*) AS event_count
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240701' AND '20240731'
    AND event_name IN ('session_start', 'page_view')
  GROUP BY
    1, 2, 3, 4
)
SELECT
  user_pseudo_id,
  ga_session_id,
  medium,
  source
FROM
  session_data
WHERE
  event_count = 1  -- セッション内イベントが1件のみ（直帰の近似）
LIMIT 500;
```

### 09. Gemini CLIをGA4データアナリストとして使う具体的な設定と活用例（活用例②：購入完了ファネルのドロップオフ分析）

**用途**: 活用例②：購入完了ファネルのドロップオフ分析

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH funnel AS (
  SELECT
    user_pseudo_id,
    MAX(IF(event_name = 'view_item', 1, 0))   AS viewed,
    MAX(IF(event_name = 'add_to_cart', 1, 0)) AS added,
    MAX(IF(event_name = 'purchase', 1, 0))    AS purchased
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
  GROUP BY
    user_pseudo_id
)
SELECT
  SUM(viewed)    AS view_item_users,
  SUM(added)     AS add_to_cart_users,
  SUM(purchased) AS purchase_users,
  ROUND(SUM(added)     / NULLIF(SUM(viewed), 0) * 100, 1) AS add_rate_pct,
  ROUND(SUM(purchased) / NULLIF(SUM(added), 0)  * 100, 1) AS purchase_rate_pct
FROM funnel;
```

### 10. AI×BigQueryでEC商品説明文のA/Bテスト結果を自動分析・改善提案する仕組み

**用途**: BigQueryでA/Bテスト結果を集計するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH session_base AS (
  SELECT
    -- セッションIDはevent_paramsのUNNESTから取得
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS session_id,
    user_pseudo_id,
    event_name,
    event_timestamp,
    -- A/Bバリアントパラメータを取得
    (
      SELECT ep.value.string_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ab_variant'
    ) AS ab_variant,
    -- 商品ページのURLやIDを取得
    (
      SELECT ep.value.string_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'page_location'
    ) AS page_location,
    -- 流入元情報
    collected_traffic_source.manual_medium AS traffic_medium,
    collected_traffic_source.manual_source AS traffic_source
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
                      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
    AND event_name IN ('page_view', 'purchase', 'add_to_cart')
),

session_summary AS (
  SELECT
    CONCAT(user_pseudo_id, '_', CAST(session_id AS STRING)) AS unique_session,
    ab_variant,
    page_location,
    traffic_medium,
    traffic_source,
    MAX(IF(event_name = 'purchase', 1, 0)) AS purchased,
    MAX(IF(event_name = 'add_to_cart', 1, 0)) AS added_to_cart
  FROM session_base
  WHERE ab_variant IS NOT NULL
  GROUP BY 1, 2, 3, 4, 5
)

SELECT
  ab_variant,
  COUNT(DISTINCT unique_session)                          AS sessions,
  SUM(added_to_cart)                                     AS add_to_cart_count,
  SUM(purchased)                                         AS purchase_count,
  ROUND(SAFE_DIVIDE(SUM(added_to_cart), COUNT(DISTINCT unique_session)) * 100, 2) AS add_to_cart_rate,
  ROUND(SAFE_DIVIDE(SUM(purchased), COUNT(DISTINCT unique_session)) * 100, 2)     AS purchase_rate
FROM session_summary
GROUP BY ab_variant
ORDER BY ab_variant;
```

### 11. BigQuery × Vertex AIでEC商品レコメンドエンジンを自作した話（Step 5: 流入元別にレコメンドの効果を検証する）

**用途**: Step 5: 流入元別にレコメンドの効果を検証する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT user_pseudo_id) AS total_users,
  COUNTIF(event_name = 'select_promotion' AND promotion_name LIKE '%recommend%') AS recommend_clicks,
  COUNTIF(event_name = 'purchase') AS purchases,
  SAFE_DIVIDE(
    COUNTIF(event_name = 'select_promotion' AND promotion_name LIKE '%recommend%'),
    COUNT(DISTINCT user_pseudo_id)
  ) AS recommend_ctr,
  SAFE_DIVIDE(
    COUNTIF(event_name = 'purchase'),
    COUNT(DISTINCT user_pseudo_id)
  ) AS cvr
FROM
  `${PROJECT}.${DATASET}.events_*`,
  UNNEST(promotions) AS promotion
WHERE
  _TABLE_SUFFIX BETWEEN '20240701' AND '20240731'
GROUP BY 1, 2
ORDER BY recommend_ctr DESC
```

### 12. AIコーディングアシスタント3種でBigQueryのデータパイプラインを作り比べた（Claude（Anthropic）の評価）

**用途**: Claude（Anthropic）の評価

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
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS conversions
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY
  event_date, medium, source
ORDER BY
  event_date DESC, sessions DESC
```

### 13. AIコーディングアシスタント3種でBigQueryのデータパイプラインを作り比べた（Gemini（Google）の評価）

**用途**: Gemini（Google）の評価

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_date,
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
  COUNT(DISTINCT
    (SELECT ep.value.int_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS session_count,
  COUNTIF(event_name = 'purchase') AS cv_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
GROUP BY 1, 2, 3
ORDER BY 1 DESC
```

### 14. BigQuery × AI.EMBED関数でEC商品の類似度検索を実装する（GA4データと組み合わせた活用例）

**用途**: GA4データと組み合わせた活用例

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  ep.value.string_value AS product_id_viewed,
  COUNT(DISTINCT
    (SELECT ep2.value.string_value
     FROM UNNEST(event_params) ep2
     WHERE ep2.key = 'ga_session_id')
  ) AS session_count,
  collected_traffic_source.manual_medium AS traffic_medium,
  collected_traffic_source.manual_source AS traffic_source
FROM
  `${PROJECT}.${DATASET}.events_*`,
  UNNEST(event_params) ep
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  AND event_name = 'view_item'
  AND ep.key = 'item_id'
GROUP BY
  product_id_viewed,
  traffic_medium,
  traffic_source
ORDER BY
  session_count DESC
LIMIT 20;
```

### 15. BigQueryのGeminiアシスタントで非エンジニアが自力でSQL分析できるか検証した（実際にやってみた：セッション数の集計）

**用途**: 実際にやってみた：セッション数の集計

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  DATE(TIMESTAMP_MICROS(event_timestamp)) AS date,
  COUNT(DISTINCT
    (SELECT value.int_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS sessions
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'session_start'
GROUP BY
  date
ORDER BY
  date;
```

### 16. BigQueryのGeminiアシスタントで非エンジニアが自力でSQL分析できるか検証した（流入元別のセッション分析に挑戦）

**用途**: 流入元別のセッション分析に挑戦

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.int_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS sessions
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'session_start'
GROUP BY
  medium, source
ORDER BY
  sessions DESC;
```

### 17. BigQuery ML × 時系列モデルARIMA_PLUSでEC売上の週次予測を自動化する（ステップ1: GA4データから週次売上を集計する） その1

**用途**: ステップ1: GA4データから週次売上を集計する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), WEEK(MONDAY)) AS week_start,
  SUM(
    (SELECT COALESCE(ep.value.double_value, ep.value.int_value)
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'value')
  ) AS weekly_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  event_name = 'purchase'
  AND _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
GROUP BY
  week_start
ORDER BY
  week_start ASC;
```

### 18. BigQuery ML × 時系列モデルARIMA_PLUSでEC売上の週次予測を自動化する（ステップ1: GA4データから週次売上を集計する） その2

**用途**: ステップ1: GA4データから週次売上を集計する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), WEEK(MONDAY)) AS week_start,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  SUM(
    (SELECT COALESCE(ep.value.double_value, ep.value.int_value)
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'value')
  ) AS weekly_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  event_name = 'purchase'
  AND _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
GROUP BY
  week_start, medium, source
ORDER BY
  week_start ASC;
```

### 19. BigQuery MLの需要予測モデルでEC仕入れ量を最適化する実装手順（データ準備：GA4のBigQueryエクスポートを活用する）

**用途**: データ準備：GA4のBigQueryエクスポートを活用する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS date,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.string_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'view_item') AS view_item_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
GROUP BY
  date, medium, source
ORDER BY
  date;
```

### 20. ChatGPT・Claude・GeminiのデータAI分析能力を実データで徹底比較した（ChatGPTの回答傾向：汎用性は高いが GA4仕様に要注意）

**用途**: ChatGPTの回答傾向：汎用性は高いが GA4仕様に要注意

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
  ) AS sessions
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
GROUP BY
  medium, source
ORDER BY
  sessions DESC
```

### 21. Claude CodeでGA4のイベント計測漏れを自動検知・修正提案する仕組み（BigQueryでイベント計測漏れを検知するSQL） その1

**用途**: BigQueryでイベント計測漏れを検知するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_date,
  event_name,
  COUNT(*) AS event_count,
  COUNT(DISTINCT
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')
  ) AS session_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY
  event_date,
  event_name
ORDER BY
  event_name,
  event_date
```

### 22. Claude CodeでGA4のイベント計測漏れを自動検知・修正提案する仕組み（BigQueryでイベント計測漏れを検知するSQL） その2

**用途**: BigQueryでイベント計測漏れを検知するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_date,
  event_name,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(*) AS event_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
  AND event_name IN ('add_to_cart', 'begin_checkout', 'purchase')
GROUP BY
  event_date,
  event_name,
  medium,
  source
ORDER BY
  event_date,
  event_name
```

### 23. Gemini in BigQueryで自然言語からSQLを生成する実践ガイド【2026年版】（セッション数の日別集計）

**用途**: セッション数の日別集計

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  DATE(TIMESTAMP_MICROS(event_timestamp)) AS event_date,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id,
      CAST(
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
        AS STRING
      )
    )
  ) AS sessions
FROM
  `プロジェクトID.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
  AND event_name = 'session_start'
GROUP BY
  event_date
ORDER BY
  event_date;
```

### 24. Gemini in BigQueryで自然言語からSQLを生成する実践ガイド【2026年版】（流入チャネル別のセッション数集計）

**用途**: 流入チャネル別のセッション数集計

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id,
      CAST(
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
        AS STRING
      )
    )
  ) AS sessions
FROM
  `プロジェクトID.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
  AND event_name = 'session_start'
GROUP BY
  medium,
  source
ORDER BY
  sessions DESC
LIMIT 20;
```

### 25. Gemini in BigQuery Studioのリソース検出機能でマルチプロジェクト分析を効率化する（流入元分析への応用）

**用途**: 流入元分析への応用

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNTIF(event_name = 'purchase') AS purchases,
  SUM(
    (SELECT ep.value.int_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'value')
  ) AS total_revenue
FROM
  `project-brand-a.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'purchase'
GROUP BY
  medium, source
ORDER BY
  purchases DESC
LIMIT 20;
```

### 26. Gemini CLIをGA4データアナリストとして使う具体的な設定と活用例（活用例①：流入元別セッション数の集計）

**用途**: 活用例①：流入元別セッション数の集計

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id,
      CAST(
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
        AS STRING
      )
    )
  ) AS sessions
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250721' AND '20250727'
  AND event_name = 'session_start'
GROUP BY
  source, medium
ORDER BY
  sessions DESC
LIMIT 50;
```

### 27. NotebookLM × BigQueryエクスポートでGA4データを対話的に分析する（GA4データをBigQueryからCSVに取り出す）

**用途**: GA4データをBigQueryからCSVに取り出す

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  cs.manual_medium AS medium,
  cs.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.string_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases
FROM
  `${PROJECT}.${DATASET}.events_*`
  , UNNEST(collected_traffic_source) AS cs
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
GROUP BY
  medium, source
ORDER BY
  sessions DESC
LIMIT 100;
```

### 28. NotebookLM × BigQueryエクスポートでGA4データを対話的に分析する（複数のクエリ結果を組み合わせてより深い分析を行う）

**用途**: 複数のクエリ結果を組み合わせてより深い分析を行う

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  (SELECT value.string_value
   FROM UNNEST(event_params)
   WHERE key = 'item_category') AS item_category,
  COUNT(*) AS purchase_events,
  SUM(
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'value')
  ) AS total_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'purchase'
GROUP BY
  item_category
ORDER BY
  purchase_events DESC;
```

### 29. BigQuery × Vertex AIでEC商品レコメンドエンジンを自作した話（Step 2: ユーザー×商品のインタラクションマトリクスを作成する）

**用途**: Step 2: ユーザー×商品のインタラクションマトリクスを作成する

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
CREATE OR REPLACE TABLE `your_project.ml_dataset.user_item_interactions` AS
SELECT
  user_pseudo_id,
  item_id,
  item_name,
  item_category,
  -- 購入を閲覧より重視したスコア設計
  LEAST((view_count * 1.0 + purchase_count * 5.0), 10.0) AS interaction_score
FROM (
  SELECT
    user_pseudo_id,
    item_id,
    item_name,
    item_category,
    SUM(view_count) AS view_count,
    SUM(purchase_count) AS purchase_count
  FROM `your_project.ml_dataset.raw_interactions`
  GROUP BY 1, 2, 3, 4
)
WHERE
  -- 一定のインタラクションがあるユーザーのみ対象
  view_count + purchase_count >= 2
```

### 30. Claude Codeで競合ECサイトのSEO戦略をGA4×Search Consoleデータから逆算する（Search Consoleデータから検索キーワードの傾向を把握するSQL）

**用途**: Search Consoleデータから検索キーワードの傾向を把握するSQL

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  query,
  SUM(impressions)                          AS total_impressions,
  SUM(clicks)                               AS total_clicks,
  ROUND(SUM(clicks) / SUM(impressions) * 100, 2) AS ctr_pct,
  ROUND(AVG(position), 1)                   AS avg_position
FROM
  `your_project.search_console_dataset.searchdata_site_impression`
WHERE
  data_date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY) AND CURRENT_DATE()
  AND impressions > 100
GROUP BY
  query
HAVING
  ctr_pct < 2.0            -- CTR 2%未満に絞る
  AND avg_position <= 20   -- 検索結果2ページ目以内
ORDER BY
  total_impressions DESC
LIMIT 100;
```

### 31. AIが生成したSQLは本当に正しいのか？BigQueryでの検証フレームワークを作った（AIがよく間違えるGA4 SQLのパターン） その1

**用途**: AIがよく間違えるGA4 SQLのパターン

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  COUNT(*) AS event_count
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
GROUP BY 1, 2
```

### 32. Claude CodeのAgents SDKでEC在庫アラート→発注提案→Slack通知を全自動化した

**用途**: BigQuery での在庫 × 売上集計 SQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

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
    `${PROJECT}.${DATASET}.events_*`,
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

### 33. AIエージェントにBigQueryのクエリレビューをさせてコスト削減した方法（AIが提案した最適化クエリの例）

**用途**: AIが提案した最適化クエリの例

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_date,
  user_pseudo_id,
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_id'
  ) AS ga_session_id,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  ecommerce.purchase_revenue AS revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20250731'
  AND event_name = 'purchase'
```

### 34. AIが生成したSQLは本当に正しいのか？BigQueryでの検証フレームワークを作った（AIがよく間違えるGA4 SQLのパターン） その2

**用途**: AIがよく間違えるGA4 SQLのパターン

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください

```sql
SELECT
  user_pseudo_id,
  ga_session_id,
  COUNT(*) AS event_count
FROM `${PROJECT}.${DATASET}.events_*`
GROUP BY 1, 2
```

### 35. Claude Code × Pythonで顧客レビューを感情分析してNPS予測に使う

**用途**: BigQueryからレビューデータとGA4流入情報を取得する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  ep.value.int_value AS ga_session_id,
  e.user_pseudo_id,
  e.event_date,
  cts.manual_medium AS medium,
  cts.manual_source AS source,
  ep2.value.string_value AS review_text
FROM
  `${PROJECT}.${DATASET}.events_*` AS e,
  UNNEST(e.event_params) AS ep,
  UNNEST(e.event_params) AS ep2
LEFT JOIN
  UNNEST([e.collected_traffic_source]) AS cts
WHERE
  e.event_name = 'review_submit'
  AND ep.key = 'ga_session_id'
  AND ep2.key = 'review_body'
  AND _TABLE_SUFFIX BETWEEN '20250101' AND '20250731'
```

### 36. Gemini in BigQuery Studioのリソース検出機能でマルチプロジェクト分析を効率化する（シナリオ: 2ブランドのコンバージョンを横断集計したい）

**用途**: シナリオ: 2ブランドのコンバージョンを横断集計したい

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  'brand_a' AS brand,
  COUNT(DISTINCT
    (SELECT ep.value.string_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases
FROM
  `project-brand-a.analytics_XXXXXXXXX.events_*`
WHERE
  event_name IN ('session_start', 'purchase')
  AND _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH))
    AND FORMAT_DATE('%Y%m%d', LAST_DAY(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)))

UNION ALL

-- ブランドB: 先月の購入件数
SELECT
  'brand_b' AS brand,
  COUNT(DISTINCT
    (SELECT ep.value.string_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases
FROM
  `project-brand-b.analytics_YYYYYYYYY.events_*`
WHERE
  event_name IN ('session_start', 'purchase')
  AND _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH))
    AND FORMAT_DATE('%Y%m%d', LAST_DAY(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)));
```

### 37. BigQuery × AI.EMBED関数でEC商品の類似度検索を実装する（AI.EMBEDで商品ベクトルを生成する）

**用途**: AI.EMBEDで商品ベクトルを生成する

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
CREATE OR REPLACE TABLE `your_project.ec_dataset.product_embeddings` AS
SELECT
  product_id,
  product_name,
  category,
  ml_generate_embedding_result AS embedding
FROM
  ML.GENERATE_EMBEDDING(
    MODEL `your_project.ec_dataset.embedding_model`,
    (
      SELECT
        product_id,
        product_name,
        category,
        CONCAT(product_name, ' ', category, ' ', description) AS content
      FROM
        `your_project.ec_dataset.products`
    ),
    STRUCT(TRUE AS flatten_json_output)
  );
```

### 38. BigQuery ML × 時系列モデルARIMA_PLUSでEC売上の週次予測を自動化する（ステップ2: ARIMA_PLUSモデルを学習させる）

**用途**: ステップ2: ARIMA_PLUSモデルを学習させる

**必要なテーブル**: `${DATASET}.ec_weekly_forecast_model`, `${DATASET}.weekly_revenue_summary`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
CREATE OR REPLACE MODEL
  `${PROJECT}.${DATASET}.ec_weekly_forecast_model`
OPTIONS(
  model_type = 'ARIMA_PLUS',
  time_series_timestamp_col = 'week_start',
  time_series_data_col = 'weekly_revenue',
  data_frequency = 'WEEKLY',
  horizon = 8,
  holiday_region = 'JP'
) AS
SELECT
  week_start,
  weekly_revenue
FROM
  `${PROJECT}.${DATASET}.weekly_revenue_summary`
WHERE
  weekly_revenue IS NOT NULL;
```

### 39. BigQuery MLの需要予測モデルでEC仕入れ量を最適化する実装手順（ARIMA_PLUSモデルの構築手順）

**用途**: ARIMA_PLUSモデルの構築手順

**必要なテーブル**: `${DATASET}.daily_sales_summary`, `${DATASET}.demand_forecast_model`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
CREATE OR REPLACE MODEL `${PROJECT}.${DATASET}.demand_forecast_model`
OPTIONS(
  model_type = 'ARIMA_PLUS',
  time_series_timestamp_col = 'date',
  time_series_data_col = 'units_sold',
  auto_arima = TRUE,
  data_frequency = 'DAILY',
  decompose_time_series = TRUE,
  holiday_region = 'JP'
) AS
SELECT
  date,
  units_sold
FROM
  `${PROJECT}.${DATASET}.daily_sales_summary`
WHERE
  date BETWEEN '2023-01-01' AND '2024-12-31'
ORDER BY
  date;
```

### 40. BigQuery ML × Gemini でEC顧客の購買予測モデルを構築する（BigQuery MLでロジスティック回帰モデルを訓練する）

**用途**: BigQuery MLでロジスティック回帰モデルを訓練する

**必要なテーブル**: `${DATASET}.ec_user_features`, `${DATASET}.purchase_prediction_model`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
CREATE OR REPLACE MODEL `${PROJECT}.${DATASET}.purchase_prediction_model`
OPTIONS (
  model_type = 'LOGISTIC_REG',
  input_label_cols = ['label'],
  auto_class_weights = TRUE,
  data_split_method = 'AUTO_SPLIT'
) AS
SELECT
  session_count,
  page_view_count,
  view_item_count,
  add_to_cart_count,
  begin_checkout_count,
  has_email_session,
  has_paid_search_session,
  label
FROM
  `${PROJECT}.${DATASET}.ec_user_features`;
```

### 41. BigQuery ML × Gemini でEC顧客の購買予測モデルを構築する（購買確率を予測してセグメントを抽出する）

**用途**: 購買確率を予測してセグメントを抽出する

**必要なテーブル**: `${DATASET}.ec_user_features`, `${DATASET}.purchase_prediction_model`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  user_pseudo_id,
  predicted_label,
  predicted_label_probs
FROM
  ML.PREDICT(
    MODEL `${PROJECT}.${DATASET}.purchase_prediction_model`,
    (
      SELECT
        user_pseudo_id,
        session_count,
        page_view_count,
        view_item_count,
        add_to_cart_count,
        begin_checkout_count,
        has_email_session,
        has_paid_search_session
      FROM
        `${PROJECT}.${DATASET}.ec_user_features`
      WHERE
        label = 0  -- 未購買ユーザーのみ対象
    )
  )
ORDER BY
  (SELECT p.prob FROM UNNEST(predicted_label_probs) p WHERE p.label = '1') DESC
LIMIT 500;
```

### 42. BigQuery ML × Gemini でEC顧客の購買予測モデルを構築する（GeminiでセグメントのインサイトをAIに言語化させる）

**用途**: GeminiでセグメントのインサイトをAIに言語化させる

**必要なテーブル**: `${DATASET}.ec_user_features`, `${DATASET}.gemini_model`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  ml_generate_text_result['candidates'][0]['content']['parts'][0]['text'] AS gemini_insight
FROM
  ML.GENERATE_TEXT(
    MODEL `${PROJECT}.${DATASET}.gemini_model`,
    (
      SELECT
        CONCAT(
          '以下はECサイトにおける購買確率の高いユーザーセグメントの行動集計データです。',
          'このセグメントの特徴と、効果的なアプローチ方法を200文字以内で教えてください。\n\n',
          '平均セッション数: ', AVG(session_count),
          ', 平均商品閲覧数: ', AVG(view_item_count),
          ', カート追加率: ', COUNTIF(add_to_cart_count > 0) / COUNT(*),
          ', メール経由割合: ', AVG(has_email_session)
        ) AS prompt
      FROM
        `${PROJECT}.${DATASET}.ec_user_features`
      WHERE
        label = 0
    ),
    STRUCT(0.3 AS temperature, 512 AS max_output_tokens)
  );
```

### 43. BigQuery × Vertex AIでEC商品レコメンドエンジンを自作した話（Step 3: BigQuery MLで協調フィルタリングモデルを学習する）

**用途**: Step 3: BigQuery MLで協調フィルタリングモデルを学習する

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
CREATE OR REPLACE MODEL `your_project.ml_dataset.item_recommender`
OPTIONS (
  model_type = 'matrix_factorization',
  user_col = 'user_pseudo_id',
  item_col = 'item_id',
  rating_col = 'interaction_score',
  feedback_type = 'implicit',  -- 暗黙的フィードバック
  num_factors = 16,
  l2_reg = 0.1
) AS
SELECT
  user_pseudo_id,
  item_id,
  interaction_score
FROM
  `your_project.ml_dataset.user_item_interactions`
```

### 44. AIが生成したSQLは本当に正しいのか？BigQueryでの検証フレームワークを作った（ステップ2: 既知の値と突き合わせる論理チェック）

**用途**: ステップ2: 既知の値と突き合わせる論理チェック

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  COUNT(DISTINCT CONCAT(
    user_pseudo_id,
    CAST(
      (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
      AS STRING
    )
  )) AS total_sessions
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
  AND event_name = 'session_start'
```

### 45. Claude Code × dbtでデータ変換パイプラインのテストコードを自動生成する

**用途**: dbt × BigQueryの基本構成を整理する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_date,
  event_name,
  user_pseudo_id,
  (SELECT value.int_value
   FROM UNNEST(event_params) AS ep
   WHERE ep.key = 'ga_session_id') AS ga_session_id,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
```

### 46. AIエージェントにBigQueryのクエリレビューをさせてコスト削減した方法（BigQueryのコストが膨らむ典型的な原因）

**用途**: BigQueryのコストが膨らむ典型的な原因

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください / `SELECT *` を含みます。必要な列だけに絞るとコストが下がります

```sql
SELECT
  *
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  event_name = 'purchase'
```

### 47. BigQuery × AI.EMBED関数でEC商品の類似度検索を実装する（商品データをBigQueryに格納する）

**用途**: 商品データをBigQueryに格納する

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
CREATE OR REPLACE TABLE `your_project.ec_dataset.products` (
  product_id   STRING,
  product_name STRING,
  category     STRING,
  description  STRING
);
```

### 48. BigQuery ML × 時系列モデルARIMA_PLUSでEC売上の週次予測を自動化する（ステップ3: 予測結果を取得する）

**用途**: ステップ3: 予測結果を取得する

**必要なテーブル**: `${DATASET}.ec_weekly_forecast_model`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  forecast_timestamp AS week_start,
  ROUND(forecast_value, 0) AS predicted_revenue,
  ROUND(prediction_interval_lower_bound, 0) AS lower_bound,
  ROUND(prediction_interval_upper_bound, 0) AS upper_bound
FROM
  ML.FORECAST(
    MODEL `${PROJECT}.${DATASET}.ec_weekly_forecast_model`,
    STRUCT(8 AS horizon, 0.9 AS confidence_level)
  )
ORDER BY
  forecast_timestamp ASC;
```

### 49. BigQuery MLの需要予測モデルでEC仕入れ量を最適化する実装手順（予測結果を仕入れ計画に反映する）

**用途**: 予測結果を仕入れ計画に反映する

**必要なテーブル**: `${DATASET}.demand_forecast_model`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  forecast_timestamp,
  forecast_value,
  prediction_interval_lower_bound,
  prediction_interval_upper_bound
FROM
  ML.FORECAST(
    MODEL `${PROJECT}.${DATASET}.demand_forecast_model`,
    STRUCT(30 AS horizon, 0.9 AS confidence_level)
  )
ORDER BY
  forecast_timestamp;
```

### 50. GA4×BigQueryでコンバージョン経路を分析するSQL（ファーストタッチ分析：最初に見たページ）

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

### 51. GA4×BigQueryでコンバージョン経路を分析するSQL（ラストタッチ分析：コンバージョン直前のページ）

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

### 52. GA4×BigQueryでユーザーのファーストタッチ・ラストタッチを取得する（ラストタッチを取得するSQL）

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

### 53. BigQueryでGA4のeコマースイベントを完全解析する【purchase/add_to_cart】（ファネル分析：view_item → add_to_cart → purchase の転換率）

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

### 54. GA4×BigQueryでリピーターと新規ユーザーを分離して分析する（新規/リピーター別のセッション指標を比較する）

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

### 55. GA4×BigQueryでSearch Consoleデータを結合してオーガニック分析する（GA4 × Search Console結合クエリ）

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

### 56. BigQueryでGA4のページ別滞在時間を正しく集計する方法（最後のページ問題への対処）

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

### 57. GA4×BigQueryでコンバージョン経路を分析するSQL（コンバージョンしたセッションの経路だけを抽出する）

**用途**: コンバージョンしたセッションの経路だけを抽出する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

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
  FROM `${PROJECT}.${DATASET}.events_*`
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

### 58. GA4×BigQueryでコンバージョン経路を分析するSQL（よく通るコンバージョン経路をランキングする）

**用途**: よく通るコンバージョン経路をランキングする

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

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
  FROM `${PROJECT}.${DATASET}.events_*`
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

### 59. GA4×BigQueryでカスタムディメンションを活用した分析（実践例2：会員ランク別の行動分析）

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

### 60. GA4×BigQueryでユーザーのファーストタッチ・ラストタッチを取得する（ファーストタッチを取得するSQL）

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

### 61. GA4×BigQueryでユーザーのファーストタッチ・ラストタッチを取得する（ファーストタッチとラストタッチを並べて比較する）

**用途**: ファーストタッチとラストタッチを並べて比較する

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
  SELECT DISTINCT user_pseudo_id
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
),

attribution AS (
  SELECT DISTINCT
    s.user_pseudo_id,
    FIRST_VALUE(s.session_source) OVER w AS first_touch_source,
    FIRST_VALUE(s.session_medium) OVER w AS first_touch_medium,
    LAST_VALUE(s.session_source) OVER w AS last_touch_source,
    LAST_VALUE(s.session_medium) OVER w AS last_touch_medium
  FROM sessions s
  INNER JOIN converters c ON s.user_pseudo_id = c.user_pseudo_id
  WINDOW w AS (
    PARTITION BY s.user_pseudo_id
    ORDER BY s.event_timestamp
    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
  )
)

SELECT
  first_touch_source,
  first_touch_medium,
  last_touch_source,
  last_touch_medium,
  COUNT(DISTINCT user_pseudo_id) AS converting_users
FROM attribution
GROUP BY 1, 2, 3, 4
ORDER BY converting_users DESC
LIMIT 30
```

### 62. GA4×BigQueryでリピーターと新規ユーザーを分離して分析する（応用パターン：初回訪問日を特定して分類する）

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

### 63. GA4×BigQueryでリピーターと新規ユーザーを分離して分析する（新規/リピーター別のチャネル分析）

**用途**: 新規/リピーター別のチャネル分析

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
)

SELECT
  CASE
    WHEN f.first_visit_date BETWEEN '2025-03-01' AND '2025-03-31'
    THEN '新規'
    ELSE 'リピーター'
  END AS user_type,
  IFNULL(e.collected_traffic_source.manual_medium, '(none)') AS medium,
  COUNT(DISTINCT e.user_pseudo_id) AS users,
  COUNT(DISTINCT
    CONCAT(e.user_pseudo_id, '-',
    CAST((SELECT value.int_value FROM UNNEST(e.event_params) WHERE key = 'ga_session_id') AS STRING))
  ) AS sessions
FROM `${PROJECT}.${DATASET}.events_*` e
LEFT JOIN first_visit_date f ON e.user_pseudo_id = f.user_pseudo_id
WHERE e._TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
  AND e.event_name = 'session_start'
GROUP BY user_type, medium
ORDER BY user_type, sessions DESC
```

### 64. GA4×BigQueryでカスタムディメンションを活用した分析（実践例1：ABテストのバリアント別コンバージョン分析）

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

### 65. BigQueryでGA4のeコマースイベントを完全解析する【purchase/add_to_cart】（add_to_cart分析：カートに入れたが購入されなかった商品）

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

### 66. BigQueryでGA4のページ別滞在時間を正しく集計する方法（ページ別の平均滞在時間を集計するSQL）

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

### 67. BigQueryでGA4のページ別滞在時間を正しく集計する方法（セッション単位で滞在時間を集計する）

**用途**: セッション単位で滞在時間を集計する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH session_engagement AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    SUM(
      (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'engagement_time_msec')
    ) AS total_engagement_msec
  FROM `${PROJECT}.${DATASET}.events_*`
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

### 68. BigQueryでGA4の直帰率を正確に計算する方法（GA4に直帰率はない問題）（方法1：session_engagedを使う（推奨））

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

### 69. BigQueryでGA4の直帰率を正確に計算する方法（GA4に直帰率はない問題）（方法2：engagement_time_msecを使う）

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

### 70. BigQueryでGA4の直帰率を正確に計算する方法（GA4に直帰率はない問題）（ページ別の直帰率を計算する）

**用途**: ページ別の直帰率を計算する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH session_landing AS (
  SELECT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    (SELECT value.string_value
     FROM UNNEST(event_params)
     WHERE key = 'page_location') AS landing_page,
    MAX(
      (SELECT value.string_value
       FROM UNNEST(event_params)
       WHERE key = 'session_engaged')
    ) AS session_engaged
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
    AND event_name = 'session_start'
  GROUP BY session_id, landing_page
)
SELECT
  landing_page,
  COUNT(*) AS sessions,
  COUNTIF(session_engaged != '1' OR session_engaged IS NULL) AS bounced,
  ROUND(
    COUNTIF(session_engaged != '1' OR session_engaged IS NULL)
    / COUNT(*) * 100, 2
  ) AS bounce_rate_percent
FROM session_landing
GROUP BY landing_page
HAVING sessions >= 10
ORDER BY bounce_rate_percent DESC
LIMIT 20
```

### 71. BigQueryでGA4の直帰率を正確に計算する方法（GA4に直帰率はない問題）（チャネル別の直帰率を比較する）

**用途**: チャネル別の直帰率を比較する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH session_channel AS (
  SELECT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    collected_traffic_source.manual_medium AS medium,
    MAX(
      (SELECT value.string_value
       FROM UNNEST(event_params)
       WHERE key = 'session_engaged')
    ) AS session_engaged
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
    AND event_name = 'session_start'
  GROUP BY session_id, medium
)
SELECT
  IFNULL(medium, '(none)') AS medium,
  COUNT(*) AS sessions,
  ROUND(
    COUNTIF(session_engaged != '1' OR session_engaged IS NULL)
    / COUNT(*) * 100, 2
  ) AS bounce_rate_percent
FROM session_channel
GROUP BY medium
ORDER BY sessions DESC
```

### 72. BigQueryでGA4の直帰率を正確に計算する方法（GA4に直帰率はない問題）（UAの直帰率定義をBigQueryで再現する）

**用途**: UAの直帰率定義をBigQueryで再現する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

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
    COUNTIF(event_name = 'page_view') AS page_views
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  GROUP BY session_id
)
SELECT
  COUNT(*) AS total_sessions,
  COUNTIF(page_views <= 1) AS single_page_sessions,
  ROUND(
    COUNTIF(page_views <= 1) / COUNT(*) * 100, 2
  ) AS ua_style_bounce_rate_percent
FROM session_pages
```

### 73. GA4×BigQueryでコンバージョン経路を分析するSQL（セッション内のページ遷移パスをSQLで生成する）

**用途**: セッション内のページ遷移パスをSQLで生成する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

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
  FROM `${PROJECT}.${DATASET}.events_*`
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

### 74. GA4×BigQueryでデバイス別・地域別セグメント分析をする（デバイス別セッション数・コンバージョン率）

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

### 75. GA4×BigQueryでデバイス別・地域別セグメント分析をする（デバイス別×チャネル別のクロス集計）

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

### 76. GA4×BigQueryでデバイス別・地域別セグメント分析をする（PIVOT的なデバイス別集計（日別×デバイス））

**用途**: PIVOT的なデバイス別集計（日別×デバイス）

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH daily_device AS (
  SELECT
    event_date,
    device.category AS device_category,
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
  GROUP BY event_date, device_category
)
SELECT
  event_date,
  SUM(CASE WHEN device_category = 'desktop' THEN sessions ELSE 0 END) AS desktop,
  SUM(CASE WHEN device_category = 'mobile' THEN sessions ELSE 0 END) AS mobile,
  SUM(CASE WHEN device_category = 'tablet' THEN sessions ELSE 0 END) AS tablet,
  SUM(sessions) AS total
FROM daily_device
GROUP BY event_date
ORDER BY event_date
```

### 77. GA4×BigQueryでSearch Consoleデータを結合してオーガニック分析する（結合のためのGA4側の準備）

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

### 78. GA4×BigQueryでセッションIDを正しく定義する方法（セッションごとのPV数）

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

### 79. GA4×BigQueryでセッションIDを正しく定義する方法（セッション開始時刻と流入元を紐づける）

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

### 80. GA4×BigQueryでカスタムディメンションを活用した分析（user_propertiesの注意点）

**用途**: user_propertiesの注意点

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH latest_properties AS (
  SELECT
    user_pseudo_id,
    prop.key AS property_key,
    prop.value.string_value AS property_value,
    prop.value.set_timestamp_micros AS set_timestamp,
    ROW_NUMBER() OVER (
      PARTITION BY user_pseudo_id, prop.key
      ORDER BY prop.value.set_timestamp_micros DESC
    ) AS rn
  FROM `${PROJECT}.${DATASET}.events_*`,
    UNNEST(user_properties) AS prop
  WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
    AND prop.key = 'membership_tier'
)
SELECT
  user_pseudo_id,
  property_value AS membership_tier
FROM latest_properties
WHERE rn = 1
```

### 81. BigQueryでGA4のeコマースイベントを完全解析する【purchase/add_to_cart】（カテゴリ別・商品別の売上集計） その1

**用途**: カテゴリ別・商品別の売上集計

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  item.item_category,
  COUNT(DISTINCT ecommerce.transaction_id) AS transactions,
  SUM(item.quantity) AS total_quantity,
  ROUND(SUM(item.item_revenue), 0) AS total_revenue,
  ROUND(SAFE_DIVIDE(SUM(item.item_revenue), SUM(item.quantity)), 0) AS avg_unit_price
FROM
  `${PROJECT}.${DATASET}.events_*`,
  UNNEST(items) AS item
WHERE
  _TABLE_SUFFIX BETWEEN '20260101' AND '20260331'
  AND event_name = 'purchase'
  AND item.item_category IS NOT NULL
GROUP BY
  item.item_category
ORDER BY
  total_revenue DESC
```

### 82. GA4のデータをBigQueryに繋ぐと何が変わるのか【3層設計まで解説】（mart層）

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

### 83. BigQueryでGA4のサンプリングを回避して正確な数値を出す（BigQueryなら100%のデータで分析できる）

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

### 84. GA4×BigQueryでデバイス別・地域別セグメント分析をする（地域別セッション数（都道府県ランキング））

**用途**: 地域別セッション数（都道府県ランキング）

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  geo.region AS region,
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
  AND geo.country = 'Japan'
GROUP BY region
ORDER BY sessions DESC
LIMIT 20
```

### 85. GA4×BigQueryでデバイス別・地域別セグメント分析をする（国別セッション数（海外展開サイト向け））

**用途**: 国別セッション数（海外展開サイト向け）

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  geo.country AS country,
  geo.continent AS continent,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    )
  ) AS sessions,
  COUNT(DISTINCT user_pseudo_id) AS users
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'session_start'
GROUP BY country, continent
ORDER BY sessions DESC
LIMIT 30
```

### 86. GA4×BigQueryでデバイス別・地域別セグメント分析をする（地域×デバイスのクロス分析）

**用途**: 地域×デバイスのクロス分析

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  geo.region AS region,
  device.category AS device_category,
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
  AND geo.country = 'Japan'
GROUP BY region, device_category
HAVING sessions >= 5
ORDER BY region, sessions DESC
```

### 87. GA4×BigQueryでデバイス別・地域別セグメント分析をする（OS別・ブラウザ別の分析）

**用途**: OS別・ブラウザ別の分析

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  device.operating_system AS os,
  device.web_info.browser AS browser,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    )
  ) AS sessions,
  ROUND(AVG(
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'engagement_time_msec')
  ) / 1000, 1) AS avg_engagement_sec
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'session_start'
GROUP BY os, browser
HAVING sessions >= 10
ORDER BY sessions DESC
LIMIT 20
```

### 88. BigQueryでGA4のeコマースイベントを完全解析する【purchase/add_to_cart】（purchaseイベントから商品別売上を抽出するSQL） その1

**用途**: purchaseイベントから商品別売上を抽出するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  item.item_id,
  item.item_name,
  item.item_category,
  COUNT(DISTINCT ecommerce.transaction_id) AS transaction_count,
  SUM(item.quantity) AS total_quantity,
  SUM(item.item_revenue) AS total_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`,
  UNNEST(items) AS item
WHERE
  _TABLE_SUFFIX BETWEEN '20260101' AND '20260331'
  AND event_name = 'purchase'
GROUP BY
  item.item_id, item.item_name, item.item_category
ORDER BY
  total_revenue DESC
```

### 89. BigQueryでGA4のeコマースイベントを完全解析する【purchase/add_to_cart】（eコマーストラッキングの検証Tips）

**用途**: eコマーストラッキングの検証Tips

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS date,
  COUNT(*) AS purchase_events,
  COUNT(DISTINCT ecommerce.transaction_id) AS unique_transactions,
  COUNTIF(ARRAY_LENGTH(items) = 0) AS empty_items_count,
  ROUND(AVG(ecommerce.purchase_revenue), 0) AS avg_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
  AND event_name = 'purchase'
GROUP BY
  event_date
ORDER BY
  date
```

### 90. GA4×BigQueryでリピーターと新規ユーザーを分離して分析する（基本パターン：first_visitイベントの有無で判定）

**用途**: 基本パターン：first_visitイベントの有無で判定

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH user_type AS (
  SELECT
    user_pseudo_id,
    MAX(CASE WHEN event_name = 'first_visit' THEN 1 ELSE 0 END) AS is_new_user
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
  GROUP BY user_pseudo_id
)
SELECT
  CASE WHEN is_new_user = 1 THEN '新規' ELSE 'リピーター' END AS user_type,
  COUNT(*) AS users
FROM user_type
GROUP BY user_type
```

### 91. GA4×BigQueryでSearch Consoleデータを結合してオーガニック分析する（キーワード × ランディングページの分析）

**用途**: キーワード × ランディングページの分析

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  query,
  REGEXP_EXTRACT(url, r'^https?://[^/]+(/.*)') AS page_path,
  SUM(impressions) AS impressions,
  SUM(clicks) AS clicks,
  ROUND(SAFE_DIVIDE(SUM(clicks), SUM(impressions)) * 100, 2) AS ctr_pct,
  ROUND(SAFE_DIVIDE(SUM(sum_position), SUM(impressions)), 1) AS avg_position
FROM `your-project.searchconsole.searchdata_url_impression`
WHERE data_date BETWEEN '2025-03-01' AND '2025-03-31'
  AND url LIKE '%/blog/%'
  AND query IS NOT NULL
GROUP BY query, page_path
HAVING clicks >= 2
ORDER BY clicks DESC
LIMIT 50
```

### 92. GA4×BigQueryでセッションIDを正しく定義する方法（セッション数のカウント）

**用途**: セッション数のカウント

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

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
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
GROUP BY event_date
ORDER BY event_date
```

### 93. BigQueryでGA4データのコスト管理・クエリ最適化入門（パターン1：_TABLE_SUFFIXを使わない） その1

**用途**: パターン1：_TABLE_SUFFIXを使わない

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT event_date, COUNT(*) AS events
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
GROUP BY event_date
ORDER BY event_date
```

### 94. BigQueryでGA4データのコスト管理・クエリ最適化入門（月額コストの見積もり方）

**用途**: 月額コストの見積もり方

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  _TABLE_SUFFIX AS table_date,
  COUNT(*) AS row_count,
  SUM(OCTET_LENGTH(TO_JSON_STRING(t))) / 1024 / 1024 AS approx_mb
FROM `${PROJECT}.${DATASET}.events_*` t
WHERE _TABLE_SUFFIX = '20260330'
GROUP BY table_date
```

### 95. BigQueryでGA4のサンプリングを回避して正確な数値を出す（GA4 UIとBigQueryの数値を比較してみる）

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

### 96. GA4×BigQueryでカスタムディメンションを活用した分析（event_paramsのキー一覧）

**用途**: event_paramsのキー一覧

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  ep.key,
  COUNT(*) AS occurrences,
  COUNTIF(ep.value.string_value IS NOT NULL) AS has_string,
  COUNTIF(ep.value.int_value IS NOT NULL) AS has_int,
  COUNTIF(ep.value.float_value IS NOT NULL) AS has_float
FROM `${PROJECT}.${DATASET}.events_*`,
  UNNEST(event_params) AS ep
WHERE _TABLE_SUFFIX = '20250330'
GROUP BY ep.key
ORDER BY occurrences DESC
```

### 97. GA4×BigQueryでカスタムディメンションを活用した分析（user_propertiesのキー一覧）

**用途**: user_propertiesのキー一覧

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  prop.key,
  COUNT(*) AS occurrences,
  COUNTIF(prop.value.string_value IS NOT NULL) AS has_string,
  COUNTIF(prop.value.int_value IS NOT NULL) AS has_int
FROM `${PROJECT}.${DATASET}.events_*`,
  UNNEST(user_properties) AS prop
WHERE _TABLE_SUFFIX = '20250330'
GROUP BY prop.key
ORDER BY occurrences DESC
```

### 98. BigQueryでGA4のeコマースイベントを完全解析する【purchase/add_to_cart】（カテゴリ別・商品別の売上集計） その2

**用途**: カテゴリ別・商品別の売上集計

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT ecommerce.transaction_id) AS transactions,
  ROUND(SUM(ecommerce.purchase_revenue), 0) AS total_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20260101' AND '20260331'
  AND event_name = 'purchase'
GROUP BY
  medium, source
ORDER BY
  total_revenue DESC
```

### 99. GA4×BigQueryでSearch Consoleデータを結合してオーガニック分析する（キーワード別パフォーマンス）

**用途**: キーワード別パフォーマンス

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  query,
  SUM(impressions) AS total_impressions,
  SUM(clicks) AS total_clicks,
  ROUND(SAFE_DIVIDE(SUM(clicks), SUM(impressions)) * 100, 2) AS ctr_pct,
  ROUND(SAFE_DIVIDE(SUM(sum_position), SUM(impressions)), 1) AS avg_position
FROM `your-project.searchconsole.searchdata_url_impression`
WHERE data_date BETWEEN '2025-03-01' AND '2025-03-31'
  AND query IS NOT NULL
GROUP BY query
HAVING total_impressions >= 10
ORDER BY total_clicks DESC
LIMIT 30
```

### 100. GA4×BigQueryでSearch Consoleデータを結合してオーガニック分析する（ランディングページ別パフォーマンス）

**用途**: ランディングページ別パフォーマンス

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  REGEXP_EXTRACT(url, r'^https?://[^/]+(/.*)') AS page_path,
  SUM(impressions) AS total_impressions,
  SUM(clicks) AS total_clicks,
  ROUND(SAFE_DIVIDE(SUM(clicks), SUM(impressions)) * 100, 2) AS ctr_pct,
  ROUND(SAFE_DIVIDE(SUM(sum_position), SUM(impressions)), 1) AS avg_position,
  COUNT(DISTINCT query) AS unique_queries
FROM `your-project.searchconsole.searchdata_url_impression`
WHERE data_date BETWEEN '2025-03-01' AND '2025-03-31'
GROUP BY page_path
ORDER BY total_clicks DESC
LIMIT 20
```

### 101. BigQueryでGA4データのコスト管理・クエリ最適化入門（パターン1：_TABLE_SUFFIXを使わない） その2

**用途**: パターン1：_TABLE_SUFFIXを使わない

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください

```sql
SELECT event_date, COUNT(*) AS events
FROM `${PROJECT}.${DATASET}.events_*`
GROUP BY event_date
ORDER BY event_date
```

### 102. BigQueryでGA4データのコスト管理・クエリ最適化入門（テクニック3：中間テーブルやビューを活用する）

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

### 103. BigQueryでGA4データのコスト管理・クエリ最適化入門（パーティション）

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

### 104. BigQueryでGA4の直帰率を正確に計算する方法（GA4に直帰率はない問題）（BigQueryでエンゲージメント情報を取得する）

**用途**: BigQueryでエンゲージメント情報を取得する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  user_pseudo_id,
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_id') AS ga_session_id,
  (SELECT value.string_value
   FROM UNNEST(event_params)
   WHERE key = 'session_engaged') AS session_engaged,
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'engagement_time_msec') AS engagement_time_msec
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'session_start'
LIMIT 20
```

### 105. BigQueryでGA4の生データ構造を理解する【eventsテーブル解説】（event_paramsのUNNEST展開）

**用途**: event_paramsのUNNEST展開

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_date,
  event_name,
  user_pseudo_id,
  (SELECT value.string_value
   FROM UNNEST(event_params)
   WHERE key = 'page_location') AS page_location,
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_id') AS ga_session_id,
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'engagement_time_msec') AS engagement_time_msec
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'page_view'
LIMIT 100
```

### 106. GA4のBigQueryエクスポート完全設定ガイド【2026年版】（流入元（メディア）を取得するクエリ例）

**用途**: 流入元（メディア）を取得するクエリ例

**必要なテーブル**: `${DATASET}.events_20260328`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(*) AS event_count
FROM
  `${PROJECT}.${DATASET}.events_20260328`
WHERE
  event_name = 'session_start'
GROUP BY
  medium, source
ORDER BY
  event_count DESC
```

### 107. GA4×BigQueryでセッションIDを正しく定義する方法（user_pseudo_id + ga_session_idで一意なセッションIDを作る）

**用途**: user_pseudo_id + ga_session_idで一意なセッションIDを作る

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

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
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
ORDER BY session_id, event_timestamp
LIMIT 100
```

### 108. GA4×BigQueryでセッションIDを正しく定義する方法（ga_session_numberで新規・リピートを判定する）

**用途**: ga_session_numberで新規・リピートを判定する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

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
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'session_start'
```

### 109. GA4イベントパラメータをUNNESTで展開するSQLパターン集（パターン4：CROSS JOINでitemを展開する）

**用途**: パターン4：CROSS JOINでitemを展開する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_date,
  user_pseudo_id,
  item.item_id,
  item.item_name,
  item.item_category,
  item.price,
  item.quantity
FROM `${PROJECT}.${DATASET}.events_*`
CROSS JOIN UNNEST(items) AS item
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
  AND event_name = 'purchase'
```

### 110. GA4×BigQueryでセッションIDを正しく定義する方法（stagingビューとして定義する）

**用途**: stagingビューとして定義する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください

```sql
CREATE OR REPLACE VIEW `your-project.staging.stg_sessions` AS
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
FROM `${PROJECT}.${DATASET}.events_*`
WHERE event_name = 'session_start'
```

### 111. GA4イベントパラメータをUNNESTで展開するSQLパターン集（パターン7：stagingビューにまとめる）

**用途**: パターン7：stagingビューにまとめる

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください

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
FROM `${PROJECT}.${DATASET}.events_*`
```

### 112. BigQueryでGA4データのコスト管理・クエリ最適化入門（パターン2：SELECT * を使う） その1

**用途**: パターン2：SELECT * を使う

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です / `SELECT *` を含みます。必要な列だけに絞るとコストが下がります

```sql
SELECT *
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX = '20260330'
LIMIT 100
```

### 113. BigQueryでGA4データのコスト管理・クエリ最適化入門（パターン2：SELECT * を使う） その2

**用途**: パターン2：SELECT * を使う

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT event_date, event_name, user_pseudo_id
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX = '20260330'
LIMIT 100
```

### 114. BigQueryでGA4データのコスト管理・クエリ最適化入門（テクニック2：必要なカラムだけSELECTする）

**用途**: テクニック2：必要なカラムだけSELECTする

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_date,
  user_pseudo_id,
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_id') AS ga_session_id
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX = '20260330'
```

### 115. BigQueryでGA4のページ別滞在時間を正しく集計する方法（engagement_time_msecをBigQueryで取得する）

**用途**: engagement_time_msecをBigQueryで取得する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_name,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'engagement_time_msec') AS engagement_time_msec,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
  AND event_name = 'user_engagement'
```

### 116. BigQueryのパーティション・クラスタリングでGA4クエリを高速化する（集計テーブルにパーティションを設定する）

**用途**: 集計テーブルにパーティションを設定する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
CREATE OR REPLACE TABLE `your-project.mart.mart_daily_sessions`
PARTITION BY event_date
CLUSTER BY session_medium, device_category
AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS event_date,
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  IFNULL(collected_traffic_source.manual_medium, '(none)') AS session_medium,
  device.category AS device_category,
  geo.country AS country
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
  AND event_name = 'session_start'
```

### 117. BigQueryのパーティション・クラスタリングでGA4クエリを高速化する（パターン1：セッション集計テーブル）

**用途**: パターン1：セッション集計テーブル

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
CREATE OR REPLACE TABLE `your-project.mart.mart_sessions`
PARTITION BY event_date
CLUSTER BY session_medium, device_category
AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS event_date,
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  IFNULL(collected_traffic_source.manual_medium, '(none)') AS session_medium,
  device.category AS device_category
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
  AND event_name = 'session_start'
```

### 118. BigQueryのパーティション・クラスタリングでGA4クエリを高速化する（パターン2：ページビュー集計テーブル）

**用途**: パターン2：ページビュー集計テーブル

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
CREATE OR REPLACE TABLE `your-project.mart.mart_page_views`
PARTITION BY event_date
CLUSTER BY page_path, device_category
AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS event_date,
  user_pseudo_id,
  REGEXP_EXTRACT(
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location'),
    r'^https?://[^/]+(/.*)') AS page_path,
  device.category AS device_category
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
  AND event_name = 'page_view'
```

### 119. GA4のデータをBigQueryに繋ぐと何が変わるのか【3層設計まで解説】（生データをそのまま使わない方がいい理由）

**用途**: 生データをそのまま使わない方がいい理由

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  user_pseudo_id,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
  AND event_name = 'page_view'
```

### 120. GA4×BigQueryでカスタムディメンションを活用した分析（基本的な取得パターン）

**用途**: 基本的な取得パターン

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_name,
  event_timestamp,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'button_variant') AS button_variant,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'form_step') AS form_step
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
  AND event_name = 'click'
```

### 121. GA4×BigQueryでカスタムディメンションを活用した分析（user_propertiesからカスタムディメンションを取得する）

**用途**: user_propertiesからカスタムディメンションを取得する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  user_pseudo_id,
  (SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'membership_tier') AS membership_tier,
  (SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'signup_method') AS signup_method
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
  AND event_name = 'session_start'
```

### 122. BigQueryでGA4のeコマースイベントを完全解析する【purchase/add_to_cart】（purchaseイベントから商品別売上を抽出するSQL） その2

**用途**: purchaseイベントから商品別売上を抽出するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  user_pseudo_id,
  ecommerce.transaction_id,
  item.item_name,
  item.item_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`,
  UNNEST(items) AS item
WHERE
  _TABLE_SUFFIX BETWEEN '20260101' AND '20260331'
  AND event_name = 'purchase'
```

### 123. BigQueryでGA4の生データ構造を理解する【eventsテーブル解説】（user_propertiesの展開）

**用途**: user_propertiesの展開

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  user_pseudo_id,
  (SELECT value.string_value
   FROM UNNEST(user_properties)
   WHERE key = 'membership_level') AS membership_level
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'session_start'
```

### 124. BigQueryでGA4の生データ構造を理解する【eventsテーブル解説】（itemsの展開（eコマースの場合））

**用途**: itemsの展開（eコマースの場合）

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_date,
  user_pseudo_id,
  items.item_id,
  items.item_name,
  items.item_category,
  items.price,
  items.quantity
FROM `${PROJECT}.${DATASET}.events_*`,
  UNNEST(items) AS items
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'purchase'
```

### 125. GA4×BigQueryでセッションIDを正しく定義する方法（ga_session_idはevent_paramsの中にある）

**用途**: ga_session_idはevent_paramsの中にある

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  user_pseudo_id,
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_id') AS ga_session_id
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'session_start'
LIMIT 10
```

### 126. GA4イベントパラメータをUNNESTで展開するSQLパターン集（パターン1：サブクエリで単一パラメータを取り出す）

**用途**: パターン1：サブクエリで単一パラメータを取り出す

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_date,
  user_pseudo_id,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
  AND event_name = 'page_view'
```

### 127. GA4イベントパラメータをUNNESTで展開するSQLパターン集（パターン2：複数パラメータを一度に展開する）

**用途**: パターン2：複数パラメータを一度に展開する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

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
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
```

### 128. GA4イベントパラメータをUNNESTで展開するSQLパターン集（パターン3：セッションIDを構築する）

**用途**: パターン3：セッションIDを構築する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  CONCAT(
    user_pseudo_id,
    '-',
    CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
  ) AS session_id,
  event_date,
  event_name
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
```

### 129. GA4イベントパラメータをUNNESTで展開するSQLパターン集（パターン5：user_propertiesを展開する）

**用途**: パターン5：user_propertiesを展開する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(user_properties) WHERE key = 'first_open_time') AS first_open_time,
  (SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'user_tier') AS user_tier
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
```

### 130. GA4イベントパラメータをUNNESTで展開するSQLパターン集（パターン6：トラフィックソースを正しく取得する）

**用途**: パターン6：トラフィックソースを正しく取得する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_date,
  user_pseudo_id,
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_campaign_name AS campaign
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
  AND event_name = 'session_start'
```

### 131. BigQueryのパーティション・クラスタリングでGA4クエリを高速化する（クラスタリングキーの選定）

**用途**: クラスタリングキーの選定

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
CREATE OR REPLACE TABLE `your-project.mart.mart_daily_sessions`
PARTITION BY event_date
CLUSTER BY session_medium, device_category, country
AS
...
```

### 132. BigQueryのパーティション・クラスタリングでGA4クエリを高速化する（確認方法2：INFORMATION_SCHEMAで確認）

**用途**: 確認方法2：INFORMATION_SCHEMAで確認

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  table_name,
  ROUND(total_logical_bytes / POW(1024, 3), 3) AS size_gb,
  ROUND(total_physical_bytes / POW(1024, 3), 3) AS physical_size_gb
FROM `your-project.mart.INFORMATION_SCHEMA.TABLE_STORAGE`
WHERE table_name LIKE 'mart_daily%'
```

### 133. GA4のデータをBigQueryに繋ぐと何が変わるのか【3層設計まで解説】（staging層）

**用途**: staging層

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください

```sql
CREATE OR REPLACE VIEW `project.staging.stg_page_views` AS
SELECT
  event_date,
  user_pseudo_id,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') AS source
FROM `${PROJECT}.${DATASET}.events_*`
WHERE event_name = 'page_view'
```

### 134. GA4のBigQueryエクスポート完全設定ガイド【2026年版】（セッションIDを取得するクエリ例）

**用途**: セッションIDを取得するクエリ例

**必要なテーブル**: `${DATASET}.events_20260328`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
  event_name,
  event_timestamp
FROM
  `${PROJECT}.${DATASET}.events_20260328`
WHERE
  event_name = 'page_view'
LIMIT 100
```

### 135. GA4×BigQueryのエクスポートが止まったときのトラブルシューティング（STEP 1：最新テーブルの日付を確認する）

**用途**: STEP 1：最新テーブルの日付を確認する

**必要なテーブル**: `${DATASET}.__TABLES__`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  table_id,
  TIMESTAMP_MILLIS(last_modified_time) AS last_modified
FROM `${PROJECT}.${DATASET}.__TABLES__`
WHERE table_id LIKE 'events_%'
ORDER BY table_id DESC
LIMIT 10
```

### 136. GA4×BigQueryのエクスポートが止まったときのトラブルシューティング（テーブルの作成日時と行数）

**用途**: テーブルの作成日時と行数

**必要なテーブル**: `${DATASET}.INFORMATION_SCHEMA`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  table_name,
  creation_time,
  ROUND(total_rows / 1000, 1) AS rows_k,
  ROUND(total_logical_bytes / POW(1024, 2), 1) AS size_mb
FROM `${PROJECT}.${DATASET}.INFORMATION_SCHEMA.TABLE_STORAGE`
WHERE table_name LIKE 'events_%'
ORDER BY table_name DESC
LIMIT 10
```

### 137. GA4×BigQueryのエクスポートが止まったときのトラブルシューティング（直近のテーブル作成状況をチェック）

**用途**: 直近のテーブル作成状況をチェック

**必要なテーブル**: `${DATASET}.INFORMATION_SCHEMA`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  table_name,
  creation_time,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), creation_time, HOUR) AS hours_ago
FROM `${PROJECT}.${DATASET}.INFORMATION_SCHEMA.TABLES`
WHERE table_name LIKE 'events_%'
ORDER BY creation_time DESC
LIMIT 5
```

### 138. GA4×BigQueryでSearch Consoleデータを結合してオーガニック分析する（Search Consoleデータの構造を確認する）

**用途**: Search Consoleデータの構造を確認する

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  data_date,
  query,
  url,
  country,
  device,
  impressions,
  clicks,
  sum_position
FROM `your-project.searchconsole.searchdata_url_impression`
WHERE data_date BETWEEN '2025-03-01' AND '2025-03-31'
ORDER BY clicks DESC
LIMIT 20
```

### 139. GA4×BigQueryでSearch Consoleデータを結合してオーガニック分析する（URLの正規化）

**用途**: URLの正規化

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  REGEXP_EXTRACT(
    'https://example.com/blog/post-1?utm_source=twitter',
    r'^(https?://[^?#]+)'
  ) AS ga4_clean_url,
  REGEXP_EXTRACT(
    'https://example.com/blog/post-1',
    r'^(https?://[^?#]+)'
  ) AS search_console_clean_url
```

### 140. Claude Codeでクロスチャネルアトリビューション分析を自動化した（Step 1：ユーザーのタッチポイント経路を抽出する）

**用途**: Step 1：ユーザーのタッチポイント経路を抽出する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH user_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id,
    PARSE_TIMESTAMP(
      '%Y%m%d%H%M%S',
      CONCAT(event_date, LPAD(
        CAST(EXTRACT(HOUR FROM TIMESTAMP_MICROS(event_timestamp)) AS STRING),
        2, '0'),
        LPAD(
        CAST(EXTRACT(MINUTE FROM TIMESTAMP_MICROS(event_timestamp)) AS STRING),
        2, '0'),
        LPAD(
        CAST(EXTRACT(SECOND FROM TIMESTAMP_MICROS(event_timestamp)) AS STRING),
        2, '0')
      )
    ) AS session_start,
    CONCAT(
      IFNULL(collected_traffic_source.manual_source, '(direct)'),
      ' / ',
      IFNULL(collected_traffic_source.manual_medium, '(none)')
    ) AS channel,
    MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) AS has_purchase,
    SUM(CASE WHEN event_name = 'purchase'
      THEN ecommerce.purchase_revenue ELSE 0 END) AS revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260201' AND '20260331'
  GROUP BY user_pseudo_id, session_id, session_start, channel
),
converting_users AS (
  SELECT user_pseudo_id
  FROM user_sessions
  WHERE has_purchase = 1
)
SELECT
  s.user_pseudo_id,
  s.channel,
  s.session_start,
  s.has_purchase,
  s.revenue,
  ROW_NUMBER() OVER (
    PARTITION BY s.user_pseudo_id
    ORDER BY s.session_start
  ) AS touchpoint_order,
  COUNT(*) OVER (
    PARTITION BY s.user_pseudo_id
  ) AS total_touchpoints
FROM user_sessions s
INNER JOIN converting_users c
  ON s.user_pseudo_id = c.user_pseudo_id
ORDER BY s.user_pseudo_id, s.session_start;
```

### 141. BigQuery × Claude Codeで異常検知アラートを作る【売上急落を即通知】（異常検知ロジックのSQL）

**用途**: 異常検知ロジックのSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です / `SELECT *` を含みます。必要な列だけに絞るとコストが下がります

```sql
WITH daily_metrics AS (
  SELECT
    event_date,
    COUNT(DISTINCT
      CONCAT(user_pseudo_id, '-',
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
      )
    ) AS sessions,
    IFNULL(SUM(ecommerce.purchase_revenue), 0) AS revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
  GROUP BY
    event_date
),

with_moving_avg AS (
  SELECT
    *,
    AVG(sessions) OVER (
      ORDER BY event_date ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
    ) AS avg_sessions_7d,
    AVG(revenue) OVER (
      ORDER BY event_date ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
    ) AS avg_revenue_7d
  FROM daily_metrics
)

SELECT
  event_date,
  sessions,
  revenue,
  avg_sessions_7d,
  avg_revenue_7d,
  SAFE_DIVIDE(sessions - avg_sessions_7d, avg_sessions_7d) * 100 AS session_deviation_pct,
  SAFE_DIVIDE(revenue - avg_revenue_7d, avg_revenue_7d) * 100 AS revenue_deviation_pct,
  CASE
    WHEN SAFE_DIVIDE(sessions - avg_sessions_7d, avg_sessions_7d) * 100 < -30 THEN TRUE
    WHEN SAFE_DIVIDE(revenue - avg_revenue_7d, avg_revenue_7d) * 100 < -30 THEN TRUE
    ELSE FALSE
  END AS is_anomaly
FROM with_moving_avg
WHERE event_date = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
```

### 142. Claude Codeに競合サイトの施策をGA4データから推測させた話（Step 1：トレンド変化を検出するSQLを用意する）

**用途**: Step 1：トレンド変化を検出するSQLを用意する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH sessions AS (
  SELECT
    DATE_TRUNC(
      PARSE_DATE('%Y%m%d', event_date), WEEK
    ) AS week_start,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium,
    (SELECT value.int_value FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id,
    user_pseudo_id
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
),
weekly_metrics AS (
  SELECT
    week_start,
    CONCAT(IFNULL(source, '(direct)'), ' / ', IFNULL(medium, '(none)')) AS channel,
    COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(session_id AS STRING))) AS sessions
  FROM sessions
  GROUP BY week_start, channel
)
SELECT
  week_start,
  channel,
  sessions,
  LAG(sessions) OVER (PARTITION BY channel ORDER BY week_start) AS prev_week_sessions,
  SAFE_DIVIDE(
    sessions - LAG(sessions) OVER (PARTITION BY channel ORDER BY week_start),
    LAG(sessions) OVER (PARTITION BY channel ORDER BY week_start)
  ) AS wow_change_rate
FROM weekly_metrics
ORDER BY week_start DESC, sessions DESC;
```

### 143. Claude Codeでクロスチャネルアトリビューション分析を自動化した（Step 2：線形モデルを実装する）

**用途**: Step 2：線形モデルを実装する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH user_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id,
    PARSE_TIMESTAMP(
      '%Y%m%d%H%M%S',
      CONCAT(event_date, LPAD(
        CAST(EXTRACT(HOUR FROM TIMESTAMP_MICROS(event_timestamp)) AS STRING),
        2, '0'),
        LPAD(
        CAST(EXTRACT(MINUTE FROM TIMESTAMP_MICROS(event_timestamp)) AS STRING),
        2, '0'),
        LPAD(
        CAST(EXTRACT(SECOND FROM TIMESTAMP_MICROS(event_timestamp)) AS STRING),
        2, '0')
      )
    ) AS session_start,
    CONCAT(
      IFNULL(collected_traffic_source.manual_source, '(direct)'),
      ' / ',
      IFNULL(collected_traffic_source.manual_medium, '(none)')
    ) AS channel,
    MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) AS has_purchase,
    SUM(CASE WHEN event_name = 'purchase'
      THEN ecommerce.purchase_revenue ELSE 0 END) AS revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260201' AND '20260331'
  GROUP BY user_pseudo_id, session_id, session_start, channel
),
converting_users AS (
  SELECT user_pseudo_id
  FROM user_sessions
  WHERE has_purchase = 1
),
touchpoints AS (
  SELECT
    s.user_pseudo_id,
    s.channel,
    s.session_start,
    s.revenue,
    ROW_NUMBER() OVER (
      PARTITION BY s.user_pseudo_id
      ORDER BY s.session_start
    ) AS touchpoint_order,
    COUNT(*) OVER (
      PARTITION BY s.user_pseudo_id
    ) AS total_touchpoints
  FROM user_sessions s
  INNER JOIN converting_users c
    ON s.user_pseudo_id = c.user_pseudo_id
),
linear_attribution AS (
  SELECT
    user_pseudo_id,
    channel,
    touchpoint_order,
    total_touchpoints,
    revenue,
    -- 各タッチポイントに均等配分
    SAFE_DIVIDE(
      MAX(revenue) OVER (PARTITION BY user_pseudo_id),
      total_touchpoints
    ) AS attributed_revenue
  FROM touchpoints
)
SELECT
  channel,
  COUNT(*) AS touchpoints,
  ROUND(SUM(attributed_revenue), 0) AS linear_revenue,
  ROUND(AVG(attributed_revenue), 0) AS avg_attributed_revenue
FROM linear_attribution
GROUP BY channel
ORDER BY linear_revenue DESC;
```

### 144. Claude Codeでクロスチャネルアトリビューション分析を自動化した（Step 3：時間減衰モデルを実装する）

**用途**: Step 3：時間減衰モデルを実装する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です / `SELECT *` を含みます。必要な列だけに絞るとコストが下がります

```sql
WITH user_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id,
    PARSE_TIMESTAMP(
      '%Y%m%d%H%M%S',
      CONCAT(event_date, LPAD(
        CAST(EXTRACT(HOUR FROM TIMESTAMP_MICROS(event_timestamp)) AS STRING),
        2, '0'),
        LPAD(
        CAST(EXTRACT(MINUTE FROM TIMESTAMP_MICROS(event_timestamp)) AS STRING),
        2, '0'),
        LPAD(
        CAST(EXTRACT(SECOND FROM TIMESTAMP_MICROS(event_timestamp)) AS STRING),
        2, '0')
      )
    ) AS session_start,
    CONCAT(
      IFNULL(collected_traffic_source.manual_source, '(direct)'),
      ' / ',
      IFNULL(collected_traffic_source.manual_medium, '(none)')
    ) AS channel,
    MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) AS has_purchase,
    SUM(CASE WHEN event_name = 'purchase'
      THEN ecommerce.purchase_revenue ELSE 0 END) AS revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260201' AND '20260331'
  GROUP BY user_pseudo_id, session_id, session_start, channel
),
converting_users AS (
  SELECT user_pseudo_id
  FROM user_sessions
  WHERE has_purchase = 1
),
touchpoints AS (
  SELECT
    s.user_pseudo_id,
    s.channel,
    s.session_start,
    s.revenue,
    ROW_NUMBER() OVER (
      PARTITION BY s.user_pseudo_id
      ORDER BY s.session_start
    ) AS touchpoint_order,
    COUNT(*) OVER (
      PARTITION BY s.user_pseudo_id
    ) AS total_touchpoints
  FROM user_sessions s
  INNER JOIN converting_users c
    ON s.user_pseudo_id = c.user_pseudo_id
),
time_decay AS (
  SELECT
    user_pseudo_id,
    channel,
    touchpoint_order,
    total_touchpoints,
    revenue,
    -- 指数関数的に重みを増やす（半減期7日）
    EXP(
      -0.693 * TIMESTAMP_DIFF(
        MAX(session_start) OVER (PARTITION BY user_pseudo_id),
        session_start,
        DAY
      ) / 7.0
    ) AS decay_weight
  FROM touchpoints
),
weighted AS (
  SELECT
    *,
    SAFE_DIVIDE(
      decay_weight,
      SUM(decay_weight) OVER (PARTITION BY user_pseudo_id)
    ) AS normalized_weight,
    MAX(revenue) OVER (PARTITION BY user_pseudo_id) AS total_revenue
  FROM time_decay
)
SELECT
  channel,
  COUNT(*) AS touchpoints,
  ROUND(SUM(normalized_weight * total_revenue), 0) AS decay_revenue
FROM weighted
GROUP BY channel
ORDER BY decay_revenue DESC;
```

### 145. BigQuery × Claude Codeで異常検知アラートを作る【売上急落を即通知】（日次メトリクスと移動平均のSQL）

**用途**: 日次メトリクスと移動平均のSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH daily_metrics AS (
  SELECT
    event_date,
    COUNT(DISTINCT
      CONCAT(user_pseudo_id, '-',
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
      )
    ) AS sessions,
    SUM(ecommerce.purchase_revenue) AS revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
  GROUP BY
    event_date
)

SELECT
  event_date,
  sessions,
  revenue,
  AVG(sessions) OVER (
    ORDER BY event_date
    ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
  ) AS avg_sessions_7d,
  AVG(revenue) OVER (
    ORDER BY event_date
    ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
  ) AS avg_revenue_7d
FROM daily_metrics
ORDER BY event_date DESC
```

### 146. Claude Code × MCPでGA4レポートを毎朝Slack通知する仕組みを作った

**用途**: 日次レポート用SQLクエリ

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
WITH yesterday AS (
  SELECT
    session_default_channel_group AS channel,
    COUNT(DISTINCT session_id) AS sessions,
    COUNTIF(has_purchase = TRUE) AS conversions,
    SUM(purchase_revenue) AS revenue
  FROM `your_project.your_dataset_staging.stg_sessions`
  WHERE session_date = DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 1 DAY)
  GROUP BY channel
),
day_before AS (
  SELECT
    session_default_channel_group AS channel,
    COUNT(DISTINCT session_id) AS sessions,
    COUNTIF(has_purchase = TRUE) AS conversions,
    SUM(purchase_revenue) AS revenue
  FROM `your_project.your_dataset_staging.stg_sessions`
  WHERE session_date = DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 2 DAY)
  GROUP BY channel
)
SELECT
  y.channel,
  y.sessions,
  y.conversions,
  y.revenue,
  SAFE_DIVIDE(y.sessions - d.sessions, d.sessions) * 100 AS sessions_change_pct,
  SAFE_DIVIDE(y.conversions - d.conversions, d.conversions) * 100 AS conversions_change_pct
FROM yesterday y
LEFT JOIN day_before d USING (channel)
ORDER BY y.sessions DESC
```

### 147. BigQuery × Claude Codeで月次事業報告書を自動作成する仕組み（セッション・CV・売上の月次サマリ）

**用途**: セッション・CV・売上の月次サマリ

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH monthly_data AS (
  SELECT
    FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m%d', event_date)) AS month,
    COUNT(DISTINCT CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params)
            WHERE key = 'ga_session_id') AS STRING)
    )) AS sessions,
    COUNT(DISTINCT CASE WHEN event_name = 'purchase'
      THEN user_pseudo_id END) AS purchasers,
    SUM(CASE WHEN event_name = 'purchase'
      THEN ecommerce.purchase_revenue ELSE 0 END) AS revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_TRUNC(
      DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH))
    AND FORMAT_DATE('%Y%m%d', LAST_DAY(
      DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)))
  GROUP BY month
)
SELECT
  month,
  sessions,
  purchasers,
  revenue,
  SAFE_DIVIDE(purchasers, sessions) AS cvr,
  SAFE_DIVIDE(revenue, purchasers) AS avg_order_value
FROM monthly_data;
```

### 148. Claude CodeでEC×GA4のA/Bテスト結果をBigQueryから自動集計する

**用途**: Step 1: BigQueryでA/Bテストデータを集計するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH ab_impressions AS (
  -- A/Bテストのインプレッション
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ab_test_name') AS test_name,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ab_test_variant') AS variant
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    event_name = 'ab_test_impression'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
),
session_conversions AS (
  -- 購入イベントのあったセッション
  SELECT DISTINCT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    ecommerce.purchase_revenue AS revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
)

SELECT
  ai.test_name,
  ai.variant,
  COUNT(DISTINCT ai.user_pseudo_id) AS users,
  COUNT(DISTINCT ai.ga_session_id) AS sessions,
  COUNT(DISTINCT sc.ga_session_id) AS conversions,
  SAFE_DIVIDE(
    COUNT(DISTINCT sc.ga_session_id),
    COUNT(DISTINCT ai.ga_session_id)
  ) AS cvr,
  SUM(sc.revenue) AS total_revenue,
  SAFE_DIVIDE(
    SUM(sc.revenue),
    COUNT(DISTINCT ai.ga_session_id)
  ) AS revenue_per_session
FROM
  ab_impressions ai
LEFT JOIN
  session_conversions sc
  ON ai.user_pseudo_id = sc.user_pseudo_id
  AND ai.ga_session_id = sc.ga_session_id
GROUP BY
  ai.test_name, ai.variant
ORDER BY
  ai.test_name, ai.variant
```

### 149. Claude Code × BigQueryでEC広告の予算配分を自動最適化する提案ツールを作った

**用途**: GA4データから売上を抽出するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH channel_revenue AS (
  SELECT
    CONCAT(
      IFNULL(collected_traffic_source.manual_source, '(direct)'),
      ' / ',
      IFNULL(collected_traffic_source.manual_medium, '(none)')
    ) AS channel,
    SUM(CASE WHEN event_name = 'purchase'
      THEN ecommerce.purchase_revenue ELSE 0 END) AS revenue,
    COUNT(DISTINCT CASE WHEN event_name = 'purchase'
      THEN CONCAT(
        user_pseudo_id,
        CAST((SELECT value.int_value FROM UNNEST(event_params)
              WHERE key = 'ga_session_id') AS STRING)
      ) END) AS conversions,
    COUNT(DISTINCT CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params)
            WHERE key = 'ga_session_id') AS STRING)
    )) AS sessions
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_TRUNC(
      DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH))
    AND FORMAT_DATE('%Y%m%d', LAST_DAY(
      DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)))
  GROUP BY channel
)
SELECT
  channel,
  sessions,
  conversions,
  revenue,
  SAFE_DIVIDE(conversions, sessions) * 100 AS cvr,
  SAFE_DIVIDE(revenue, sessions) AS revenue_per_session
FROM channel_revenue
ORDER BY revenue DESC;
```

### 150. Claude Codeに競合サイトの施策をGA4データから推測させた話（Step 3：購入率の変動も加える）

**用途**: Step 3：購入率の変動も加える

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH purchase_sessions AS (
  SELECT
    DATE_TRUNC(
      PARSE_DATE('%Y%m%d', event_date), WEEK
    ) AS week_start,
    (SELECT value.string_value FROM UNNEST(event_params)
     WHERE key = 'page_location') AS page_location,
    (SELECT value.int_value FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id,
    user_pseudo_id,
    event_name
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
    AND event_name IN ('page_view', 'purchase')
)
SELECT
  week_start,
  COUNT(DISTINCT CASE WHEN event_name = 'purchase'
    THEN CONCAT(user_pseudo_id, CAST(session_id AS STRING))
  END) AS purchase_sessions,
  COUNT(DISTINCT
    CONCAT(user_pseudo_id, CAST(session_id AS STRING))
  ) AS total_sessions,
  SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN event_name = 'purchase'
      THEN CONCAT(user_pseudo_id, CAST(session_id AS STRING))
    END),
    COUNT(DISTINCT
      CONCAT(user_pseudo_id, CAST(session_id AS STRING))
    )
  ) AS cvr
FROM purchase_sessions
GROUP BY week_start
ORDER BY week_start DESC;
```

### 151. Claude Code × Python × BigQueryでLTV予測モデルを作った（RFM（Recency, Frequency, Monetary）データの取得SQL）

**用途**: RFM（Recency, Frequency, Monetary）データの取得SQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH purchases AS (
  SELECT
    user_pseudo_id,
    PARSE_DATE('%Y%m%d', event_date) AS purchase_date,
    ecommerce.purchase_revenue AS revenue,
    ecommerce.transaction_id
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    event_name = 'purchase'
    AND ecommerce.transaction_id IS NOT NULL
    AND _TABLE_SUFFIX BETWEEN '20250101' AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
),
user_metrics AS (
  SELECT
    user_pseudo_id,
    MIN(purchase_date) AS first_purchase,
    MAX(purchase_date) AS last_purchase,
    COUNT(DISTINCT transaction_id) AS frequency,
    SUM(revenue) AS monetary,
    DATE_DIFF(MAX(purchase_date), MIN(purchase_date), DAY) AS recency_days,
    DATE_DIFF(CURRENT_DATE(), MIN(purchase_date), DAY) AS tenure_days
  FROM purchases
  GROUP BY user_pseudo_id
)
SELECT
  user_pseudo_id,
  frequency,
  recency_days,
  tenure_days,
  monetary,
  monetary / frequency AS avg_order_value,
  first_purchase,
  last_purchase
FROM user_metrics
WHERE frequency >= 1
ORDER BY monetary DESC
```

### 152. BigQuery × Claude Codeで月次事業報告書を自動作成する仕組み（チャネル別パフォーマンス）

**用途**: チャネル別パフォーマンス

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  CONCAT(
    IFNULL(collected_traffic_source.manual_source, '(direct)'),
    ' / ',
    IFNULL(collected_traffic_source.manual_medium, '(none)')
  ) AS channel,
  COUNT(DISTINCT CONCAT(
    user_pseudo_id,
    CAST((SELECT value.int_value FROM UNNEST(event_params)
          WHERE key = 'ga_session_id') AS STRING)
  )) AS sessions,
  SUM(CASE WHEN event_name = 'purchase'
    THEN ecommerce.purchase_revenue ELSE 0 END) AS revenue
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN
  FORMAT_DATE('%Y%m%d', DATE_TRUNC(
    DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH))
  AND FORMAT_DATE('%Y%m%d', LAST_DAY(
    DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)))
GROUP BY channel
ORDER BY sessions DESC
LIMIT 10;
```

### 153. Claude CodeのAgentモードでEC売上データを自動分析させた結果

**用途**: Step 1: BigQueryクエリの自動生成

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS date,
  collected_traffic_source.manual_medium AS medium,
  COUNT(DISTINCT
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases,
  SUM(ecommerce.purchase_revenue) AS revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY
  date, medium
ORDER BY
  date DESC, revenue DESC
```

### 154. Claude Code × BigQuery MCPでGA4分析を完全自動化する方法【EC事業者向け実践ガイド】

**用途**: ケース1：チャネル別セッション数・CV数の確認

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  COUNT(DISTINCT
    CONCAT(user_pseudo_id, CAST(
      (SELECT value.int_value FROM UNNEST(event_params)
       WHERE key = 'ga_session_id') AS STRING))
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS conversions,
  ROUND(
    COUNTIF(event_name = 'purchase') /
    COUNT(DISTINCT
      CONCAT(user_pseudo_id, CAST(
        (SELECT value.int_value FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING))
    ) * 100, 2
  ) AS cvr_pct
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN
  FORMAT_DATE('%Y%m%d', DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH))
  AND FORMAT_DATE('%Y%m%d', LAST_DAY(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)))
GROUP BY 1
ORDER BY sessions DESC
```

### 155. Claude CodeでBigQueryのSQLを自然言語から自動生成する（実例1：セッション数をチャネル別に集計）

**用途**: 実例1：セッション数をチャネル別に集計

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  collected_traffic_source.manual_source AS channel,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id,
      (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
    )
  ) AS sessions
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH))
    AND FORMAT_DATE('%Y%m%d', LAST_DAY(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)))
GROUP BY
  channel
ORDER BY
  sessions DESC
```

### 156. Claude CodeでBigQueryのSQLを自然言語から自動生成する（実例2：purchaseイベントから商品別売上を集計）

**用途**: 実例2：purchaseイベントから商品別売上を集計

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  items.item_name,
  SUM(items.item_revenue) AS total_revenue,
  COUNT(*) AS purchase_count
FROM
  `${PROJECT}.${DATASET}.events_*`,
  UNNEST(items) AS items
WHERE
  event_name = 'purchase'
  AND _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH))
    AND FORMAT_DATE('%Y%m%d', LAST_DAY(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)))
GROUP BY
  items.item_name
ORDER BY
  total_revenue DESC
```

### 157. Claude CodeでGA4のイベント設計書を自動生成する方法（イベント名とパラメータの一覧を取得するSQL）

**用途**: イベント名とパラメータの一覧を取得するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_name,
  COUNT(*) AS event_count,
  COUNT(DISTINCT user_pseudo_id) AS unique_users,
  MIN(PARSE_DATE('%Y%m%d', event_date)) AS first_seen,
  MAX(PARSE_DATE('%Y%m%d', event_date)) AS last_seen
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY
  event_name
ORDER BY
  event_count DESC
```

### 158. Claude CodeでGA4のイベント設計書を自動生成する方法（イベントごとのパラメータ一覧を取得するSQL）

**用途**: イベントごとのパラメータ一覧を取得するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_name,
  ep.key AS param_key,
  CASE
    WHEN ep.value.string_value IS NOT NULL THEN 'string'
    WHEN ep.value.int_value IS NOT NULL THEN 'int'
    WHEN ep.value.float_value IS NOT NULL THEN 'float'
    WHEN ep.value.double_value IS NOT NULL THEN 'double'
    ELSE 'unknown'
  END AS param_type,
  COUNT(*) AS occurrence_count,
  -- サンプル値（string型の場合）
  APPROX_TOP_COUNT(ep.value.string_value, 3) AS sample_values_string
FROM
  `${PROJECT}.${DATASET}.events_*`,
  UNNEST(event_params) AS ep
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY
  event_name, param_key, param_type
ORDER BY
  event_name, occurrence_count DESC
```

### 159. Claude CodeでGA4のイベント設計書を自動生成する方法（Step 2: ecommerce関連イベントの詳細を取得する）

**用途**: Step 2: ecommerce関連イベントの詳細を取得する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_name,
  COUNT(*) AS event_count,
  COUNT(DISTINCT
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
  ) AS unique_sessions,
  SUM(ecommerce.purchase_revenue) AS total_revenue,
  COUNT(DISTINCT ecommerce.transaction_id) AS unique_transactions
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  event_name IN (
    'view_item', 'add_to_cart', 'begin_checkout',
    'add_payment_info', 'add_shipping_info', 'purchase'
  )
  AND _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY
  event_name
ORDER BY
  event_count DESC
```

### 160. Claude Codeで複数広告媒体のROASを一括比較するスクリプトを作成した（Step 3: GA4のコンバージョンデータと突合する）

**用途**: Step 3: GA4のコンバージョンデータと突合する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS ga4_conversions,
  SUM(ecommerce.purchase_revenue) AS ga4_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY
  medium, source
ORDER BY
  ga4_revenue DESC
```

### 161. Claude Code × Python × BigQueryでLTV予測モデルを作った（セッション行動データの取得SQL（回帰モデル用））

**用途**: セッション行動データの取得SQL（回帰モデル用）

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  user_pseudo_id,
  COUNT(DISTINCT
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
  ) AS total_sessions,
  COUNTIF(event_name = 'view_item') AS view_item_count,
  COUNTIF(event_name = 'add_to_cart') AS add_to_cart_count,
  COUNTIF(event_name = 'page_view') AS page_view_count,
  collected_traffic_source.manual_medium AS first_medium,
  device.category AS device_category
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY
  user_pseudo_id, first_medium, device_category
```

### 162. Claude Code × Google Sheets APIでBigQueryレポートを自動更新する

**用途**: Step 2: BigQueryからデータを取得するSQL

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS date,
  collected_traffic_source.manual_medium AS medium,
  COUNT(DISTINCT
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases,
  SUM(ecommerce.purchase_revenue) AS revenue
FROM
  `{project_id}.{dataset}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY
  date, medium
ORDER BY
  date DESC, revenue DESC
```

### 163. 非エンジニアEC経営者がClaude Code × BigQueryで自走できるようになるまで（体験3：定期的に見たい数字を「型」にする）

**用途**: 体験3：定期的に見たい数字を「型」にする

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH base AS (
  SELECT
    user_pseudo_id,
    event_name,
    event_date,
    (SELECT value.int_value FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id,
    CONCAT(
      IFNULL(collected_traffic_source.manual_source, '(direct)'),
      ' / ',
      IFNULL(collected_traffic_source.manual_medium, '(none)')
    ) AS channel,
    ecommerce.purchase_revenue AS revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
)
SELECT
  COUNT(DISTINCT CONCAT(
    user_pseudo_id, CAST(session_id AS STRING))
  ) AS total_sessions,
  COUNTIF(event_name = 'purchase') AS purchases,
  SAFE_DIVIDE(
    COUNTIF(event_name = 'purchase'),
    COUNT(DISTINCT CONCAT(
      user_pseudo_id, CAST(session_id AS STRING)))
  ) AS purchase_rate,
  ROUND(AVG(
    CASE WHEN event_name = 'purchase' AND revenue > 0
    THEN revenue END
  ), 0) AS avg_order_value,
  SAFE_DIVIDE(
    COUNTIF(event_name = 'add_to_cart'),
    COUNT(DISTINCT CONCAT(
      user_pseudo_id, CAST(session_id AS STRING)))
  ) AS cart_add_rate
FROM base;
```

### 164. Claude Codeで売上が下がった原因をBigQueryから自動で仮説生成させる

**用途**: Step 1：売上変化の検出

**必要なテーブル**: `${DATASET}.mart_channel_performance`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
WITH current_period AS (
  SELECT SUM(total_revenue) AS revenue
  FROM `${PROJECT}.${DATASET}.mart_channel_performance`
  WHERE date BETWEEN DATE_TRUNC(CURRENT_DATE(), MONTH)
    AND CURRENT_DATE()
),
previous_period AS (
  SELECT SUM(total_revenue) AS revenue
  FROM `${PROJECT}.${DATASET}.mart_channel_performance`
  WHERE date BETWEEN DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH)
    AND LAST_DAY(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH))
)
SELECT
  c.revenue AS current_revenue,
  p.revenue AS previous_revenue,
  c.revenue - p.revenue AS diff,
  ROUND((c.revenue - p.revenue) / p.revenue * 100, 1) AS change_pct
FROM current_period c, previous_period p
```

### 165. MCP × BigQuery × Claude Codeで聞くだけで分析できる社内ツールを作った

**用途**: 例1：チャネル別セッション数の確認

**必要なテーブル**: `${DATASET}.stg_sessions`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  channel_grouping,
  COUNT(DISTINCT session_id) AS sessions
FROM `${PROJECT}.${DATASET}.stg_sessions`
WHERE session_date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY) AND CURRENT_DATE()
GROUP BY channel_grouping
ORDER BY sessions DESC
```

### 166. Claude Codeで複数広告媒体のROASを一括比較するスクリプトを作成した（テーブル設計）

**用途**: テーブル設計

**必要なテーブル**: `${DATASET}.raw_google_ads`, `${DATASET}.raw_line_ads`, `${DATASET}.raw_meta_ads`, `${DATASET}.unified_ad_performance`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
CREATE OR REPLACE VIEW `${PROJECT}.${DATASET}.unified_ad_performance` AS

-- Google Ads
SELECT
  'google' AS platform,
  segments_date AS date,
  campaign_name,
  metrics_cost_micros / 1000000 AS cost,
  metrics_conversions AS conversions,
  metrics_conversions_value AS conversion_value,
  metrics_clicks AS clicks,
  metrics_impressions AS impressions
FROM
  `${PROJECT}.${DATASET}.raw_google_ads`

UNION ALL

-- Meta Ads
SELECT
  'meta' AS platform,
  date_start AS date,
  campaign_name,
  spend AS cost,
  CAST(actions_purchase AS FLOAT64) AS conversions,
  action_values_purchase AS conversion_value,
  clicks,
  impressions
FROM
  `${PROJECT}.${DATASET}.raw_meta_ads`

UNION ALL

-- LINE Ads
SELECT
  'line' AS platform,
  report_date AS date,
  campaign_name,
  cost,
  conversions,
  conversion_value,
  clicks,
  impressions
FROM
  `${PROJECT}.${DATASET}.raw_line_ads`
```

### 167. Claude CodeでBigQueryのSQLを自然言語から自動生成する（LIMIT句で結果を確認）

**用途**: LIMIT句で結果を確認

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_date,
  event_name,
  user_pseudo_id
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX = '20260301'
LIMIT 10
```

### 168. 非エンジニアEC経営者がClaude Code × BigQueryで自走できるようになるまで（返ってきたSQL）

**用途**: 返ってきたSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  COUNT(DISTINCT CONCAT(
    user_pseudo_id,
    CAST((SELECT value.int_value FROM UNNEST(event_params)
          WHERE key = 'ga_session_id') AS STRING)
  )) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN
  FORMAT_DATE('%Y%m%d', DATE_TRUNC(
    DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH))
  AND FORMAT_DATE('%Y%m%d', LAST_DAY(
    DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)));
```

### 169. Claude Code × Looker Studio APIでダッシュボードを自動更新する

**用途**: Step 3：BigQueryテーブル変更を検知する

**必要なテーブル**: `${DATASET}.INFORMATION_SCHEMA`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  table_name,
  column_name,
  data_type,
  is_nullable
FROM `${PROJECT}.${DATASET}.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'your_table'
ORDER BY ordinal_position;
```

### 170. ユーザーの閲覧から購入までの日数分布をBigQueryで可視化する（リマーケティング期間の設定根拠）

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

### 171. BigQueryで1回しか買わない顧客と2回以上買う顧客の行動差を分析した（流入元の違いを確認する）

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

### 172. BigQueryでEC商品別の粗利×CVR×流入数をまとめた利益ダッシュボードを作った（商品別の流入数とCVRを算出するSQL）

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

### 173. ECの季節変動をBigQueryで前年比分析して仕入れ計画に活かす方法（月別売上の前年比SQL）

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

### 174. ECの季節変動をBigQueryで前年比分析して仕入れ計画に活かす方法（週別売上の前年比SQL）

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

### 175. ECの季節変動をBigQueryで前年比分析して仕入れ計画に活かす方法（商品カテゴリ別×月別の分析）

**用途**: 商品カテゴリ別×月別の分析

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH category_monthly AS (
  SELECT
    EXTRACT(YEAR FROM PARSE_DATE('%Y%m%d', event_date)) AS year,
    EXTRACT(MONTH FROM PARSE_DATE('%Y%m%d', event_date)) AS month,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_category') AS category,
    SUM(ecommerce.purchase_revenue) AS revenue,
    SUM(
      (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'quantity')
    ) AS quantity
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'purchase'
    AND ecommerce.purchase_revenue > 0
    AND _TABLE_SUFFIX BETWEEN '20250101' AND '20260331'
  GROUP BY year, month, category
)
SELECT
  curr.category,
  curr.month,
  curr.revenue AS current_revenue,
  prev.revenue AS prev_revenue,
  ROUND(SAFE_DIVIDE(curr.revenue - prev.revenue, prev.revenue) * 100, 1) AS revenue_yoy_pct,
  curr.quantity AS current_qty,
  prev.quantity AS prev_qty
FROM category_monthly curr
LEFT JOIN category_monthly prev
  ON curr.category = prev.category
  AND curr.month = prev.month
  AND curr.year = prev.year + 1
WHERE curr.year = 2026
ORDER BY curr.category, curr.month;
```

### 176. GA4×BigQueryでモバイルとPCの購買行動の違いを分析した（デバイス別の基本指標を比較する）

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

### 177. BigQueryで売上上位20%の商品が生み出す収益構造をパレート分析した（Step 1: 商品別売上集計SQL）

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

### 178. BigQueryで売上上位20%の商品が生み出す収益構造をパレート分析した（Step 2: 累積比率を算出してパレート曲線を描く）

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

### 179. BigQueryで売上上位20%の商品が生み出す収益構造をパレート分析した（Step 3: ABC分析のサマリー）

**用途**: Step 3: ABC分析のサマリー

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です / `SELECT *` を含みます。必要な列だけに絞るとコストが下がります

```sql
WITH item_revenue AS (
  SELECT
    items.item_name,
    SUM(items.item_revenue) AS total_revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`,
    UNNEST(items) AS items
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
    AND items.item_revenue > 0
  GROUP BY items.item_name
),
ranked AS (
  SELECT
    item_name,
    total_revenue,
    ROW_NUMBER() OVER (ORDER BY total_revenue DESC) AS rank,
    COUNT(*) OVER () AS total_items,
    SUM(total_revenue) OVER () AS grand_total
  FROM item_revenue
),
classified AS (
  SELECT
    *,
    ROUND(SUM(total_revenue) OVER (ORDER BY rank) / grand_total * 100, 2) AS cum_pct,
    CASE
      WHEN ROUND(SUM(total_revenue) OVER (ORDER BY rank) / grand_total * 100, 2) <= 80 THEN 'A'
      WHEN ROUND(SUM(total_revenue) OVER (ORDER BY rank) / grand_total * 100, 2) <= 95 THEN 'B'
      ELSE 'C'
    END AS abc_rank
  FROM ranked
)
SELECT
  abc_rank,
  COUNT(*) AS item_count,
  ROUND(COUNT(*) / MAX(total_items) * 100, 1) AS item_pct,
  SUM(total_revenue) AS total_revenue,
  ROUND(SUM(total_revenue) / MAX(grand_total) * 100, 1) AS revenue_pct
FROM classified
GROUP BY abc_rank
ORDER BY abc_rank
```

### 180. BigQueryでEC顧客をRFM分析してセグメント別メルマガ戦略を立てた（RFMスコアを算出するSQL）

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

### 181. BigQueryでGA4データからEC顧客の年齢・性別推定精度を検証した（Step 2: デモグラフィック別のセグメント分析）

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

### 182. BigQueryでGA4データからEC顧客の年齢・性別推定精度を検証した（Step 3: デモグラフィック別の購買行動比較）

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

### 183. BigQueryでGA4データからEC顧客の年齢・性別推定精度を検証した（Step 4: 年齢層別の購入単価・頻度分析）

**用途**: Step 4: 年齢層別の購入単価・頻度分析

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH user_demo AS (
  SELECT
    user_pseudo_id,
    MAX((SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'age')) AS age_bracket
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
  ud.age_bracket,
  COUNT(DISTINCT up.user_pseudo_id) AS purchasers,
  ROUND(AVG(up.total_revenue), 0) AS avg_ltv,
  ROUND(AVG(up.purchase_count), 2) AS avg_frequency,
  ROUND(AVG(up.total_revenue / up.purchase_count), 0) AS avg_order_value
FROM user_purchases up
INNER JOIN user_demo ud
  ON up.user_pseudo_id = ud.user_pseudo_id
WHERE ud.age_bracket IS NOT NULL
GROUP BY ud.age_bracket
ORDER BY avg_ltv DESC
```

### 184. ユーザーの閲覧から購入までの日数分布をBigQueryで可視化する（初回訪問日と初回購入日を取得するSQL）

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

### 185. ユーザーの閲覧から購入までの日数分布をBigQueryで可視化する（日数分布をヒストグラム用に集計する）

**用途**: 日数分布をヒストグラム用に集計する

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
  CASE
    WHEN days_to_purchase = 0 THEN '当日'
    WHEN days_to_purchase = 1 THEN '1日後'
    WHEN days_to_purchase BETWEEN 2 AND 3 THEN '2-3日後'
    WHEN days_to_purchase BETWEEN 4 AND 7 THEN '4-7日後'
    WHEN days_to_purchase BETWEEN 8 AND 14 THEN '8-14日後'
    WHEN days_to_purchase BETWEEN 15 AND 30 THEN '15-30日後'
    ELSE '31日以上'
  END AS purchase_timing,
  COUNT(*) AS users,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER() * 100, 1) AS pct
FROM days_calc
GROUP BY
  CASE
    WHEN days_to_purchase = 0 THEN 0
    WHEN days_to_purchase = 1 THEN 1
    WHEN days_to_purchase BETWEEN 2 AND 3 THEN 2
    WHEN days_to_purchase BETWEEN 4 AND 7 THEN 3
    WHEN days_to_purchase BETWEEN 8 AND 14 THEN 4
    WHEN days_to_purchase BETWEEN 15 AND 30 THEN 5
    ELSE 6
  END,
  purchase_timing
ORDER BY
  CASE purchase_timing
    WHEN '当日' THEN 0
    WHEN '1日後' THEN 1
    WHEN '2-3日後' THEN 2
    WHEN '4-7日後' THEN 3
    WHEN '8-14日後' THEN 4
    WHEN '15-30日後' THEN 5
    ELSE 6
  END
```

### 186. BigQueryで1回しか買わない顧客と2回以上買う顧客の行動差を分析した（初回セッションの行動指標を比較する）

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

### 187. GA4×BigQueryでEC新規顧客獲得コスト（CAC）を媒体別に正確計算する（チャネル別の新規購入者数を算出するSQL）

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

### 188. GA4×BigQueryでEC新規顧客獲得コスト（CAC）を媒体別に正確計算する（方法1: 手動でCTEに記述する）

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

### 189. GA4×BigQueryでEC新規顧客獲得コスト（CAC）を媒体別に正確計算する（CACの評価基準）

**用途**: CACの評価基準

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH customer_ltv AS (
  SELECT
    user_pseudo_id,
    COUNT(*) AS purchase_count,
    SUM(ecommerce.purchase_revenue) AS total_revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
)

SELECT
  ROUND(AVG(total_revenue), 0) AS avg_ltv,
  ROUND(PERCENTILE_CONT(total_revenue, 0.5) OVER(), 0) AS median_ltv,
  ROUND(AVG(purchase_count), 1) AS avg_purchase_count
FROM customer_ltv
LIMIT 1
```

### 190. GA4×BigQueryでカート放棄率を正確に計測・改善する方法（デバイス別のカート放棄率）

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

### 191. GA4×BigQueryでカート放棄率を正確に計測・改善する方法（流入元別のカート放棄率）

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

### 192. GA4×BigQueryでカート放棄率を正確に計測・改善する方法（商品別のカゴ落ち分析）

**用途**: 商品別のカゴ落ち分析

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH cart_items AS (
  SELECT
    user_pseudo_id,
    item.item_id,
    item.item_name
  FROM `${PROJECT}.${DATASET}.events_*`,
    UNNEST(items) AS item
  WHERE event_name = 'add_to_cart'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
),
purchased_items AS (
  SELECT
    user_pseudo_id,
    item.item_id
  FROM `${PROJECT}.${DATASET}.events_*`,
    UNNEST(items) AS item
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
)
SELECT
  c.item_id,
  c.item_name,
  COUNT(DISTINCT c.user_pseudo_id) AS cart_users,
  COUNT(DISTINCT p.user_pseudo_id) AS purchase_users,
  COUNT(DISTINCT c.user_pseudo_id) - COUNT(DISTINCT p.user_pseudo_id) AS abandoned_users,
  ROUND(
    (COUNT(DISTINCT c.user_pseudo_id) - COUNT(DISTINCT p.user_pseudo_id))
    / COUNT(DISTINCT c.user_pseudo_id) * 100, 1
  ) AS abandonment_rate
FROM cart_items c
LEFT JOIN purchased_items p
  ON c.user_pseudo_id = p.user_pseudo_id
  AND c.item_id = p.item_id
GROUP BY c.item_id, c.item_name
HAVING COUNT(DISTINCT c.user_pseudo_id) >= 5
ORDER BY abandoned_users DESC
LIMIT 20;
```

### 193. GA4×BigQueryでカート放棄率を正確に計測・改善する方法（改善の効果を時系列で追跡する）

**用途**: 改善の効果を時系列で追跡する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH weekly_cart AS (
  SELECT
    DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), WEEK) AS week_start,
    user_pseudo_id
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'add_to_cart'
    AND _TABLE_SUFFIX BETWEEN '20260101' AND '20260331'
),
weekly_purchase AS (
  SELECT
    DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), WEEK) AS week_start,
    user_pseudo_id
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20260101' AND '20260331'
)
SELECT
  c.week_start,
  COUNT(DISTINCT c.user_pseudo_id) AS cart_users,
  COUNT(DISTINCT p.user_pseudo_id) AS purchase_users,
  ROUND(
    (COUNT(DISTINCT c.user_pseudo_id) - COUNT(DISTINCT p.user_pseudo_id))
    / COUNT(DISTINCT c.user_pseudo_id) * 100, 1
  ) AS cart_abandonment_rate
FROM weekly_cart c
LEFT JOIN weekly_purchase p
  ON c.week_start = p.week_start
  AND c.user_pseudo_id = p.user_pseudo_id
GROUP BY c.week_start
ORDER BY c.week_start;
```

### 194. GA4×BigQueryでメルマガのROIを正確に測定する（セッションをまたいだアトリビューション）

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

### 195. GA4×BigQueryでメルマガのROIを正確に測定する（ROIを算出する）

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

### 196. GA4×BigQueryでGoogle広告のキーワード別CVRを正確に測定する（キーワード別CVRを算出するSQL）

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

### 197. GA4×BigQueryでモバイルとPCの購買行動の違いを分析した（モバイルの離脱ポイントを深掘りする）

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

### 198. GA4×BigQueryでポイント還元施策の効果をコホート分析で検証した（Step 2: コホート別の月次購入回数）

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

### 199. GA4×BigQueryでポイント還元施策の効果をコホート分析で検証した（Step 3: コホート別LTVの比較）

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

### 200. EC商品ページの離脱率をGA4×BigQueryで分析して改善につなげた事例（基本SQL：商品ページ別の離脱率を算出する）

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

### 201. ECサイトのサイト内検索キーワードをGA4×BigQueryで分析して品揃えを改善した（検索キーワードごとの購入転換率を算出する）

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

### 202. ECサイトのサイト内検索キーワードをGA4×BigQueryで分析して品揃えを改善した（検索後の行動を詳細に追う）

**用途**: 検索後の行動を詳細に追う

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH search_events AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'search_term') AS search_term,
    event_timestamp AS search_timestamp
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'view_search_results'
),

post_search_actions AS (
  SELECT
    e.user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(e.event_params) WHERE key = 'ga_session_id') AS session_id,
    e.event_name,
    e.event_timestamp
  FROM `${PROJECT}.${DATASET}.events_*` e
  WHERE e._TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND e.event_name IN ('view_item', 'add_to_cart', 'begin_checkout', 'purchase')
)

SELECT
  se.search_term,
  COUNT(DISTINCT se.user_pseudo_id) AS searchers,
  -- 検索後に商品詳細を見た割合
  ROUND(COUNT(DISTINCT IF(psa.event_name = 'view_item', se.user_pseudo_id, NULL))
    / COUNT(DISTINCT se.user_pseudo_id) * 100, 1) AS view_item_rate,
  -- 検索後にカート追加した割合
  ROUND(COUNT(DISTINCT IF(psa.event_name = 'add_to_cart', se.user_pseudo_id, NULL))
    / COUNT(DISTINCT se.user_pseudo_id) * 100, 1) AS add_to_cart_rate,
  -- 検索後に購入した割合
  ROUND(COUNT(DISTINCT IF(psa.event_name = 'purchase', se.user_pseudo_id, NULL))
    / COUNT(DISTINCT se.user_pseudo_id) * 100, 1) AS purchase_rate
FROM search_events se
LEFT JOIN post_search_actions psa
  ON se.user_pseudo_id = psa.user_pseudo_id
  AND se.session_id = psa.session_id
  AND psa.event_timestamp > se.search_timestamp
WHERE se.search_term IS NOT NULL
GROUP BY se.search_term
HAVING searchers >= 10
ORDER BY searchers DESC
LIMIT 30
```

### 203. GA4×BigQueryでSNS流入の質を測定してInstagramとTikTokを比較した（SNS流入のアシストコンバージョンを確認する）

**用途**: SNS流入のアシストコンバージョンを確認する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH sns_users AS (
  -- SNS経由で訪問したことがあるユーザー
  SELECT DISTINCT user_pseudo_id, collected_traffic_source.manual_source AS first_sns
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND collected_traffic_source.manual_medium = 'social'
    AND event_name = 'session_start'
),

purchasers AS (
  -- 購入したユーザー
  SELECT DISTINCT user_pseudo_id
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
)

SELECT
  s.first_sns,
  COUNT(DISTINCT s.user_pseudo_id) AS sns_visitors,
  COUNT(DISTINCT p.user_pseudo_id) AS eventual_purchasers,
  ROUND(COUNT(DISTINCT p.user_pseudo_id) / COUNT(DISTINCT s.user_pseudo_id) * 100, 2) AS eventual_cvr
FROM sns_users s
LEFT JOIN purchasers p ON s.user_pseudo_id = p.user_pseudo_id
GROUP BY s.first_sns
ORDER BY sns_visitors DESC
```

### 204. GA4×BigQueryでECサイトの速度改善がCVRに与えた影響を測定した（Step 2: LCPとCVRの相関分析）

**用途**: Step 2: LCPとCVRの相関分析

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH user_lcp AS (
  SELECT
    user_pseudo_id,
    APPROX_QUANTILES(
      (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'metric_value'),
      100
    )[OFFSET(50)] AS median_lcp
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'web_vitals'
    AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'metric_name') = 'LCP'
  GROUP BY user_pseudo_id
),
user_conversions AS (
  SELECT
    user_pseudo_id,
    COUNTIF(event_name = 'purchase') AS purchases
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
  GROUP BY user_pseudo_id
),
combined AS (
  SELECT
    l.user_pseudo_id,
    l.median_lcp,
    CASE
      WHEN l.median_lcp <= 2500 THEN '良好（2.5秒以下）'
      WHEN l.median_lcp <= 4000 THEN '改善が必要（2.5-4秒）'
      ELSE '不良（4秒超）'
    END AS lcp_category,
    IFNULL(c.purchases, 0) AS purchases,
    IF(IFNULL(c.purchases, 0) > 0, 1, 0) AS converted
  FROM user_lcp l
  LEFT JOIN user_conversions c
    ON l.user_pseudo_id = c.user_pseudo_id
)
SELECT
  lcp_category,
  COUNT(*) AS users,
  SUM(converted) AS converters,
  ROUND(SUM(converted) / COUNT(*) * 100, 2) AS cvr_pct
FROM combined
GROUP BY lcp_category
ORDER BY cvr_pct DESC
```

### 205. GA4×BigQueryでECサイトの速度改善がCVRに与えた影響を測定した（Step 3: 速度改善前後の比較）

**用途**: Step 3: 速度改善前後の比較

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH period_metrics AS (
  SELECT
    CASE
      WHEN DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo')
        BETWEEN '2025-06-01' AND '2025-06-30' THEN '改善前（6月）'
      WHEN DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo')
        BETWEEN '2025-08-01' AND '2025-08-31' THEN '改善後（8月）'
    END AS period,
    event_name,
    user_pseudo_id,
    (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'metric_value') AS lcp_value,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'metric_name') AS metric_name
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250831'
    AND (
      event_name = 'web_vitals'
      OR event_name = 'purchase'
      OR event_name = 'session_start'
    )
),
lcp_summary AS (
  SELECT
    period,
    ROUND(APPROX_QUANTILES(lcp_value, 100)[OFFSET(75)], 0) AS lcp_p75
  FROM period_metrics
  WHERE metric_name = 'LCP'
    AND period IS NOT NULL
  GROUP BY period
),
cvr_summary AS (
  SELECT
    period,
    COUNT(DISTINCT CASE WHEN event_name = 'session_start' THEN user_pseudo_id END) AS sessions,
    COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN user_pseudo_id END) AS purchasers,
    ROUND(
      COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN user_pseudo_id END)
      / COUNT(DISTINCT CASE WHEN event_name = 'session_start' THEN user_pseudo_id END) * 100,
      2
    ) AS cvr_pct
  FROM period_metrics
  WHERE period IS NOT NULL
  GROUP BY period
)
SELECT
  c.period,
  l.lcp_p75,
  c.sessions,
  c.purchasers,
  c.cvr_pct
FROM cvr_summary c
INNER JOIN lcp_summary l
  ON c.period = l.period
ORDER BY c.period
```

### 206. GA4×BigQueryでECサイトの速度改善がCVRに与えた影響を測定した（Step 4: デバイス別の速度×CVR分析）

**用途**: Step 4: デバイス別の速度×CVR分析

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH device_performance AS (
  SELECT
    device.category AS device_category,
    CASE
      WHEN (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'metric_value') <= 2500 THEN '良好'
      WHEN (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'metric_value') <= 4000 THEN '要改善'
      ELSE '不良'
    END AS lcp_status,
    user_pseudo_id
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'web_vitals'
    AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'metric_name') = 'LCP'
),
device_conversions AS (
  SELECT
    user_pseudo_id,
    1 AS converted
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
)
SELECT
  dp.device_category,
  dp.lcp_status,
  COUNT(DISTINCT dp.user_pseudo_id) AS users,
  COUNTIF(dc.converted = 1) AS converters,
  ROUND(COUNTIF(dc.converted = 1) / COUNT(DISTINCT dp.user_pseudo_id) * 100, 2) AS cvr_pct
FROM device_performance dp
LEFT JOIN device_conversions dc
  ON dp.user_pseudo_id = dc.user_pseudo_id
GROUP BY dp.device_category, dp.lcp_status
ORDER BY dp.device_category, dp.lcp_status
```

### 207. GA4×BigQueryでEC定期購入の継続率を分析する（Step 2: 月別継続率の算出）

**用途**: Step 2: 月別継続率の算出

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
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
),
monthly_purchases AS (
  SELECT
    user_pseudo_id,
    FORMAT_DATE('%Y-%m',
      DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo')
    ) AS purchase_month
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id, purchase_month
),
cohort_activity AS (
  SELECT
    fp.cohort_month,
    DATE_DIFF(
      PARSE_DATE('%Y-%m', mp.purchase_month),
      PARSE_DATE('%Y-%m', fp.cohort_month),
      MONTH
    ) AS months_since_first,
    COUNT(DISTINCT fp.user_pseudo_id) AS active_users
  FROM first_purchase fp
  INNER JOIN monthly_purchases mp
    ON fp.user_pseudo_id = mp.user_pseudo_id
  GROUP BY fp.cohort_month, months_since_first
),
cohort_size AS (
  SELECT
    cohort_month,
    COUNT(*) AS total_users
  FROM first_purchase
  GROUP BY cohort_month
)
SELECT
  ca.cohort_month,
  ca.months_since_first,
  cs.total_users,
  ca.active_users,
  ROUND(ca.active_users / cs.total_users * 100, 1) AS retention_pct
FROM cohort_activity ca
INNER JOIN cohort_size cs
  ON ca.cohort_month = cs.cohort_month
WHERE ca.months_since_first BETWEEN 0 AND 12
ORDER BY ca.cohort_month, ca.months_since_first
```

### 208. チャネル別ROASをBigQueryで集計してLooker Studioに可視化する（Step 3：ROASをSQLで算出する）

**用途**: Step 3：ROASをSQLで算出する

**必要なテーブル**: `${DATASET}.ad_spend`, `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH channel_revenue AS (
  SELECT
    FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m%d', event_date)) AS month,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    COUNT(DISTINCT user_pseudo_id) AS users,
    COUNTIF(event_name = 'purchase') AS purchases,
    SUM(
      IF(event_name = 'purchase', ecommerce.purchase_revenue, 0)
    ) AS revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND collected_traffic_source.manual_medium IS NOT NULL
  GROUP BY
    month, medium, source
),

channel_spend AS (
  SELECT
    month,
    medium,
    source,
    spend
  FROM
    `${PROJECT}.${DATASET}.ad_spend`
)

SELECT
  r.month,
  r.medium,
  r.source,
  r.users,
  r.purchases,
  r.revenue,
  s.spend,
  SAFE_DIVIDE(r.revenue, s.spend) * 100 AS roas_pct,
  SAFE_DIVIDE(s.spend, r.purchases) AS cpa
FROM
  channel_revenue r
LEFT JOIN
  channel_spend s
  ON r.month = s.month
  AND r.medium = s.medium
  AND r.source = s.source
ORDER BY
  r.month, roas_pct DESC
```

### 209. チャネル別ROASをBigQueryで集計してLooker Studioに可視化する（Step 4：マートテーブルに保存する）

**用途**: Step 4：マートテーブルに保存する

**必要なテーブル**: `${DATASET}.ad_spend`, `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
CREATE OR REPLACE VIEW `project.dataset_mart.mart_channel_roas` AS
WITH channel_revenue AS (
  SELECT
    FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m%d', event_date)) AS month,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    COUNT(DISTINCT user_pseudo_id) AS users,
    COUNTIF(event_name = 'purchase') AS purchases,
    SUM(
      IF(event_name = 'purchase', ecommerce.purchase_revenue, 0)
    ) AS revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND collected_traffic_source.manual_medium IS NOT NULL
  GROUP BY
    month, medium, source
),
channel_spend AS (
  SELECT month, medium, source, spend
  FROM `${PROJECT}.${DATASET}.ad_spend`
)
SELECT
  r.month,
  r.medium,
  r.source,
  r.users,
  r.purchases,
  r.revenue,
  COALESCE(s.spend, 0) AS spend,
  SAFE_DIVIDE(r.revenue, s.spend) * 100 AS roas_pct,
  SAFE_DIVIDE(s.spend, r.purchases) AS cpa
FROM
  channel_revenue r
LEFT JOIN
  channel_spend s
  ON r.month = s.month
  AND r.medium = s.medium
  AND r.source = s.source;
```

### 210. EC売上が下がったとき最初に確認すべきBigQueryクエリ5選（クエリ3：デバイス別CVR比較（モバイル vs デスクトップ））

**用途**: クエリ3：デバイス別CVR比較（モバイル vs デスクトップ）

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH sessions AS (
  SELECT
    CASE
      WHEN _TABLE_SUFFIX BETWEEN '20260301' AND '20260328' THEN 'current'
      WHEN _TABLE_SUFFIX BETWEEN '20260201' AND '20260228' THEN 'previous'
    END AS period,
    device.category AS device,
    CONCAT(user_pseudo_id, CAST(
      (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING
    )) AS session_id,
    MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) AS has_purchase
  FROM
    `analytics_XXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20260201' AND '20260328'
  GROUP BY
    period, device, session_id
)
SELECT
  period,
  device,
  COUNT(*) AS sessions,
  SUM(has_purchase) AS converting_sessions,
  ROUND(SAFE_DIVIDE(SUM(has_purchase), COUNT(*)) * 100, 2) AS cvr_percent
FROM
  sessions
WHERE
  period IS NOT NULL
GROUP BY
  period, device
ORDER BY
  period, device
```

### 211. EC売上が下がったとき最初に確認すべきBigQueryクエリ5選（クエリ5：ファネルステップ比較（どの段階で離脱が増えたか））

**用途**: クエリ5：ファネルステップ比較（どの段階で離脱が増えたか）

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH funnel AS (
  SELECT
    CASE
      WHEN _TABLE_SUFFIX BETWEEN '20260301' AND '20260328' THEN 'current'
      WHEN _TABLE_SUFFIX BETWEEN '20260201' AND '20260228' THEN 'previous'
    END AS period,
    CONCAT(user_pseudo_id, CAST(
      (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING
    )) AS session_id,
    event_name
  FROM
    `analytics_XXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20260201' AND '20260328'
    AND event_name IN ('view_item', 'add_to_cart', 'begin_checkout', 'purchase')
)
SELECT
  period,
  COUNT(DISTINCT CASE WHEN event_name = 'view_item' THEN session_id END) AS view_item_sessions,
  COUNT(DISTINCT CASE WHEN event_name = 'add_to_cart' THEN session_id END) AS add_to_cart_sessions,
  COUNT(DISTINCT CASE WHEN event_name = 'begin_checkout' THEN session_id END) AS begin_checkout_sessions,
  COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN session_id END) AS purchase_sessions,
  ROUND(SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN event_name = 'add_to_cart' THEN session_id END),
    COUNT(DISTINCT CASE WHEN event_name = 'view_item' THEN session_id END)
  ) * 100, 2) AS view_to_cart_rate,
  ROUND(SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN session_id END),
    COUNT(DISTINCT CASE WHEN event_name = 'add_to_cart' THEN session_id END)
  ) * 100, 2) AS cart_to_purchase_rate
FROM
  funnel
WHERE
  period IS NOT NULL
GROUP BY
  period
ORDER BY
  period
```

### 212. GA4×BigQueryで初回購入→リピートまでのファネルを可視化する（Step 2：2回目・3回目の購入と購入間隔を算出する）

**用途**: Step 2：2回目・3回目の購入と購入間隔を算出する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください

```sql
WITH purchases AS (
  SELECT
    user_pseudo_id,
    PARSE_DATE('%Y%m%d', event_date) AS purchase_date,
    ecommerce.transaction_id
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    event_name = 'purchase'
    AND ecommerce.transaction_id IS NOT NULL
),

numbered AS (
  SELECT
    user_pseudo_id,
    purchase_date,
    ROW_NUMBER() OVER (
      PARTITION BY user_pseudo_id
      ORDER BY purchase_date, transaction_id
    ) AS purchase_number
  FROM purchases
),

with_intervals AS (
  SELECT
    user_pseudo_id,
    purchase_number,
    purchase_date,
    LAG(purchase_date) OVER (
      PARTITION BY user_pseudo_id
      ORDER BY purchase_number
    ) AS prev_purchase_date,
    DATE_DIFF(
      purchase_date,
      LAG(purchase_date) OVER (
        PARTITION BY user_pseudo_id
        ORDER BY purchase_number
      ),
      DAY
    ) AS days_since_prev_purchase
  FROM numbered
)

SELECT
  purchase_number,
  COUNT(*) AS user_count,
  ROUND(AVG(days_since_prev_purchase), 1) AS avg_days_between,
  APPROX_QUANTILES(days_since_prev_purchase, 2)[OFFSET(1)] AS median_days_between
FROM with_intervals
GROUP BY purchase_number
ORDER BY purchase_number;
```

### 213. GA4×BigQueryで初回購入→リピートまでのファネルを可視化する（Step 3：月次コホート別リピート率を算出する）

**用途**: Step 3：月次コホート別リピート率を算出する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください

```sql
WITH purchases AS (
  SELECT
    user_pseudo_id,
    PARSE_DATE('%Y%m%d', event_date) AS purchase_date,
    ecommerce.transaction_id
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    event_name = 'purchase'
    AND ecommerce.transaction_id IS NOT NULL
),

first_purchase AS (
  SELECT
    user_pseudo_id,
    MIN(purchase_date) AS first_purchase_date
  FROM purchases
  GROUP BY user_pseudo_id
),

cohort_repeat AS (
  SELECT
    fp.user_pseudo_id,
    FORMAT_DATE('%Y-%m', fp.first_purchase_date) AS cohort_month,
    fp.first_purchase_date,
    MIN(
      CASE WHEN p.purchase_date > fp.first_purchase_date
      THEN p.purchase_date END
    ) AS second_purchase_date
  FROM first_purchase fp
  LEFT JOIN purchases p
    ON fp.user_pseudo_id = p.user_pseudo_id
  GROUP BY fp.user_pseudo_id, fp.first_purchase_date
)

SELECT
  cohort_month,
  COUNT(*) AS first_time_buyers,
  COUNTIF(second_purchase_date IS NOT NULL) AS repeat_buyers,
  COUNTIF(DATE_DIFF(second_purchase_date, first_purchase_date, DAY) <= 30) AS repeat_within_30d,
  COUNTIF(DATE_DIFF(second_purchase_date, first_purchase_date, DAY) <= 60) AS repeat_within_60d,
  COUNTIF(DATE_DIFF(second_purchase_date, first_purchase_date, DAY) <= 90) AS repeat_within_90d,
  ROUND(COUNTIF(second_purchase_date IS NOT NULL) / COUNT(*) * 100, 1) AS repeat_rate_pct,
  ROUND(COUNTIF(DATE_DIFF(second_purchase_date, first_purchase_date, DAY) <= 30) / COUNT(*) * 100, 1) AS repeat_30d_pct,
  ROUND(COUNTIF(DATE_DIFF(second_purchase_date, first_purchase_date, DAY) <= 60) / COUNT(*) * 100, 1) AS repeat_60d_pct,
  ROUND(COUNTIF(DATE_DIFF(second_purchase_date, first_purchase_date, DAY) <= 90) / COUNT(*) * 100, 1) AS repeat_90d_pct
FROM cohort_repeat
GROUP BY cohort_month
ORDER BY cohort_month;
```

### 214. GA4×BigQueryで初回購入→リピートまでのファネルを可視化する（Step 4：ファネル形式で可視化用データを作成する）

**用途**: Step 4：ファネル形式で可視化用データを作成する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください

```sql
WITH purchases AS (
  SELECT
    user_pseudo_id,
    PARSE_DATE('%Y%m%d', event_date) AS purchase_date,
    ecommerce.transaction_id
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    event_name = 'purchase'
    AND ecommerce.transaction_id IS NOT NULL
),

numbered AS (
  SELECT
    user_pseudo_id,
    ROW_NUMBER() OVER (
      PARTITION BY user_pseudo_id
      ORDER BY purchase_date, transaction_id
    ) AS purchase_number
  FROM purchases
),

funnel AS (
  SELECT
    purchase_number,
    COUNT(DISTINCT user_pseudo_id) AS users
  FROM numbered
  WHERE purchase_number <= 5
  GROUP BY purchase_number
)

SELECT
  purchase_number,
  users,
  FIRST_VALUE(users) OVER (ORDER BY purchase_number) AS first_purchase_users,
  ROUND(users / FIRST_VALUE(users) OVER (ORDER BY purchase_number) * 100, 1) AS retention_pct,
  ROUND(users / LAG(users) OVER (ORDER BY purchase_number) * 100, 1) AS step_conversion_pct
FROM funnel
ORDER BY purchase_number;
```

### 215. Meta広告×GA4×BigQueryでクリエイティブ別ROASを深掘りする（クリエイティブ別ROASを算出するSQL）

**用途**: クリエイティブ別ROASを算出するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH meta_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'campaign') AS campaign,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'content') AS creative_name,
    event_name,
    ecommerce.purchase_revenue AS revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
    AND collected_traffic_source.manual_source = 'facebook'
    AND collected_traffic_source.manual_medium = 'paid_social'
),
session_summary AS (
  SELECT
    creative_name,
    campaign,
    COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))) AS sessions,
    COUNTIF(event_name = 'purchase') AS purchases,
    SUM(CASE WHEN event_name = 'purchase' THEN revenue ELSE 0 END) AS total_revenue
  FROM meta_sessions
  WHERE creative_name IS NOT NULL
  GROUP BY creative_name, campaign
)
SELECT
  creative_name,
  campaign,
  sessions,
  purchases,
  total_revenue,
  ROUND(SAFE_DIVIDE(purchases, sessions) * 100, 2) AS cvr,
  ROUND(SAFE_DIVIDE(total_revenue, sessions), 0) AS revenue_per_session
FROM session_summary
ORDER BY total_revenue DESC;
```

### 216. BigQueryでGA4データからEC顧客の年齢・性別推定精度を検証した（Step 1: デモグラフィックデータのカバレッジを確認する）

**用途**: Step 1: デモグラフィックデータのカバレッジを確認する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH user_demographics AS (
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
  COUNT(*) AS total_users,
  COUNTIF(age_bracket IS NOT NULL) AS users_with_age,
  COUNTIF(gender IS NOT NULL) AS users_with_gender,
  ROUND(COUNTIF(age_bracket IS NOT NULL) / COUNT(*) * 100, 1) AS age_coverage_pct,
  ROUND(COUNTIF(gender IS NOT NULL) / COUNT(*) * 100, 1) AS gender_coverage_pct
FROM user_demographics
```

### 217. BigQueryでGA4の流入経路×購入金額のヒートマップを作成した（チャネル×デバイスのクロス集計SQL）

**用途**: チャネル×デバイスのクロス集計SQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH session_data AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    device.category AS device_category,
    event_name,
    ecommerce.purchase_revenue AS revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
),

session_summary AS (
  SELECT
    user_pseudo_id,
    session_id,
    -- チャネルグルーピング
    CASE
      WHEN medium = 'organic' THEN 'Organic Search'
      WHEN medium = 'cpc' THEN 'Paid Search'
      WHEN medium = 'social' THEN 'Social'
      WHEN medium = 'email' THEN 'Email'
      WHEN medium = 'referral' THEN 'Referral'
      WHEN medium = '(none)' OR medium IS NULL THEN 'Direct'
      ELSE 'Other'
    END AS channel,
    device_category,
    MAX(IF(event_name = 'purchase', 1, 0)) AS has_purchase,
    SUM(IF(event_name = 'purchase', revenue, 0)) AS session_revenue
  FROM session_data
  GROUP BY user_pseudo_id, session_id, channel, device_category
)

SELECT
  channel,
  device_category,
  COUNT(*) AS sessions,
  SUM(has_purchase) AS purchases,
  ROUND(SUM(session_revenue), 0) AS total_revenue,
  ROUND(SUM(session_revenue) / COUNT(*), 0) AS revenue_per_session,
  ROUND(SUM(has_purchase) / COUNT(*) * 100, 2) AS cvr
FROM session_summary
GROUP BY channel, device_category
ORDER BY total_revenue DESC
```

### 218. BigQueryでGA4の流入経路×購入金額のヒートマップを作成した（チャネル×地域のクロス集計SQL）

**用途**: チャネル×地域のクロス集計SQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH session_data AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    CASE
      WHEN collected_traffic_source.manual_medium = 'organic' THEN 'Organic Search'
      WHEN collected_traffic_source.manual_medium = 'cpc' THEN 'Paid Search'
      WHEN collected_traffic_source.manual_medium = 'social' THEN 'Social'
      WHEN collected_traffic_source.manual_medium = 'email' THEN 'Email'
      WHEN collected_traffic_source.manual_medium = 'referral' THEN 'Referral'
      WHEN collected_traffic_source.manual_medium = '(none)'
        OR collected_traffic_source.manual_medium IS NULL THEN 'Direct'
      ELSE 'Other'
    END AS channel,
    geo.region AS region,
    event_name,
    ecommerce.purchase_revenue AS revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND geo.country = 'Japan'
),

session_summary AS (
  SELECT
    user_pseudo_id,
    session_id,
    channel,
    region,
    MAX(IF(event_name = 'purchase', 1, 0)) AS has_purchase,
    SUM(IF(event_name = 'purchase', revenue, 0)) AS session_revenue
  FROM session_data
  GROUP BY user_pseudo_id, session_id, channel, region
)

SELECT
  channel,
  region,
  COUNT(*) AS sessions,
  ROUND(SUM(session_revenue), 0) AS total_revenue,
  ROUND(SUM(session_revenue) / NULLIF(COUNT(*), 0), 0) AS revenue_per_session
FROM session_summary
GROUP BY channel, region
HAVING sessions >= 10
ORDER BY total_revenue DESC
```

### 219. BigQueryでGA4の流入経路×購入金額のヒートマップを作成した（時間帯×チャネルのクロス集計）

**用途**: 時間帯×チャネルのクロス集計

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH session_data AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    CASE
      WHEN collected_traffic_source.manual_medium = 'organic' THEN 'Organic Search'
      WHEN collected_traffic_source.manual_medium = 'cpc' THEN 'Paid Search'
      WHEN collected_traffic_source.manual_medium = 'social' THEN 'Social'
      WHEN collected_traffic_source.manual_medium = 'email' THEN 'Email'
      ELSE 'Other'
    END AS channel,
    -- 日本時間に変換
    EXTRACT(HOUR FROM TIMESTAMP_ADD(TIMESTAMP_MICROS(event_timestamp), INTERVAL 9 HOUR)) AS hour_jst,
    EXTRACT(DAYOFWEEK FROM TIMESTAMP_ADD(TIMESTAMP_MICROS(event_timestamp), INTERVAL 9 HOUR)) AS dow,
    event_name,
    ecommerce.purchase_revenue AS revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
),

session_summary AS (
  SELECT
    user_pseudo_id,
    session_id,
    channel,
    -- 時間帯を4分割
    CASE
      WHEN hour_jst BETWEEN 6 AND 11 THEN '朝(6-11時)'
      WHEN hour_jst BETWEEN 12 AND 17 THEN '昼(12-17時)'
      WHEN hour_jst BETWEEN 18 AND 23 THEN '夜(18-23時)'
      ELSE '深夜(0-5時)'
    END AS time_slot,
    MAX(IF(event_name = 'purchase', 1, 0)) AS has_purchase,
    SUM(IF(event_name = 'purchase', revenue, 0)) AS session_revenue
  FROM session_data
  GROUP BY user_pseudo_id, session_id, channel, time_slot
)

SELECT
  channel,
  time_slot,
  COUNT(*) AS sessions,
  SUM(has_purchase) AS purchases,
  ROUND(SUM(session_revenue), 0) AS total_revenue,
  ROUND(SUM(has_purchase) / COUNT(*) * 100, 2) AS cvr
FROM session_summary
GROUP BY channel, time_slot
ORDER BY channel, time_slot
```

### 220. BigQueryで1回しか買わない顧客と2回以上買う顧客の行動差を分析した（ユーザーを購入回数で分類するSQL）

**用途**: ユーザーを購入回数で分類するSQL

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
)

SELECT
  CASE
    WHEN purchase_count = 1 THEN 'one_time'
    ELSE 'repeat'
  END AS buyer_type,
  COUNT(*) AS users,
  ROUND(AVG(purchase_count), 1) AS avg_purchases
FROM purchase_counts
GROUP BY buyer_type
```

### 221. EC売上が下がったとき最初に確認すべきBigQueryクエリ5選（クエリ2：チャネル別売上比較（どのチャネルが落ちたか））

**用途**: クエリ2：チャネル別売上比較（どのチャネルが落ちたか）

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH period_data AS (
  SELECT
    CASE
      WHEN _TABLE_SUFFIX BETWEEN '20260301' AND '20260328' THEN 'current'
      WHEN _TABLE_SUFFIX BETWEEN '20260201' AND '20260228' THEN 'previous'
    END AS period,
    collected_traffic_source.manual_medium AS medium,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    user_pseudo_id,
    event_name,
    ecommerce.purchase_revenue,
    ecommerce.transaction_id
  FROM
    `analytics_XXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20260201' AND '20260328'
)
SELECT
  period,
  IFNULL(medium, '(none)') AS medium,
  COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING))) AS sessions,
  COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN transaction_id END) AS transactions,
  SUM(CASE WHEN event_name = 'purchase' THEN purchase_revenue END) AS revenue
FROM
  period_data
WHERE
  period IS NOT NULL
GROUP BY
  period, medium
ORDER BY
  period, revenue DESC
```

### 222. EC売上が下がったとき最初に確認すべきBigQueryクエリ5選（クエリ4：主要ランディングページの流入比較（どのページでトラフィックが減ったか））

**用途**: クエリ4：主要ランディングページの流入比較（どのページでトラフィックが減ったか）

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH landing_pages AS (
  SELECT
    CASE
      WHEN _TABLE_SUFFIX BETWEEN '20260301' AND '20260328' THEN 'current'
      WHEN _TABLE_SUFFIX BETWEEN '20260201' AND '20260228' THEN 'previous'
    END AS period,
    CONCAT(user_pseudo_id, CAST(
      (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING
    )) AS session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
    event_name
  FROM
    `analytics_XXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20260201' AND '20260328'
    AND event_name = 'session_start'
)
SELECT
  period,
  REGEXP_EXTRACT(page_location, r'https?://[^/]+(/.*)') AS landing_path,
  COUNT(DISTINCT session_id) AS sessions
FROM
  landing_pages
WHERE
  period IS NOT NULL
GROUP BY
  period, landing_path
HAVING
  sessions >= 10
ORDER BY
  period, sessions DESC
LIMIT 50
```

### 223. GA4×BigQueryでメルマガのROIを正確に測定する（メルマガ流入セッションを特定するSQL）

**用途**: メルマガ流入セッションを特定するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH email_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_campaign AS campaign,
    event_name,
    event_timestamp,
    ecommerce.purchase_revenue AS revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND collected_traffic_source.manual_medium = 'email'
)

SELECT
  campaign,
  COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(session_id AS STRING))) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases,
  ROUND(SUM(IF(event_name = 'purchase', revenue, 0)), 0) AS total_revenue,
  ROUND(
    COUNTIF(event_name = 'purchase')
    / COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(session_id AS STRING))) * 100,
    2
  ) AS cvr
FROM email_sessions
GROUP BY campaign
ORDER BY total_revenue DESC
```

### 224. GA4×BigQueryでモバイルとPCの購買行動の違いを分析した（デバイス別ファネル分析）

**用途**: デバイス別ファネル分析

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH funnel_events AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    device.category AS device_category,
    event_name
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name IN ('view_item', 'add_to_cart', 'begin_checkout', 'purchase')
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
)
SELECT
  device_category,
  COUNT(DISTINCT CASE WHEN event_name = 'view_item'
    THEN CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING)) END) AS view_item,
  COUNT(DISTINCT CASE WHEN event_name = 'add_to_cart'
    THEN CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING)) END) AS add_to_cart,
  COUNT(DISTINCT CASE WHEN event_name = 'begin_checkout'
    THEN CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING)) END) AS begin_checkout,
  COUNT(DISTINCT CASE WHEN event_name = 'purchase'
    THEN CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING)) END) AS purchase
FROM funnel_events
GROUP BY device_category
ORDER BY view_item DESC;
```

### 225. GA4×BigQueryでポイント還元施策の効果をコホート分析で検証した（Step 1: コホートの抽出）

**用途**: Step 1: コホートの抽出

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
)
SELECT
  cohort_month,
  CASE
    WHEN cohort_month = '2025-03' THEN '施策前'
    WHEN cohort_month = '2025-04' THEN '施策後'
  END AS cohort_label,
  COUNT(*) AS new_customers
FROM first_purchase
WHERE cohort_month IN ('2025-03', '2025-04')
GROUP BY cohort_month, cohort_label
ORDER BY cohort_month
```

### 226. EC商品ページの離脱率をGA4×BigQueryで分析して改善につなげた事例（流入元別に商品ページ離脱率を比較する）

**用途**: 流入元別に商品ページ離脱率を比較する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH session_source AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'session_start'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
),
product_exits AS (
  -- 前述のクエリで算出した商品ページ別の離脱フラグを使う
  SELECT
    user_pseudo_id,
    ga_session_id,
    is_exit
  FROM product_page_views
)
SELECT
  IFNULL(ss.source, '(direct)') AS source,
  IFNULL(ss.medium, '(none)') AS medium,
  COUNT(*) AS sessions,
  SUM(pe.is_exit) AS exit_sessions,
  ROUND(SUM(pe.is_exit) / COUNT(*) * 100, 1) AS exit_rate
FROM product_exits pe
JOIN session_source ss
  ON pe.user_pseudo_id = ss.user_pseudo_id
  AND pe.ga_session_id = ss.ga_session_id
GROUP BY source, medium
ORDER BY sessions DESC;
```

### 227. EC商品ページの離脱率をGA4×BigQueryで分析して改善につなげた事例（改善施策の前後比較SQL）

**用途**: 改善施策の前後比較SQL

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH product_exit_data AS (
  -- 前述のproduct_page_viewsと同様のロジック
  -- _TABLE_SUFFIXを広めに取る（施策前後をカバーする期間）
  SELECT
    page_location,
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    is_exit,
    user_pseudo_id,
    ga_session_id
  FROM product_page_views_with_date
)
SELECT
  page_location,
  CASE
    WHEN event_date < '2026-03-15' THEN 'before'
    ELSE 'after'
  END AS period,
  COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))) AS sessions,
  SUM(is_exit) AS exits,
  ROUND(SUM(is_exit) / COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))) * 100, 1) AS exit_rate
FROM product_exit_data
WHERE page_location = '/products/target-product'
GROUP BY page_location, period
ORDER BY period;
```

### 228. GA4×BigQueryでSNS流入の質を測定してInstagramとTikTokを比較した（セッション単位でSNS流入を集計するSQL）

**用途**: セッション単位でSNS流入を集計するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH session_base AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium,
    event_name,
    event_timestamp,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'engagement_time_msec') AS engagement_time_msec
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND collected_traffic_source.manual_medium = 'social'
),

session_metrics AS (
  SELECT
    user_pseudo_id,
    session_id,
    source,
    -- セッション内のエンゲージメント時間合計（秒）
    SUM(engagement_time_msec) / 1000 AS engagement_sec,
    -- セッション内のページビュー数
    COUNTIF(event_name = 'page_view') AS page_views,
    -- 購入の有無
    MAX(IF(event_name = 'purchase', 1, 0)) AS has_purchase,
    -- セッション開始・終了タイムスタンプ
    MIN(event_timestamp) AS session_start,
    MAX(event_timestamp) AS session_end
  FROM session_base
  GROUP BY user_pseudo_id, session_id, source
)

SELECT
  source,
  COUNT(*) AS sessions,
  ROUND(AVG(engagement_sec), 1) AS avg_engagement_sec,
  ROUND(AVG(page_views), 1) AS avg_page_views,
  -- 直帰率（ページビュー1以下のセッション割合）
  ROUND(COUNTIF(page_views <= 1) / COUNT(*) * 100, 1) AS bounce_rate,
  -- CV率
  ROUND(SUM(has_purchase) / COUNT(*) * 100, 2) AS cvr
FROM session_metrics
GROUP BY source
ORDER BY sessions DESC
```

### 229. GA4×BigQueryでECサイトの速度改善がCVRに与えた影響を測定した（Step 1: GA4でページ速度関連のイベントを取得する）

**用途**: Step 1: GA4でページ速度関連のイベントを取得する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH web_vitals AS (
  SELECT
    user_pseudo_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'metric_name') AS metric_name,
    (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'metric_value') AS metric_value,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
    DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo') AS event_date,
    device.category AS device_category
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'web_vitals'
)
SELECT
  metric_name,
  device_category,
  COUNT(*) AS sample_count,
  ROUND(APPROX_QUANTILES(metric_value, 100)[OFFSET(50)], 2) AS p50,
  ROUND(APPROX_QUANTILES(metric_value, 100)[OFFSET(75)], 2) AS p75,
  ROUND(APPROX_QUANTILES(metric_value, 100)[OFFSET(90)], 2) AS p90
FROM web_vitals
WHERE metric_name IN ('LCP', 'INP', 'CLS')
GROUP BY metric_name, device_category
ORDER BY metric_name, device_category
```

### 230. GA4×BigQueryでEC定期購入の継続率を分析する（Step 1: 初回購入月の特定）

**用途**: Step 1: 初回購入月の特定

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH first_purchase AS (
  SELECT
    user_pseudo_id,
    FORMAT_DATE('%Y-%m',
      DATE(TIMESTAMP_MICROS(MIN(event_timestamp)), 'Asia/Tokyo')
    ) AS cohort_month
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
)
SELECT
  cohort_month,
  COUNT(*) AS new_subscribers
FROM first_purchase
GROUP BY cohort_month
ORDER BY cohort_month
```

### 231. Meta広告×GA4×BigQueryでクリエイティブ別ROASを深掘りする（広告費データとの結合）

**用途**: 広告費データとの結合

**必要なテーブル**: `${DATASET}.meta_ads_cost`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
WITH ga4_revenue AS (
  -- 前述のクエリ結果
  SELECT
    creative_name,
    total_revenue,
    sessions,
    purchases
  FROM session_summary
),
meta_cost AS (
  -- Meta広告費用テーブル（API or CSVインポート）
  SELECT
    ad_name AS creative_name,
    SUM(spend) AS total_spend,
    SUM(impressions) AS total_impressions,
    SUM(clicks) AS total_clicks
  FROM `${PROJECT}.${DATASET}.meta_ads_cost`
  WHERE date BETWEEN '2026-03-01' AND '2026-03-31'
  GROUP BY ad_name
)
SELECT
  g.creative_name,
  g.sessions,
  g.purchases,
  g.total_revenue,
  m.total_spend,
  m.total_clicks,
  ROUND(SAFE_DIVIDE(g.total_revenue, m.total_spend), 2) AS roas,
  ROUND(SAFE_DIVIDE(m.total_spend, g.purchases), 0) AS cpa
FROM ga4_revenue g
JOIN meta_cost m
  ON g.creative_name = m.creative_name
ORDER BY roas DESC;
```

### 232. BigQueryでEC商品別の粗利×CVR×流入数をまとめた利益ダッシュボードを作った（原価データとの結合で粗利を算出する） その1

**用途**: 原価データとの結合で粗利を算出する

**必要なテーブル**: `${DATASET}.product_cost`

**コストの注意**: `SELECT *` を含みます。必要な列だけに絞るとコストが下がります

```sql
WITH product_performance AS (
  -- 前述のクエリ結果（item_id, view_sessions, purchase_sessions, cvr, total_revenue）
  SELECT * FROM product_cvr_data
),
product_profit AS (
  SELECT
    pp.item_id,
    pp.item_name,
    pp.view_sessions,
    pp.purchase_sessions,
    pp.cvr,
    pp.total_revenue,
    pc.cost_price,
    pc.selling_price,
    ROUND(pp.total_revenue - (pc.cost_price * pp.purchase_sessions), 0) AS gross_profit,
    ROUND(
      SAFE_DIVIDE(
        pp.total_revenue - (pc.cost_price * pp.purchase_sessions),
        pp.total_revenue
      ) * 100, 1
    ) AS gross_margin_pct
  FROM product_performance pp
  LEFT JOIN `${PROJECT}.${DATASET}.product_cost` pc
    ON pp.item_id = pc.item_id
)
SELECT
  item_id,
  item_name,
  view_sessions,
  purchase_sessions,
  cvr,
  total_revenue,
  gross_profit,
  gross_margin_pct,
  ROUND(SAFE_DIVIDE(gross_profit, view_sessions), 0) AS profit_per_view
FROM product_profit
ORDER BY gross_profit DESC;
```

### 233. 中小ECのLTV分析をGA4×BigQueryで無料構築する方法【SQLテンプレ付き】（SQL Template 2: コホート月別のリピート率（購入頻度））

**用途**: SQL Template 2: コホート月別のリピート率（購入頻度）

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください

```sql
WITH user_first_purchase AS (
  SELECT
    user_pseudo_id,
    MIN(FORMAT_TIMESTAMP('%Y-%m', TIMESTAMP_MICROS(event_timestamp))) AS first_purchase_month
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    event_name = 'purchase'
  GROUP BY
    user_pseudo_id
),
monthly_purchases AS (
  SELECT
    e.user_pseudo_id,
    FORMAT_TIMESTAMP('%Y-%m', TIMESTAMP_MICROS(e.event_timestamp)) AS purchase_month,
    COUNT(*) AS purchases_in_month
  FROM
    `${PROJECT}.${DATASET}.events_*` e
  WHERE
    e.event_name = 'purchase'
  GROUP BY
    e.user_pseudo_id, purchase_month
)
SELECT
  fp.first_purchase_month AS cohort_month,
  COUNT(DISTINCT fp.user_pseudo_id) AS cohort_size,
  AVG(mp.purchases_in_month) AS avg_monthly_purchases,
  COUNT(DISTINCT CASE
    WHEN mp.purchase_month > fp.first_purchase_month THEN mp.user_pseudo_id
  END) AS repeat_users,
  ROUND(
    COUNT(DISTINCT CASE
      WHEN mp.purchase_month > fp.first_purchase_month THEN mp.user_pseudo_id
    END) / COUNT(DISTINCT fp.user_pseudo_id), 3
  ) AS repeat_rate
FROM
  user_first_purchase fp
LEFT JOIN
  monthly_purchases mp ON fp.user_pseudo_id = mp.user_pseudo_id
GROUP BY
  cohort_month
ORDER BY
  cohort_month
```

### 234. 中小ECのLTV分析をGA4×BigQueryで無料構築する方法【SQLテンプレ付き】（SQL Template 3: シンプルLTV計算）

**用途**: SQL Template 3: シンプルLTV計算

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください

```sql
WITH user_metrics AS (
  SELECT
    user_pseudo_id,
    COUNT(*) AS purchase_count,
    AVG(ecommerce.purchase_revenue) AS avg_purchase_value,
    DATE_DIFF(
      MAX(DATE(TIMESTAMP_MICROS(event_timestamp))),
      MIN(DATE(TIMESTAMP_MICROS(event_timestamp))),
      DAY
    ) / 365.0 AS lifespan_years
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    event_name = 'purchase'
  GROUP BY
    user_pseudo_id
  HAVING
    COUNT(*) >= 2  -- リピーターのみ対象
)
SELECT
  COUNT(*) AS user_count,
  ROUND(AVG(avg_purchase_value), 0) AS avg_purchase_value,
  ROUND(AVG(purchase_count), 1) AS avg_purchase_frequency,
  ROUND(AVG(lifespan_years), 2) AS avg_lifespan_years,
  ROUND(
    AVG(avg_purchase_value) * AVG(purchase_count) * AVG(lifespan_years), 0
  ) AS estimated_ltv
FROM
  user_metrics
```

### 235. 中小ECのLTV分析をGA4×BigQueryで無料構築する方法【SQLテンプレ付き】（SQL Template 4: コホート別LTV（月次リテンション））

**用途**: SQL Template 4: コホート別LTV（月次リテンション）

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください

```sql
WITH user_cohort AS (
  SELECT
    user_pseudo_id,
    MIN(FORMAT_TIMESTAMP('%Y-%m', TIMESTAMP_MICROS(event_timestamp))) AS cohort_month
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    event_name = 'purchase'
  GROUP BY
    user_pseudo_id
),
purchase_data AS (
  SELECT
    e.user_pseudo_id,
    FORMAT_TIMESTAMP('%Y-%m', TIMESTAMP_MICROS(e.event_timestamp)) AS purchase_month,
    SUM(e.ecommerce.purchase_revenue) AS revenue
  FROM
    `${PROJECT}.${DATASET}.events_*` e
  WHERE
    e.event_name = 'purchase'
  GROUP BY
    e.user_pseudo_id, purchase_month
)
SELECT
  uc.cohort_month,
  DATE_DIFF(
    PARSE_DATE('%Y-%m', pd.purchase_month),
    PARSE_DATE('%Y-%m', uc.cohort_month),
    MONTH
  ) AS months_since_first_purchase,
  COUNT(DISTINCT uc.user_pseudo_id) AS active_users,
  (SELECT COUNT(DISTINCT user_pseudo_id) FROM user_cohort WHERE cohort_month = uc.cohort_month) AS cohort_size,
  ROUND(SUM(pd.revenue), 0) AS monthly_revenue,
  ROUND(SUM(pd.revenue) / (SELECT COUNT(DISTINCT user_pseudo_id) FROM user_cohort WHERE cohort_month = uc.cohort_month), 0) AS revenue_per_cohort_user
FROM
  user_cohort uc
INNER JOIN
  purchase_data pd ON uc.user_pseudo_id = pd.user_pseudo_id
GROUP BY
  uc.cohort_month, months_since_first_purchase, cohort_size
ORDER BY
  uc.cohort_month, months_since_first_purchase
```

### 236. 中小ECのLTV分析をGA4×BigQueryで無料構築する方法【SQLテンプレ付き】（LTVを意思決定に活用する: LTV:CAC比率）

**用途**: LTVを意思決定に活用する: LTV:CAC比率

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください

```sql
WITH user_first_session AS (
  SELECT
    user_pseudo_id,
    collected_traffic_source.manual_medium AS first_medium,
    collected_traffic_source.manual_source AS first_source,
    MIN(event_timestamp) AS first_event_timestamp
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    collected_traffic_source.manual_medium IS NOT NULL
  GROUP BY
    user_pseudo_id,
    collected_traffic_source.manual_medium,
    collected_traffic_source.manual_source
),
user_revenue AS (
  SELECT
    user_pseudo_id,
    SUM(ecommerce.purchase_revenue) AS total_revenue,
    COUNT(*) AS purchase_count
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    event_name = 'purchase'
  GROUP BY
    user_pseudo_id
)
SELECT
  fs.first_medium,
  fs.first_source,
  COUNT(DISTINCT ur.user_pseudo_id) AS paying_users,
  ROUND(AVG(ur.total_revenue), 0) AS avg_ltv,
  ROUND(AVG(ur.purchase_count), 1) AS avg_purchase_count
FROM
  user_first_session fs
INNER JOIN
  user_revenue ur ON fs.user_pseudo_id = ur.user_pseudo_id
GROUP BY
  fs.first_medium, fs.first_source
HAVING
  COUNT(DISTINCT ur.user_pseudo_id) >= 10  -- サンプル数が少なすぎるチャネルを除外
ORDER BY
  avg_ltv DESC
```

### 237. GA4×BigQueryでカート放棄率を正確に計測・改善する方法（基本SQL：カート放棄率を算出する）

**用途**: 基本SQL：カート放棄率を算出する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH add_to_cart_users AS (
  SELECT DISTINCT user_pseudo_id
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
  COUNT(*) AS total_add_to_cart_users,
  COUNTIF(p.user_pseudo_id IS NULL) AS abandoned_users,
  ROUND(
    COUNTIF(p.user_pseudo_id IS NULL) / COUNT(*) * 100, 1
  ) AS cart_abandonment_rate
FROM add_to_cart_users a
LEFT JOIN purchase_users p
  ON a.user_pseudo_id = p.user_pseudo_id;
```

### 238. チャネル別ROASをBigQueryで集計してLooker Studioに可視化する（Step 1：チャネル別売上をBigQueryで集計する）

**用途**: Step 1：チャネル別売上をBigQueryで集計する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m%d', event_date)) AS month,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNTIF(event_name = 'purchase') AS purchases,
  SUM(
    IF(event_name = 'purchase', ecommerce.purchase_revenue, 0)
  ) AS revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
  AND collected_traffic_source.manual_medium IS NOT NULL
GROUP BY
  month, medium, source
ORDER BY
  month, revenue DESC
```

### 239. BigQueryでEC季節商品の売上予測モデルを作った話（Step 5: 予測精度の検証（バックテスト））

**用途**: Step 5: 予測精度の検証（バックテスト）

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
CREATE OR REPLACE MODEL `your-project.mart.sales_forecast_backtest`
OPTIONS (
  model_type = 'ARIMA_PLUS',
  time_series_timestamp_col = 'sale_date',
  time_series_data_col = 'daily_revenue',
  auto_arima = TRUE,
  data_frequency = 'DAILY',
  holiday_region = 'JP'
) AS
SELECT sale_date, daily_revenue
FROM `your-project.mart.daily_sales`
WHERE sale_date BETWEEN '2024-01-01' AND '2025-09-30';

-- 予測と実績の比較
WITH forecast AS (
  SELECT
    forecast_timestamp AS predicted_date,
    forecast_value AS predicted_revenue
  FROM ML.FORECAST(
    MODEL `your-project.mart.sales_forecast_backtest`,
    STRUCT(92 AS horizon, 0.95 AS confidence_level)
  )
),
actual AS (
  SELECT
    sale_date,
    daily_revenue AS actual_revenue
  FROM `your-project.mart.daily_sales`
  WHERE sale_date BETWEEN '2025-10-01' AND '2025-12-31'
)
SELECT
  a.sale_date,
  a.actual_revenue,
  f.predicted_revenue,
  ROUND(ABS(a.actual_revenue - f.predicted_revenue) / a.actual_revenue * 100, 1) AS error_pct
FROM actual a
INNER JOIN forecast f
  ON a.sale_date = DATE(f.predicted_date)
ORDER BY a.sale_date
```

### 240. BigQueryでGA4データからEC顧客の年齢・性別推定精度を検証した（BigQueryでCRMデータと統合するSQL例）

**用途**: BigQueryでCRMデータと統合するSQL例

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  ga.user_pseudo_id,
  crm.age,
  crm.gender,
  crm.prefecture,
  COUNT(DISTINCT CASE WHEN ga.event_name = 'purchase' THEN ga.event_bundle_sequence_id END) AS purchases,
  SUM(CASE WHEN ga.event_name = 'purchase' THEN ga.ecommerce.purchase_revenue END) AS total_revenue
FROM
  `${PROJECT}.${DATASET}.events_*` ga
INNER JOIN
  `your-project.crm.members` crm
  ON ga.user_id = crm.user_id
WHERE
  ga._TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
GROUP BY
  ga.user_pseudo_id, crm.age, crm.gender, crm.prefecture
```

### 241. 中小ECのLTV分析をGA4×BigQueryで無料構築する方法【SQLテンプレ付き】（SQL Template 1: ユーザーごとの平均購入単価）

**用途**: SQL Template 1: ユーザーごとの平均購入単価

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  user_pseudo_id,
  COUNT(*) AS purchase_count,
  SUM(ecommerce.purchase_revenue) AS total_revenue,
  AVG(ecommerce.purchase_revenue) AS avg_purchase_value
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  event_name = 'purchase'
  AND _TABLE_SUFFIX BETWEEN '20250101' AND '20260329'
GROUP BY
  user_pseudo_id
ORDER BY
  total_revenue DESC
```

### 242. EC売上が下がったとき最初に確認すべきBigQueryクエリ5選（クエリ1：日別売上推移（いつから下がったかを特定する））

**用途**: クエリ1：日別売上推移（いつから下がったかを特定する）

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_date,
  COUNT(DISTINCT
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
  ) AS sessions,
  COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN ecommerce.transaction_id END) AS transactions,
  SUM(ecommerce.purchase_revenue) AS revenue
FROM
  `analytics_XXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20260201' AND '20260328'
GROUP BY
  event_date
ORDER BY
  event_date
```

### 243. GA4×BigQueryで初回購入→リピートまでのファネルを可視化する（Step 1：ユーザーごとの初回購入日を特定する）

**用途**: Step 1：ユーザーごとの初回購入日を特定する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください / `SELECT *` を含みます。必要な列だけに絞るとコストが下がります

```sql
WITH purchases AS (
  SELECT
    user_pseudo_id,
    PARSE_DATE('%Y%m%d', event_date) AS purchase_date,
    ecommerce.transaction_id,
    ecommerce.purchase_revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    event_name = 'purchase'
    AND ecommerce.transaction_id IS NOT NULL
),

user_purchases AS (
  SELECT
    user_pseudo_id,
    purchase_date,
    transaction_id,
    purchase_revenue,
    ROW_NUMBER() OVER (
      PARTITION BY user_pseudo_id
      ORDER BY purchase_date, transaction_id
    ) AS purchase_number,
    MIN(purchase_date) OVER (
      PARTITION BY user_pseudo_id
    ) AS first_purchase_date
  FROM purchases
)

SELECT * FROM user_purchases
ORDER BY user_pseudo_id, purchase_number;
```

### 244. Meta広告×GA4×BigQueryでクリエイティブ別ROASを深掘りする（フォーマット別の傾向分析）

**用途**: フォーマット別の傾向分析

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  CASE
    WHEN creative_name LIKE '%video%' THEN 'video'
    WHEN creative_name LIKE '%static%' THEN 'static'
    WHEN creative_name LIKE '%carousel%' THEN 'carousel'
    ELSE 'other'
  END AS format_type,
  SUM(sessions) AS total_sessions,
  SUM(purchases) AS total_purchases,
  SUM(total_revenue) AS total_revenue,
  SUM(total_spend) AS total_spend,
  ROUND(SAFE_DIVIDE(SUM(total_revenue), SUM(total_spend)), 2) AS roas
FROM creative_performance
GROUP BY format_type
ORDER BY roas DESC;
```

### 245. GA4×BigQueryでGoogle広告のキーワード別CVRを正確に測定する（GA4データからgclidを抽出するSQL）

**用途**: GA4データからgclidを抽出するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH ga4_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium,
    event_name,
    event_date
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
),
gclid_extracted AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    REGEXP_EXTRACT(page_location, r'gclid=([^&]+)') AS gclid,
    event_name,
    event_date
  FROM ga4_sessions
  WHERE medium = 'cpc'
    AND source = 'google'
)
SELECT DISTINCT
  user_pseudo_id,
  ga_session_id,
  gclid,
  event_date
FROM gclid_extracted
WHERE gclid IS NOT NULL;
```

### 246. GA4×BigQueryでモバイルとPCの購買行動の違いを分析した（クロスデバイスの考慮）

**用途**: クロスデバイスの考慮

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH cross_device AS (
  SELECT
    user_id,
    device.category AS device_category,
    event_name
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name IN ('add_to_cart', 'purchase')
    AND user_id IS NOT NULL
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
)
SELECT
  cart.user_id,
  cart.device_category AS cart_device,
  purchase.device_category AS purchase_device
FROM (
  SELECT DISTINCT user_id, device_category
  FROM cross_device WHERE event_name = 'add_to_cart'
) cart
JOIN (
  SELECT DISTINCT user_id, device_category
  FROM cross_device WHERE event_name = 'purchase'
) purchase
  ON cart.user_id = purchase.user_id
WHERE cart.device_category != purchase.device_category;
```

### 247. Meta広告×GA4×BigQueryでクリエイティブ別ROASを深掘りする（GA4×BigQueryでUTMパラメータを取得するSQL）

**用途**: GA4×BigQueryでUTMパラメータを取得するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH ad_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'campaign') AS campaign,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'content') AS content,
    event_name,
    event_date
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
    AND collected_traffic_source.manual_source = 'facebook'
    AND collected_traffic_source.manual_medium = 'paid_social'
)
SELECT DISTINCT
  user_pseudo_id,
  ga_session_id,
  campaign,
  content AS creative_name,
  event_date
FROM ad_sessions
WHERE content IS NOT NULL;
```

### 248. BigQueryでEC顧客をRFM分析してセグメント別メルマガ戦略を立てた（セグメント分類SQL）

**用途**: セグメント分類SQL

**コストの注意**: `SELECT *` を含みます。必要な列だけに絞るとコストが下がります

```sql
WITH rfm_scores AS (
  -- 前述のクエリでr_score, f_score, m_scoreを取得済み
  SELECT *
  FROM user_rfm_scored
)
SELECT
  user_pseudo_id,
  r_score,
  f_score,
  m_score,
  CASE
    WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'VIP顧客'
    WHEN r_score >= 4 AND f_score >= 3 THEN 'アクティブ優良'
    WHEN r_score >= 4 AND f_score <= 2 THEN '新規・単発'
    WHEN r_score <= 2 AND f_score >= 3 THEN '休眠リスク'
    WHEN r_score <= 2 AND f_score <= 2 THEN '離脱済み'
    ELSE 'その他'
  END AS segment
FROM rfm_scores;
```

### 249. BigQueryでEC季節商品の売上予測モデルを作った話（Step 1: 日別売上データの準備）

**用途**: Step 1: 日別売上データの準備

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
CREATE OR REPLACE TABLE `your-project.mart.daily_sales` AS
SELECT
  DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo') AS sale_date,
  SUM(ecommerce.purchase_revenue) AS daily_revenue,
  COUNT(DISTINCT user_pseudo_id) AS unique_buyers,
  COUNT(*) AS transaction_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240101' AND '20251231'
  AND event_name = 'purchase'
  AND ecommerce.purchase_revenue > 0
GROUP BY sale_date
ORDER BY sale_date
```

### 250. GA4×BigQueryでEC新規顧客獲得コスト（CAC）を媒体別に正確計算する（方法2: Google Sheetsを外部テーブルとして使う）

**用途**: 方法2: Google Sheetsを外部テーブルとして使う

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  nc.channel,
  nc.source,
  nc.new_customers,
  ac.cost AS monthly_cost,
  ROUND(ac.cost / NULLIF(nc.new_customers, 0), 0) AS cac
FROM new_customers_by_source nc
INNER JOIN `your-project.ad_costs.monthly_costs` ac
  ON nc.channel = ac.channel AND nc.source = ac.source
ORDER BY cac
```

### 251. GA4×BigQueryでポイント還元施策の効果をコホート分析で検証した（Step 4: 施策のROI算出）

**用途**: Step 4: 施策のROI算出

**コストの注意**: `SELECT *` を含みます。必要な列だけに絞るとコストが下がります

```sql
WITH cohort_metrics AS (
  -- Step 3の結果を仮定
  SELECT '施策前' AS label, 150 AS customers, 12500 AS avg_ltv UNION ALL
  SELECT '施策後' AS label, 220 AS customers, 11800 AS avg_ltv
)
SELECT
  *,
  customers * avg_ltv AS total_ltv,
  CASE
    WHEN label = '施策後' THEN customers * 500  -- ポイント還元500円/人
    ELSE 0
  END AS campaign_cost,
  CASE
    WHEN label = '施策後' THEN (customers * avg_ltv) - (customers * 500)
    ELSE customers * avg_ltv
  END AS net_revenue
FROM cohort_metrics
```

### 252. ECサイトのサイト内検索キーワードをGA4×BigQueryで分析して品揃えを改善した（検索キーワードのランキングを取得する）

**用途**: 検索キーワードのランキングを取得する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'search_term') AS search_term,
  COUNT(*) AS search_count,
  COUNT(DISTINCT user_pseudo_id) AS unique_users
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
  AND event_name = 'view_search_results'
GROUP BY search_term
HAVING search_term IS NOT NULL
ORDER BY search_count DESC
LIMIT 50
```

### 253. BigQueryでEC顧客をRFM分析してセグメント別メルマガ戦略を立てた（セグメント別の集計）

**用途**: セグメント別の集計

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  segment,
  COUNT(*) AS user_count,
  ROUND(AVG(recency), 0) AS avg_recency_days,
  ROUND(AVG(frequency), 1) AS avg_frequency,
  ROUND(AVG(monetary), 0) AS avg_monetary
FROM rfm_segmented
GROUP BY segment
ORDER BY avg_monetary DESC;
```

### 254. BigQueryでEC季節商品の売上予測モデルを作った話（Step 2: ARIMA_PLUSモデルの作成）

**用途**: Step 2: ARIMA_PLUSモデルの作成

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
CREATE OR REPLACE MODEL `your-project.mart.sales_forecast_model`
OPTIONS (
  model_type = 'ARIMA_PLUS',
  time_series_timestamp_col = 'sale_date',
  time_series_data_col = 'daily_revenue',
  auto_arima = TRUE,
  data_frequency = 'DAILY',
  holiday_region = 'JP'
) AS
SELECT
  sale_date,
  daily_revenue
FROM
  `your-project.mart.daily_sales`
WHERE
  sale_date BETWEEN '2024-01-01' AND '2025-12-31'
```

### 255. BigQueryでEC季節商品の売上予測モデルを作った話（線形回帰モデルとの比較）

**用途**: 線形回帰モデルとの比較

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
CREATE OR REPLACE MODEL `your-project.mart.sales_linear_model`
OPTIONS (
  model_type = 'LINEAR_REG',
  input_label_cols = ['daily_revenue']
) AS
SELECT
  daily_revenue,
  EXTRACT(MONTH FROM sale_date) AS month,
  EXTRACT(DAYOFWEEK FROM sale_date) AS day_of_week,
  CASE
    WHEN EXTRACT(MONTH FROM sale_date) IN (12, 1, 7, 8) THEN 1
    ELSE 0
  END AS is_peak_season,
  unique_buyers,
  transaction_count
FROM `your-project.mart.daily_sales`
WHERE sale_date BETWEEN '2024-01-01' AND '2025-12-31'
```

### 256. チャネル別ROASをBigQueryで集計してLooker Studioに可視化する（Step 2：広告費データを用意する）

**用途**: Step 2：広告費データを用意する

**必要なテーブル**: `${DATASET}.ad_spend`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
CREATE TABLE IF NOT EXISTS `${PROJECT}.${DATASET}.ad_spend` (
  month STRING,        -- '2025-01' 形式
  medium STRING,       -- 'cpc', 'display', 'social' など
  source STRING,       -- 'google', 'meta', 'line' など
  spend INT64          -- 広告費（円）
);
```

### 257. BigQueryでEC商品別の粗利×CVR×流入数をまとめた利益ダッシュボードを作った（原価データとの結合で粗利を算出する） その2

**用途**: 原価データとの結合で粗利を算出する

**必要なテーブル**: `${DATASET}.product_cost`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
CREATE TABLE IF NOT EXISTS `${PROJECT}.${DATASET}.product_cost` (
  item_id STRING,
  item_name STRING,
  cost_price FLOAT64,
  selling_price FLOAT64
);
```

### 258. BigQueryでEC商品別の粗利×CVR×流入数をまとめた利益ダッシュボードを作った（4象限マトリクスで優先度を整理する）

**用途**: 4象限マトリクスで優先度を整理する

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  item_id,
  item_name,
  cvr,
  gross_margin_pct,
  CASE
    WHEN cvr >= 3.0 AND gross_margin_pct >= 40 THEN '最優先投資'
    WHEN cvr >= 3.0 AND gross_margin_pct < 40 THEN '改善不要（維持）'
    WHEN cvr < 3.0 AND gross_margin_pct >= 40 THEN 'CVR改善'
    ELSE '撤退検討'
  END AS quadrant
FROM product_profit
ORDER BY quadrant, gross_profit DESC;
```

### 259. BigQueryでEC季節商品の売上予測モデルを作った話（Step 4: 売上予測の実行）

**用途**: Step 4: 売上予測の実行

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  forecast_timestamp AS predicted_date,
  forecast_value AS predicted_revenue,
  prediction_interval_lower_bound AS lower_bound,
  prediction_interval_upper_bound AS upper_bound
FROM
  ML.FORECAST(
    MODEL `your-project.mart.sales_forecast_model`,
    STRUCT(90 AS horizon, 0.95 AS confidence_level)
  )
ORDER BY forecast_timestamp
```

### 260. GA4×BigQueryでGoogle広告のキーワード別CVRを正確に測定する（gclidの仕組みと取得方法）

**用途**: gclidの仕組みと取得方法

**必要なテーブル**: `${DATASET}.ads_click_keyword`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
CREATE TABLE IF NOT EXISTS `${PROJECT}.${DATASET}.ads_click_keyword` (
  gclid STRING,
  campaign_name STRING,
  ad_group_name STRING,
  keyword STRING,
  match_type STRING,
  click_date DATE
);
```

### 261. GA4×BigQueryでECサイトの速度改善がCVRに与えた影響を測定した（CrUXデータをBigQueryで活用する）

**用途**: CrUXデータをBigQueryで活用する

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  origin,
  effective_connection_type.name AS connection_type,
  form_factor.name AS device,
  largest_contentful_paint.histogram AS lcp_histogram,
  interaction_to_next_paint.histogram AS inp_histogram,
  cumulative_layout_shift.histogram AS cls_histogram
FROM
  `chrome-ux-report.all.202503`
WHERE
  origin = 'https://your-ec-site.com'
```

### 262. ECの商品レビュー数×売上の関係をBigQueryで定量分析した結果（SQLで商品ごとの転換率とレビュー数を集計する）

**用途**: SQLで商品ごとの転換率とレビュー数を集計する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH session_base AS (
  SELECT
    event_date,
    user_pseudo_id,
    -- ga_session_idはevent_paramsからUNNEST経由で取得
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS ga_session_id,
    event_name,
    (SELECT value.string_value
     FROM UNNEST(items)
     LIMIT 1) AS item_id
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
    AND event_name IN ('view_item', 'add_to_cart', 'purchase')
),

item_funnel AS (
  SELECT
    item_id,
    COUNTIF(event_name = 'view_item')   AS view_count,
    COUNTIF(event_name = 'add_to_cart') AS cart_count,
    COUNTIF(event_name = 'purchase')    AS purchase_count
  FROM session_base
  WHERE item_id IS NOT NULL
  GROUP BY item_id
)

SELECT
  f.item_id,
  f.view_count,
  f.cart_count,
  f.purchase_count,
  SAFE_DIVIDE(f.purchase_count, f.view_count) AS view_to_purchase_rate,
  r.review_count,
  r.avg_rating,
  r.category
FROM item_funnel f
LEFT JOIN `your_project.ec_data.product_reviews` r
  ON f.item_id = r.item_id
ORDER BY f.view_count DESC
LIMIT 200;
```

### 263. ECの商品レビュー数×売上の関係をBigQueryで定量分析した結果（レビュー件数を段階別に区切って比較する）

**用途**: レビュー件数を段階別に区切って比較する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH item_funnel AS (
  -- 前節のitem_funnelクエリをここに入れる
  SELECT
    item_id,
    COUNTIF(event_name = 'view_item')   AS view_count,
    COUNTIF(event_name = 'purchase')    AS purchase_count
  FROM (
    SELECT
      event_name,
      (SELECT value.string_value FROM UNNEST(items) LIMIT 1) AS item_id
    FROM `${PROJECT}.${DATASET}.events_*`
    WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
      AND event_name IN ('view_item', 'purchase')
  )
  WHERE item_id IS NOT NULL
  GROUP BY item_id
),

joined AS (
  SELECT
    f.item_id,
    f.view_count,
    f.purchase_count,
    r.review_count,
    r.category,
    CASE
      WHEN r.review_count = 0          THEN '0件'
      WHEN r.review_count BETWEEN 1 AND 4  THEN '1〜4件'
      WHEN r.review_count BETWEEN 5 AND 9  THEN '5〜9件'
      WHEN r.review_count >= 10        THEN '10件以上'
      ELSE '不明'
    END AS review_bucket
  FROM item_funnel f
  LEFT JOIN `your_project.ec_data.product_reviews` r
    ON f.item_id = r.item_id
)

SELECT
  review_bucket,
  COUNT(DISTINCT item_id)                           AS item_count,
  SUM(view_count)                                   AS total_views,
  SUM(purchase_count)                               AS total_purchases,
  ROUND(SAFE_DIVIDE(SUM(purchase_count), SUM(view_count)) * 100, 2) AS cvr_pct
FROM joined
GROUP BY review_bucket
ORDER BY
  CASE review_bucket
    WHEN '0件'   THEN 1
    WHEN '1〜4件' THEN 2
    WHEN '5〜9件' THEN 3
    WHEN '10件以上' THEN 4
    ELSE 5
  END;
```

### 264. ECの商品レビュー数×売上の関係をBigQueryで定量分析した結果（流入元別にレビュー効果の差を見る）

**用途**: 流入元別にレビュー効果の差を見る

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH session_traffic AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS ga_session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    event_name,
    (SELECT value.string_value FROM UNNEST(items) LIMIT 1) AS item_id
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
    AND event_name IN ('view_item', 'purchase')
),

funnel_by_traffic AS (
  SELECT
    COALESCE(medium, '(none)') AS medium,
    item_id,
    COUNTIF(event_name = 'view_item')  AS views,
    COUNTIF(event_name = 'purchase')   AS purchases
  FROM session_traffic
  WHERE item_id IS NOT NULL
  GROUP BY medium, item_id
)

SELECT
  f.medium,
  CASE
    WHEN r.review_count = 0        THEN '0件'
    WHEN r.review_count < 5        THEN '1〜4件'
    WHEN r.review_count < 10       THEN '5〜9件'
    ELSE '10件以上'
  END AS review_bucket,
  COUNT(DISTINCT f.item_id)                                        AS item_count,
  SUM(f.views)                                                     AS total_views,
  SUM(f.purchases)                                                 AS total_purchases,
  ROUND(SAFE_DIVIDE(SUM(f.purchases), SUM(f.views)) * 100, 2)     AS cvr_pct
FROM funnel_by_traffic f
LEFT JOIN `your_project.ec_data.product_reviews` r
  ON f.item_id = r.item_id
GROUP BY f.medium, review_bucket
ORDER BY f.medium, review_bucket;
```

### 265. ECの送料無料ラインをBigQueryの購買データから最適設定する分析手法（注文金額の分布を把握する）

**用途**: 注文金額の分布を把握する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH purchase_events AS (
  SELECT
    event_date,
    user_pseudo_id,
    (
      SELECT COALESCE(ep.value.int_value, ep.value.float_value, ep.value.double_value)
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'value'
    ) AS purchase_value
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
    AND event_name = 'purchase'
)

SELECT
  CASE
    WHEN purchase_value < 2000  THEN '〜2,000円未満'
    WHEN purchase_value < 3000  THEN '2,000〜3,000円未満'
    WHEN purchase_value < 4000  THEN '3,000〜4,000円未満'
    WHEN purchase_value < 5000  THEN '4,000〜5,000円未満'
    WHEN purchase_value < 7000  THEN '5,000〜7,000円未満'
    ELSE                             '7,000円以上'
  END AS price_range,
  COUNT(*) AS order_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pct
FROM
  purchase_events
WHERE
  purchase_value IS NOT NULL
GROUP BY
  price_range
ORDER BY
  MIN(purchase_value)
```

### 266. ECの送料無料ラインをBigQueryの購買データから最適設定する分析手法（カゴ落ちセッションの注文金額帯を特定する）

**用途**: カゴ落ちセッションの注文金額帯を特定する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH sessions AS (
  SELECT
    user_pseudo_id,
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS session_id,
    event_name,
    (
      SELECT COALESCE(ep.value.int_value, ep.value.float_value, ep.value.double_value)
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'value'
    ) AS cart_value
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
    AND event_name IN ('begin_checkout', 'purchase')
),

checkout_sessions AS (
  SELECT user_pseudo_id, session_id, MAX(cart_value) AS cart_value
  FROM sessions
  WHERE event_name = 'begin_checkout'
  GROUP BY user_pseudo_id, session_id
),

purchase_sessions AS (
  SELECT DISTINCT user_pseudo_id, session_id
  FROM sessions
  WHERE event_name = 'purchase'
),

abandoned AS (
  SELECT c.*
  FROM checkout_sessions c
  LEFT JOIN purchase_sessions p
    ON c.user_pseudo_id = p.user_pseudo_id
    AND c.session_id = p.session_id
  WHERE p.session_id IS NULL
)

SELECT
  CASE
    WHEN cart_value < 2000 THEN '〜2,000円未満'
    WHEN cart_value < 3000 THEN '2,000〜3,000円未満'
    WHEN cart_value < 4000 THEN '3,000〜4,000円未満'
    WHEN cart_value < 5000 THEN '4,000〜5,000円未満'
    ELSE                        '5,000円以上'
  END AS cart_range,
  COUNT(*) AS abandoned_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pct
FROM
  abandoned
WHERE
  cart_value IS NOT NULL
GROUP BY
  cart_range
ORDER BY
  MIN(cart_value)
```

### 267. GA4×BigQueryでECクーポン施策のカニバリゼーションを検証する（ステップ2：施策前後でリピーターの購入傾向を比較する）

**用途**: ステップ2：施策前後でリピーターの購入傾向を比較する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH before_period AS (
  SELECT
    user_pseudo_id,
    COUNT(*) AS purchase_count_before
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
),

-- 施策後期間（例：2025-08-01〜08-31）の購入ユーザーとクーポン利用有無
after_period AS (
  SELECT
    user_pseudo_id,
    (SELECT value.string_value
       FROM UNNEST(event_params)
      WHERE key = 'coupon') AS coupon_code,
    COUNT(*) AS purchase_count_after
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250801' AND '20250831'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id, coupon_code
)

SELECT
  CASE
    WHEN b.user_pseudo_id IS NOT NULL THEN '既存リピーター'
    ELSE '新規ユーザー'
  END AS user_type,
  CASE
    WHEN a.coupon_code IS NOT NULL AND a.coupon_code != ''
    THEN 'クーポン使用'
    ELSE 'クーポン未使用'
  END AS coupon_flag,
  COUNT(*)                              AS user_count,
  ROUND(AVG(a.purchase_count_after), 2) AS avg_purchase_count
FROM after_period a
LEFT JOIN before_period b
  ON a.user_pseudo_id = b.user_pseudo_id
GROUP BY user_type, coupon_flag
ORDER BY user_type, coupon_flag;
```

### 268. 2024年問題に備えるデータ基盤―配送コストをBigQueryで最適化する（流入経路別・配送コスト分析のSQLサンプル） その1

**用途**: 流入経路別・配送コスト分析のSQLサンプル

**必要なテーブル**: `${DATASET}.events_*`, `${DATASET}.shipping_costs`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH ga4_purchases AS (
  SELECT
    (
      SELECT ep.value.string_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'transaction_id'
    ) AS transaction_id,
    collected_traffic_source.manual_medium AS traffic_medium,
    collected_traffic_source.manual_source AS traffic_source,
    ecommerce.purchase_revenue             AS revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20260101' AND '20260731'
    AND event_name = 'purchase'
)
SELECT
  COALESCE(g.traffic_medium, '(none)')       AS medium,
  COALESCE(g.traffic_source, '(direct)')     AS source,
  COUNT(*)                                    AS order_count,
  ROUND(SUM(g.revenue), 0)                   AS total_revenue,
  ROUND(SUM(s.shipping_cost), 0)             AS total_shipping_cost,
  ROUND(AVG(s.shipping_cost), 0)             AS avg_shipping_cost_per_order,
  ROUND(SUM(s.shipping_cost) / SUM(g.revenue) * 100, 1) AS shipping_cost_ratio_pct
FROM
  ga4_purchases AS g
  LEFT JOIN `${PROJECT}.${DATASET}.shipping_costs` AS s
    ON g.transaction_id = s.order_id
GROUP BY
  medium,
  source
ORDER BY
  total_shipping_cost DESC
```

### 269. 楽天・Amazon・自社ECの売上データをBigQueryに集約して一元管理する方法（GA4データと売上を紐づける分析クエリ）

**用途**: GA4データと売上を紐づける分析クエリ

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH sessions AS (
  SELECT
    -- ga_session_id は event_params 経由で取得
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    )                                                          AS ga_session_id,
    user_pseudo_id,
    -- 流入元は collected_traffic_source を参照
    collected_traffic_source.manual_medium                     AS medium,
    collected_traffic_source.manual_source                     AS source,
    DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo')      AS session_date
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'session_start'
),

purchases AS (
  SELECT
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    )                                                          AS ga_session_id,
    user_pseudo_id,
    event_value_in_usd                                         AS purchase_value
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
)

SELECT
  s.medium,
  s.source,
  COUNT(DISTINCT s.ga_session_id)  AS sessions,
  COUNT(DISTINCT p.ga_session_id)  AS converting_sessions,
  ROUND(SUM(p.purchase_value), 0)  AS total_revenue_usd
FROM sessions AS s
LEFT JOIN purchases AS p
  ON s.ga_session_id  = p.ga_session_id
 AND s.user_pseudo_id = p.user_pseudo_id
GROUP BY s.medium, s.source
ORDER BY total_revenue_usd DESC;
```

### 270. ECメルマガのクリック→購入をGA4×BigQueryで追跡してセグメント別効果を測定する（メルマガ経由セッションを抽出するSQL）

**用途**: メルマガ経由セッションを抽出するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH email_sessions AS (
  SELECT
    user_pseudo_id,
    -- ga_session_id は event_params をUNNESTして取得する
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS session_id,
    collected_traffic_source.manual_medium AS utm_medium,
    collected_traffic_source.manual_source AS utm_source,
    collected_traffic_source.manual_campaign_name AS utm_campaign,
    event_name,
    event_timestamp
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
    AND collected_traffic_source.manual_medium = 'email'
),

-- セッション単位で最初のイベントと購入有無を集計
session_summary AS (
  SELECT
    user_pseudo_id,
    session_id,
    utm_source,
    utm_campaign,
    COUNTIF(event_name = 'purchase') AS purchase_count,
    MIN(event_timestamp) AS session_start_ts
  FROM email_sessions
  GROUP BY
    user_pseudo_id,
    session_id,
    utm_source,
    utm_campaign
)

SELECT
  utm_campaign,
  COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(session_id AS STRING))) AS total_sessions,
  COUNTIF(purchase_count > 0) AS purchase_sessions,
  ROUND(
    SAFE_DIVIDE(COUNTIF(purchase_count > 0), COUNT(*)) * 100, 2
  ) AS conversion_rate_pct
FROM session_summary
GROUP BY utm_campaign
ORDER BY conversion_rate_pct DESC;
```

### 271. ECメルマガのクリック→購入をGA4×BigQueryで追跡してセグメント別効果を測定する（リピーター・新規ユーザー別に効果を分ける）

**用途**: リピーター・新規ユーザー別に効果を分ける

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH email_sessions AS (
  SELECT
    user_pseudo_id,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS session_id,
    collected_traffic_source.manual_campaign_name AS utm_campaign,
    event_name,
    -- user_first_touch_timestamp はマイクロ秒単位
    TIMESTAMP_MICROS(user_first_touch_timestamp) AS first_touch_ts,
    TIMESTAMP_MICROS(event_timestamp) AS event_ts
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
    AND collected_traffic_source.manual_medium = 'email'
),

session_agg AS (
  SELECT
    user_pseudo_id,
    session_id,
    utm_campaign,
    MIN(first_touch_ts) AS first_touch_ts,
    MIN(event_ts)        AS session_start_ts,
    COUNTIF(event_name = 'purchase') AS purchased
  FROM email_sessions
  GROUP BY user_pseudo_id, session_id, utm_campaign
)

SELECT
  utm_campaign,
  CASE
    WHEN TIMESTAMP_DIFF(session_start_ts, first_touch_ts, DAY) < 30
      THEN '新規（初回接触30日以内）'
    ELSE 'リピーター'
  END AS user_segment,
  COUNT(*) AS sessions,
  COUNTIF(purchased > 0) AS conversions,
  ROUND(SAFE_DIVIDE(COUNTIF(purchased > 0), COUNT(*)) * 100, 2) AS cvr_pct
FROM session_agg
GROUP BY utm_campaign, user_segment
ORDER BY utm_campaign, user_segment;
```

### 272. ECの在庫回転率をGA4×BigQueryで商品別に可視化して死に筋を特定する（在庫マスタと結合して回転率を算出するSQL）

**用途**: 在庫マスタと結合して回転率を算出するSQL

**必要なテーブル**: `${DATASET}.events_*`, `${DATASET}.inventory_master`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH sales AS (
  SELECT
    item.item_id                     AS product_id,
    SUM(item.quantity)               AS total_quantity_sold
  FROM
    `${PROJECT}.${DATASET}.events_*`,
    UNNEST(items) AS item
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
    AND event_name = 'purchase'
    AND item.quantity > 0
  GROUP BY
    product_id
),
inventory AS (
  SELECT
    product_id,
    product_name,
    stock_start,
    stock_end,
    SAFE_DIVIDE(stock_start + stock_end, 2) AS avg_stock
  FROM
    `${PROJECT}.${DATASET}.inventory_master`
)
SELECT
  inv.product_id,
  inv.product_name,
  COALESCE(s.total_quantity_sold, 0)              AS total_quantity_sold,
  inv.avg_stock,
  ROUND(
    SAFE_DIVIDE(COALESCE(s.total_quantity_sold, 0), inv.avg_stock),
    2
  )                                               AS inventory_turnover_rate
FROM
  inventory AS inv
LEFT JOIN
  sales AS s
  ON inv.product_id = s.product_id
ORDER BY
  inventory_turnover_rate ASC  -- 回転率の低い順（死に筋候補が上位に）
;
```

### 273. ECの価格変更がCVRと売上に与えた影響をGA4×BigQueryで因果推論する（GA4×BigQueryでデータを準備する）

**用途**: GA4×BigQueryでデータを準備する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH base AS (
  SELECT
    DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo') AS event_date,
    user_pseudo_id,
    -- ga_session_idはevent_paramsからUNNESTで取得
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    event_name,
    -- 商品IDはevent_paramsのitem_idから取得（purchase/view_itemイベント向け）
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_id') AS item_id,
    -- 流入元はcollected_traffic_sourceを使用
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source  AS source
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250731'
    AND event_name IN ('view_item', 'purchase')
),

session_level AS (
  SELECT
    event_date,
    item_id,
    CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING)) AS session_key,
    MAX(IF(event_name = 'view_item',  1, 0)) AS viewed,
    MAX(IF(event_name = 'purchase',   1, 0)) AS purchased
  FROM base
  WHERE item_id IS NOT NULL
  GROUP BY 1, 2, 3
)

SELECT
  event_date,
  item_id,
  COUNT(*)                    AS sessions,
  SUM(purchased)              AS conversions,
  SAFE_DIVIDE(SUM(purchased), COUNT(*)) AS cvr
FROM session_level
WHERE viewed = 1
GROUP BY 1, 2
ORDER BY 1, 2
```

### 274. ECの価格変更がCVRと売上に与えた影響をGA4×BigQueryで因果推論する（売上への影響も合わせて確認する）

**用途**: 売上への影響も合わせて確認する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH revenue_base AS (
  SELECT
    DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo') AS event_date,
    user_pseudo_id,
    (SELECT value.int_value  FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    event_name,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_id')   AS item_id,
    ecommerce.purchase_revenue AS revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250731'
    AND event_name IN ('view_item', 'purchase')
)

SELECT
  event_date,
  item_id,
  COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING))) AS sessions,
  SUM(IF(event_name = 'purchase', revenue, 0))                          AS total_revenue,
  SAFE_DIVIDE(
    SUM(IF(event_name = 'purchase', revenue, 0)),
    COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING)))
  ) AS rps
FROM revenue_base
WHERE item_id IS NOT NULL
GROUP BY 1, 2
ORDER BY 1, 2
```

### 275. Amazon広告とGA4自社ECデータをBigQueryで統合してチャネルミックスを最適化する（Amazon広告データとGA4データをBigQueryで結合する）

**用途**: Amazon広告データとGA4データをBigQueryで結合する

**必要なテーブル**: `${DATASET}.amazon_ads_campaign_report`, `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH amazon_summary AS (
  SELECT
    report_date,
    SUM(spend) AS amazon_spend,
    SUM(sales_14d) AS amazon_revenue,
    SUM(clicks) AS amazon_clicks,
    SUM(impressions) AS amazon_impressions
  FROM
    `${PROJECT}.${DATASET}.amazon_ads_campaign_report`
  GROUP BY
    report_date
),

ga4_paid AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    SUM(
      CASE
        WHEN event_name = 'purchase'
        THEN (
          SELECT value.double_value
          FROM UNNEST(event_params) AS ep
          WHERE ep.key = 'value'
        )
        ELSE 0
      END
    ) AS own_ec_revenue,
    COUNTIF(event_name = 'purchase') AS own_ec_purchases
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250131'
    AND collected_traffic_source.manual_medium IN ('cpc', 'paid', 'ppc')
  GROUP BY
    event_date
)

SELECT
  COALESCE(a.report_date, g.event_date) AS date,
  COALESCE(a.amazon_spend, 0) AS amazon_spend,
  COALESCE(a.amazon_revenue, 0) AS amazon_revenue,
  COALESCE(g.own_ec_revenue, 0) AS own_ec_revenue,
  COALESCE(a.amazon_revenue, 0) + COALESCE(g.own_ec_revenue, 0) AS total_revenue
FROM
  amazon_summary a
FULL OUTER JOIN
  ga4_paid g
ON
  a.report_date = g.event_date
ORDER BY
  date
```

### 276. BigQueryでEC受注データ×GA4データを結合して正確な売上帰属分析をする（分析結果をLooker Studioで可視化する）

**用途**: 分析結果をLooker Studioで可視化する

**必要なテーブル**: `${DATASET}.ec_orders`, `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  DATE(o.ordered_at)                       AS order_date,
  COALESCE(s.traffic_source, '(direct)')   AS traffic_source,
  COALESCE(s.traffic_medium, '(none)')     AS traffic_medium,
  COUNT(o.order_id)                        AS order_count,
  SUM(o.order_amount)                      AS total_revenue
FROM
  `${PROJECT}.${DATASET}.ec_orders` AS o
LEFT JOIN (
  SELECT
    user_pseudo_id,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,
    collected_traffic_source.manual_source AS traffic_source,
    collected_traffic_source.manual_medium AS traffic_medium
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    AND event_name = 'session_start'
) AS s
  ON  o.user_pseudo_id = s.user_pseudo_id
  AND o.ga_session_id  = s.ga_session_id
WHERE
  o.order_status = 'confirmed'
  AND DATE(o.ordered_at) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
GROUP BY
  order_date,
  traffic_source,
  traffic_medium
```

### 277. 越境ECのGA4多言語計測をBigQueryで国別に正確に集計する方法（国別・言語別のセッション数をBigQueryで集計する）

**用途**: 国別・言語別のセッション数をBigQueryで集計する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH session_base AS (
  SELECT
    user_pseudo_id,
    geo.country AS country,
    device.language AS browser_language,
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250731'
    AND event_name = 'session_start'
)

SELECT
  country,
  browser_language,
  COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING))) AS session_count
FROM
  session_base
GROUP BY
  country,
  browser_language
ORDER BY
  session_count DESC
LIMIT 50;
```

### 278. 越境ECのGA4多言語計測をBigQueryで国別に正確に集計する方法（流入元と購買行動を国別に分析するSQL）

**用途**: 流入元と購買行動を国別に分析するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH purchase_events AS (
  SELECT
    user_pseudo_id,
    geo.country AS country,
    device.language AS browser_language,
    collected_traffic_source.manual_source AS utm_source,
    collected_traffic_source.manual_medium AS utm_medium,
    ecommerce.purchase_revenue AS revenue,
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250731'
    AND event_name = 'purchase'
)

SELECT
  country,
  browser_language,
  COALESCE(utm_medium, '(none)') AS medium,
  COALESCE(utm_source, '(direct)') AS source,
  COUNT(*) AS purchase_count,
  ROUND(SUM(revenue), 2) AS total_revenue,
  ROUND(AVG(revenue), 2) AS avg_order_value
FROM
  purchase_events
GROUP BY
  country,
  browser_language,
  medium,
  source
HAVING
  purchase_count >= 3
ORDER BY
  total_revenue DESC;
```

### 279. ECメルマガのクリック→購入をGA4×BigQueryで追跡してセグメント別効果を測定する（セグメント別の購入金額を集計するSQL）

**用途**: セグメント別の購入金額を集計するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH email_purchase_events AS (
  SELECT
    user_pseudo_id,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS session_id,
    collected_traffic_source.manual_campaign_name AS utm_campaign,
    (
      SELECT value.double_value
      FROM UNNEST(event_params)
      WHERE key = 'value'
    ) AS purchase_value,
    (
      SELECT value.string_value
      FROM UNNEST(event_params)
      WHERE key = 'currency'
    ) AS currency
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
    AND event_name = 'purchase'
    AND collected_traffic_source.manual_medium = 'email'
)

SELECT
  utm_campaign,
  currency,
  COUNT(*) AS purchase_count,
  ROUND(SUM(purchase_value), 0) AS total_revenue,
  ROUND(AVG(purchase_value), 0) AS avg_order_value
FROM email_purchase_events
WHERE purchase_value IS NOT NULL
GROUP BY utm_campaign, currency
ORDER BY total_revenue DESC;
```

### 280. ECの同梱チラシ施策効果をGA4のオフラインCV連携×BigQueryで測定する

**用途**: BigQueryでチラシ経由CV数・売上を集計するSQLの書き方

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH session_params AS (
  SELECT
    user_pseudo_id,
    -- ga_session_idはevent_paramsをUNNESTして取得
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,
    -- 流入元はcollected_traffic_sourceから取得
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_campaign_name AS campaign,
    event_name,
    event_timestamp,
    -- purchase金額
    (
      SELECT value.double_value
      FROM UNNEST(event_params)
      WHERE key = 'value'
    ) AS purchase_value
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250731'
    AND event_name IN ('session_start', 'purchase')
),
flyer_sessions AS (
  -- チラシ（print）経由のセッションを特定
  SELECT DISTINCT
    user_pseudo_id,
    ga_session_id
  FROM session_params
  WHERE
    medium = 'print'
    AND source = 'flyer'
    AND event_name = 'session_start'
)
SELECT
  s.campaign,
  COUNT(DISTINCT CONCAT(sp.user_pseudo_id, CAST(sp.ga_session_id AS STRING))) AS sessions,
  COUNT(DISTINCT CASE WHEN sp.event_name = 'purchase' THEN sp.user_pseudo_id END) AS purchasers,
  SUM(CASE WHEN sp.event_name = 'purchase' THEN sp.purchase_value ELSE 0 END) AS total_revenue
FROM
  session_params sp
INNER JOIN
  flyer_sessions s
  ON sp.user_pseudo_id = s.user_pseudo_id
  AND sp.ga_session_id = s.ga_session_id
GROUP BY
  s.campaign
ORDER BY
  total_revenue DESC;
```

### 281. ECの送料無料ラインをBigQueryの購買データから最適設定する分析手法（流入元別に送料感度を分析する）

**用途**: 流入元別に送料感度を分析する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH purchase_source AS (
  SELECT
    user_pseudo_id,
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    (
      SELECT COALESCE(ep.value.int_value, ep.value.float_value, ep.value.double_value)
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'value'
    ) AS purchase_value
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
    AND event_name = 'purchase'
)

SELECT
  COALESCE(medium, '(none)') AS medium,
  COALESCE(source, '(direct)') AS source,
  COUNT(*) AS order_count,
  ROUND(AVG(purchase_value), 0) AS avg_order_value,
  ROUND(MIN(purchase_value), 0) AS min_order_value,
  ROUND(APPROX_QUANTILES(purchase_value, 100)[OFFSET(50)], 0) AS median_order_value
FROM
  purchase_source
WHERE
  purchase_value IS NOT NULL
GROUP BY
  medium, source
ORDER BY
  order_count DESC
LIMIT 20
```

### 282. ECのギフト需要をGA4×BigQueryで時系列分析して在庫計画に反映する（ギフトイベント前の「需要立ち上がり」タイミングを特定する）

**用途**: ギフトイベント前の「需要立ち上がり」タイミングを特定する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH daily_orders AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS order_date,
    EXTRACT(YEAR FROM PARSE_DATE('%Y%m%d', event_date)) AS order_year,
    FORMAT_DATE('%m-%d', PARSE_DATE('%Y%m%d', event_date)) AS month_day,
    COUNT(DISTINCT (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'transaction_id')) AS order_count
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20231101' AND '20241231'
    AND event_name = 'purchase'
  GROUP BY
    order_date, order_year, month_day
)
SELECT
  month_day,
  MAX(CASE WHEN order_year = 2023 THEN order_count END) AS orders_2023,
  MAX(CASE WHEN order_year = 2024 THEN order_count END) AS orders_2024
FROM
  daily_orders
WHERE
  month_day BETWEEN '11-01' AND '12-25'
ORDER BY
  month_day
```

### 283. EC事業の粗利率をBigQueryで商品×チャネル別に自動計算する仕組み（商品×チャネル別の粗利率を計算するSQL）

**用途**: 商品×チャネル別の粗利率を計算するSQL

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
WITH session_purchase AS (
  -- （前述のクエリをCTEとして再利用）
  SELECT
    medium,
    source,
    transaction_id,
    revenue,
    event_date
  FROM /* 上記のSQLをここにネスト、またはビューとして呼び出す */
    `your_project.analytics.session_purchase_view`
),

item_margin AS (
  SELECT
    oi.order_id,
    oi.item_sku,
    oi.item_name,
    SUM(oi.quantity * oi.unit_price) AS item_revenue,
    SUM(oi.quantity * oi.unit_cost)  AS item_cost,
    SUM(oi.quantity * (oi.unit_price - oi.unit_cost)) AS gross_profit
  FROM
    `your_project.sales.order_items` AS oi
  GROUP BY
    oi.order_id, oi.item_sku, oi.item_name
)

SELECT
  sp.medium,
  sp.source,
  CONCAT(sp.medium, ' / ', COALESCE(sp.source, '(not set)')) AS channel,
  im.item_sku,
  im.item_name,
  SUM(im.item_revenue)  AS total_revenue,
  SUM(im.item_cost)     AS total_cost,
  SUM(im.gross_profit)  AS total_gross_profit,
  ROUND(
    SAFE_DIVIDE(SUM(im.gross_profit), SUM(im.item_revenue)) * 100,
    2
  ) AS gross_margin_rate
FROM
  item_margin AS im
LEFT JOIN
  session_purchase AS sp
  ON im.order_id = sp.transaction_id
GROUP BY
  sp.medium, sp.source, channel, im.item_sku, im.item_name
ORDER BY
  total_gross_profit DESC
```

### 284. ECの価格変更がCVRと売上に与えた影響をGA4×BigQueryで因果推論する（SQLで差分の差分を計算する）

**用途**: SQLで差分の差分を計算する

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
WITH daily_cvr AS (
  -- 上記クエリの結果をCTEとして再利用するイメージ
  SELECT
    event_date,
    item_id,
    SAFE_DIVIDE(SUM(purchased), COUNT(*)) AS cvr
  FROM session_level
  WHERE viewed = 1
  GROUP BY 1, 2
),

grouped AS (
  SELECT
    item_id,
    CASE
      WHEN item_id = 'ITEM_A' THEN 'treated'   -- 価格変更あり
      WHEN item_id = 'ITEM_B' THEN 'control'   -- 価格変更なし
    END AS group_type,
    CASE
      WHEN event_date < '2025-07-01' THEN 'pre'
      ELSE 'post'
    END AS period,
    AVG(cvr) AS avg_cvr
  FROM daily_cvr
  WHERE item_id IN ('ITEM_A', 'ITEM_B')
  GROUP BY 1, 2, 3
),

pivoted AS (
  SELECT
    item_id,
    group_type,
    MAX(IF(period = 'pre',  avg_cvr, NULL)) AS cvr_pre,
    MAX(IF(period = 'post', avg_cvr, NULL)) AS cvr_post
  FROM grouped
  GROUP BY 1, 2
),

diff AS (
  SELECT
    item_id,
    group_type,
    cvr_pre,
    cvr_post,
    cvr_post - cvr_pre AS delta_cvr
  FROM pivoted
)

-- DiD = 処置群のdelta − 対照群のdelta
SELECT
  MAX(IF(group_type = 'treated', delta_cvr, NULL))
    - MAX(IF(group_type = 'control', delta_cvr, NULL)) AS did_estimate,
  MAX(IF(group_type = 'treated', cvr_pre,  NULL)) AS treated_cvr_pre,
  MAX(IF(group_type = 'treated', cvr_post, NULL)) AS treated_cvr_post,
  MAX(IF(group_type = 'control', cvr_pre,  NULL)) AS control_cvr_pre,
  MAX(IF(group_type = 'control', cvr_post, NULL)) AS control_cvr_post
FROM diff
```

### 285. ECサイトのサイト速度がCVRに与える影響をBigQueryのCrUXデータで検証する（GA4のBigQueryエクスポートでCVRを算出するSQL）

**用途**: GA4のBigQueryエクスポートでCVRを算出するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です / `SELECT *` を含みます。必要な列だけに絞るとコストが下がります

```sql
WITH sessions AS (
  SELECT
    -- ga_session_idはUNNEST経由で取得
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id,
    user_pseudo_id,
    -- 流入元はcollected_traffic_sourceから取得
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source  AS source,
    -- 購入フラグ（purchaseイベントが存在するセッションを1とする）
    MAX(IF(event_name = 'purchase', 1, 0)) AS is_converted,
    COUNT(DISTINCT event_name)             AS event_count
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240701' AND '20240731'
  GROUP BY
    session_id,
    user_pseudo_id,
    medium,
    source
),

cvr_by_channel AS (
  SELECT
    medium,
    source,
    COUNT(*)                                  AS total_sessions,
    SUM(is_converted)                         AS converted_sessions,
    ROUND(SUM(is_converted) / COUNT(*), 4)    AS cvr
  FROM sessions
  WHERE session_id IS NOT NULL
  GROUP BY medium, source
  ORDER BY total_sessions DESC
)

SELECT * FROM cvr_by_channel;
```

### 286. Shopifyのチェックアウト拡張機能のイベントをGA4×BigQueryで分析する（BigQueryでチェックアウトイベントを集計するSQL）

**用途**: BigQueryでチェックアウトイベントを集計するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH base AS (
  SELECT
    event_date,
    event_name,
    -- ga_session_idはevent_paramsをUNNESTして取得する
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id,
    -- チェックアウトステップ（カスタムパラメータ）を取得
    (
      SELECT ep.value.string_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'checkout_step'
    ) AS checkout_step,
    -- 流入元はcollected_traffic_sourceから取得
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250131'
    AND event_name = 'checkout_step_reached'
)

SELECT
  event_date,
  checkout_step,
  medium,
  source,
  COUNT(DISTINCT ga_session_id) AS sessions,
  COUNT(*) AS event_count
FROM base
GROUP BY
  event_date,
  checkout_step,
  medium,
  source
ORDER BY
  event_date,
  checkout_step;
```

### 287. Shopifyのチェックアウト拡張機能のイベントをGA4×BigQueryで分析する（ファネル分析でボトルネックを特定する）

**用途**: ファネル分析でボトルネックを特定する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH step_sessions AS (
  SELECT
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id,
    (
      SELECT ep.value.string_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'checkout_step'
    ) AS checkout_step
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250131'
    AND event_name = 'checkout_step_reached'
),

funnel AS (
  SELECT
    COUNTIF(checkout_step = 'delivery_address') AS step1_delivery,
    COUNTIF(checkout_step = 'shipping_method')  AS step2_shipping,
    COUNTIF(checkout_step = 'payment')          AS step3_payment,
    COUNTIF(checkout_step = 'review')           AS step4_review
  FROM (
    SELECT ga_session_id, checkout_step
    FROM step_sessions
    GROUP BY ga_session_id, checkout_step
  )
)

SELECT
  step1_delivery,
  step2_shipping,
  ROUND(step2_shipping / NULLIF(step1_delivery, 0) * 100, 1) AS step1_to_step2_pct,
  step3_payment,
  ROUND(step3_payment / NULLIF(step2_shipping, 0) * 100, 1) AS step2_to_step3_pct,
  step4_review,
  ROUND(step4_review / NULLIF(step3_payment, 0) * 100, 1) AS step3_to_step4_pct
FROM funnel;
```

### 288. 定期購入ECの解約予兆をGA4行動ログから検知するBigQueryモデル（解約予兆シグナルとなる行動パターンを定義する）

**用途**: 解約予兆シグナルとなる行動パターンを定義する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH raw_events AS (
  SELECT
    user_pseudo_id,
    (SELECT value.string_value
     FROM UNNEST(event_params)
     WHERE key = 'page_location') AS page_location,
    event_name,
    event_date
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY))
      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
    AND event_name = 'page_view'
)

SELECT
  user_pseudo_id,
  COUNTIF(page_location LIKE '%/cancel%' OR page_location LIKE '%/unsubscribe%')
    AS cancel_page_views,
  COUNTIF(page_location LIKE '%/mypage%')
    AS mypage_views,
  COUNTIF(page_location LIKE '%/help%' OR page_location LIKE '%/faq%')
    AS help_page_views,
  COUNT(DISTINCT event_date) AS active_days
FROM raw_events
GROUP BY user_pseudo_id
```

### 289. 定期購入ECの解約予兆をGA4行動ログから検知するBigQueryモデル（解約予兆スコアをSQLで算出する）

**用途**: 解約予兆スコアをSQLで算出する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH behavior_signals AS (
  -- （前述のCTEを再利用）
  SELECT
    user_pseudo_id,
    COUNTIF(page_location LIKE '%/cancel%' OR page_location LIKE '%/unsubscribe%')
      AS cancel_page_views,
    COUNTIF(page_location LIKE '%/mypage%')
      AS mypage_views,
    COUNTIF(page_location LIKE '%/help%' OR page_location LIKE '%/faq%')
      AS help_page_views,
    COUNT(DISTINCT event_date) AS active_days
  FROM (
    SELECT
      user_pseudo_id,
      (SELECT value.string_value
       FROM UNNEST(event_params)
       WHERE key = 'page_location') AS page_location,
      event_date
    FROM
      `${PROJECT}.${DATASET}.events_*`
    WHERE
      _TABLE_SUFFIX BETWEEN
        FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY))
        AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
      AND event_name = 'page_view'
  )
  GROUP BY user_pseudo_id
)

SELECT
  user_pseudo_id,
  cancel_page_views,
  mypage_views,
  help_page_views,
  active_days,
  -- スコアリング（重みは要チューニング）
  ROUND(
    (cancel_page_views * 40)
    + (GREATEST(0, 5 - active_days) * 5)
    + (help_page_views * 3)
    + (GREATEST(0, 10 - mypage_views) * 2)
  , 1) AS churn_risk_score
FROM behavior_signals
ORDER BY churn_risk_score DESC
```

### 290. ECの商品ページ写真枚数×CVRの相関をGA4×BigQueryで検証した（写真枚数データとのJOIN：相関を可視化する）

**用途**: 写真枚数データとのJOIN：相関を可視化する

**必要なテーブル**: `${DATASET}.events_*`, `${DATASET}.photo_master`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH photo_master AS (
  SELECT
    product_url,
    photo_count
  FROM
    `${PROJECT}.${DATASET}.photo_master`
),

-- ここから cvr_base：前セクションのCVR集計をそのまま取り込む
product_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id,
    (SELECT value.string_value
     FROM UNNEST(event_params)
     WHERE key = 'page_location') AS page_location
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250630'
    AND event_name = 'page_view'
    AND (SELECT value.string_value
         FROM UNNEST(event_params)
         WHERE key = 'page_location') LIKE '%/products/%'
),

purchase_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250630'
    AND event_name = 'purchase'
),

cvr_base AS (
  SELECT
    ps.page_location,
    COUNT(DISTINCT CONCAT(ps.user_pseudo_id, CAST(ps.session_id AS STRING))) AS total_sessions,
    COUNT(DISTINCT
      CASE WHEN pur.session_id IS NOT NULL
      THEN CONCAT(ps.user_pseudo_id, CAST(ps.session_id AS STRING))
      END
    ) AS purchase_sessions,
    ROUND(
      SAFE_DIVIDE(
        COUNT(DISTINCT
          CASE WHEN pur.session_id IS NOT NULL
          THEN CONCAT(ps.user_pseudo_id, CAST(ps.session_id AS STRING))
          END
        ),
        COUNT(DISTINCT CONCAT(ps.user_pseudo_id, CAST(ps.session_id AS STRING)))
      ) * 100, 2
    ) AS cvr_pct
  FROM
    product_sessions ps
  LEFT JOIN
    purchase_sessions pur
    ON ps.user_pseudo_id = pur.user_pseudo_id
    AND ps.session_id = pur.session_id
  GROUP BY
    ps.page_location
)

SELECT
  pm.photo_count,
  COUNT(*) AS product_count,
  ROUND(AVG(cb.cvr_pct), 2) AS avg_cvr_pct,
  ROUND(MIN(cb.cvr_pct), 2) AS min_cvr_pct,
  ROUND(MAX(cb.cvr_pct), 2) AS max_cvr_pct
FROM
  cvr_base cb
LEFT JOIN
  photo_master pm
  ON cb.page_location LIKE CONCAT('%', pm.product_url, '%')
WHERE
  pm.photo_count IS NOT NULL
  AND cb.total_sessions >= 30  -- 統計的に意味のある最低セッション数
GROUP BY
  pm.photo_count
ORDER BY
  pm.photo_count ASC
```

### 291. ECの返品率をGA4×BigQueryで商品カテゴリ別に分析して原因を特定した（BigQueryで商品カテゴリ別の返品率を集計するSQL）

**用途**: BigQueryで商品カテゴリ別の返品率を集計するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH
-- 購入イベントをカテゴリ別に集計
purchases AS (
  SELECT
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_category') AS item_category,
    COUNT(*) AS purchase_count
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20240731'
    AND event_name = 'purchase'
  GROUP BY
    item_category
),

-- 返品イベントをカテゴリ別に集計
returns AS (
  SELECT
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_category') AS item_category,
    COUNT(*) AS return_count
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20240731'
    AND event_name = 'return_request_complete'
  GROUP BY
    item_category
)

SELECT
  p.item_category,
  p.purchase_count,
  COALESCE(r.return_count, 0) AS return_count,
  ROUND(SAFE_DIVIDE(COALESCE(r.return_count, 0), p.purchase_count) * 100, 2) AS return_rate_pct
FROM
  purchases p
LEFT JOIN
  returns r ON p.item_category = r.item_category
WHERE
  p.item_category IS NOT NULL
ORDER BY
  return_rate_pct DESC
;
```

### 292. ECの返品率をGA4×BigQueryで商品カテゴリ別に分析して原因を特定した（返品率が高いカテゴリの流入元を深掘りする）

**用途**: 返品率が高いカテゴリの流入元を深掘りする

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH
purchases AS (
  SELECT
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_category') AS item_category,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'order_id') AS order_id
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20240731'
    AND event_name = 'purchase'
),

returns AS (
  SELECT
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'order_id') AS order_id
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20240731'
    AND event_name = 'return_request_complete'
)

SELECT
  p.item_category,
  p.medium,
  p.source,
  COUNT(DISTINCT p.order_id) AS purchase_count,
  COUNT(DISTINCT r.order_id) AS return_count,
  ROUND(
    SAFE_DIVIDE(COUNT(DISTINCT r.order_id), COUNT(DISTINCT p.order_id)) * 100, 2
  ) AS return_rate_pct
FROM
  purchases p
LEFT JOIN
  returns r ON p.order_id = r.order_id
WHERE
  p.item_category IN ('shoes', 'outerwear')   -- 返品率が高いカテゴリに絞る
  AND p.item_category IS NOT NULL
GROUP BY
  p.item_category, p.medium, p.source
ORDER BY
  p.item_category, return_rate_pct DESC
;
```

### 293. GA4×BigQueryでECクーポン施策のカニバリゼーションを検証する（ステップ1：クーポン利用有無別の購入数と売上を流入元ごとに集計する）

**用途**: ステップ1：クーポン利用有無別の購入数と売上を流入元ごとに集計する

**必要なテーブル**: `${DATASET}.events_20250801`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
WITH purchase_events AS (
  SELECT
    user_pseudo_id,
    -- ga_session_id は UNNEST 経由で取得（直接参照不可）
    (SELECT value.int_value
       FROM UNNEST(event_params)
      WHERE key = 'ga_session_id') AS session_id,
    -- クーポンコードも同様に取得
    (SELECT value.string_value
       FROM UNNEST(event_params)
      WHERE key = 'coupon') AS coupon_code,
    (SELECT value.double_value
       FROM UNNEST(event_params)
      WHERE key = 'value') AS purchase_value,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source  AS source
  FROM
    `${PROJECT}.${DATASET}.events_20250801`
  WHERE
    event_name = 'purchase'
)

SELECT
  CASE
    WHEN coupon_code IS NOT NULL AND coupon_code != ''
    THEN 'クーポン使用'
    ELSE 'クーポン未使用'
  END AS coupon_flag,
  medium,
  source,
  COUNT(*)                        AS purchase_count,
  ROUND(SUM(purchase_value), 0)   AS total_revenue
FROM purchase_events
GROUP BY coupon_flag, medium, source
ORDER BY total_revenue DESC;
```

### 294. 2024年問題に備えるデータ基盤―配送コストをBigQueryで最適化する（商品カテゴリ別の配送コスト分析で値付けを見直す）

**用途**: 商品カテゴリ別の配送コスト分析で値付けを見直す

**必要なテーブル**: `${DATASET}.orders`, `${DATASET}.products`, `${DATASET}.shipping_costs`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  p.category                                              AS product_category,
  COUNT(DISTINCT o.order_id)                              AS order_count,
  ROUND(SUM(o.revenue), 0)                               AS total_revenue,
  ROUND(SUM(o.cost_of_goods), 0)                         AS total_cogs,
  ROUND(SUM(s.shipping_cost), 0)                         AS total_shipping_cost,
  ROUND(SUM(o.revenue - o.cost_of_goods - s.shipping_cost), 0) AS actual_profit,
  ROUND(
    SUM(o.revenue - o.cost_of_goods - s.shipping_cost)
    / NULLIF(SUM(o.revenue), 0) * 100, 1
  )                                                       AS actual_margin_pct
FROM
  `${PROJECT}.${DATASET}.orders`          AS o
  LEFT JOIN `${PROJECT}.${DATASET}.products`       AS p
    ON o.product_id = p.product_id
  LEFT JOIN `${PROJECT}.${DATASET}.shipping_costs` AS s
    ON o.order_id = s.order_id
WHERE
  o.order_date BETWEEN '2026-01-01' AND '2026-07-31'
GROUP BY
  product_category
ORDER BY
  actual_margin_pct ASC
```

### 295. Amazon広告とGA4自社ECデータをBigQueryで統合してチャネルミックスを最適化する（GA4のBigQueryエクスポートデータでチャネル別売上を集計する）

**用途**: GA4のBigQueryエクスポートデータでチャネル別売上を集計する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_date,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.int_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases,
  SUM(
    CASE
      WHEN event_name = 'purchase'
      THEN (
        SELECT value.double_value
        FROM UNNEST(event_params) AS ep
        WHERE ep.key = 'value'
      )
      ELSE 0
    END
  ) AS revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20250131'
GROUP BY
  event_date,
  medium,
  source
ORDER BY
  event_date,
  revenue DESC
```

### 296. BASE・STORES・ShopifyのGA4計測精度を比較検証した【2026年版】（Shopify：GA4計測の拡張性は最も高いが設定コストも高い）

**用途**: Shopify：GA4計測の拡張性は最も高いが設定コストも高い

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
  ) AS sessions,
  COUNT(*) AS purchase_events,
  SUM(
    (SELECT value.double_value
     FROM UNNEST(event_params)
     WHERE key = 'value')
  ) AS total_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20260701' AND '20260731'
  AND event_name = 'purchase'
GROUP BY
  medium, source
ORDER BY
  total_revenue DESC
```

### 297. 越境ECのGA4多言語計測をBigQueryで国別に正確に集計する方法（多言語サイトにおける注意点とデータ品質の改善方法）

**用途**: 多言語サイトにおける注意点とデータ品質の改善方法

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  geo.country AS country,
  REGEXP_EXTRACT(
    (SELECT ep.value.string_value FROM UNNEST(event_params) AS ep WHERE ep.key = 'page_location'),
    r'https?://[^/]+/([a-z]{2})(?:-[a-z]{2})?/'
  ) AS lang_path,
  device.language AS browser_language,
  COUNT(*) AS event_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250731'
  AND event_name = 'page_view'
GROUP BY
  country,
  lang_path,
  browser_language
ORDER BY
  event_count DESC;
```

### 298. ECの送料無料ラインをBigQueryの購買データから最適設定する分析手法（送料無料ライン変更のA/Bテスト設計と効果測定）

**用途**: 送料無料ライン変更のA/Bテスト設計と効果測定

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  (
    SELECT ep.value.string_value
    FROM UNNEST(event_params) AS ep
    WHERE ep.key = 'ab_variant'
  ) AS variant,
  COUNT(*) AS purchase_count,
  ROUND(AVG(
    (
      SELECT COALESCE(ep.value.int_value, ep.value.float_value, ep.value.double_value)
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'value'
    )
  ), 0) AS avg_order_value
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240901' AND '20240930'
  AND event_name = 'purchase'
GROUP BY
  variant
```

### 299. ECのギフト需要をGA4×BigQueryで時系列分析して在庫計画に反映する（流入元別にギフト購入者の行動を分析する）

**用途**: 流入元別にギフト購入者の行動を分析する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  EXTRACT(MONTH FROM PARSE_DATE('%Y%m%d', event_date)) AS month,
  COUNT(DISTINCT (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'transaction_id')) AS order_count,
  SUM((SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'value')) AS total_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
  AND event_name = 'purchase'
GROUP BY
  medium,
  source,
  month
ORDER BY
  month,
  order_count DESC
```

### 300. ECの在庫回転率をGA4×BigQueryで商品別に可視化して死に筋を特定する（GA4のBigQueryエクスポートから商品別販売数量を取得するSQL）

**用途**: GA4のBigQueryエクスポートから商品別販売数量を取得するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  item.item_id                          AS product_id,
  item.item_name                        AS product_name,
  SUM(item.quantity)                    AS total_quantity_sold,
  ROUND(SUM(item.item_revenue), 2)      AS total_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`,
  UNNEST(items) AS item
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'purchase'
  AND item.quantity > 0
GROUP BY
  product_id,
  product_name
ORDER BY
  total_quantity_sold DESC
;
```

### 301. ECの在庫回転率をGA4×BigQueryで商品別に可視化して死に筋を特定する（流入チャネル別に死に筋を掘り下げる）

**用途**: 流入チャネル別に死に筋を掘り下げる

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  collected_traffic_source.manual_medium   AS medium,
  collected_traffic_source.manual_source   AS source,
  item.item_id                             AS product_id,
  item.item_name                           AS product_name,
  SUM(item.quantity)                       AS total_quantity_sold
FROM
  `${PROJECT}.${DATASET}.events_*`,
  UNNEST(items) AS item
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'purchase'
  AND item.quantity > 0
GROUP BY
  medium,
  source,
  product_id,
  product_name
ORDER BY
  product_id,
  total_quantity_sold DESC
;
```

### 302. ECのセール施策効果をGA4×BigQueryでbefore/after比較する分析テンプレート（SQLテンプレート：セール前後の主要KPIを比較する）

**用途**: SQLテンプレート：セール前後の主要KPIを比較する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH
-- 期間ラベルを付与するベーステーブル
base AS (
  SELECT
    event_date,
    event_name,
    CASE
      WHEN event_date BETWEEN '20250601' AND '20250614' THEN 'before'
      WHEN event_date BETWEEN '20250615' AND '20250621' THEN 'during'
      WHEN event_date BETWEEN '20250622' AND '20250705' THEN 'after'
      ELSE NULL
    END AS period,
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id,
    (SELECT value.double_value
     FROM UNNEST(event_params)
     WHERE key = 'value') AS purchase_value
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250705'
),

-- セッション単位に集約
sessions AS (
  SELECT
    period,
    session_id,
    COUNTIF(event_name = 'purchase') AS purchase_count,
    SUM(IF(event_name = 'purchase', purchase_value, 0)) AS revenue
  FROM base
  WHERE period IS NOT NULL
    AND session_id IS NOT NULL
  GROUP BY period, session_id
)

-- 期間別KPIの集計
SELECT
  period,
  COUNT(DISTINCT session_id)                        AS sessions,
  SUM(purchase_count)                               AS purchases,
  ROUND(SUM(purchase_count) / COUNT(DISTINCT session_id) * 100, 2) AS conversion_rate_pct,
  ROUND(SUM(revenue), 0)                            AS total_revenue
FROM sessions
GROUP BY period
ORDER BY
  CASE period WHEN 'before' THEN 1 WHEN 'during' THEN 2 WHEN 'after' THEN 3 END
;
```

### 303. ECのセール施策効果をGA4×BigQueryでbefore/after比較する分析テンプレート（流入元別の効果測定：どのチャネルがセール集客に貢献したか）

**用途**: 流入元別の効果測定：どのチャネルがセール集客に貢献したか

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH
session_source AS (
  SELECT
    event_date,
    event_name,
    CASE
      WHEN event_date BETWEEN '20250615' AND '20250621' THEN 'during'
      ELSE NULL
    END AS period,
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    (SELECT value.double_value
     FROM UNNEST(event_params)
     WHERE key = 'value') AS purchase_value
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250615' AND '20250621'
),

sessions_agg AS (
  SELECT
    period,
    session_id,
    -- セッション最初の流入元を使用（first_valueで代替も可）
    MAX(medium) AS medium,
    MAX(source) AS source,
    COUNTIF(event_name = 'purchase') AS purchase_count,
    SUM(IF(event_name = 'purchase', purchase_value, 0)) AS revenue
  FROM session_source
  WHERE period IS NOT NULL
    AND session_id IS NOT NULL
  GROUP BY period, session_id
)

SELECT
  COALESCE(medium, '(none)')  AS medium,
  COALESCE(source, '(direct)') AS source,
  COUNT(DISTINCT session_id)   AS sessions,
  SUM(purchase_count)          AS purchases,
  ROUND(SUM(purchase_count) / COUNT(DISTINCT session_id) * 100, 2) AS cvr_pct,
  ROUND(SUM(revenue), 0)       AS revenue
FROM sessions_agg
GROUP BY medium, source
ORDER BY revenue DESC
LIMIT 20
;
```

### 304. Shopify × GA4のエコマース計測でデータが合わない問題を徹底解決する（transaction_idの重複を確認する）

**用途**: transaction_idの重複を確認する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  ep.value.string_value AS transaction_id,
  COUNT(*) AS send_count
FROM
  `${PROJECT}.${DATASET}.events_*`,
  UNNEST(event_params) AS ep
WHERE
  _TABLE_SUFFIX BETWEEN '20240601' AND '20240630'
  AND event_name = 'purchase'
  AND ep.key = 'transaction_id'
GROUP BY
  transaction_id
HAVING
  send_count > 1
ORDER BY
  send_count DESC
```

### 305. Shopify × GA4のエコマース計測でデータが合わない問題を徹底解決する（流入元別のpurchase数を確認する）

**用途**: 流入元別のpurchase数を確認する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  cs.manual_medium AS medium,
  cs.manual_source AS source,
  COUNT(*) AS purchase_count,
  SUM(ecommerce.purchase_revenue) AS revenue
FROM
  `${PROJECT}.${DATASET}.events_*` AS e
LEFT JOIN
  UNNEST([e.collected_traffic_source]) AS cs
WHERE
  _TABLE_SUFFIX BETWEEN '20240601' AND '20240630'
  AND e.event_name = 'purchase'
GROUP BY
  medium,
  source
ORDER BY
  purchase_count DESC
```

### 306. Shopify×GTM×GA4でカスタムピクセルを使った高精度エコマース計測を実装する

**用途**: GA4でのデータ確認とBigQueryでの分析クエリ

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  s.manual_medium AS medium,
  s.manual_source AS source,
  COUNT(DISTINCT ep_session.value.int_value) AS sessions,
  COUNT(DISTINCT CASE WHEN e.event_name = 'purchase' THEN e.user_pseudo_id END) AS purchasers,
  SUM(
    CASE WHEN e.event_name = 'purchase'
    THEN (
      SELECT ep.value.double_value
      FROM UNNEST(e.event_params) AS ep
      WHERE ep.key = 'value'
    )
    END
  ) AS total_revenue
FROM
  `${PROJECT}.${DATASET}.events_*` AS e,
  UNNEST(e.event_params) AS ep_session,
  UNNEST([e.collected_traffic_source]) AS s
WHERE
  ep_session.key = 'ga_session_id'
  AND _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
GROUP BY
  medium, source
ORDER BY
  total_revenue DESC;
```

### 307. 定期購入ECの解約予兆をGA4行動ログから検知するBigQueryモデル（流入チャネル別に解約リスクを分析する）

**用途**: 流入チャネル別に解約リスクを分析する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  collected_traffic_source.manual_medium AS traffic_medium,
  collected_traffic_source.manual_source AS traffic_source,
  COUNT(DISTINCT user_pseudo_id) AS user_count,
  AVG(
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')
  ) AS avg_session_count,
  COUNTIF(
    EXISTS(
      SELECT 1
      FROM UNNEST(event_params) ep
      WHERE ep.key = 'page_location'
        AND ep.value.string_value LIKE '%/cancel%'
    )
  ) AS users_with_cancel_view
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY
  traffic_medium,
  traffic_source
ORDER BY
  users_with_cancel_view DESC
```

### 308. ECのCS問い合わせデータをBigQueryに集約して商品改善に活かす方法（問い合わせカテゴリ別・商品別の集計SQL）

**用途**: 問い合わせカテゴリ別・商品別の集計SQL

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  product_sku,
  category,
  COUNT(*) AS inquiry_count,
  COUNTIF(LOWER(category) LIKE '%return%' OR LOWER(category) LIKE '%返品%') AS return_count,
  COUNTIF(LOWER(category) LIKE '%defect%' OR LOWER(category) LIKE '%不良%') AS defect_count
FROM
  `your_project.cs_dataset.tickets`
WHERE
  DATE(created_at) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY) AND CURRENT_DATE()
GROUP BY
  product_sku,
  category
ORDER BY
  inquiry_count DESC
LIMIT 50
```

### 309. EC事業の粗利率をBigQueryで商品×チャネル別に自動計算する仕組み（BigQueryで流入チャネルと購入を紐づけるSQL）

**用途**: BigQueryで流入チャネルと購入を紐づけるSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH session_source AS (
  SELECT
    -- ga_session_idはevent_params経由で取得
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id,
    user_pseudo_id,
    -- 流入元はcollected_traffic_sourceを使用
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    event_date
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'session_start'
),

purchase_events AS (
  SELECT
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id,
    user_pseudo_id,
    (
      SELECT ep.value.string_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'transaction_id'
    ) AS transaction_id,
    (
      SELECT ep.value.double_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'value'
    ) AS revenue,
    event_date
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
)

SELECT
  ss.medium,
  ss.source,
  pe.transaction_id,
  pe.revenue,
  pe.event_date
FROM
  purchase_events AS pe
LEFT JOIN
  session_source AS ss
  ON pe.ga_session_id = ss.ga_session_id
  AND pe.user_pseudo_id = ss.user_pseudo_id
WHERE
  pe.transaction_id IS NOT NULL
```

### 310. ECの商品ページ写真枚数×CVRの相関をGA4×BigQueryで検証した（BigQueryでのセッションCVR集計SQL）

**用途**: BigQueryでのセッションCVR集計SQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH
-- セッションIDをUNNESTで取得し、商品ページのセッションを抽出
product_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id,
    (SELECT value.string_value
     FROM UNNEST(event_params)
     WHERE key = 'page_location') AS page_location
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250630'
    AND event_name = 'page_view'
    AND (SELECT value.string_value
         FROM UNNEST(event_params)
         WHERE key = 'page_location') LIKE '%/products/%'
),

-- 購入が発生したセッションを抽出
purchase_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250630'
    AND event_name = 'purchase'
)

-- 商品URLごとにセッションCVRを算出
SELECT
  ps.page_location,
  COUNT(DISTINCT CONCAT(ps.user_pseudo_id, CAST(ps.session_id AS STRING))) AS total_sessions,
  COUNT(DISTINCT
    CASE WHEN pur.session_id IS NOT NULL
    THEN CONCAT(ps.user_pseudo_id, CAST(ps.session_id AS STRING))
    END
  ) AS purchase_sessions,
  ROUND(
    SAFE_DIVIDE(
      COUNT(DISTINCT
        CASE WHEN pur.session_id IS NOT NULL
        THEN CONCAT(ps.user_pseudo_id, CAST(ps.session_id AS STRING))
        END
      ),
      COUNT(DISTINCT CONCAT(ps.user_pseudo_id, CAST(ps.session_id AS STRING)))
    ) * 100, 2
  ) AS cvr_pct
FROM
  product_sessions ps
LEFT JOIN
  purchase_sessions pur
  ON ps.user_pseudo_id = pur.user_pseudo_id
  AND ps.session_id = pur.session_id
GROUP BY
  ps.page_location
ORDER BY
  total_sessions DESC
```

### 311. BigQueryでEC受注データ×GA4データを結合して正確な売上帰属分析をする（GA4データと受注データを結合するSQL）

**用途**: GA4データと受注データを結合するSQL

**必要なテーブル**: `${DATASET}.ec_orders`, `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH
-- 受注が発生したセッションのGA4情報を取得
ga4_sessions AS (
  SELECT
    user_pseudo_id,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,
    collected_traffic_source.manual_source AS traffic_source,
    collected_traffic_source.manual_medium AS traffic_medium,
    collected_traffic_source.manual_campaign_name AS campaign_name,
    MIN(event_timestamp) AS session_start_at
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20260101' AND '20260131'
    AND event_name = 'session_start'
  GROUP BY
    user_pseudo_id,
    ga_session_id,
    traffic_source,
    traffic_medium,
    campaign_name
),

-- 確定済み受注のみを対象にする
confirmed_orders AS (
  SELECT
    order_id,
    user_pseudo_id,
    ga_session_id,
    order_amount,
    ordered_at
  FROM
    `${PROJECT}.${DATASET}.ec_orders`
  WHERE
    order_status = 'confirmed'
    AND DATE(ordered_at) BETWEEN '2026-01-01' AND '2026-01-31'
)

-- 受注と流入元を結合して集計
SELECT
  COALESCE(s.traffic_source, '(direct)')   AS traffic_source,
  COALESCE(s.traffic_medium, '(none)')     AS traffic_medium,
  COALESCE(s.campaign_name, '(not set)')   AS campaign_name,
  COUNT(o.order_id)                        AS order_count,
  SUM(o.order_amount)                      AS total_revenue,
  ROUND(AVG(o.order_amount), 0)            AS avg_order_value
FROM
  confirmed_orders AS o
LEFT JOIN
  ga4_sessions AS s
  ON  o.user_pseudo_id = s.user_pseudo_id
  AND o.ga_session_id  = s.ga_session_id
GROUP BY
  traffic_source,
  traffic_medium,
  campaign_name
ORDER BY
  total_revenue DESC
```

### 312. ECのギフト需要をGA4×BigQueryで時系列分析して在庫計画に反映する（月別・週別の売上推移をBigQueryで時系列分析する）

**用途**: 月別・週別の売上推移をBigQueryで時系列分析する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), WEEK(MONDAY)) AS week_start,
  COUNT(DISTINCT (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'transaction_id')) AS order_count,
  SUM((SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'value')) AS total_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
  AND event_name = 'purchase'
GROUP BY
  week_start
ORDER BY
  week_start
```

### 313. Shopify × GA4のエコマース計測でデータが合わない問題を徹底解決する（日別のpurchaseイベント件数と売上を確認する）

**用途**: 日別のpurchaseイベント件数と売上を確認する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo') AS event_date,
  COUNT(*) AS purchase_count,
  SUM(ecommerce.purchase_revenue) AS total_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240601' AND '20240630'
  AND event_name = 'purchase'
GROUP BY
  event_date
ORDER BY
  event_date
```

### 314. ShopifyのWebhook × Cloud Functions × BigQueryでリアルタイム売上基盤を作る（BigQueryで売上を集計・分析する） その1

**用途**: BigQueryで売上を集計・分析する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  ep.value.string_value AS ga_session_id,
  t.manual_medium       AS medium,
  t.manual_source       AS source,
  COUNT(*)              AS sessions
FROM
  `${PROJECT}.${DATASET}.events_*`,
  UNNEST(event_params) AS ep
JOIN UNNEST([collected_traffic_source]) AS t
WHERE
  ep.key = 'ga_session_id'
  AND _TABLE_SUFFIX BETWEEN '20260701' AND '20260731'
GROUP BY
  ga_session_id, medium, source;
```

### 315. BASE・STORES・ShopifyのGA4計測精度を比較検証した【2026年版】（GA4計測の精度を高めるための共通対策）

**用途**: GA4計測の精度を高めるための共通対策

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id,
      '-',
      CAST(
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
        AS STRING
      )
    )
  ) AS unique_sessions
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20260701' AND '20260731'
```

### 316. ECのCS問い合わせデータをBigQueryに集約して商品改善に活かす方法（GA4データと組み合わせて購入〜問い合わせの流れを把握する）

**用途**: GA4データと組み合わせて購入〜問い合わせの流れを把握する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  user_pseudo_id,
  event_date,
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_id'
  ) AS ga_session_id,
  collected_traffic_source.manual_medium AS traffic_medium,
  collected_traffic_source.manual_source AS traffic_source,
  (
    SELECT value.string_value
    FROM UNNEST(event_params)
    WHERE key = 'transaction_id'
  ) AS transaction_id
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  AND event_name = 'purchase'
```

### 317. ECの返品率をGA4×BigQueryで商品カテゴリ別に分析して原因を特定した（LookerStudioでダッシュボード化して継続モニタリング）

**用途**: LookerStudioでダッシュボード化して継続モニタリング

**必要なテーブル**: `${DATASET}.events_*`, `${DATASET}.v_return_rate_by_category`

**コストの注意**: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください

```sql
CREATE OR REPLACE VIEW `${PROJECT}.${DATASET}.v_return_rate_by_category` AS
SELECT
  FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m%d', event_date)) AS month,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_category') AS item_category,
  COUNT(*) AS purchase_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  event_name = 'purchase'
GROUP BY
  month, item_category
;
```

### 318. 2024年問題に備えるデータ基盤―配送コストをBigQueryで最適化する（流入経路別・配送コスト分析のSQLサンプル） その2

**用途**: 流入経路別・配送コスト分析のSQLサンプル

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_date,
  -- ga_session_idはevent_paramsをUNNESTして取得する
  (
    SELECT ep.value.int_value
    FROM UNNEST(event_params) AS ep
    WHERE ep.key = 'ga_session_id'
  ) AS session_id,
  -- 流入元はcollected_traffic_sourceから取得する
  collected_traffic_source.manual_medium  AS traffic_medium,
  collected_traffic_source.manual_source  AS traffic_source,
  -- ecommerce情報
  ecommerce.purchase_revenue             AS revenue,
  (
    SELECT ep.value.string_value
    FROM UNNEST(event_params) AS ep
    WHERE ep.key = 'transaction_id'
  ) AS transaction_id
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20260101' AND '20260731'
  AND event_name = 'purchase'
```

### 319. ShopifyのWebhook × Cloud Functions × BigQueryでリアルタイム売上基盤を作る（BigQueryで売上を集計・分析する） その2

**用途**: BigQueryで売上を集計・分析する

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  DATE(TIMESTAMP(created_at)) AS order_date,
  COUNT(DISTINCT order_id)   AS order_count,
  ROUND(SUM(total_price), 0) AS total_revenue,
  currency
FROM
  `your-project-id.shopify_raw.orders`
WHERE
  financial_status = 'paid'
  AND DATE(TIMESTAMP(created_at)) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY
  order_date, currency
ORDER BY
  order_date DESC;
```

### 320. 定期購入ECの解約予兆をGA4行動ログから検知するBigQueryモデル（GA4×BigQueryエクスポートの基本構造を理解する）

**用途**: GA4×BigQueryエクスポートの基本構造を理解する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  user_pseudo_id,
  -- ga_session_idはevent_paramsをUNNESTして取得
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_id') AS ga_session_id,
  event_name,
  collected_traffic_source.manual_medium AS traffic_medium,
  collected_traffic_source.manual_source AS traffic_source,
  event_date
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
```

### 321. BigQueryでEC受注データ×GA4データを結合して正確な売上帰属分析をする（データ構造を理解する：GA4のBigQueryエクスポートとは）

**用途**: データ構造を理解する：GA4のBigQueryエクスポートとは

**必要なテーブル**: `${DATASET}.events_20260101`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  user_pseudo_id,
  -- ga_session_idはevent_paramsをUNNESTして取得する
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_id'
  ) AS ga_session_id,
  -- 流入元はcollected_traffic_sourceから取得
  collected_traffic_source.manual_source     AS traffic_source,
  collected_traffic_source.manual_medium     AS traffic_medium,
  collected_traffic_source.manual_campaign_name AS campaign_name,
  event_timestamp,
  event_name
FROM
  `${PROJECT}.${DATASET}.events_20260101`
WHERE
  event_name = 'session_start'
```

### 322. ECサイトのサイト速度がCVRに与える影響をBigQueryのCrUXデータで検証する（BigQueryでCrUXデータを取得するSQL）

**用途**: BigQueryでCrUXデータを取得するSQL

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  origin,
  -- LCP（良好・要改善・不良の割合）
  ROUND(
    (SELECT value FROM UNNEST(largest_contentful_paint.histogram.bin)
     WHERE start < 2500 LIMIT 1), 4
  ) AS lcp_good_ratio,
  ROUND(
    (SELECT value FROM UNNEST(largest_contentful_paint.histogram.bin)
     WHERE start >= 2500 AND start < 4000 LIMIT 1), 4
  ) AS lcp_needs_improvement_ratio,
  ROUND(
    (SELECT value FROM UNNEST(largest_contentful_paint.histogram.bin)
     WHERE start >= 4000 LIMIT 1), 4
  ) AS lcp_poor_ratio,
  -- LCP中央値
  largest_contentful_paint.percentiles.p75 AS lcp_p75_ms,
  -- FCP中央値
  first_contentful_paint.percentiles.p75 AS fcp_p75_ms
FROM
  `chrome-ux-report.country_jp.202407`
WHERE
  origin = 'https://your-ec-site.com'  -- 自社ドメインに変更
```

### 323. ECサイトのサイト速度がCVRに与える影響をBigQueryのCrUXデータで検証する（CrUXとGA4データを組み合わせた分析アプローチ） その1

**用途**: CrUXとGA4データを組み合わせた分析アプローチ

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  PARSE_DATE('%Y%m', CAST(yyyymm AS STRING)) AS month,
  largest_contentful_paint.percentiles.p75   AS lcp_p75_ms
FROM (
  SELECT 202405 AS yyyymm, largest_contentful_paint
  FROM `chrome-ux-report.country_jp.202405`
  WHERE origin = 'https://your-ec-site.com'
  UNION ALL
  SELECT 202406, largest_contentful_paint
  FROM `chrome-ux-report.country_jp.202406`
  WHERE origin = 'https://your-ec-site.com'
  UNION ALL
  SELECT 202407, largest_contentful_paint
  FROM `chrome-ux-report.country_jp.202407`
  WHERE origin = 'https://your-ec-site.com'
)
ORDER BY month;
```

### 324. 楽天・Amazon・自社ECの売上データをBigQueryに集約して一元管理する方法（BigQuery上でデータを統合するテーブル設計）

**用途**: BigQuery上でデータを統合するテーブル設計

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
CREATE OR REPLACE VIEW `your_project.ec_dataset.unified_sales` AS

-- 楽天市場の売上データ
SELECT
  '楽天市場'                              AS channel,
  PARSE_DATE('%Y%m%d', order_date_str)   AS order_date,
  order_id,
  item_id                                 AS product_id,
  item_name                               AS product_name,
  unit_price                              AS price,
  quantity,
  unit_price * quantity                   AS revenue,
  shipping_fee,
  status
FROM `your_project.ec_dataset.rakuten_orders`

UNION ALL

-- Amazon の売上データ
SELECT
  'Amazon'                                AS channel,
  DATE(purchase_date)                     AS order_date,
  amazon_order_id                         AS order_id,
  asin                                    AS product_id,
  product_name,
  item_price                              AS price,
  quantity_ordered                        AS quantity,
  item_price * quantity_ordered           AS revenue,
  shipping_price                          AS shipping_fee,
  order_status                            AS status
FROM `your_project.ec_dataset.amazon_orders`

UNION ALL

-- 自社ECの売上データ
SELECT
  '自社EC'                                AS channel,
  DATE(created_at)                        AS order_date,
  CAST(id AS STRING)                      AS order_id,
  sku                                     AS product_id,
  product_name,
  price,
  quantity,
  price * quantity                        AS revenue,
  shipping_amount                         AS shipping_fee,
  order_status                            AS status
FROM `your_project.ec_dataset.mysite_orders`;
```

### 325. ECの商品ページ写真枚数×CVRの相関をGA4×BigQueryで検証した（流入元別に見る：オーガニックとSNSでCVRは変わるか）

**用途**: 流入元別に見る：オーガニックとSNSでCVRは変わるか

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_date,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_id') AS session_id,
  user_pseudo_id
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20250630'
  AND event_name = 'session_start'
```

### 326. ECサイトのサイト速度がCVRに与える影響をBigQueryのCrUXデータで検証する（CrUXとGA4データを組み合わせた分析アプローチ） その2

**用途**: CrUXとGA4データを組み合わせた分析アプローチ

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  form_factor.name                           AS device_type,
  largest_contentful_paint.percentiles.p75   AS lcp_p75_ms
FROM
  `chrome-ux-report.country_jp.202407`
WHERE
  origin = 'https://your-ec-site.com'
  AND form_factor.name = 'phone'
```

### 327. ShopifyのWebhook × Cloud Functions × BigQueryでリアルタイム売上基盤を作る（BigQueryのテーブルを設計する）

**用途**: BigQueryのテーブルを設計する

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
CREATE TABLE IF NOT EXISTS `your-project-id.shopify_raw.orders` (
  order_id       STRING,
  total_price    FLOAT64,
  currency       STRING,
  email          STRING,
  financial_status STRING,
  created_at     STRING,
  ingested_at    TIMESTAMP
)
OPTIONS(
  description = "Shopify Webhookから取得した受注データ"
);
```

### 328. GTM × GA4でA/Bテスト結果を自動計測する仕組みを作る（バリアント別のコンバージョン率を算出）

**用途**: バリアント別のコンバージョン率を算出

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH test_users AS (
  SELECT
    user_pseudo_id,
    (SELECT value.string_value
     FROM UNNEST(event_params) WHERE key = 'ab_test_variant') AS variant
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'ab_test_impression'
    AND (SELECT value.string_value
         FROM UNNEST(event_params) WHERE key = 'ab_test_name') = 'cta_color_test_202603'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  GROUP BY user_pseudo_id, variant
),
conversions AS (
  SELECT DISTINCT user_pseudo_id
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
)
SELECT
  t.variant,
  COUNT(DISTINCT t.user_pseudo_id) AS total_users,
  COUNT(DISTINCT c.user_pseudo_id) AS converted_users,
  ROUND(
    COUNT(DISTINCT c.user_pseudo_id) / COUNT(DISTINCT t.user_pseudo_id) * 100, 2
  ) AS conversion_rate_pct
FROM test_users t
LEFT JOIN conversions c ON t.user_pseudo_id = c.user_pseudo_id
GROUP BY t.variant
ORDER BY t.variant
```

### 329. GTM × GA4でA/Bテスト結果を自動計測する仕組みを作る（統計的有意差の検証（Z検定））

**用途**: 統計的有意差の検証（Z検定）

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
WITH stats AS (
  -- 上記のクエリ結果を使用
  SELECT
    variant,
    COUNT(DISTINCT t.user_pseudo_id) AS n,
    COUNT(DISTINCT c.user_pseudo_id) AS x
  FROM test_users t
  LEFT JOIN conversions c ON t.user_pseudo_id = c.user_pseudo_id
  GROUP BY variant
),
ab AS (
  SELECT
    MAX(IF(variant = 'A', n, 0)) AS n_a,
    MAX(IF(variant = 'A', x, 0)) AS x_a,
    MAX(IF(variant = 'B', n, 0)) AS n_b,
    MAX(IF(variant = 'B', x, 0)) AS x_b
  FROM stats
)
SELECT
  x_a / n_a AS rate_a,
  x_b / n_b AS rate_b,
  (x_a + x_b) / (n_a + n_b) AS pooled_rate,
  (x_b / n_b - x_a / n_a) /
    SQRT(
      ((x_a + x_b) / (n_a + n_b)) *
      (1 - (x_a + x_b) / (n_a + n_b)) *
      (1.0 / n_a + 1.0 / n_b)
    ) AS z_score
FROM ab
```

### 330. GA4×GTMでサイト内検索キーワードを正しく計測する設定（検索後のコンバージョン率）

**用途**: 検索後のコンバージョン率

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH search_users AS (
  SELECT DISTINCT user_pseudo_id
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'view_search_results'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
),
purchase_users AS (
  SELECT DISTINCT user_pseudo_id
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
)
SELECT
  COUNT(s.user_pseudo_id) AS search_users,
  COUNT(p.user_pseudo_id) AS search_and_purchase_users,
  ROUND(COUNT(p.user_pseudo_id) / COUNT(s.user_pseudo_id) * 100, 2) AS conversion_rate
FROM search_users s
LEFT JOIN purchase_users p ON s.user_pseudo_id = p.user_pseudo_id
```

### 331. GA4×GTMでサイト内検索キーワードを正しく計測する設定（検索キーワードランキング）

**用途**: 検索キーワードランキング

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  (SELECT value.string_value
   FROM UNNEST(event_params) WHERE key = 'search_term') AS search_term,
  COUNT(*) AS search_count,
  COUNT(DISTINCT user_pseudo_id) AS unique_users
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  event_name = 'view_search_results'
  AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
GROUP BY
  search_term
ORDER BY
  search_count DESC
LIMIT 50
```

### 332. GTMでGA4のスクロール率・動画再生をイベント計測する方法

**用途**: BigQueryでのスクロールデータ分析例

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  (SELECT value.string_value
   FROM UNNEST(event_params) WHERE key = 'page_path') AS page_path,
  (SELECT value.string_value
   FROM UNNEST(event_params) WHERE key = 'scroll_percentage') AS scroll_pct,
  COUNT(DISTINCT user_pseudo_id) AS users
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  event_name = 'scroll_depth'
  AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
GROUP BY
  page_path, scroll_pct
ORDER BY
  page_path, CAST(scroll_pct AS INT64)
```

### 333. GA4移行後にデータが取れていない問題を解決するGTMデバッグ手順

**用途**: BigQueryエクスポートとGA4 UIのデータ差異

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_date,
  COUNT(*) AS event_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20260325' AND '20260329'
GROUP BY
  event_date
ORDER BY
  event_date
```

### 334. Looker Studio × BigQueryでEC売上ダッシュボードを1日で作る完全手順

**用途**: Step 1: ダッシュボード用のmartテーブルを作成する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
CREATE OR REPLACE VIEW `your_project.your_mart_dataset.mart_dashboard_daily` AS
WITH sessions AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS date,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium,
    device.category AS device_category,
    COUNT(DISTINCT CONCAT(user_pseudo_id, '-',
      (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id'))
    ) AS sessions
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  GROUP BY date, source, medium, device_category
),

purchases AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS date,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium,
    device.category AS device_category,
    COUNT(DISTINCT ecommerce.transaction_id) AS transactions,
    SUM(ecommerce.purchase_revenue) AS revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  GROUP BY date, source, medium, device_category
)

SELECT
  s.date,
  COALESCE(s.source, '(direct)') AS source,
  COALESCE(s.medium, '(none)') AS medium,
  s.device_category,
  s.sessions,
  COALESCE(p.transactions, 0) AS transactions,
  COALESCE(p.revenue, 0) AS revenue,
  SAFE_DIVIDE(COALESCE(p.transactions, 0), s.sessions) AS cvr,
  SAFE_DIVIDE(COALESCE(p.revenue, 0), COALESCE(p.transactions, 0)) AS aov
FROM sessions s
LEFT JOIN purchases p
  ON s.date = p.date
  AND COALESCE(s.source, '') = COALESCE(p.source, '')
  AND COALESCE(s.medium, '') = COALESCE(p.medium, '')
  AND s.device_category = p.device_category
ORDER BY s.date DESC;
```

### 335. BigQuery × Looker StudioでEC事業の月次KPIレポートを自動化した（mart層のKPIビュー）

**用途**: mart層のKPIビュー

**必要なテーブル**: `${DATASET}.events_*`, `${DATASET}.mart_monthly_kpi`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
CREATE OR REPLACE VIEW `${PROJECT}.${DATASET}.mart_monthly_kpi` AS
WITH sessions AS (
  SELECT
    DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), MONTH) AS month,
    CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    user_pseudo_id,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium,
    device.category AS device,
    MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) AS has_purchase,
    SUM(CASE WHEN event_name = 'purchase' THEN ecommerce.purchase_revenue ELSE 0 END) AS revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 13 MONTH))
  GROUP BY
    month, session_id, user_pseudo_id, source, medium, device
)

SELECT
  month,
  COUNT(DISTINCT session_id) AS sessions,
  COUNT(DISTINCT user_pseudo_id) AS users,
  SUM(has_purchase) AS purchases,
  SUM(revenue) AS revenue,
  SAFE_DIVIDE(SUM(has_purchase), COUNT(DISTINCT session_id)) AS cvr,
  SAFE_DIVIDE(SUM(revenue), COUNT(DISTINCT session_id)) AS revenue_per_session,
  SAFE_DIVIDE(SUM(revenue), SUM(has_purchase)) AS avg_order_value
FROM
  sessions
GROUP BY
  month
ORDER BY
  month DESC
```

### 336. BigQuery × Looker Studioで前年同期比グラフを作る方法（基本パターン: 日別の売上を今年・前年で横並びにする）

**用途**: 基本パターン: 日別の売上を今年・前年で横並びにする

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH current_year AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS date,
    SUM(ecommerce.purchase_revenue) AS revenue,
    COUNTIF(event_name = 'purchase') AS purchases,
    COUNT(DISTINCT CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    )) AS sessions
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_TRUNC(CURRENT_DATE(), MONTH))
      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  GROUP BY date
),

previous_year AS (
  SELECT
    DATE_ADD(PARSE_DATE('%Y%m%d', event_date), INTERVAL 1 YEAR) AS date,
    SUM(ecommerce.purchase_revenue) AS revenue_ly,
    COUNTIF(event_name = 'purchase') AS purchases_ly,
    COUNT(DISTINCT CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    )) AS sessions_ly
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL 1 YEAR))
      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 YEAR))
  GROUP BY date
)

SELECT
  c.date,
  c.revenue AS revenue_current,
  p.revenue_ly AS revenue_previous,
  c.sessions AS sessions_current,
  p.sessions_ly AS sessions_previous,
  SAFE_DIVIDE(c.revenue - p.revenue_ly, p.revenue_ly) * 100 AS revenue_yoy_pct,
  SAFE_DIVIDE(c.sessions - p.sessions_ly, p.sessions_ly) * 100 AS sessions_yoy_pct
FROM
  current_year c
LEFT JOIN
  previous_year p ON c.date = p.date
ORDER BY
  c.date
```

### 337. BigQuery × Looker Studioで前年同期比グラフを作る方法（月別集計パターン）

**用途**: 月別集計パターン

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH monthly_data AS (
  SELECT
    DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), MONTH) AS month,
    EXTRACT(YEAR FROM PARSE_DATE('%Y%m%d', event_date)) AS year,
    EXTRACT(MONTH FROM PARSE_DATE('%Y%m%d', event_date)) AS month_num,
    SUM(ecommerce.purchase_revenue) AS revenue,
    COUNTIF(event_name = 'purchase') AS purchases
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 24 MONTH))
  GROUP BY month, year, month_num
)

SELECT
  cy.month,
  cy.month_num,
  cy.revenue AS revenue_current_year,
  ly.revenue AS revenue_last_year,
  SAFE_DIVIDE(cy.revenue - ly.revenue, ly.revenue) * 100 AS yoy_change_pct
FROM
  monthly_data cy
LEFT JOIN
  monthly_data ly
  ON cy.month_num = ly.month_num
  AND cy.year = ly.year + 1
WHERE
  cy.year = EXTRACT(YEAR FROM CURRENT_DATE())
ORDER BY
  cy.month_num
```

### 338. Looker StudioのブレンディングでGA4×広告データを結合する方法

**用途**: GA4とGoogle広告を結合するSQL

**必要なテーブル**: `${DATASET}.events_*`, `${DATASET}.p_CampaignStats_XXXXXXX`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH ga4_daily AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS date,
    COUNT(DISTINCT CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    )) AS sessions,
    COUNTIF(event_name = 'purchase') AS purchases,
    SUM(ecommerce.purchase_revenue) AS revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
  GROUP BY
    date
),

ads_daily AS (
  SELECT
    segments_date AS date,
    SUM(metrics_cost_micros / 1000000) AS ad_cost,
    SUM(metrics_clicks) AS ad_clicks,
    SUM(metrics_impressions) AS ad_impressions
  FROM
    `${PROJECT}.${DATASET}.p_CampaignStats_XXXXXXX`
  GROUP BY
    date
)

SELECT
  g.date,
  g.sessions,
  g.purchases,
  g.revenue,
  a.ad_cost,
  a.ad_clicks,
  a.ad_impressions,
  SAFE_DIVIDE(g.revenue, a.ad_cost) AS roas,
  SAFE_DIVIDE(a.ad_cost, g.purchases) AS cpa
FROM
  ga4_daily g
LEFT JOIN
  ads_daily a ON g.date = a.date
ORDER BY
  g.date DESC;
```

### 339. BigQuery × Looker StudioでEC事業の月次KPIレポートを自動化した（広告データとの統合ビュー）

**用途**: 広告データとの統合ビュー

**必要なテーブル**: `${DATASET}.mart_monthly_kpi`, `${DATASET}.mart_monthly_kpi_with_ads`, `${DATASET}.p_CampaignStats_XXXXXXX`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
CREATE OR REPLACE VIEW `${PROJECT}.${DATASET}.mart_monthly_kpi_with_ads` AS
SELECT
  kpi.month,
  kpi.sessions,
  kpi.users,
  kpi.purchases,
  kpi.revenue,
  kpi.cvr,
  kpi.revenue_per_session,
  kpi.avg_order_value,
  ads.ad_cost,
  SAFE_DIVIDE(kpi.revenue, ads.ad_cost) AS roas,
  SAFE_DIVIDE(ads.ad_cost, kpi.purchases) AS cpa
FROM
  `${PROJECT}.${DATASET}.mart_monthly_kpi` kpi
LEFT JOIN (
  SELECT
    DATE_TRUNC(segments_date, MONTH) AS month,
    SUM(metrics_cost_micros / 1000000) AS ad_cost
  FROM
    `${PROJECT}.${DATASET}.p_CampaignStats_XXXXXXX`
  GROUP BY month
) ads ON kpi.month = ads.month
```

### 340. GA4 × BigQuery × Looker Studioで完全自動のEC分析基盤を0から構築する全手順（mart_cohort（月次コホート分析））

**用途**: mart_cohort（月次コホート分析）

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

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

### 341. Looker Studio × BigQueryでスマホ最適化したダッシュボードを作る

**用途**: BigQuery側でスマホ用のデータを準備する

**必要なテーブル**: `${DATASET}.events_*`, `${DATASET}.mobile_dashboard_daily`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
CREATE OR REPLACE VIEW `${PROJECT}.${DATASET}.mobile_dashboard_daily` AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS date,
  COUNT(DISTINCT CONCAT(
    user_pseudo_id,
    CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
  )) AS sessions,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNTIF(event_name = 'purchase') AS purchases,
  IFNULL(SUM(ecommerce.purchase_revenue), 0) AS revenue,
  SAFE_DIVIDE(
    COUNTIF(event_name = 'purchase'),
    COUNT(DISTINCT CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    ))
  ) AS cvr
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
GROUP BY
  date
ORDER BY
  date DESC
```

### 342. Looker StudioでBigQueryに接続するときの料金を最小化する設定（方法2: マテリアライズドビューで集計済みデータを用意する）

**用途**: 方法2: マテリアライズドビューで集計済みデータを用意する

**必要なテーブル**: `${DATASET}.events_*`, `${DATASET}.mv_daily_sessions`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
CREATE MATERIALIZED VIEW `${PROJECT}.${DATASET}.mv_daily_sessions`
OPTIONS (
  enable_refresh = true,
  refresh_interval_minutes = 720
)
AS
SELECT
  event_date,
  COUNT(DISTINCT CONCAT(user_pseudo_id,
    CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING))
  ) AS sessions,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNTIF(event_name = 'purchase') AS purchases
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
GROUP BY
  event_date;
```

### 343. Looker Studio × BigQueryでGoogle広告とMeta広告を一画面で比較する（KPI集計ビュー）

**用途**: KPI集計ビュー

**必要なテーブル**: `${DATASET}.ads_platform_comparison`, `${DATASET}.unified_ads_daily`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
CREATE OR REPLACE VIEW `${PROJECT}.${DATASET}.ads_platform_comparison` AS
SELECT
  platform,
  SUM(spend) AS total_spend,
  SUM(impressions) AS total_impressions,
  SUM(clicks) AS total_clicks,
  SUM(conversions) AS total_conversions,
  SUM(conversion_value) AS total_conversion_value,
  SAFE_DIVIDE(SUM(clicks), SUM(impressions)) AS ctr,
  SAFE_DIVIDE(SUM(conversions), SUM(clicks)) AS cvr,
  SAFE_DIVIDE(SUM(spend), SUM(clicks)) AS cpc,
  SAFE_DIVIDE(SUM(spend), SUM(conversions)) AS cpa,
  SAFE_DIVIDE(SUM(conversion_value), SUM(spend)) AS roas
FROM
  `${PROJECT}.${DATASET}.unified_ads_daily`
WHERE
  date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY
  platform
```

### 344. Looker StudioのGA4コネクタとBigQueryコネクタの違いと使い分け

**用途**: Looker Studioでの接続手順

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS date,
  device.category AS device,
  traffic_source.source AS source,
  traffic_source.medium AS medium,
  COUNT(DISTINCT CONCAT(
    user_pseudo_id,
    CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
  )) AS sessions,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNTIF(event_name = 'purchase') AS purchases,
  SUM(ecommerce.purchase_revenue) AS revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
GROUP BY
  date, device, source, medium
```

### 345. Looker Studioのデータポータルが重い・遅い問題をBigQuery化で解決した（マートテーブルの作り方：日別サマリーの例）

**用途**: マートテーブルの作り方：日別サマリーの例

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
CREATE OR REPLACE TABLE `your_project.mart.daily_summary`
PARTITION BY event_date
AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS event_date,
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
  device.category AS device_category,

  -- セッション数
  COUNT(DISTINCT
    CONCAT(user_pseudo_id, CAST(
      (SELECT value.int_value FROM UNNEST(event_params)
       WHERE key = 'ga_session_id') AS STRING))
  ) AS sessions,

  -- ユーザー数
  COUNT(DISTINCT user_pseudo_id) AS users,

  -- PV数
  COUNTIF(event_name = 'page_view') AS page_views,

  -- コンバージョン数
  COUNTIF(event_name = 'purchase') AS conversions,

  -- 収益
  SUM(IF(event_name = 'purchase', ecommerce.purchase_revenue, 0)) AS revenue

FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY 1, 2, 3, 4
```

### 346. GA4 × BigQuery × Looker Studioで完全自動のEC分析基盤を0から構築する全手順（stg_sessions（セッション単位の集約））

**用途**: stg_sessions（セッション単位の集約）

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください

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
FROM `${PROJECT}.${DATASET}.events_*`
GROUP BY
  event_date, user_pseudo_id, ga_session_id,
  source, medium, device_category
```

### 347. Looker Studio × BigQueryでGoogle広告とMeta広告を一画面で比較する（ステップ3: 統合ビューをBigQueryで作成する）

**用途**: ステップ3: 統合ビューをBigQueryで作成する

**必要なテーブル**: `${DATASET}.meta_ads_daily`, `${DATASET}.p_CampaignStats_XXXXXXX`, `${DATASET}.p_Campaigns_XXXXXXX`, `${DATASET}.unified_ads_daily`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
CREATE OR REPLACE VIEW `${PROJECT}.${DATASET}.unified_ads_daily` AS

-- Google Ads
SELECT
  segments_date AS date,
  'Google Ads' AS platform,
  campaign_name,
  SUM(metrics_cost_micros / 1000000) AS spend,
  SUM(metrics_impressions) AS impressions,
  SUM(metrics_clicks) AS clicks,
  SUM(metrics_conversions) AS conversions,
  SUM(metrics_conversions_value) AS conversion_value
FROM
  `${PROJECT}.${DATASET}.p_CampaignStats_XXXXXXX` stats
JOIN
  `${PROJECT}.${DATASET}.p_Campaigns_XXXXXXX` campaigns
  ON stats.campaign_id = campaigns.campaign_id
GROUP BY
  date, platform, campaign_name

UNION ALL

-- Meta Ads
SELECT
  date,
  'Meta Ads' AS platform,
  campaign_name,
  SUM(spend) AS spend,
  SUM(impressions) AS impressions,
  SUM(clicks) AS clicks,
  SUM(purchases) AS conversions,
  SUM(purchase_value) AS conversion_value
FROM
  `${PROJECT}.${DATASET}.meta_ads_daily`
GROUP BY
  date, platform, campaign_name
```

### 348. Looker Studioのカスタム指標でROAS・CPAを自動計算する設定（BigQueryで統合広告テーブルを作るSQL）

**用途**: BigQueryで統合広告テーブルを作るSQL

**必要なテーブル**: `${DATASET}.meta_ads_daily`, `${DATASET}.p_CampaignStats_XXXXXXX`, `${DATASET}.unified_ads_performance`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
CREATE OR REPLACE VIEW `${PROJECT}.${DATASET}.unified_ads_performance` AS

-- Google Ads
SELECT
  segments_date AS date,
  'Google Ads' AS platform,
  campaign_name,
  SUM(metrics_cost_micros / 1000000) AS ad_cost,
  SUM(metrics_clicks) AS clicks,
  SUM(metrics_impressions) AS impressions,
  SUM(metrics_conversions) AS conversions,
  SUM(metrics_conversions_value) AS conversion_value
FROM
  `${PROJECT}.${DATASET}.p_CampaignStats_XXXXXXX`
GROUP BY date, campaign_name

UNION ALL

-- Meta Ads（別途BigQueryに連携済みの想定）
SELECT
  date,
  'Meta Ads' AS platform,
  campaign_name,
  SUM(spend) AS ad_cost,
  SUM(clicks) AS clicks,
  SUM(impressions) AS impressions,
  SUM(purchases) AS conversions,
  SUM(purchase_value) AS conversion_value
FROM
  `${PROJECT}.${DATASET}.meta_ads_daily`
GROUP BY date, campaign_name
```

### 349. Looker Studioのカスタム指標でROAS・CPAを自動計算する設定（BigQueryでROASを事前計算する方法）

**用途**: BigQueryでROASを事前計算する方法

**必要なテーブル**: `${DATASET}.campaign_performance`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  date,
  campaign_name,
  SUM(revenue) AS revenue,
  SUM(ad_cost) AS ad_cost,
  SAFE_DIVIDE(SUM(revenue), SUM(ad_cost)) AS roas
FROM
  `${PROJECT}.${DATASET}.campaign_performance`
GROUP BY
  date, campaign_name
```

### 350. GA4 × BigQuery × Looker Studioで完全自動のEC分析基盤を0から構築する全手順（mart_traffic（日別×チャネル別トラフィック））

**用途**: mart_traffic（日別×チャネル別トラフィック）

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

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

### 351. GA4 × BigQuery × Looker Studioで完全自動のEC分析基盤を0から構築する全手順（mart_funnel（月次ファネル分析））

**用途**: mart_funnel（月次ファネル分析）

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

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

### 352. Looker Studioでドリルダウン機能を使ったEC分析ダッシュボードを作る（ステップ1: データソースの準備）

**用途**: ステップ1: データソースの準備

**必要なテーブル**: `${DATASET}.ec_sales_drilldown`, `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
CREATE OR REPLACE VIEW `${PROJECT}.${DATASET}.ec_sales_drilldown` AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS date,
  items.item_category AS category,
  items.item_brand AS brand,
  items.item_name AS product_name,
  device.category AS device_type,
  traffic_source.source AS source,
  traffic_source.medium AS medium,
  items.quantity AS quantity,
  items.item_revenue AS revenue
FROM
  `${PROJECT}.${DATASET}.events_*`,
  UNNEST(items) AS items
WHERE
  event_name = 'purchase'
  AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY))
```

### 353. Looker Studioでドリルダウン機能を使ったEC分析ダッシュボードを作る（NULL値の対策をする）

**用途**: NULL値の対策をする

**必要なテーブル**: `${DATASET}.ec_sales_drilldown`, `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
CREATE OR REPLACE VIEW `${PROJECT}.${DATASET}.ec_sales_drilldown` AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS date,
  IFNULL(items.item_category, '未分類') AS category,
  IFNULL(items.item_brand, 'ノーブランド') AS brand,
  items.item_name AS product_name,
  device.category AS device_type,
  traffic_source.source AS source,
  traffic_source.medium AS medium,
  items.quantity AS quantity,
  items.item_revenue AS revenue
FROM
  `${PROJECT}.${DATASET}.events_*`,
  UNNEST(items) AS items
WHERE
  event_name = 'purchase'
  AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY))
```

### 354. GA4 × BigQuery × Looker Studioで完全自動のEC分析基盤を0から構築する全手順（stg_events（イベント単位のフラット化））

**用途**: stg_events（イベント単位のフラット化）

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください

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
FROM `${PROJECT}.${DATASET}.events_*`
```

### 355. BigQuery × Looker Studioで前年同期比グラフを作る方法（パターン3: スコアカードで前年比を大きく表示）

**用途**: パターン3: スコアカードで前年比を大きく表示

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  SUM(CASE WHEN year = EXTRACT(YEAR FROM CURRENT_DATE()) THEN revenue END) AS revenue_ytd,
  SUM(CASE WHEN year = EXTRACT(YEAR FROM CURRENT_DATE()) - 1 THEN revenue END) AS revenue_ytd_ly,
  SAFE_DIVIDE(
    SUM(CASE WHEN year = EXTRACT(YEAR FROM CURRENT_DATE()) THEN revenue END)
    - SUM(CASE WHEN year = EXTRACT(YEAR FROM CURRENT_DATE()) - 1 THEN revenue END),
    SUM(CASE WHEN year = EXTRACT(YEAR FROM CURRENT_DATE()) - 1 THEN revenue END)
  ) * 100 AS ytd_yoy_pct
FROM monthly_data
WHERE month_num <= EXTRACT(MONTH FROM CURRENT_DATE())
```

### 356. BigQuery × Looker Studioで前年同期比グラフを作る方法（日付パラメータとの連携）

**用途**: 日付パラメータとの連携

**必要なテーブル**: `${DATASET}.yoy_daily_view`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  date,
  revenue_current,
  revenue_previous,
  revenue_yoy_pct
FROM
  `${PROJECT}.${DATASET}.yoy_daily_view`
WHERE
  date BETWEEN @DS_START_DATE AND @DS_END_DATE
```

### 357. GA4 × BigQuery × Looker Studioで完全自動のEC分析基盤を0から構築する全手順（stg_purchases（購入イベントのみ抽出））

**用途**: stg_purchases（購入イベントのみ抽出）

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください

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
FROM `${PROJECT}.${DATASET}.events_*`
WHERE event_name = 'purchase'
  AND ecommerce.transaction_id IS NOT NULL
```

### 358. Looker StudioでBigQueryに接続するときの料金を最小化する設定（方法4: パーティションテーブルを活用する）

**用途**: 方法4: パーティションテーブルを活用する

**必要なテーブル**: `${DATASET}.events_*`, `${DATASET}.sessions_partitioned`

**コストの注意**: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください

```sql
CREATE TABLE `${PROJECT}.${DATASET}.sessions_partitioned`
PARTITION BY event_date
CLUSTER BY traffic_source
AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS event_date,
  user_pseudo_id,
  traffic_source.source AS traffic_source,
  traffic_source.medium AS traffic_medium,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id
FROM
  `${PROJECT}.${DATASET}.events_*`;
```

### 359. Looker Studioのデータポータルが重い・遅い問題をBigQuery化で解決した（パーティションとクラスタリング）

**用途**: パーティションとクラスタリング

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
CREATE OR REPLACE TABLE `your_project.mart.daily_summary`
PARTITION BY event_date
CLUSTER BY source, medium, device_category
AS
-- (上記と同じSELECT文)
```

### 360. BigQueryのSTRUCT・ARRAY型を活用してGA4データを効率的にモデリングする（セッションテーブルをデータマートとして整形する）

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

### 361. dbt × BigQueryで再現可能なデータパイプラインを構築する入門【GA4データ編】

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

### 362. BigQueryのデータリネージ機能でデータマートの依存関係を可視化する（GA4データを使ったビューの依存関係を実際に確認する） その1

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

### 363. BigQueryのエクスポート上限に引っかかったときの回避策まとめ

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

### 364. BigQueryのアクセス制御をIAMで適切に設計する【チーム運用編】

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

### 365. BigQueryのラベル機能でプロジェクト横断のコスト配分を自動管理する（クエリジョブへのラベル付与方法）

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

### 366. BigQueryのマテリアライズドビューでGA4集計クエリを高速化した（マテリアライズドビューの作成手順） その1

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

### 367. BigQueryのクエリキャッシュの仕組みを理解してコスト効率を最大化する（GA4データを活用するクエリでのキャッシュ設計）

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

### 368. BigQueryのクエリコストを月1万円以下に抑える7つの実践テクニック（テクニック7：不要なテーブルと期限切れポリシーを活用する）

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

### 369. BigQueryのクエリ結果をCloud Storageに自動エクスポートして外部ツール連携する

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

### 370. BigQueryのスケジュールクエリでデータマートを毎朝自動更新する設定と監視方法（データマート用SQLの書き方（GA4エクスポートテーブル使用））

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

### 371. BigQueryからGoogleスプレッドシートに自動出力して非エンジニアとデータ共有する

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

### 372. BigQueryのSTRUCT・ARRAY型を活用してGA4データを効率的にモデリングする（流入元データをcollected_traffic_sourceから取得する）

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

### 373. BigQueryのタイムトラベル機能で誤削除・誤更新からデータを復旧する方法（過去時点のデータをSELECTで確認する）

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

### 374. BigQueryのタイムトラベル機能で誤削除・誤更新からデータを復旧する方法（GA4集計テーブルの復旧シナリオ例）

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

### 375. GA4 BigQueryエクスポートのストリーミング vs 日次の違いと使い分け（日次テーブルを対象にしたクエリ例）

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

### 376. GA4 BigQueryエクスポートのストリーミング vs 日次の違いと使い分け（流入元の取得方法）

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

### 377. GA4 BigQueryエクスポートのストリーミング vs 日次の違いと使い分け（ストリーミングテーブルを使うべきシーン）

**用途**: ストリーミングテーブルを使うべきシーン

**必要なテーブル**: `${DATASET}.events_intraday_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  FORMAT_TIMESTAMP('%H', TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo') AS hour,
  COUNT(*) AS purchase_count,
  SUM(
    (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'value')
  ) AS total_revenue
FROM
  `${PROJECT}.${DATASET}.events_intraday_*`
WHERE
  _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', CURRENT_DATE('Asia/Tokyo'))
  AND event_name = 'purchase'
GROUP BY
  hour
ORDER BY
  hour;
```

### 378. GA4 BigQueryエクスポートのストリーミング vs 日次の違いと使い分け（日次テーブルとイントラデイを組み合わせる方法）

**用途**: 日次テーブルとイントラデイを組み合わせる方法

**必要なテーブル**: `${DATASET}.events_*`, `${DATASET}.events_intraday_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_date,
  event_name,
  COUNT(DISTINCT user_pseudo_id) AS users
FROM (
  -- 確定済みの日次テーブル
  SELECT event_date, event_name, user_pseudo_id
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 6 DAY))
      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 1 DAY))

  UNION ALL

  -- 本日のストリーミングテーブル
  SELECT event_date, event_name, user_pseudo_id
  FROM `${PROJECT}.${DATASET}.events_intraday_*`
  WHERE
    _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', CURRENT_DATE('Asia/Tokyo'))
)
GROUP BY
  event_date,
  event_name
ORDER BY
  event_date DESC,
  users DESC;
```

### 379. 小規模EC事業者がBigQueryを無料枠内で運用し続けるための設計戦略（GA4データを活用する際のSQL設計パターン）

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

### 380. 小規模EC事業者がBigQueryを無料枠内で運用し続けるための設計戦略（ストレージコストを抑えるテーブル管理の工夫）

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

### 381. BigQueryのCOLUMN_FIELD_PATHSでGA4のネストされたスキーマを効率的に探索する（実際の分析クエリへの応用）

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

### 382. BigQueryのINFORMATION_SCHEMAでクエリコスト・実行履歴を自動監視する（ユーザー別・日別のコスト集計でチーム内の利用傾向を掴む）

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

### 383. BigQueryのINFORMATION_SCHEMAでクエリコスト・実行履歴を自動監視する（定期監視の仕組みをBigQueryスケジュールクエリで構築する）

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

### 384. BigQueryのラベル機能でプロジェクト横断のコスト配分を自動管理する（ラベル別コストを集計するSQL）

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

### 385. BigQueryのマテリアライズドビューでGA4集計クエリを高速化した（マテリアライズドビューの作成手順） その2

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

### 386. BigQueryのクエリコストを月1万円以下に抑える7つの実践テクニック（テクニック4：マテリアライズドビューで集計コストを自動化する）

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

### 387. BigQueryでSQLテストを書く方法―データマートの品質を担保する仕組み（GA4エクスポートデータでのNULLチェックと一意性チェック） その1

**用途**: GA4エクスポートデータでのNULLチェックと一意性チェック

**必要なテーブル**: `${DATASET}.session_summary`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  event_date,
  session_id,
  COUNT(*) AS duplicate_count
FROM
  `${PROJECT}.${DATASET}.session_summary`
WHERE
  event_date = '2025-01-15'
GROUP BY
  event_date,
  session_id
HAVING
  COUNT(*) > 1
;
```

### 388. BigQueryでSQLテストを書く方法―データマートの品質を担保する仕組み（流入元データの整合性チェック） その1

**用途**: 流入元データの整合性チェック

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH allowed_mediums AS (
  SELECT medium FROM UNNEST(['organic', 'cpc', 'email', 'social', 'referral', '(none)']) AS medium
),
actual_mediums AS (
  SELECT DISTINCT
    collected_traffic_source.manual_medium AS medium
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    AND event_name = 'session_start'
    AND collected_traffic_source.manual_medium IS NOT NULL
)
SELECT
  a.medium AS unexpected_medium
FROM
  actual_mediums a
LEFT JOIN
  allowed_mediums al ON a.medium = al.medium
WHERE
  al.medium IS NULL
;
```

### 389. BigQueryのクエリキャッシュの仕組みを理解してコスト効率を最大化する（キャッシュが効く条件と効かない条件）

**用途**: キャッシュが効く条件と効かない条件

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_date,
  COUNT(*) AS session_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  AND event_name = 'session_start'
GROUP BY
  event_date
```

### 390. BigQueryのクエリコストを月1万円以下に抑える7つの実践テクニック（テクニック1：パーティション絞り込みで読み取りデータ量を減らす）

**用途**: テクニック1：パーティション絞り込みで読み取りデータ量を減らす

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_name,
  COUNT(*) AS event_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
                    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY
  event_name
ORDER BY
  event_count DESC
```

### 391. BigQueryでSQLテストを書く方法―データマートの品質を担保する仕組み（流入元データの整合性チェック） その2

**用途**: 流入元データの整合性チェック

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  COUNT(*) AS event_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20250131'
  AND event_name = 'session_start'
GROUP BY
  medium
ORDER BY
  event_count DESC
;
```

### 392. BigQueryのBI Engineを有効化してLooker Studioの表示速度を改善する

**用途**: GA4データを使ったLooker Studio向けクエリの最適化例

**必要なテーブル**: `${DATASET}.events_*`, `${DATASET}.v_session_summary`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
CREATE OR REPLACE VIEW `${PROJECT}.${DATASET}.v_session_summary` AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS session_date,
  -- セッションIDはevent_paramsのUNNESTから取得する
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_id'
  ) AS ga_session_id,
  user_pseudo_id,
  -- 流入元はcollected_traffic_sourceから参照する
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  geo.country AS country,
  device.category AS device_category,
  event_name
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
;
```

### 393. BigQueryのデータリネージ機能でデータマートの依存関係を可視化する（GA4データを使ったビューの依存関係を実際に確認する） その2

**用途**: GA4データを使ったビューの依存関係を実際に確認する

**必要なテーブル**: `${DATASET}.mart_revenue_by_channel`, `${DATASET}.stg_sessions`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
CREATE OR REPLACE VIEW `${PROJECT}.${DATASET}.mart_revenue_by_channel` AS
SELECT
  COALESCE(medium, '(none)') AS medium,
  COALESCE(source, '(direct)') AS source,
  SUM(revenue) AS total_revenue,
  COUNT(DISTINCT ga_session_id) AS sessions
FROM
  `${PROJECT}.${DATASET}.stg_sessions`
GROUP BY
  medium,
  source
;
```

### 394. BigQueryのクエリキャッシュの仕組みを理解してコスト効率を最大化する（キャッシュを最大限活用するための運用ポイント）

**用途**: キャッシュを最大限活用するための運用ポイント

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  cache_hit,
  COUNT(*) AS job_count,
  SUM(total_bytes_processed) AS total_bytes
FROM
  `region-asia-northeast1`.INFORMATION_SCHEMA.JOBS
WHERE
  creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  AND job_type = 'QUERY'
GROUP BY
  cache_hit
```

### 395. BigQueryでSQLテストを書く方法―データマートの品質を担保する仕組み（テストの自動実行――BigQuery Scheduled Queriesを活用する）

**用途**: テストの自動実行――BigQuery Scheduled Queriesを活用する

**必要なテーブル**: `${DATASET}.events_*`, `${DATASET}.test_results`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
INSERT INTO `${PROJECT}.${DATASET}.test_results` (
  test_name,
  test_date,
  result_count,
  status,
  executed_at
)
SELECT
  'null_session_id_check' AS test_name,
  CURRENT_DATE()          AS test_date,
  COUNT(*)                AS result_count,
  IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
  CURRENT_TIMESTAMP()     AS executed_at
FROM
  `${PROJECT}.${DATASET}.events_*`,
  UNNEST(event_params) AS ep
WHERE
  _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
  AND ep.key = 'ga_session_id'
  AND ep.value.int_value IS NULL
;
```

### 396. BigQueryのSTRUCT・ARRAY型を活用してGA4データを効率的にモデリングする（UNNESTでevent_paramsを展開する） その1

**用途**: UNNESTでevent_paramsを展開する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_date,
  event_name,
  user_pseudo_id,
  (
    SELECT ep.value.int_value
    FROM UNNEST(event_params) AS ep
    WHERE ep.key = 'ga_session_id'
  ) AS ga_session_id
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240801' AND '20240831'
  AND event_name = 'page_view'
```

### 397. BigQueryのSTRUCT・ARRAY型を活用してGA4データを効率的にモデリングする（UNNESTでevent_paramsを展開する） その2

**用途**: UNNESTでevent_paramsを展開する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_date,
  user_pseudo_id,
  (
    SELECT ep.value.int_value
    FROM UNNEST(event_params) AS ep
    WHERE ep.key = 'ga_session_id'
  ) AS ga_session_id,
  (
    SELECT ep.value.string_value
    FROM UNNEST(event_params) AS ep
    WHERE ep.key = 'page_title'
  ) AS page_title,
  (
    SELECT ep.value.string_value
    FROM UNNEST(event_params) AS ep
    WHERE ep.key = 'page_location'
  ) AS page_location
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240801' AND '20240831'
  AND event_name = 'page_view'
```

### 398. GA4×BigQueryのテーブル肥大化を防ぐパーティション有効期限の設定方法

**用途**: 方法2：パーティションテーブルに統合して有効期限を管理する

**必要なテーブル**: `${DATASET}.events_*`, `${DATASET}.events_partitioned`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
CREATE TABLE IF NOT EXISTS `${PROJECT}.${DATASET}.events_partitioned`
PARTITION BY event_date
OPTIONS (
  partition_expiration_days = 365
)
AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS event_date,
  event_timestamp,
  event_name,
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  collected_traffic_source.manual_medium AS traffic_medium,
  collected_traffic_source.manual_source AS traffic_source,
  ecommerce.purchase_revenue AS purchase_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240101' AND FORMAT_DATE('%Y%m%d', CURRENT_DATE());
```

### 399. GCSにバックアップしたGA4データをBigQueryに再インポートする手順（インポート後のデータ確認：GA4特有の構造を踏まえたSQL） その1

**用途**: インポート後のデータ確認：GA4特有の構造を踏まえたSQL

**必要なテーブル**: `${DATASET}.events_20240101`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  event_name,
  COUNT(*) AS event_count
FROM
  `${PROJECT}.${DATASET}.events_20240101`
GROUP BY
  event_name
ORDER BY
  event_count DESC
LIMIT 20;
```

### 400. GCSにバックアップしたGA4データをBigQueryに再インポートする手順（インポート後のデータ確認：GA4特有の構造を踏まえたSQL） その2

**用途**: インポート後のデータ確認：GA4特有の構造を踏まえたSQL

**必要なテーブル**: `${DATASET}.events_20240101`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
  COUNT(*) AS session_count
FROM
  `${PROJECT}.${DATASET}.events_20240101`
WHERE
  event_name = 'session_start'
GROUP BY
  source,
  medium
ORDER BY
  session_count DESC;
```

### 401. BigQueryのINFORMATION_SCHEMAでクエリコスト・実行履歴を自動監視する（直近7日間のコスト上位クエリを抽出する）

**用途**: 直近7日間のコスト上位クエリを抽出する

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  job_id,
  user_email,
  query,
  creation_time,
  ROUND(total_bytes_processed / POW(1024, 4), 4) AS processed_tb,
  ROUND(total_bytes_processed / POW(1024, 4) * 6.25, 2) AS estimated_cost_usd,
  TIMESTAMP_DIFF(end_time, start_time, SECOND) AS duration_sec,
  state
FROM
  `region-asia-northeast1`.INFORMATION_SCHEMA.JOBS
WHERE
  creation_time BETWEEN TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
    AND CURRENT_TIMESTAMP()
  AND job_type = 'QUERY'
  AND state = 'DONE'
  AND error_result IS NULL
ORDER BY
  total_bytes_processed DESC
LIMIT 10;
```

### 402. BigQueryのラベル機能でプロジェクト横断のコスト配分を自動管理する（プロジェクト横断でのコスト配分を自動化するポイント）

**用途**: プロジェクト横断でのコスト配分を自動化するポイント

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  job_id,
  user_email,
  total_bytes_processed,
  creation_time,
  labels
FROM
  `region-asia-northeast1`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE
  DATE(creation_time) = CURRENT_DATE() - 1
  AND ARRAY_LENGTH(labels) = 0
  AND job_type = 'QUERY'
ORDER BY
  total_bytes_processed DESC
LIMIT 50
```

### 403. BigQueryのフラットレート vs オンデマンド料金を実データで比較してどちらが安いか検証した

**用途**: 実際のクエリで処理量を比較してみた

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = "ga_session_id"
    LIMIT 1
  ) AS ga_session_id
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN "20240101" AND "20240131"
  AND event_name = "session_start"
```

### 404. BigQueryのマテリアライズドビューでGA4集計クエリを高速化した（GA4のBigQueryエクスポートテーブル構造を理解する） その1

**用途**: GA4のBigQueryエクスポートテーブル構造を理解する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_date,
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
```

### 405. BigQueryのマテリアライズドビューでGA4集計クエリを高速化した（GA4のBigQueryエクスポートテーブル構造を理解する） その2

**用途**: GA4のBigQueryエクスポートテーブル構造を理解する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_date,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX >= '20250601'
  AND event_name = 'session_start'
```

### 406. BigQueryのクエリコストを月1万円以下に抑える7つの実践テクニック（テクニック2：SELECT * を避けて必要な列だけ取得する）

**用途**: テクニック2：SELECT * を避けて必要な列だけ取得する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  user_pseudo_id,
  event_timestamp,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  collected_traffic_source.manual_medium AS traffic_medium,
  collected_traffic_source.manual_source AS traffic_source
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
  AND event_name = 'session_start'
```

### 407. BigQueryでSQLテストを書く方法―データマートの品質を担保する仕組み（GA4エクスポートデータでのNULLチェックと一意性チェック） その2

**用途**: GA4エクスポートデータでのNULLチェックと一意性チェック

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  COUNT(*) AS null_session_id_count
FROM
  `${PROJECT}.${DATASET}.events_*`,
  UNNEST(event_params) AS ep
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20250131'
  AND ep.key = 'ga_session_id'
  AND ep.value.int_value IS NULL
;
```

### 408. BigQueryのSTRUCT・ARRAY型を活用してGA4データを効率的にモデリングする（STRUCT型とARRAY型の基本を理解する）

**用途**: STRUCT型とARRAY型の基本を理解する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_name,
  event_params
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX = '20240801'
LIMIT 1
```

### 409. 小規模EC事業者がBigQueryを無料枠内で運用し続けるための設計戦略（クエリ設計でスキャン量を最小化する）

**用途**: クエリ設計でスキャン量を最小化する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です / `SELECT *` を含みます。必要な列だけに絞るとコストが下がります

```sql
SELECT *
FROM `${PROJECT}.${DATASET}.events_*`
WHERE event_name = 'purchase';

-- 良い例：期間を絞り込む
SELECT *
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'purchase';
```

### 410. BigQueryのCOLUMN_FIELD_PATHSでGA4のネストされたスキーマを効率的に探索する（COLUMN_FIELD_PATHSとは）

**用途**: COLUMN_FIELD_PATHSとは

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  field_path,
  data_type,
  description
FROM
  `プロジェクトID.データセット名`.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
WHERE
  table_name = 'テーブル名'
ORDER BY
  field_path;
```

### 411. BigQueryのCOLUMN_FIELD_PATHSでGA4のネストされたスキーマを効率的に探索する（実践：GA4テーブルのスキーマ全体を取得する）

**用途**: 実践：GA4テーブルのスキーマ全体を取得する

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  field_path,
  data_type
FROM
  `your-project.analytics_XXXXXXXXX`.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
WHERE
  table_name = 'events_20250101'
ORDER BY
  field_path;
```

### 412. BigQueryのCOLUMN_FIELD_PATHSでGA4のネストされたスキーマを効率的に探索する（特定フィールドだけを絞り込んで探索する） その1

**用途**: 特定フィールドだけを絞り込んで探索する

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  field_path,
  data_type
FROM
  `your-project.analytics_XXXXXXXXX`.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
WHERE
  table_name = 'events_20250101'
  AND field_path LIKE 'items%'
ORDER BY
  field_path;
```

### 413. BigQueryのCOLUMN_FIELD_PATHSでGA4のネストされたスキーマを効率的に探索する（特定フィールドだけを絞り込んで探索する） その2

**用途**: 特定フィールドだけを絞り込んで探索する

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  field_path,
  data_type
FROM
  `your-project.analytics_XXXXXXXXX`.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
WHERE
  table_name = 'events_20250101'
  AND field_path LIKE 'collected_traffic_source%'
ORDER BY
  field_path;
```

### 414. BigQueryのスケジュールクエリでデータマートを毎朝自動更新する設定と監視方法（データの鮮度をSQLで確認する）

**用途**: データの鮮度をSQLで確認する

**必要なテーブル**: `${DATASET}.INFORMATION_SCHEMA`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  table_name,
  TIMESTAMP_MILLIS(last_modified_time) AS last_modified_jst
FROM
  `${PROJECT}.${DATASET}.INFORMATION_SCHEMA.TABLES`
WHERE
  table_name = 'session_summary'
```

### 415. BigQueryのタイムトラベル機能で誤削除・誤更新からデータを復旧する方法（誤更新したデータを元に戻す（テーブル上書き）） その1

**用途**: 誤更新したデータを元に戻す（テーブル上書き）

**必要なテーブル**: `${DATASET}.target_table`

**コストの注意**: `SELECT *` を含みます。必要な列だけに絞るとコストが下がります

```sql
CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.target_table`
AS
SELECT *
FROM `${PROJECT}.${DATASET}.target_table`
FOR SYSTEM_TIME AS OF TIMESTAMP '2025-07-30 09:00:00 UTC';
```

### 416. BigQueryのタイムトラベル機能で誤削除・誤更新からデータを復旧する方法（誤更新したデータを元に戻す（テーブル上書き）） その2

**用途**: 誤更新したデータを元に戻す（テーブル上書き）

**必要なテーブル**: `${DATASET}.target_table`

**コストの注意**: `SELECT *` を含みます。必要な列だけに絞るとコストが下がります

```sql
MERGE `${PROJECT}.${DATASET}.target_table` AS current
USING (
  SELECT *
  FROM `${PROJECT}.${DATASET}.target_table`
  FOR SYSTEM_TIME AS OF TIMESTAMP '2025-07-30 09:00:00 UTC'
  WHERE order_status = 'cancelled'  -- 誤更新された行の条件
) AS past
ON current.order_id = past.order_id
WHEN MATCHED THEN
  UPDATE SET
    current.order_status = past.order_status,
    current.updated_at   = past.updated_at;
```

### 417. GA4 BigQueryエクスポートのストリーミング vs 日次の違いと使い分け（ga_session_id の取得方法）

**用途**: ga_session_id の取得方法

**必要なテーブル**: `${DATASET}.events_20250801`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  user_pseudo_id,
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_id'
  ) AS ga_session_id,
  event_name,
  event_timestamp
FROM
  `${PROJECT}.${DATASET}.events_20250801`
WHERE
  event_name = 'purchase'
LIMIT 100;
```

### 418. GCSにバックアップしたGA4データをBigQueryに再インポートする手順（インポート後のデータ確認：GA4特有の構造を踏まえたSQL） その3

**用途**: インポート後のデータ確認：GA4特有の構造を踏まえたSQL

**必要なテーブル**: `${DATASET}.events_20240101`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  user_pseudo_id,
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_id'
  ) AS ga_session_id,
  event_name,
  event_timestamp
FROM
  `${PROJECT}.${DATASET}.events_20240101`
WHERE
  event_name = 'page_view'
LIMIT 100;
```

### 419. AI検索時代のGA4活用術―ChatGPT流入をBigQueryで追跡する（AI検索 vs オーガニック vs ダイレクトの行動比較）

**用途**: AI検索 vs オーガニック vs ダイレクトの行動比較

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH session_base AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    event_name,
    event_timestamp,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_referrer') AS page_referrer,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium') AS medium,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
),

session_channel AS (
  SELECT
    user_pseudo_id,
    session_id,
    CASE
      WHEN REGEXP_CONTAINS(
        MAX(IF(event_name = 'session_start', page_referrer, NULL)),
        r'chatgpt\.com|chat\.openai\.com|perplexity\.ai|gemini\.google\.com|copilot\.microsoft\.com|claude\.ai'
      ) THEN 'AI Search'
      WHEN MAX(IF(event_name = 'session_start', medium, NULL)) = 'organic' THEN 'Organic Search'
      WHEN MAX(IF(event_name = 'session_start', page_referrer, NULL)) IS NULL THEN 'Direct'
      ELSE 'Other'
    END AS channel,
    COUNT(DISTINCT IF(event_name = 'page_view', page_location, NULL)) AS pages_per_session,
    TIMESTAMP_DIFF(
      TIMESTAMP_MICROS(MAX(event_timestamp)),
      TIMESTAMP_MICROS(MIN(event_timestamp)),
      SECOND
    ) AS session_duration_sec,
    MAX(IF(event_name = 'purchase', 1, 0)) AS has_conversion
  FROM session_base
  GROUP BY user_pseudo_id, session_id
)

SELECT
  channel,
  COUNT(*) AS sessions,
  ROUND(AVG(pages_per_session), 1) AS avg_pages_per_session,
  ROUND(AVG(session_duration_sec), 0) AS avg_session_duration_sec,
  ROUND(SAFE_DIVIDE(SUM(has_conversion), COUNT(*)) * 100, 2) AS cvr_pct
FROM session_channel
WHERE channel IN ('AI Search', 'Organic Search', 'Direct')
GROUP BY channel
ORDER BY sessions DESC;
```

### 420. AI検索時代のGA4活用術―ChatGPT流入をBigQueryで追跡する（BigQueryでAI検索セッションを特定するSQL）

**用途**: BigQueryでAI検索セッションを特定するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です / `SELECT *` を含みます。必要な列だけに絞るとコストが下がります

```sql
WITH session_referrers AS (
  SELECT
    event_date,
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_referrer') AS page_referrer
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
    AND event_name = 'session_start'
),

ai_sessions AS (
  SELECT
    *,
    CASE
      WHEN REGEXP_CONTAINS(page_referrer, r'chatgpt\.com|chat\.openai\.com') THEN 'ChatGPT'
      WHEN REGEXP_CONTAINS(page_referrer, r'perplexity\.ai') THEN 'Perplexity'
      WHEN REGEXP_CONTAINS(page_referrer, r'gemini\.google\.com') THEN 'Gemini'
      WHEN REGEXP_CONTAINS(page_referrer, r'copilot\.microsoft\.com') THEN 'Copilot'
      WHEN REGEXP_CONTAINS(page_referrer, r'claude\.ai') THEN 'Claude'
      ELSE NULL
    END AS ai_source
  FROM session_referrers
)

SELECT
  PARSE_DATE('%Y%m%d', event_date) AS date,
  ai_source,
  COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(session_id AS STRING))) AS sessions
FROM ai_sessions
WHERE ai_source IS NOT NULL
GROUP BY date, ai_source
ORDER BY date DESC, sessions DESC;
```

### 421. AI検索時代のGA4活用術―ChatGPT流入をBigQueryで追跡する（AI検索流入のトレンド監視）

**用途**: AI検索流入のトレンド監視

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), WEEK) AS week_start,
  COUNTIF(REGEXP_CONTAINS(
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_referrer'),
    r'chatgpt\.com|chat\.openai\.com|perplexity\.ai|gemini\.google\.com|copilot\.microsoft\.com|claude\.ai'
  )) AS ai_search_sessions,
  COUNT(*) AS total_sessions,
  ROUND(SAFE_DIVIDE(
    COUNTIF(REGEXP_CONTAINS(
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_referrer'),
      r'chatgpt\.com|chat\.openai\.com|perplexity\.ai|gemini\.google\.com|copilot\.microsoft\.com|claude\.ai'
    )),
    COUNT(*)
  ) * 100, 2) AS ai_search_pct
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  AND event_name = 'session_start'
GROUP BY week_start
ORDER BY week_start;
```

### 422. GA4×BigQueryを自社導入したEC事業者が最初の1週間で気づいたこと（Day 2：テーブル構造に驚く）

**用途**: Day 2：テーブル構造に驚く

**必要なテーブル**: `${DATASET}.events_20260329`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT event_name, COUNT(*) as event_count
FROM `${PROJECT}.${DATASET}.events_20260329`
GROUP BY event_name
ORDER BY event_count DESC
LIMIT 20
```

### 423. GA4×BigQueryを自社導入したEC事業者が最初の1週間で気づいたこと（Day 4：セッションの概念が違う）

**用途**: Day 4：セッションの概念が違う

**必要なテーブル**: `${DATASET}.events_20260329`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
  user_pseudo_id,
  MIN(event_timestamp) AS session_start,
  MAX(event_timestamp) AS session_end
FROM `${PROJECT}.${DATASET}.events_20260329`
GROUP BY session_id, user_pseudo_id
```

### 424. AI検索時代のGA4活用術―ChatGPT流入をBigQueryで追跡する（BigQueryでカスタムチャネルグループを定義する）

**用途**: BigQueryでカスタムチャネルグループを定義する

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
CREATE TEMP FUNCTION classify_channel(
  source STRING, medium STRING, page_referrer STRING
) AS (
  CASE
    WHEN REGEXP_CONTAINS(COALESCE(page_referrer, ''),
      r'chatgpt\.com|chat\.openai\.com|perplexity\.ai|gemini\.google\.com|copilot\.microsoft\.com|claude\.ai')
      THEN 'AI Search'
    WHEN source = 'chatgpt' AND medium = 'ai-search' THEN 'AI Search'
    WHEN medium = 'organic' THEN 'Organic Search'
    WHEN medium = 'cpc' THEN 'Paid Search'
    WHEN medium = 'referral' THEN 'Referral'
    WHEN medium = '(none)' AND source = '(direct)' THEN 'Direct'
    ELSE 'Other'
  END
);
```

### 425. 中小EC経営者がデータ分析に月1万円投資すべき理由

**用途**: 2. 離脱ポイントの特定

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  COUNT(DISTINCT CASE WHEN event_name = 'view_item' THEN user_pseudo_id END) AS view_item_users,
  COUNT(DISTINCT CASE WHEN event_name = 'add_to_cart' THEN user_pseudo_id END) AS add_to_cart_users,
  COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN user_pseudo_id END) AS purchase_users
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
```

### 426. GA4×BigQueryを自社導入したEC事業者が最初の1週間で気づいたこと（Day 3：UNNESTとの格闘）

**用途**: Day 3：UNNESTとの格闘

**必要なテーブル**: `${DATASET}.events_20260329`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  event_timestamp,
  event_name,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location
FROM `${PROJECT}.${DATASET}.events_20260329`
WHERE event_name = 'page_view'
LIMIT 100
```

### 427. BigQueryで広告の貢献度をデータドリブンアトリビューションで再計算する（チャネルごとの貢献度を線形モデルで計算する）

**用途**: チャネルごとの貢献度を線形モデルで計算する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH session_source AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS ga_session_id,
    event_name,
    event_timestamp,
    collected_traffic_source.manual_source  AS source,
    collected_traffic_source.manual_medium  AS medium
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250731'
    AND event_name IN ('session_start', 'purchase')
),

session_agg AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    MAX(source)        AS source,
    MAX(medium)        AS medium,
    MAX(event_timestamp) AS session_ts,
    MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) AS is_converted
  FROM session_source
  GROUP BY 1, 2
),

-- コンバージョンしたユーザーの経路のみ対象
converted_users AS (
  SELECT user_pseudo_id
  FROM session_agg
  GROUP BY 1
  HAVING MAX(is_converted) = 1
),

-- ユーザーあたりのタッチポイント数を算出
user_touch AS (
  SELECT
    s.user_pseudo_id,
    s.ga_session_id,
    CONCAT(COALESCE(s.source,'(direct)'), ' / ', COALESCE(s.medium,'(none)')) AS channel,
    COUNT(*) OVER (PARTITION BY s.user_pseudo_id) AS touch_count
  FROM session_agg s
  INNER JOIN converted_users c USING (user_pseudo_id)
)

-- チャネルごとに線形配分の合計を集計
SELECT
  channel,
  ROUND(SUM(1.0 / touch_count), 2) AS linear_attribution_score,
  COUNT(*)                          AS total_touchpoints
FROM user_touch
GROUP BY channel
ORDER BY linear_attribution_score DESC;
```

### 428. 広告クリエイティブ別のLTVをBigQueryで追跡して勝ちパターンを見つける（BigQueryでの初回流入情報の取得）

**用途**: BigQueryでの初回流入情報の取得

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です / `SELECT *` を含みます。必要な列だけに絞るとコストが下がります

```sql
WITH first_touch AS (
  SELECT
    user_pseudo_id,
    MIN(event_timestamp) AS first_event_timestamp,
    -- ga_session_id は event_params から取得する（直接参照不可）
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
      LIMIT 1
    ) AS session_id,
    collected_traffic_source.manual_medium   AS first_medium,
    collected_traffic_source.manual_source   AS first_source,
    collected_traffic_source.manual_campaign_name AS first_campaign,
    collected_traffic_source.manual_content  AS first_creative
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
    AND event_name = 'session_start'
    AND collected_traffic_source.manual_medium IS NOT NULL
  GROUP BY
    user_pseudo_id,
    session_id,
    first_medium,
    first_source,
    first_campaign,
    first_creative
),
-- 各ユーザーの最初のセッションのみを残す
first_session AS (
  SELECT
    user_pseudo_id,
    first_medium,
    first_source,
    first_campaign,
    first_creative,
    first_event_timestamp
  FROM first_touch
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY user_pseudo_id
    ORDER BY first_event_timestamp ASC
  ) = 1
)

SELECT * FROM first_session
LIMIT 100;
```

### 429. 広告クリエイティブ別のLTVをBigQueryで追跡して勝ちパターンを見つける（クリエイティブ別LTVを集計するSQLクエリ）

**用途**: クリエイティブ別LTVを集計するSQLクエリ

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH first_session AS (
  -- （上記のfirst_sessionクエリをここに挿入）
  SELECT
    user_pseudo_id,
    first_medium,
    first_source,
    first_campaign,
    first_creative,
    first_event_timestamp
  FROM (
    SELECT
      user_pseudo_id,
      collected_traffic_source.manual_medium   AS first_medium,
      collected_traffic_source.manual_source   AS first_source,
      collected_traffic_source.manual_campaign_name AS first_campaign,
      collected_traffic_source.manual_content  AS first_creative,
      MIN(event_timestamp) AS first_event_timestamp,
      ROW_NUMBER() OVER (
        PARTITION BY user_pseudo_id
        ORDER BY MIN(event_timestamp) ASC
      ) AS rn
    FROM
      `${PROJECT}.${DATASET}.events_*`
    WHERE
      _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
      AND event_name = 'session_start'
      AND collected_traffic_source.manual_medium IS NOT NULL
    GROUP BY
      user_pseudo_id,
      first_medium,
      first_source,
      first_campaign,
      first_creative
  )
  WHERE rn = 1
),

-- 購買イベントの集計
purchases AS (
  SELECT
    user_pseudo_id,
    event_timestamp AS purchase_timestamp,
    ecommerce.purchase_revenue AS revenue,
    (
      SELECT value.string_value
      FROM UNNEST(event_params)
      WHERE key = 'transaction_id'
      LIMIT 1
    ) AS transaction_id
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
    AND event_name = 'purchase'
    AND ecommerce.purchase_revenue IS NOT NULL
),

-- 初回流入情報と購買を結合してLTVを計算
user_ltv AS (
  SELECT
    fs.user_pseudo_id,
    fs.first_campaign,
    fs.first_creative,
    fs.first_medium,
    fs.first_source,
    COUNT(DISTINCT p.transaction_id)          AS purchase_count,
    ROUND(SUM(p.revenue), 2)                  AS total_revenue
  FROM first_session fs
  LEFT JOIN purchases p
    ON fs.user_pseudo_id = p.user_pseudo_id
  GROUP BY
    fs.user_pseudo_id,
    fs.first_campaign,
    fs.first_creative,
    fs.first_medium,
    fs.first_source
)

-- クリエイティブ別に集計
SELECT
  first_campaign,
  first_creative,
  first_medium,
  first_source,
  COUNT(DISTINCT user_pseudo_id)              AS user_count,
  SUM(purchase_count)                         AS total_orders,
  ROUND(AVG(total_revenue), 2)                AS avg_ltv_per_user,
  ROUND(SUM(total_revenue), 2)                AS total_revenue,
  ROUND(SUM(purchase_count) / NULLIF(COUNT(DISTINCT user_pseudo_id), 0), 2) AS avg_orders_per_user
FROM user_ltv
GROUP BY
  first_campaign,
  first_creative,
  first_medium,
  first_source
ORDER BY
  avg_ltv_per_user DESC;
```

### 430. EC広告費の予算配分をBigQueryの過去データから最適化するフレームワーク（チャネル別のパフォーマンスをBigQueryで可視化する）

**用途**: チャネル別のパフォーマンスをBigQueryで可視化する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH session_base AS (
  SELECT
    CONCAT(
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ga_session_id'),
      '-',
      user_pseudo_id
    ) AS session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    event_name
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
                      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
),
session_summary AS (
  SELECT
    session_id,
    MAX(medium) AS medium,
    MAX(source) AS source,
    COUNTIF(event_name = 'session_start') AS sessions,
    COUNTIF(event_name = 'purchase') AS purchases
  FROM session_base
  GROUP BY session_id
)
SELECT
  COALESCE(medium, '(none)') AS medium,
  COALESCE(source, '(direct)') AS source,
  COUNT(DISTINCT session_id) AS total_sessions,
  SUM(purchases) AS total_purchases,
  ROUND(SAFE_DIVIDE(SUM(purchases), COUNT(DISTINCT session_id)) * 100, 2) AS cvr_pct
FROM session_summary
GROUP BY medium, source
ORDER BY total_purchases DESC
LIMIT 20;
```

### 431. BigQueryで広告の貢献度をデータドリブンアトリビューションで再計算する（BigQueryでコンバージョン経路を抽出するSQL）

**用途**: BigQueryでコンバージョン経路を抽出するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH session_base AS (
  SELECT
    user_pseudo_id,
    -- ga_session_id は event_params から取得
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS ga_session_id,
    event_name,
    event_timestamp,
    -- 流入元は collected_traffic_source から参照
    collected_traffic_source.manual_source   AS source,
    collected_traffic_source.manual_medium  AS medium
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250731'
    AND event_name IN ('session_start', 'purchase')
),

-- セッション単位に流入元を集約
session_source AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    MAX(source)  AS source,
    MAX(medium)  AS medium,
    MAX(event_timestamp) AS session_ts,
    MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) AS is_converted
  FROM session_base
  GROUP BY 1, 2
),

-- ユーザーごとにセッションを時系列で並べてコンバージョン経路を構築
conversion_path AS (
  SELECT
    user_pseudo_id,
    STRING_AGG(
      CONCAT(COALESCE(source, '(direct)'), ' / ', COALESCE(medium, '(none)')),
      ' > '
      ORDER BY session_ts
    ) AS path,
    MAX(is_converted) AS converted
  FROM session_source
  GROUP BY user_pseudo_id
)

SELECT
  path,
  COUNT(*)                                        AS total_users,
  SUM(converted)                                  AS conversions,
  ROUND(SUM(converted) / COUNT(*) * 100, 2)       AS conversion_rate_pct
FROM conversion_path
GROUP BY path
ORDER BY conversions DESC
LIMIT 30;
```

### 432. BigQueryでGoogle広告×GA4データを結合してキーワード別の真のROASを計算する（GA4側でキーワード別売上を集計するSQL）

**用途**: GA4側でキーワード別売上を集計するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です / `SELECT *` を含みます。必要な列だけに絞るとコストが下がります

```sql
WITH ga4_raw AS (
  SELECT
    user_pseudo_id,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,
    collected_traffic_source.manual_medium  AS medium,
    collected_traffic_source.manual_source  AS source,
    collected_traffic_source.manual_term    AS keyword,
    event_date,
    event_name,
    ecommerce.purchase_revenue              AS revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
),

-- cpcかつgoogle流入のセッションに絞る
paid_search_sessions AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    MAX(keyword)    AS keyword,
    MAX(event_date) AS event_date
  FROM ga4_raw
  WHERE
    medium = 'cpc'
    AND source = 'google'
    AND keyword IS NOT NULL
  GROUP BY
    user_pseudo_id,
    ga_session_id
),

-- purchaseイベントの売上をセッションに紐づける
session_revenue AS (
  SELECT
    r.user_pseudo_id,
    r.ga_session_id,
    SUM(r.revenue) AS session_revenue
  FROM ga4_raw r
  WHERE r.event_name = 'purchase'
  GROUP BY
    r.user_pseudo_id,
    r.ga_session_id
),

-- キーワード別に集計
keyword_ga4 AS (
  SELECT
    s.keyword,
    COUNT(DISTINCT CONCAT(s.user_pseudo_id, CAST(s.ga_session_id AS STRING))) AS sessions,
    COALESCE(SUM(sr.session_revenue), 0) AS revenue
  FROM paid_search_sessions s
  LEFT JOIN session_revenue sr
    ON s.user_pseudo_id = sr.user_pseudo_id
    AND s.ga_session_id = sr.ga_session_id
  GROUP BY
    s.keyword
)

SELECT * FROM keyword_ga4
ORDER BY revenue DESC;
```

### 433. BigQueryでGoogle広告×GA4データを結合してキーワード別の真のROASを計算する（Google広告データと結合してキーワード別ROASを算出するSQL）

**用途**: Google広告データと結合してキーワード別ROASを算出するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH ga4_raw AS (
  SELECT
    user_pseudo_id,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,
    collected_traffic_source.manual_medium  AS medium,
    collected_traffic_source.manual_source  AS source,
    collected_traffic_source.manual_term    AS keyword,
    event_date,
    event_name,
    ecommerce.purchase_revenue              AS revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
),

paid_search_sessions AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    MAX(keyword) AS keyword
  FROM ga4_raw
  WHERE
    medium = 'cpc'
    AND source = 'google'
    AND keyword IS NOT NULL
  GROUP BY
    user_pseudo_id,
    ga_session_id
),

session_revenue AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    SUM(revenue) AS session_revenue
  FROM ga4_raw
  WHERE event_name = 'purchase'
  GROUP BY
    user_pseudo_id,
    ga_session_id
),

keyword_ga4 AS (
  SELECT
    LOWER(TRIM(s.keyword)) AS keyword_normalized,
    COUNT(DISTINCT CONCAT(s.user_pseudo_id, CAST(s.ga_session_id AS STRING))) AS sessions,
    COALESCE(SUM(sr.session_revenue), 0) AS revenue
  FROM paid_search_sessions s
  LEFT JOIN session_revenue sr
    ON s.user_pseudo_id = sr.user_pseudo_id
    AND s.ga_session_id = sr.ga_session_id
  GROUP BY
    keyword_normalized
),

keyword_ads AS (
  SELECT
    LOWER(TRIM(keyword_text)) AS keyword_normalized,
    SUM(cost)                 AS cost,
    SUM(clicks)               AS clicks,
    SUM(impressions)          AS impressions
  FROM
    `your_project.ads_data.keyword_stats`
  WHERE
    date BETWEEN '2025-06-01' AND '2025-06-30'
  GROUP BY
    keyword_normalized
)

-- 結合してROASを算出
SELECT
  COALESCE(g.keyword_normalized, a.keyword_normalized) AS keyword,
  COALESCE(a.cost, 0)         AS cost,
  COALESCE(a.clicks, 0)       AS clicks,
  COALESCE(a.impressions, 0)  AS impressions,
  COALESCE(g.sessions, 0)     AS ga4_sessions,
  COALESCE(g.revenue, 0)      AS ga4_revenue,
  CASE
    WHEN COALESCE(a.cost, 0) = 0 THEN NULL
    ELSE ROUND(COALESCE(g.revenue, 0) / a.cost, 2)
  END AS roas
FROM keyword_ga4 g
FULL OUTER JOIN keyword_ads a
  ON g.keyword_normalized = a.keyword_normalized
ORDER BY
  ga4_revenue DESC;
```

### 434. BigQueryでリスティング広告の検索クエリとGA4行動データを突合分析する（Google広告の検索クエリデータと突合する）

**用途**: Google広告の検索クエリデータと突合する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH ga4_sessions AS (
  SELECT
    user_pseudo_id,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,
    collected_traffic_source.manual_term AS keyword,
    event_name,
    (
      SELECT value.string_value
      FROM UNNEST(event_params)
      WHERE key = 'page_location'
    ) AS page_location,
    DATE(TIMESTAMP_MICROS(event_timestamp)) AS event_date
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
    AND collected_traffic_source.manual_medium = 'cpc'
),

ads_queries AS (
  SELECT
    Query AS search_query,
    Clicks,
    Cost,
    Conversions,
    Date AS query_date
  FROM
    `your_project.google_ads_export.SearchQueryPerformance`
  WHERE
    Date BETWEEN '2025-06-01' AND '2025-06-30'
)

SELECT
  aq.search_query,
  aq.Clicks,
  aq.Cost,
  aq.Conversions,
  COUNT(DISTINCT CONCAT(gs.user_pseudo_id, CAST(gs.ga_session_id AS STRING))) AS ga4_sessions,
  COUNTIF(gs.event_name = 'purchase') AS purchase_events,
  COUNTIF(gs.event_name = 'generate_lead') AS lead_events
FROM
  ads_queries aq
LEFT JOIN
  ga4_sessions gs
  ON aq.search_query = gs.keyword
  AND aq.query_date = gs.event_date
GROUP BY
  aq.search_query, aq.Clicks, aq.Cost, aq.Conversions
ORDER BY
  aq.Cost DESC
LIMIT 100
```

### 435. BigQuery × Looker Studioで広告媒体横断ROASダッシュボードを構築する全手順（4. BigQueryで統合ビューを作成する）

**用途**: 4. BigQueryで統合ビューを作成する

**必要なテーブル**: `${DATASET}.ad_cost`, `${DATASET}.events_*`, `${DATASET}.v_roas_summary`

**コストの注意**: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください

```sql
CREATE OR REPLACE VIEW `${PROJECT}.${DATASET}.v_roas_summary` AS

WITH ga4_revenue AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS date,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    SUM(ecommerce.purchase_revenue) AS revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    event_name = 'purchase'
  GROUP BY
    1, 2, 3
),

ad_cost AS (
  SELECT
    date,
    medium,
    source,
    SUM(cost) AS cost
  FROM
    `${PROJECT}.${DATASET}.ad_cost`
  GROUP BY
    1, 2, 3
)

SELECT
  COALESCE(r.date, c.date) AS date,
  COALESCE(r.medium, c.medium) AS medium,
  COALESCE(r.source, c.source) AS source,
  COALESCE(r.revenue, 0) AS revenue,
  COALESCE(c.cost, 0) AS cost,
  SAFE_DIVIDE(COALESCE(r.revenue, 0), COALESCE(c.cost, 0)) AS roas
FROM
  ga4_revenue r
FULL OUTER JOIN
  ad_cost c
  ON r.date = c.date
  AND r.medium = c.medium
  AND r.source = c.source
```

### 436. Cookie規制後のEC広告効果測定をファーストパーティデータ×BigQueryで再構築する

**用途**: BigQueryでチャネル別コンバージョンを集計するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH purchase_sessions AS (
  SELECT
    -- セッションIDはevent_paramsをUNNESTして取得
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id,
    user_pseudo_id,
    -- 流入元はcollected_traffic_sourceから取得
    collected_traffic_source.manual_source       AS traffic_source,
    collected_traffic_source.manual_medium       AS traffic_medium,
    collected_traffic_source.manual_campaign_name AS campaign_name,
    (
      SELECT ep.value.double_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'value'
    ) AS purchase_value,
    event_date
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
    AND event_name = 'purchase'
)

SELECT
  traffic_medium,
  traffic_source,
  campaign_name,
  COUNT(*)                         AS purchase_count,
  COUNT(DISTINCT user_pseudo_id)   AS unique_buyers,
  ROUND(SUM(purchase_value), 0)    AS total_revenue
FROM
  purchase_sessions
GROUP BY
  traffic_medium,
  traffic_source,
  campaign_name
ORDER BY
  total_revenue DESC
;
```

### 437. EC広告費の予算配分をBigQueryの過去データから最適化するフレームワーク（売上貢献額ベースで予算配分の優先順位をつける）

**用途**: 売上貢献額ベースで予算配分の優先順位をつける

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH purchase_events AS (
  SELECT
    CONCAT(
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ga_session_id'),
      '-',
      user_pseudo_id
    ) AS session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'value') AS revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
                      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
    AND event_name = 'purchase'
)
SELECT
  COALESCE(medium, '(none)') AS medium,
  COALESCE(source, '(direct)') AS source,
  COUNT(*) AS purchase_count,
  ROUND(SUM(revenue), 0) AS total_revenue,
  ROUND(AVG(revenue), 0) AS avg_order_value
FROM purchase_events
GROUP BY medium, source
ORDER BY total_revenue DESC;
```

### 438. Google広告データをBigQuery Data Transfer Serviceで自動連携する完全手順（GA4データと掛け合わせて流入経路を確認するSQL）

**用途**: GA4データと掛け合わせて流入経路を確認するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH google_ads_sessions AS (
  SELECT
    -- ga_session_idはevent_paramsのUNNESTで取得する
    (
      SELECT value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id,
    user_pseudo_id,
    -- 流入元はcollected_traffic_sourceから取得
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    COUNT(*) AS event_count
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250731'
    AND collected_traffic_source.manual_medium = 'cpc'
  GROUP BY
    ga_session_id,
    user_pseudo_id,
    medium,
    source
)

SELECT
  source,
  medium,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNT(DISTINCT ga_session_id) AS sessions,
  SUM(event_count) AS total_events
FROM
  google_ads_sessions
GROUP BY
  source,
  medium
ORDER BY
  sessions DESC;
```

### 439. P-MAXキャンペーンの配信実績をBigQueryで詳細分析する方法（エンゲージメント率でセッション品質を評価する）

**用途**: エンゲージメント率でセッション品質を評価する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH session_data AS (
  SELECT
    (SELECT ep.value.string_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')       AS session_id,
    (SELECT ep.value.string_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'session_engaged')     AS engaged,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240701' AND '20240731'
    AND event_name = 'session_start'
    AND collected_traffic_source.manual_source = 'google'
    AND collected_traffic_source.manual_medium = 'cpc'
)

SELECT
  source,
  medium,
  COUNT(DISTINCT session_id)                                        AS total_sessions,
  COUNTIF(engaged = '1')                                            AS engaged_sessions,
  ROUND(
    COUNTIF(engaged = '1') / COUNT(DISTINCT session_id) * 100, 1
  )                                                                 AS engagement_rate_pct
FROM session_data
GROUP BY source, medium
ORDER BY total_sessions DESC
```

### 440. P-MAXキャンペーンの配信実績をBigQueryで詳細分析する方法（Google広告データとの掛け合わせでCPAを算出する）

**用途**: Google広告データとの掛け合わせでCPAを算出する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  ads.campaign_name,
  ROUND(ads.cost_micros / 1000000, 0)              AS cost_jpy,
  ga.conversions,
  ROUND(
    (ads.cost_micros / 1000000) / NULLIF(ga.conversions, 0), 0
  )                                                AS cpa_jpy
FROM (
  SELECT
    campaign_name,
    SUM(cost_micros) AS cost_micros
  FROM `your_project.google_ads_transfer.p_Campaign_XXXXXXXXX`
  WHERE _PARTITIONDATE = '2024-07-31'
  GROUP BY campaign_name
) AS ads
LEFT JOIN (
  SELECT
    collected_traffic_source.manual_source AS source,
    COUNT(*) AS conversions
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX = '20240731'
    AND event_name = 'purchase'
    AND collected_traffic_source.manual_source = 'google'
    AND collected_traffic_source.manual_medium = 'cpc'
  GROUP BY source
) AS ga
ON TRUE  -- キャンペーン名でのJOINはUTM設定が必要
```

### 441. Google広告のオフラインコンバージョンをBigQuery経由で自動化する（CRMデータと結合してコンバージョンテーブルを作る）

**用途**: CRMデータと結合してコンバージョンテーブルを作る

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH gclid_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.string_value
     FROM UNNEST(event_params)
     WHERE key = 'gclid') AS gclid,
    DATE(TIMESTAMP_MICROS(event_timestamp)) AS click_date
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
    AND event_name = 'session_start'
    AND collected_traffic_source.manual_medium = 'cpc'
),
conversions AS (
  SELECT
    user_email,
    contract_date,
    contract_value,
    crm_user_id
  FROM
    `your_project.crm_dataset.contracts`
  WHERE
    contract_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
)
SELECT
  g.gclid,
  c.contract_date AS conversion_time,
  'Offline_Contract' AS conversion_name,
  c.contract_value AS conversion_value,
  'JPY' AS currency_code
FROM
  gclid_sessions g
  INNER JOIN `your_project.crm_dataset.users` u
    ON g.user_pseudo_id = u.ga_user_pseudo_id
  INNER JOIN conversions c
    ON u.user_email = c.user_email
WHERE
  g.gclid IS NOT NULL
```

### 442. BigQueryでリスティング広告の検索クエリとGA4行動データを突合分析する（分析視点：クエリごとのサイト行動をどう読むか）

**用途**: 分析視点：クエリごとのサイト行動をどう読むか

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  (
    SELECT value.string_value
    FROM UNNEST(event_params)
    WHERE key = 'page_location'
  ) AS page_location,
  COUNT(*) AS view_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'page_view'
  AND collected_traffic_source.manual_medium = 'cpc'
  AND CONCAT(user_pseudo_id, CAST(
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS STRING
  )) IN (
    -- 購入セッションのIDリスト（サブクエリやWITH句で生成）
    SELECT DISTINCT
      CONCAT(user_pseudo_id, CAST(
        (
          SELECT value.int_value
          FROM UNNEST(event_params)
          WHERE key = 'ga_session_id'
        ) AS STRING
      ))
    FROM
      `${PROJECT}.${DATASET}.events_*`
    WHERE
      _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
      AND event_name = 'purchase'
  )
GROUP BY page_location
ORDER BY view_count DESC
```

### 443. BigQuery × Looker Studioで広告媒体横断ROASダッシュボードを構築する全手順（2. GA4 BigQueryエクスポートからROAS計算に必要なデータを取得する）

**用途**: 2. GA4 BigQueryエクスポートからROAS計算に必要なデータを取得する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS date,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.string_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')
  ) AS sessions,
  SUM(ecommerce.purchase_revenue) AS revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  event_name = 'purchase'
  AND _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
GROUP BY
  1, 2, 3
ORDER BY
  date DESC
```

### 444. EC広告費の予算配分をBigQueryの過去データから最適化するフレームワーク（月別トレンドから季節変動と広告効果の相関を読む）

**用途**: 月別トレンドから季節変動と広告効果の相関を読む

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m%d', event_date)) AS month,
  COALESCE(collected_traffic_source.manual_medium, '(none)') AS medium,
  COUNT(*) AS purchase_count,
  ROUND(
    SUM(
      (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'value')
    ), 0
  ) AS total_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY))
                    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  AND event_name = 'purchase'
GROUP BY month, medium
ORDER BY month ASC, total_revenue DESC;
```

### 445. LINE広告×GA4×BigQueryでCPA・ROASを正確に計測する設定と集計SQL（BIgQueryでLINE広告の流入セッションを抽出するSQL）

**用途**: BIgQueryでLINE広告の流入セッションを抽出するSQL

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  user_pseudo_id,
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_id'
  ) AS ga_session_id,
  collected_traffic_source.manual_source     AS traffic_source,
  collected_traffic_source.manual_medium     AS traffic_medium,
  collected_traffic_source.manual_campaign_name AS campaign_name,
  MIN(event_timestamp) AS session_start_ts
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
  AND collected_traffic_source.manual_medium = 'cpc'
  AND collected_traffic_source.manual_source = 'line'
  AND event_name = 'session_start'
GROUP BY
  1, 2, 3, 4, 5
```

### 446. P-MAXキャンペーンの配信実績をBigQueryで詳細分析する方法（SQLでP-MAX流入のランディングページを分析する）

**用途**: SQLでP-MAX流入のランディングページを分析する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_date,
  collected_traffic_source.manual_source   AS source,
  collected_traffic_source.manual_medium   AS medium,
  (SELECT ep.value.string_value
   FROM UNNEST(event_params) AS ep
   WHERE ep.key = 'page_location')         AS landing_page,
  COUNT(DISTINCT
    (SELECT ep.value.string_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  )                                         AS sessions,
  COUNTIF(event_name = 'purchase')          AS conversions
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240701' AND '20240731'
  AND collected_traffic_source.manual_source = 'google'
  AND collected_traffic_source.manual_medium = 'cpc'
GROUP BY
  event_date, source, medium, landing_page
ORDER BY
  sessions DESC
LIMIT 50
```

### 447. サーバーサイドGTM × Consent Mode v2で広告計測精度を維持する【2026年版】

**用途**: GA4 × BigQueryで同意率を可視化する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo') AS event_date,
  (
    SELECT value.string_value
    FROM UNNEST(event_params)
    WHERE key = 'analytics_storage'
  ) AS analytics_storage,
  (
    SELECT value.string_value
    FROM UNNEST(event_params)
    WHERE key = 'ad_storage'
  ) AS ad_storage,
  (
    SELECT value.string_value
    FROM UNNEST(event_params)
    WHERE key = 'ad_user_data'
  ) AS ad_user_data,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(*) AS event_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE('Asia/Tokyo'))
  AND event_name = 'consent_update'
GROUP BY
  1, 2, 3, 4, 5, 6
ORDER BY
  event_date DESC
```

### 448. Yahoo!広告データをBigQueryに取り込んでGoogle広告と統合分析する方法（媒体横断の集計クエリ実例） その1

**用途**: 媒体横断の集計クエリ実例

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  media_source,
  FORMAT_DATE('%Y-%m', report_date) AS year_month,
  SUM(cost_jpy) AS total_cost,
  SUM(conversions) AS total_conversions,
  ROUND(
    SAFE_DIVIDE(SUM(cost_jpy), SUM(conversions)),
    0
  ) AS cpa
FROM
  `your_project.ads_dataset.unified_ads_stats`
WHERE
  report_date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 3 MONTH) AND CURRENT_DATE()
GROUP BY
  media_source, year_month
ORDER BY
  year_month, media_source
;
```

### 449. Yahoo!広告データをBigQueryに取り込んでGoogle広告と統合分析する方法（媒体横断の集計クエリ実例） その2

**用途**: 媒体横断の集計クエリ実例

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
SELECT
  media_source,
  campaign_name,
  SUM(impressions) AS impressions,
  SUM(clicks) AS clicks,
  SUM(conversions) AS conversions,
  ROUND(SAFE_DIVIDE(SUM(clicks), SUM(impressions)) * 100, 2) AS ctr_pct,
  ROUND(SAFE_DIVIDE(SUM(conversions), SUM(clicks)) * 100, 2) AS cvr_pct
FROM
  `your_project.ads_dataset.unified_ads_stats`
WHERE
  report_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY
  media_source, campaign_name
ORDER BY
  media_source, cvr_pct DESC
;
```

### 450. Yahoo!広告データをBigQueryに取り込んでGoogle広告と統合分析する方法（GA4データと組み合わせてユーザー行動を深掘りする）

**用途**: GA4データと組み合わせてユーザー行動を深掘りする

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  event_date,
  COUNT(DISTINCT
    (SELECT value.string_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')
  ) AS sessions,
  ROUND(
    AVG(
      (SELECT value.int_value
       FROM UNNEST(event_params)
       WHERE key = 'engagement_time_msec') / 1000.0
    ),
    1
  ) AS avg_engagement_sec
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  AND collected_traffic_source.manual_medium = 'cpc'
  AND collected_traffic_source.manual_source LIKE '%yahoo%'
  AND event_name = 'session_start'
GROUP BY
  event_date
ORDER BY
  event_date
;
```

### 451. LINE広告×GA4×BigQueryでCPA・ROASを正確に計測する設定と集計SQL（CPA・ROASをSQLで集計する）

**用途**: CPA・ROASをSQLで集計する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
WITH line_sessions AS (
  -- LINE広告経由のセッションを特定
  SELECT
    user_pseudo_id,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
    AND event_name = 'session_start'
    AND collected_traffic_source.manual_medium = 'cpc'
    AND collected_traffic_source.manual_source = 'line'
),

purchases AS (
  -- 購入イベントとセッションIDを紐付け
  SELECT
    e.user_pseudo_id,
    (
      SELECT value.int_value
      FROM UNNEST(e.event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,
    (
      SELECT value.double_value
      FROM UNNEST(e.event_params)
      WHERE key = 'value'
    ) AS purchase_revenue
  FROM
    `${PROJECT}.${DATASET}.events_*` AS e
  WHERE
    _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
    AND e.event_name = 'purchase'
)

SELECT
  COUNT(DISTINCT p.user_pseudo_id || CAST(p.ga_session_id AS STRING)) AS conversions,
  SUM(p.purchase_revenue)                                              AS total_revenue,
  -- 広告費は手動で入力（例: 50000円）
  50000                                                                AS ad_spend,
  ROUND(50000 / NULLIF(COUNT(DISTINCT p.user_pseudo_id || CAST(p.ga_session_id AS STRING)), 0), 0) AS cpa,
  ROUND(SUM(p.purchase_revenue) / NULLIF(50000, 0), 2)                AS roas
FROM
  purchases AS p
INNER JOIN
  line_sessions AS ls
  ON p.user_pseudo_id = ls.user_pseudo_id
  AND p.ga_session_id  = ls.ga_session_id
```

### 452. Google広告データをBigQuery Data Transfer Serviceで自動連携する完全手順（キャンペーン別コストとコンバージョンを確認するSQL）

**用途**: キャンペーン別コストとコンバージョンを確認するSQL

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  campaign.name AS campaign_name,
  metrics.impressions AS impressions,
  metrics.clicks AS clicks,
  ROUND(metrics.cost_micros / 1000000, 0) AS cost_jpy,
  metrics.conversions AS conversions,
  SAFE_DIVIDE(
    ROUND(metrics.cost_micros / 1000000, 0),
    metrics.conversions
  ) AS cpa
FROM
  `YOUR_PROJECT.google_ads_transfer.ads_Campaign_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20250731'
ORDER BY
  cost_jpy DESC
LIMIT 20;
```

### 453. BigQueryで広告の貢献度をデータドリブンアトリビューションで再計算する（分析結果をLooker Studioで可視化する）

**用途**: 分析結果をLooker Studioで可視化する

**必要なテーブル**: `${DATASET}.v_linear_attribution`

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
CREATE OR REPLACE VIEW `${PROJECT}.${DATASET}.v_linear_attribution` AS
SELECT
  channel,
  ROUND(SUM(1.0 / touch_count), 2) AS linear_attribution_score,
  COUNT(*) AS total_touchpoints
FROM (
  -- ※上記SQLのuser_touchサブクエリをここに展開
  SELECT 'placeholder' AS channel, 1 AS touch_count  -- 実際はuser_touchの内容を展開
) t
GROUP BY channel;
```

### 454. BigQueryでリスティング広告の検索クエリとGA4行動データを突合分析する（GA4テーブルから流入クエリとセッション行動を抽出する）

**用途**: GA4テーブルから流入クエリとセッション行動を抽出する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  user_pseudo_id,
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_id'
  ) AS ga_session_id,
  collected_traffic_source.manual_source AS traffic_source,
  collected_traffic_source.manual_medium AS traffic_medium,
  collected_traffic_source.manual_term AS keyword,
  event_name,
  event_timestamp,
  (
    SELECT value.string_value
    FROM UNNEST(event_params)
    WHERE key = 'page_location'
  ) AS page_location
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND collected_traffic_source.manual_medium = 'cpc'
  AND event_name IN ('page_view', 'purchase', 'generate_lead')
```

### 455. Google広告のオフラインコンバージョンをBigQuery経由で自動化する（GA4 BigQueryエクスポートからGCLIDを取得する）

**用途**: GA4 BigQueryエクスポートからGCLIDを取得する

**必要なテーブル**: `${DATASET}.events_*`

**コストの注意**: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です

```sql
SELECT
  user_pseudo_id,
  event_date,
  event_timestamp,
  (SELECT value.string_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_id') AS ga_session_id,
  (SELECT value.string_value
   FROM UNNEST(event_params)
   WHERE key = 'gclid') AS gclid,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  AND event_name = 'session_start'
  AND collected_traffic_source.manual_medium = 'cpc'
```

### 456. Yahoo!広告データをBigQueryに取り込んでGoogle広告と統合分析する方法（BigQueryにおける統合テーブルの設計方針）

**用途**: BigQueryにおける統合テーブルの設計方針

**コストの注意**: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください

```sql
CREATE OR REPLACE VIEW `your_project.ads_dataset.unified_ads_stats` AS

-- Google広告データ
SELECT
  'google' AS media_source,
  DATE(segments.date) AS report_date,
  campaign.name AS campaign_name,
  metrics.impressions AS impressions,
  metrics.clicks AS clicks,
  ROUND(metrics.cost_micros / 1000000, 2) AS cost_jpy,
  metrics.conversions AS conversions
FROM
  `your_project.google_ads.p_ads_CampaignBasicStats_*`

UNION ALL

-- Yahoo!広告データ（取り込み済みのテーブルを参照）
SELECT
  'yahoo' AS media_source,
  report_date,
  campaign_name,
  impressions,
  clicks,
  cost AS cost_jpy,
  conversions
FROM
  `your_project.yahoo_ads.campaign_report`
;
```
