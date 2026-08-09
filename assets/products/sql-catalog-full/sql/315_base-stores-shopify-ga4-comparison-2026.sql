-- 315. BASE・STORES・ShopifyのGA4計測精度を比較検証した【2026年版】（GA4計測の精度を高めるための共通対策）
-- 用途: GA4計測の精度を高めるための共通対策
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id,
      '-',
      CAST(
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
        AS STRING
      )
    )
  ) AS unique_sessions
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20260701' AND '20260731'
