-- 出典: BigQueryのタイムトラベル機能で誤削除・誤更新からデータを復旧する方法
-- 記事: articles/bigquery-time-travel-data-recovery.md（誤更新したデータを元に戻す（テーブル上書き））
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 誤更新前の状態でテーブルを上書き復元する
CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.target_table`
AS
SELECT *
FROM `${PROJECT}.${DATASET}.target_table`
FOR SYSTEM_TIME AS OF TIMESTAMP '2025-07-30 09:00:00 UTC';
