-- NotebookLM × BigQueryエクスポートでGA4データを対話的に分析する
-- 用途: GA4データをBigQueryからCSVに取り出す
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  cs.manual_medium AS medium,
  cs.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.string_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases
FROM
  `${PROJECT}.${DATASET}.events_*`
  , UNNEST(collected_traffic_source) AS cs
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
GROUP BY
  medium, source
ORDER BY
  sessions DESC
LIMIT 100;
