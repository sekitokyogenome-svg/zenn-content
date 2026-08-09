-- 23. Gemini in BigQueryで自然言語からSQLを生成する実践ガイド【2026年版】（セッション数の日別集計）
-- 用途: セッション数の日別集計
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
