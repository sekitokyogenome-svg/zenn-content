-- 出典: BigQueryのパーティション・クラスタリングでGA4クエリを高速化する
-- 記事: articles/bigquery-partition-clustering-ga4-optimization.md（確認方法1：ドライランで比較）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- BigQueryコンソールで「ドライラン」を有効にして実行
-- パーティションなしテーブル
SELECT COUNT(*) FROM `your-project.mart.mart_daily_sessions_no_partition`
WHERE event_date BETWEEN '2025-03-01' AND '2025-03-07'
  AND session_medium = 'organic'

-- パーティション＋クラスタリングありテーブル
SELECT COUNT(*) FROM `your-project.mart.mart_daily_sessions`
WHERE event_date BETWEEN '2025-03-01' AND '2025-03-07'
  AND session_medium = 'organic'
