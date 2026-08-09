-- ECの送料無料ラインをBigQueryの購買データから最適設定する分析手法
-- 用途: 注文金額の分布を把握する
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH purchase_events AS (
  SELECT
    event_date,
    user_pseudo_id,
    (
      SELECT COALESCE(ep.value.int_value, ep.value.float_value, ep.value.double_value)
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'value'
    ) AS purchase_value
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
    AND event_name = 'purchase'
)

SELECT
  CASE
    WHEN purchase_value < 2000  THEN '〜2,000円未満'
    WHEN purchase_value < 3000  THEN '2,000〜3,000円未満'
    WHEN purchase_value < 4000  THEN '3,000〜4,000円未満'
    WHEN purchase_value < 5000  THEN '4,000〜5,000円未満'
    WHEN purchase_value < 7000  THEN '5,000〜7,000円未満'
    ELSE                             '7,000円以上'
  END AS price_range,
  COUNT(*) AS order_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pct
FROM
  purchase_events
WHERE
  purchase_value IS NOT NULL
GROUP BY
  price_range
ORDER BY
  MIN(purchase_value)
