-- 出典: BASE・STORES・ShopifyのGA4計測精度を比較検証した【2026年版】
-- 記事: articles/base-stores-shopify-ga4-comparison-2026.md（GA4計測の精度を高めるための共通対策）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- セッション数の正確なカウント（ga_session_idベース）
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
