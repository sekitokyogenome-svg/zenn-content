-- BigQueryのパーティション・クラスタリングでGA4クエリを高速化する
-- 出典: articles/bigquery-partition-clustering-ga4-optimization.md

CREATE OR REPLACE TABLE `your-project.mart.mart_daily_sessions`
PARTITION BY event_date
CLUSTER BY session_medium, device_category, country
AS
...
