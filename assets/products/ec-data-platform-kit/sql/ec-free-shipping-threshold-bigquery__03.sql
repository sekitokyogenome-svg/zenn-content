-- ECの送料無料ラインをBigQueryの購買データから最適設定する分析手法
-- 用途: 流入元別に送料感度を分析する
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH purchase_source AS (
  SELECT
    user_pseudo_id,
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
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
  COALESCE(medium, '(none)') AS medium,
  COALESCE(source, '(direct)') AS source,
  COUNT(*) AS order_count,
  ROUND(AVG(purchase_value), 0) AS avg_order_value,
  ROUND(MIN(purchase_value), 0) AS min_order_value,
  ROUND(APPROX_QUANTILES(purchase_value, 100)[OFFSET(50)], 0) AS median_order_value
FROM
  purchase_source
WHERE
  purchase_value IS NOT NULL
GROUP BY
  medium, source
ORDER BY
  order_count DESC
LIMIT 20
