-- 出典: BigQueryのBI Engineを有効化してLooker Studioの表示速度を改善する
-- 記事: articles/bigquery-bi-engine-looker-studio-speedup.md（GA4データを使ったLooker Studio向けクエリの最適化例）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- GA4セッションサマリービュー（Looker Studio用）
-- プロジェクトID・データセット名は環境に合わせて変更してください
CREATE OR REPLACE VIEW `${PROJECT}.${DATASET}.v_session_summary` AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS session_date,
  -- セッションIDはevent_paramsのUNNESTから取得する
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_id'
  ) AS ga_session_id,
  user_pseudo_id,
  -- 流入元はcollected_traffic_sourceから参照する
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  geo.country AS country,
  device.category AS device_category,
  event_name
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
;
