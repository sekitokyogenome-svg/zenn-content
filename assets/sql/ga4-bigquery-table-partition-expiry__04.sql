-- 出典: GA4×BigQueryのテーブル肥大化を防ぐパーティション有効期限の設定方法
-- 記事: articles/ga4-bigquery-table-partition-expiry.md（方法3：スケジュールドクエリで古いシャードを定期削除する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 365日より古い events_ シャードテーブルを削除する
-- ※ BigQueryのDROP TABLEをストアドプロシージャで実行
FOR record IN (
  SELECT table_id
  FROM `${PROJECT}.${DATASET}.__TABLES__`
  WHERE
    REGEXP_CONTAINS(table_id, r'^events_\d{8}$')
    AND PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(table_id, r'\d{8}')) < DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)
)
DO
  EXECUTE IMMEDIATE FORMAT(
    'DROP TABLE IF EXISTS `${PROJECT}.${DATASET}.%s`',
    record.table_id
  );
END FOR;
