-- 出典: GA4×BigQueryのテーブル肥大化を防ぐパーティション有効期限の設定方法
-- 記事: articles/ga4-bigquery-table-partition-expiry.md（方法1：テーブル有効期限（Table Expiration）でシャードを自動削除する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- データセット内の全シャードに365日の有効期限を一括設定するストアドプロシージャ
FOR record IN (
  SELECT table_id
  FROM `${PROJECT}.${DATASET}.__TABLES__`
  WHERE REGEXP_CONTAINS(table_id, r'^events_\d{8}$')
)
DO
  EXECUTE IMMEDIATE FORMAT(
    """
    ALTER TABLE `${PROJECT}.${DATASET}.%s`
    SET OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 365 DAY))
    """,
    record.table_id
  );
END FOR;
