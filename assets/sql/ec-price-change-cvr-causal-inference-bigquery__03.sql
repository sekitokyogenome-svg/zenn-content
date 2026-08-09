-- 出典: ECの価格変更がCVRと売上に与えた影響をGA4×BigQueryで因果推論する
-- 記事: articles/ec-price-change-cvr-causal-inference-bigquery.md（売上への影響も合わせて確認する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- セッション当たり売上（RPS）の集計
WITH revenue_base AS (
  SELECT
    DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo') AS event_date,
    user_pseudo_id,
    (SELECT value.int_value  FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    event_name,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_id')   AS item_id,
    ecommerce.purchase_revenue AS revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250731'
    AND event_name IN ('view_item', 'purchase')
)

SELECT
  event_date,
  item_id,
  COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING))) AS sessions,
  SUM(IF(event_name = 'purchase', revenue, 0))                          AS total_revenue,
  SAFE_DIVIDE(
    SUM(IF(event_name = 'purchase', revenue, 0)),
    COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING)))
  ) AS rps
FROM revenue_base
WHERE item_id IS NOT NULL
GROUP BY 1, 2
ORDER BY 1, 2
