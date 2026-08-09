-- BigQuery × Looker Studioで前年同期比グラフを作る方法
-- 用途: 日付パラメータとの連携
-- 必要テーブル: yoy_daily_view
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
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
