-- 出典: GTM × GA4でA/Bテスト結果を自動計測する仕組みを作る
-- 記事: articles/gtm-ga4-ab-test-auto-tracking.md（バリアント別のコンバージョン率を算出）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

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
