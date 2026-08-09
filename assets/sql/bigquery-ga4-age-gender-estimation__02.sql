-- 出典: BigQueryでGA4データからEC顧客の年齢・性別推定精度を検証した
-- 記事: articles/bigquery-ga4-age-gender-estimation.md（Step 2: デモグラフィック別のセグメント分析）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

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
