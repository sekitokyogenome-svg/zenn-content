-- 333. GA4移行後にデータが取れていない問題を解決するGTMデバッグ手順
-- 用途: BigQueryエクスポートとGA4 UIのデータ差異
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
