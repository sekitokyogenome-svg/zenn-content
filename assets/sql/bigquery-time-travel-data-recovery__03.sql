-- 出典: BigQueryのタイムトラベル機能で誤削除・誤更新からデータを復旧する方法
-- 記事: articles/bigquery-time-travel-data-recovery.md（誤更新したデータを元に戻す（テーブル上書き））
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 特定条件の行のみ過去状態から復旧するMERGE例
MERGE `${PROJECT}.${DATASET}.target_table` AS current
USING (
  SELECT *
  FROM `${PROJECT}.${DATASET}.target_table`
  FOR SYSTEM_TIME AS OF TIMESTAMP '2025-07-30 09:00:00 UTC'
  WHERE order_status = 'cancelled'  -- 誤更新された行の条件
) AS past
ON current.order_id = past.order_id
WHEN MATCHED THEN
  UPDATE SET
    current.order_status = past.order_status,
    current.updated_at   = past.updated_at;
