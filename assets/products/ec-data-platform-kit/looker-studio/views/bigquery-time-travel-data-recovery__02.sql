-- BigQueryのタイムトラベル機能で誤削除・誤更新からデータを復旧する方法
-- 出典: articles/bigquery-time-travel-data-recovery.md

CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.target_table`
AS
SELECT *
FROM `${PROJECT}.${DATASET}.target_table`
FOR SYSTEM_TIME AS OF TIMESTAMP '2025-07-30 09:00:00 UTC';
