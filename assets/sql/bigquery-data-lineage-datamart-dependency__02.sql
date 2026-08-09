-- 出典: BigQueryのデータリネージ機能でデータマートの依存関係を可視化する
-- 記事: articles/bigquery-data-lineage-datamart-dependency.md（GA4データを使ったビューの依存関係を実際に確認する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- mart_revenue_by_channel: 流入チャネル別の売上集計ビュー
CREATE OR REPLACE VIEW `${PROJECT}.${DATASET}.mart_revenue_by_channel` AS
SELECT
  COALESCE(medium, '(none)') AS medium,
  COALESCE(source, '(direct)') AS source,
  SUM(revenue) AS total_revenue,
  COUNT(DISTINCT ga_session_id) AS sessions
FROM
  `${PROJECT}.${DATASET}.stg_sessions`
GROUP BY
  medium,
  source
;
