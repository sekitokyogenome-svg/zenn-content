-- 362. BigQueryのデータリネージ機能でデータマートの依存関係を可視化する（GA4データを使ったビューの依存関係を実際に確認する） その1
-- 用途: GA4データを使ったビューの依存関係を実際に確認する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE VIEW `${PROJECT}.${DATASET}.stg_sessions` AS
SELECT
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  SUM(ecommerce.purchase_revenue) AS revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
  AND event_name = 'purchase'
GROUP BY
  user_pseudo_id,
  ga_session_id,
  medium,
  source
;
