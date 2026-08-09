-- 出典: BigQuery × Looker Studioで前年同期比グラフを作る方法
-- 記事: articles/bigquery-looker-studio-yoy-comparison-chart.md（うるう年の処理）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

COALESCE(p.revenue_ly, 0) AS revenue_previous
