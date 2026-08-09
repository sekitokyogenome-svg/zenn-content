-- 出典: BigQueryからGoogleスプレッドシートに自動出力して非エンジニアとデータ共有する
-- 記事: articles/bigquery-sheets-auto-export-data-sharing.md（GA4データをコネクテッドシートで参照するカスタムクエリ例）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.string_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY
  1, 2
ORDER BY
  sessions DESC
LIMIT 100
