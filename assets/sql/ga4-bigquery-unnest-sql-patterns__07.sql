-- 出典: GA4イベントパラメータをUNNESTで展開するSQLパターン集
-- 記事: articles/ga4-bigquery-unnest-sql-patterns.md（パターン6：トラフィックソースを正しく取得する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  event_date,
  user_pseudo_id,
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_campaign_name AS campaign
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
  AND event_name = 'session_start'
