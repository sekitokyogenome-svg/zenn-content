-- BigQueryのタイムトラベル機能で誤削除・誤更新からデータを復旧する方法
-- 用途: 誤更新したデータを元に戻す（テーブル上書き）
-- 必要テーブル: target_table
-- コスト: `SELECT *` を含みます。必要な列だけに絞るとコストが下がります
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.target_table`
AS
SELECT *
FROM `${PROJECT}.${DATASET}.target_table`
FOR SYSTEM_TIME AS OF TIMESTAMP '2025-07-30 09:00:00 UTC';
