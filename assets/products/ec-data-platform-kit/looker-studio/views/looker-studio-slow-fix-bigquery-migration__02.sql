-- Looker Studioのデータポータルが重い・遅い問題をBigQuery化で解決した
-- 出典: articles/looker-studio-slow-fix-bigquery-migration.md

CREATE OR REPLACE TABLE `your_project.mart.daily_summary`
PARTITION BY event_date
CLUSTER BY source, medium, device_category
AS
-- (上記と同じSELECT文)
