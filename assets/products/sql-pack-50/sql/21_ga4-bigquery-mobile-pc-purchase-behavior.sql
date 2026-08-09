-- 21. GA4×BigQueryでモバイルとPCの購買行動の違いを分析した（モバイルの離脱ポイントを深掘りする）
-- 用途: モバイルの離脱ポイントを深掘りする
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH cart_users AS (
  SELECT
    user_pseudo_id,
    MIN(event_timestamp) AS cart_time
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'add_to_cart'
    AND device.category = 'mobile'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
  GROUP BY user_pseudo_id
),
purchase_users AS (
  SELECT
    user_pseudo_id,
    MIN(event_timestamp) AS purchase_time
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
  GROUP BY user_pseudo_id
)
SELECT
  CASE
    WHEN p.user_pseudo_id IS NULL THEN '未購入'
    WHEN TIMESTAMP_DIFF(
      TIMESTAMP_MICROS(p.purchase_time),
      TIMESTAMP_MICROS(c.cart_time),
      HOUR
    ) <= 1 THEN '1時間以内'
    WHEN TIMESTAMP_DIFF(
      TIMESTAMP_MICROS(p.purchase_time),
      TIMESTAMP_MICROS(c.cart_time),
      HOUR
    ) <= 24 THEN '24時間以内'
    WHEN TIMESTAMP_DIFF(
      TIMESTAMP_MICROS(p.purchase_time),
      TIMESTAMP_MICROS(c.cart_time),
      HOUR
    ) <= 168 THEN '1週間以内'
    ELSE '1週間以上'
  END AS purchase_timing,
  COUNT(*) AS user_count
FROM cart_users c
LEFT JOIN purchase_users p
  ON c.user_pseudo_id = p.user_pseudo_id
GROUP BY purchase_timing
ORDER BY
  CASE purchase_timing
    WHEN '1時間以内' THEN 1
    WHEN '24時間以内' THEN 2
    WHEN '1週間以内' THEN 3
    WHEN '1週間以上' THEN 4
    WHEN '未購入' THEN 5
  END;
