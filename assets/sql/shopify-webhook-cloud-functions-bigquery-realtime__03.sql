-- 出典: ShopifyのWebhook × Cloud Functions × BigQueryでリアルタイム売上基盤を作る
-- 記事: articles/shopify-webhook-cloud-functions-bigquery-realtime.md（BigQueryで売上を集計・分析する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  ep.value.string_value AS ga_session_id,
  t.manual_medium       AS medium,
  t.manual_source       AS source,
  COUNT(*)              AS sessions
FROM
  `${PROJECT}.${DATASET}.events_*`,
  UNNEST(event_params) AS ep
JOIN UNNEST([collected_traffic_source]) AS t
WHERE
  ep.key = 'ga_session_id'
  AND _TABLE_SUFFIX BETWEEN '20260701' AND '20260731'
GROUP BY
  ga_session_id, medium, source;
