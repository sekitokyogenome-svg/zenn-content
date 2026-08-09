-- 出典: BigQuery × Looker Studioで前年同期比グラフを作る方法
-- 記事: articles/bigquery-looker-studio-yoy-comparison-chart.md（日付パラメータとの連携）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  date,
  revenue_current,
  revenue_previous,
  revenue_yoy_pct
FROM
  `${PROJECT}.${DATASET}.yoy_daily_view`
WHERE
  date BETWEEN @DS_START_DATE AND @DS_END_DATE
