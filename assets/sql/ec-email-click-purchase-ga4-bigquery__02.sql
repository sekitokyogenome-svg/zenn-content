-- 出典: ECメルマガのクリック→購入をGA4×BigQueryで追跡してセグメント別効果を測定する
-- 記事: articles/ec-email-click-purchase-ga4-bigquery.md（セグメント別の購入金額を集計するSQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- セグメント別の購入金額集計
WITH email_purchase_events AS (
  SELECT
    user_pseudo_id,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS session_id,
    collected_traffic_source.manual_campaign_name AS utm_campaign,
    (
      SELECT value.double_value
      FROM UNNEST(event_params)
      WHERE key = 'value'
    ) AS purchase_value,
    (
      SELECT value.string_value
      FROM UNNEST(event_params)
      WHERE key = 'currency'
    ) AS currency
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
    AND event_name = 'purchase'
    AND collected_traffic_source.manual_medium = 'email'
)

SELECT
  utm_campaign,
  currency,
  COUNT(*) AS purchase_count,
  ROUND(SUM(purchase_value), 0) AS total_revenue,
  ROUND(AVG(purchase_value), 0) AS avg_order_value
FROM email_purchase_events
WHERE purchase_value IS NOT NULL
GROUP BY utm_campaign, currency
ORDER BY total_revenue DESC;
