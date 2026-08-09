-- GA4のデータをBigQueryに繋ぐと何が変わるのか【3層設計まで解説】
-- 用途: staging層
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE VIEW `project.staging.stg_page_views` AS
SELECT
  event_date,
  user_pseudo_id,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') AS source
FROM `${PROJECT}.${DATASET}.events_*`
WHERE event_name = 'page_view'
