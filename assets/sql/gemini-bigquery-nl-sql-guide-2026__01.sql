-- 出典: Gemini in BigQueryで自然言語からSQLを生成する実践ガイド【2026年版】
-- 記事: articles/gemini-bigquery-nl-sql-guide-2026.md（セッション数の日別集計）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  DATE(TIMESTAMP_MICROS(event_timestamp)) AS event_date,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id,
      CAST(
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
        AS STRING
      )
    )
  ) AS sessions
FROM
  `プロジェクトID.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
  AND event_name = 'session_start'
GROUP BY
  event_date
ORDER BY
  event_date;
