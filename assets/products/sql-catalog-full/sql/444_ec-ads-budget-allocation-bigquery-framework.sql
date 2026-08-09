-- 444. EC広告費の予算配分をBigQueryの過去データから最適化するフレームワーク（月別トレンドから季節変動と広告効果の相関を読む）
-- 用途: 月別トレンドから季節変動と広告効果の相関を読む
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m%d', event_date)) AS month,
  COALESCE(collected_traffic_source.manual_medium, '(none)') AS medium,
  COUNT(*) AS purchase_count,
  ROUND(
    SUM(
      (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'value')
    ), 0
  ) AS total_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY))
                    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  AND event_name = 'purchase'
GROUP BY month, medium
ORDER BY month ASC, total_revenue DESC;
