-- 95. BigQueryでGA4のサンプリングを回避して正確な数値を出す（GA4 UIとBigQueryの数値を比較してみる）
-- 用途: GA4 UIとBigQueryの数値を比較してみる
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  FORMAT_DATE('%Y%m%d',
    DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo')
  ) AS event_date_jst,
  COUNT(*) AS event_count
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
GROUP BY event_date_jst
ORDER BY event_date_jst
