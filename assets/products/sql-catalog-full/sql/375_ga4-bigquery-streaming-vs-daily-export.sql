-- 375. GA4 BigQueryエクスポートのストリーミング vs 日次の違いと使い分け（日次テーブルを対象にしたクエリ例）
-- 用途: 日次テーブルを対象にしたクエリ例
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  event_name,
  (
    SELECT value.string_value
    FROM UNNEST(event_params)
    WHERE key = 'page_location'
  ) AS page_location,
  COUNT(*) AS event_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 7 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 1 DAY))
GROUP BY
  event_name,
  page_location
ORDER BY
  event_count DESC
LIMIT 50;
