-- 出典: ECのセール施策効果をGA4×BigQueryでbefore/after比較する分析テンプレート
-- 記事: articles/ec-sale-effect-ga4-bigquery-before-after.md（分析に必要なデータ構造の理解）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- ga_session_id の取得（UNNEST経由が必須）
SELECT
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_id') AS session_id

-- 流入元の取得（collected_traffic_source を使用）
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source
