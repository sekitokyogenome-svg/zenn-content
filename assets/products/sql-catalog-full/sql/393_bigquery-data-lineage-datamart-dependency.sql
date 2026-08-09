-- 393. BigQueryのデータリネージ機能でデータマートの依存関係を可視化する（GA4データを使ったビューの依存関係を実際に確認する） その2
-- 用途: GA4データを使ったビューの依存関係を実際に確認する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
