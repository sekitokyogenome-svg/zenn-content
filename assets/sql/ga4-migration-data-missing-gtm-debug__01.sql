-- 出典: GA4移行後にデータが取れていない問題を解決するGTMデバッグ手順
-- 記事: articles/ga4-migration-data-missing-gtm-debug.md（BigQueryエクスポートとGA4 UIのデータ差異）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- BigQueryでイベント数を日別に確認
SELECT
  event_date,
  COUNT(*) AS event_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20260325' AND '20260329'
GROUP BY
  event_date
ORDER BY
  event_date
