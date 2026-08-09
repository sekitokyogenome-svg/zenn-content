-- 出典: Gemini CLIをGA4データアナリストとして使う具体的な設定と活用例
-- 記事: articles/gemini-cli-ga4-analyst-setup-guide.md（活用例①：流入元別セッション数の集計）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
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
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250721' AND '20250727'
  AND event_name = 'session_start'
GROUP BY
  source, medium
ORDER BY
  sessions DESC
LIMIT 50;
