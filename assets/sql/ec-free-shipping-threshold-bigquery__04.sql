-- 出典: ECの送料無料ラインをBigQueryの購買データから最適設定する分析手法
-- 記事: articles/ec-free-shipping-threshold-bigquery.md（送料無料ライン変更のA/Bテスト設計と効果測定）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  (
    SELECT ep.value.string_value
    FROM UNNEST(event_params) AS ep
    WHERE ep.key = 'ab_variant'
  ) AS variant,
  COUNT(*) AS purchase_count,
  ROUND(AVG(
    (
      SELECT COALESCE(ep.value.int_value, ep.value.float_value, ep.value.double_value)
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'value'
    )
  ), 0) AS avg_order_value
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240901' AND '20240930'
  AND event_name = 'purchase'
GROUP BY
  variant
