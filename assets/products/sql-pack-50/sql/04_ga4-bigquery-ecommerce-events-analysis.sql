-- 04. BigQueryでGA4のeコマースイベントを完全解析する【purchase/add_to_cart】（ファネル分析：view_item → add_to_cart → purchase の転換率）
-- 用途: ファネル分析：view_item → add_to_cart → purchase の転換率
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH funnel AS (
  SELECT
    event_name,
    COUNT(DISTINCT CONCAT(
      user_pseudo_id,
      (SELECT CAST(value.int_value AS STRING) FROM UNNEST(event_params) WHERE key = 'ga_session_id')
    )) AS unique_sessions
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20260101' AND '20260331'
    AND event_name IN ('view_item', 'add_to_cart', 'begin_checkout', 'purchase')
  GROUP BY
    event_name
)

SELECT
  event_name,
  unique_sessions,
  ROUND(
    SAFE_DIVIDE(
      unique_sessions,
      MAX(unique_sessions) OVER ()
    ) * 100, 1
  ) AS rate_from_top
FROM funnel
ORDER BY
  CASE event_name
    WHEN 'view_item' THEN 1
    WHEN 'add_to_cart' THEN 2
    WHEN 'begin_checkout' THEN 3
    WHEN 'purchase' THEN 4
  END
