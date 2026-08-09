-- GA4のデータをBigQueryに繋ぐと何が変わるのか【3層設計まで解説】
-- 出典: articles/ga4-bigquery-3layer-design.md

CREATE OR REPLACE VIEW `project.staging.stg_page_views` AS
SELECT
  event_date,
  user_pseudo_id,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') AS source
FROM `${PROJECT}.${DATASET}.events_*`
WHERE event_name = 'page_view'
