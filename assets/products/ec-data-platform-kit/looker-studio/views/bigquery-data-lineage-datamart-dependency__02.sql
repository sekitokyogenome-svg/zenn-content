-- BigQueryのデータリネージ機能でデータマートの依存関係を可視化する
-- 出典: articles/bigquery-data-lineage-datamart-dependency.md

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
