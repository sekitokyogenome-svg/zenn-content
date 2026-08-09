-- 356. BigQuery × Looker Studioで前年同期比グラフを作る方法（日付パラメータとの連携）
-- 用途: 日付パラメータとの連携
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  date,
  revenue_current,
  revenue_previous,
  revenue_yoy_pct
FROM
  `${PROJECT}.${DATASET}.yoy_daily_view`
WHERE
  date BETWEEN @DS_START_DATE AND @DS_END_DATE
