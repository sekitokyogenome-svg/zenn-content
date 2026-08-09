-- 出典: GA4×BigQueryでカスタムディメンションを活用した分析
-- 記事: articles/ga4-bigquery-custom-dimensions.md（実践例1：ABテストのバリアント別コンバージョン分析）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

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
