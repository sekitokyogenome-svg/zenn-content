-- ECの送料無料ラインをBigQueryの購買データから最適設定する分析手法
-- 用途: カゴ落ちセッションの注文金額帯を特定する
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH sessions AS (
  SELECT
    user_pseudo_id,
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS session_id,
    event_name,
    (
      SELECT COALESCE(ep.value.int_value, ep.value.float_value, ep.value.double_value)
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'value'
    ) AS cart_value
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
    AND event_name IN ('begin_checkout', 'purchase')
),

checkout_sessions AS (
  SELECT user_pseudo_id, session_id, MAX(cart_value) AS cart_value
  FROM sessions
  WHERE event_name = 'begin_checkout'
  GROUP BY user_pseudo_id, session_id
),

purchase_sessions AS (
  SELECT DISTINCT user_pseudo_id, session_id
  FROM sessions
  WHERE event_name = 'purchase'
),

abandoned AS (
  SELECT c.*
  FROM checkout_sessions c
  LEFT JOIN purchase_sessions p
    ON c.user_pseudo_id = p.user_pseudo_id
    AND c.session_id = p.session_id
  WHERE p.session_id IS NULL
)

SELECT
  CASE
    WHEN cart_value < 2000 THEN '〜2,000円未満'
    WHEN cart_value < 3000 THEN '2,000〜3,000円未満'
    WHEN cart_value < 4000 THEN '3,000〜4,000円未満'
    WHEN cart_value < 5000 THEN '4,000〜5,000円未満'
    ELSE                        '5,000円以上'
  END AS cart_range,
  COUNT(*) AS abandoned_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pct
FROM
  abandoned
WHERE
  cart_value IS NOT NULL
GROUP BY
  cart_range
ORDER BY
  MIN(cart_value)
