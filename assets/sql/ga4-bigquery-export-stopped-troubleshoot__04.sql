-- 出典: GA4×BigQueryのエクスポートが止まったときのトラブルシューティング
-- 記事: articles/ga4-bigquery-export-stopped-troubleshoot.md（BigQuery Scheduled Queryでアラート）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 日次で実行し、昨日のテーブルが存在しない場合にアラート
DECLARE yesterday STRING DEFAULT FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY));

SELECT
  CASE
    WHEN COUNT(*) = 0
    THEN ERROR(CONCAT('GA4エクスポートテーブルが見つかりません: events_', yesterday))
  END
FROM `${PROJECT}.${DATASET}.__TABLES__`
WHERE table_id = CONCAT('events_', yesterday)
