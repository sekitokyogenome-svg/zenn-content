-- 出典: BigQueryでGA4データからEC顧客の年齢・性別推定精度を検証した
-- 記事: articles/bigquery-ga4-age-gender-estimation.md（Step 1: デモグラフィックデータのカバレッジを確認する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

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
