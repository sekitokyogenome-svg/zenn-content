-- 出典: ECの商品ページ写真枚数×CVRの相関をGA4×BigQueryで検証した
-- 記事: articles/ec-product-photo-cvr-ga4-bigquery-correlation.md（流入元別に見る：オーガニックとSNSでCVRは変わるか）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  event_date,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_id') AS session_id,
  user_pseudo_id
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20250630'
  AND event_name = 'session_start'
