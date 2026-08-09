-- 出典: BigQueryでGA4のサンプリングを回避して正確な数値を出す
-- 記事: articles/ga4-bigquery-avoid-sampling.md（GA4 UIとBigQueryの数値を比較してみる）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- UTCからJSTに変換して日付を取得
SELECT
  FORMAT_DATE('%Y%m%d',
    DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo')
  ) AS event_date_jst,
  COUNT(*) AS event_count
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
GROUP BY event_date_jst
ORDER BY event_date_jst
