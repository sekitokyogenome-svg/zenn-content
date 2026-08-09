-- 30. ECの季節変動をBigQueryで前年比分析して仕入れ計画に活かす方法（週別売上の前年比SQL）
-- 用途: 週別売上の前年比SQL
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH weekly_revenue AS (
  SELECT
    EXTRACT(ISOYEAR FROM PARSE_DATE('%Y%m%d', event_date)) AS iso_year,
    EXTRACT(ISOWEEK FROM PARSE_DATE('%Y%m%d', event_date)) AS iso_week,
    SUM(ecommerce.purchase_revenue) AS revenue,
    COUNT(DISTINCT
      CONCAT(
        user_pseudo_id, '-',
        CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
      )
    ) AS purchase_sessions
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'purchase'
    AND ecommerce.purchase_revenue > 0
    AND _TABLE_SUFFIX BETWEEN '20250101' AND '20260331'
  GROUP BY iso_year, iso_week
)
SELECT
  curr.iso_week,
  curr.revenue AS current_revenue,
  prev.revenue AS prev_revenue,
  ROUND(SAFE_DIVIDE(curr.revenue - prev.revenue, prev.revenue) * 100, 1) AS revenue_yoy_pct,
  curr.purchase_sessions AS current_sessions,
  prev.purchase_sessions AS prev_sessions
FROM weekly_revenue curr
LEFT JOIN weekly_revenue prev
  ON curr.iso_week = prev.iso_week
  AND curr.iso_year = prev.iso_year + 1
WHERE curr.iso_year = 2026
ORDER BY curr.iso_week;
