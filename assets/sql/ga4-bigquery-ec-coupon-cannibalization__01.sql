-- 出典: GA4×BigQueryでECクーポン施策のカニバリゼーションを検証する
-- 記事: articles/ga4-bigquery-ec-coupon-cannibalization.md（ステップ1：クーポン利用有無別の購入数と売上を流入元ごとに集計する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH purchase_events AS (
  SELECT
    user_pseudo_id,
    -- ga_session_id は UNNEST 経由で取得（直接参照不可）
    (SELECT value.int_value
       FROM UNNEST(event_params)
      WHERE key = 'ga_session_id') AS session_id,
    -- クーポンコードも同様に取得
    (SELECT value.string_value
       FROM UNNEST(event_params)
      WHERE key = 'coupon') AS coupon_code,
    (SELECT value.double_value
       FROM UNNEST(event_params)
      WHERE key = 'value') AS purchase_value,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source  AS source
  FROM
    `${PROJECT}.${DATASET}.events_20250801`
  WHERE
    event_name = 'purchase'
)

SELECT
  CASE
    WHEN coupon_code IS NOT NULL AND coupon_code != ''
    THEN 'クーポン使用'
    ELSE 'クーポン未使用'
  END AS coupon_flag,
  medium,
  source,
  COUNT(*)                        AS purchase_count,
  ROUND(SUM(purchase_value), 0)   AS total_revenue
FROM purchase_events
GROUP BY coupon_flag, medium, source
ORDER BY total_revenue DESC;
