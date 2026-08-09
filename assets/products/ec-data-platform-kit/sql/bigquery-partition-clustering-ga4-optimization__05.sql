-- BigQueryのパーティション・クラスタリングでGA4クエリを高速化する
-- 用途: 確認方法2：INFORMATION_SCHEMAで確認
-- 必要テーブル: (なし)
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  table_name,
  ROUND(total_logical_bytes / POW(1024, 3), 3) AS size_gb,
  ROUND(total_physical_bytes / POW(1024, 3), 3) AS physical_size_gb
FROM `your-project.mart.INFORMATION_SCHEMA.TABLE_STORAGE`
WHERE table_name LIKE 'mart_daily%'
