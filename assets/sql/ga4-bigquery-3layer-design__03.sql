-- 出典: GA4のデータをBigQueryに繋ぐと何が変わるのか【3層設計まで解説】
-- 記事: articles/ga4-bigquery-3layer-design.md（mart層）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- mart例：チャネル別セッション数・CV数の集計
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
