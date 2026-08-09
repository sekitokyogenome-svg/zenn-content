-- 130. GA4イベントパラメータをUNNESTで展開するSQLパターン集（パターン6：トラフィックソースを正しく取得する）
-- 用途: パターン6：トラフィックソースを正しく取得する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  event_date,
  user_pseudo_id,
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_campaign_name AS campaign
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
  AND event_name = 'session_start'
