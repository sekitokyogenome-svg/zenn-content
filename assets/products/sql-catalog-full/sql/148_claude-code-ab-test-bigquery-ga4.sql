-- 148. Claude CodeでEC×GA4のA/Bテスト結果をBigQueryから自動集計する
-- 用途: Step 1: BigQueryでA/Bテストデータを集計するSQL
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
