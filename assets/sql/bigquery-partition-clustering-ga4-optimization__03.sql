-- 出典: BigQueryのパーティション・クラスタリングでGA4クエリを高速化する
-- 記事: articles/bigquery-partition-clustering-ga4-optimization.md（クラスタリングキーの選定）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

CREATE OR REPLACE TABLE `your-project.mart.mart_daily_sessions`
PARTITION BY event_date
CLUSTER BY session_medium, device_category, country
AS
...
