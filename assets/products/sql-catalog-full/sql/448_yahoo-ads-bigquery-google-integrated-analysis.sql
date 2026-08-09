-- 448. Yahoo!広告データをBigQueryに取り込んでGoogle広告と統合分析する方法（媒体横断の集計クエリ実例） その1
-- 用途: 媒体横断の集計クエリ実例
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  media_source,
  FORMAT_DATE('%Y-%m', report_date) AS year_month,
  SUM(cost_jpy) AS total_cost,
  SUM(conversions) AS total_conversions,
  ROUND(
    SAFE_DIVIDE(SUM(cost_jpy), SUM(conversions)),
    0
  ) AS cpa
FROM
  `your_project.ads_dataset.unified_ads_stats`
WHERE
  report_date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 3 MONTH) AND CURRENT_DATE()
GROUP BY
  media_source, year_month
ORDER BY
  year_month, media_source
;
