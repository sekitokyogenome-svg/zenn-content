-- 287. Shopifyのチェックアウト拡張機能のイベントをGA4×BigQueryで分析する（ファネル分析でボトルネックを特定する）
-- 用途: ファネル分析でボトルネックを特定する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH step_sessions AS (
  SELECT
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id,
    (
      SELECT ep.value.string_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'checkout_step'
    ) AS checkout_step
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250131'
    AND event_name = 'checkout_step_reached'
),

funnel AS (
  SELECT
    COUNTIF(checkout_step = 'delivery_address') AS step1_delivery,
    COUNTIF(checkout_step = 'shipping_method')  AS step2_shipping,
    COUNTIF(checkout_step = 'payment')          AS step3_payment,
    COUNTIF(checkout_step = 'review')           AS step4_review
  FROM (
    SELECT ga_session_id, checkout_step
    FROM step_sessions
    GROUP BY ga_session_id, checkout_step
  )
)

SELECT
  step1_delivery,
  step2_shipping,
  ROUND(step2_shipping / NULLIF(step1_delivery, 0) * 100, 1) AS step1_to_step2_pct,
  step3_payment,
  ROUND(step3_payment / NULLIF(step2_shipping, 0) * 100, 1) AS step2_to_step3_pct,
  step4_review,
  ROUND(step4_review / NULLIF(step3_payment, 0) * 100, 1) AS step3_to_step4_pct
FROM funnel;
