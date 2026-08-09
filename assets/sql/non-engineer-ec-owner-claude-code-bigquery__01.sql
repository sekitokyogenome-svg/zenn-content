-- 出典: 非エンジニアEC経営者がClaude Code × BigQueryで自走できるようになるまで
-- 記事: articles/non-engineer-ec-owner-claude-code-bigquery.md（返ってきたSQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

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
