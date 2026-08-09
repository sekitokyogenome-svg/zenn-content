-- 15. BigQueryのGeminiアシスタントで非エンジニアが自力でSQL分析できるか検証した（実際にやってみた：セッション数の集計）
-- 用途: 実際にやってみた：セッション数の集計
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  DATE(TIMESTAMP_MICROS(event_timestamp)) AS date,
  COUNT(DISTINCT
    (SELECT value.int_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS sessions
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'session_start'
GROUP BY
  date
ORDER BY
  date;
