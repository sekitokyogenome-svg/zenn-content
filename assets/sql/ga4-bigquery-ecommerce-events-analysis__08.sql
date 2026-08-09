-- 出典: BigQueryでGA4のeコマースイベントを完全解析する【purchase/add_to_cart】
-- 記事: articles/ga4-bigquery-ecommerce-events-analysis.md（2. event_paramsのkey名を間違える）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- NG: keyの名前が違う
(SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'session_id')

-- OK: 正しいkey名
(SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
