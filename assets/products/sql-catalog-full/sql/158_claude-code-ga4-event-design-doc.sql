-- 158. Claude CodeでGA4のイベント設計書を自動生成する方法（イベントごとのパラメータ一覧を取得するSQL）
-- 用途: イベントごとのパラメータ一覧を取得するSQL
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  event_name,
  ep.key AS param_key,
  CASE
    WHEN ep.value.string_value IS NOT NULL THEN 'string'
    WHEN ep.value.int_value IS NOT NULL THEN 'int'
    WHEN ep.value.float_value IS NOT NULL THEN 'float'
    WHEN ep.value.double_value IS NOT NULL THEN 'double'
    ELSE 'unknown'
  END AS param_type,
  COUNT(*) AS occurrence_count,
  -- サンプル値（string型の場合）
  APPROX_TOP_COUNT(ep.value.string_value, 3) AS sample_values_string
FROM
  `${PROJECT}.${DATASET}.events_*`,
  UNNEST(event_params) AS ep
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY
  event_name, param_key, param_type
ORDER BY
  event_name, occurrence_count DESC
