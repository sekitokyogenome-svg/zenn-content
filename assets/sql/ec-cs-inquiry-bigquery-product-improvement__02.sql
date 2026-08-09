-- 出典: ECのCS問い合わせデータをBigQueryに集約して商品改善に活かす方法
-- 記事: articles/ec-cs-inquiry-bigquery-product-improvement.md（GA4データと組み合わせて購入〜問い合わせの流れを把握する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  user_pseudo_id,
  event_date,
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_id'
  ) AS ga_session_id,
  collected_traffic_source.manual_medium AS traffic_medium,
  collected_traffic_source.manual_source AS traffic_source,
  (
    SELECT value.string_value
    FROM UNNEST(event_params)
    WHERE key = 'transaction_id'
  ) AS transaction_id
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  AND event_name = 'purchase'
