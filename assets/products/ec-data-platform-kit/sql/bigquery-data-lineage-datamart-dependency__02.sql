-- BigQueryのデータリネージ機能でデータマートの依存関係を可視化する
-- 用途: GA4データを使ったビューの依存関係を実際に確認する
-- 必要テーブル: mart_revenue_by_channel, stg_sessions
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
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
