-- 出典: Claude Code × Pythonで顧客レビューを感情分析してNPS予測に使う
-- 記事: articles/claude-code-python-review-sentiment-nps.md（BigQueryからレビューデータとGA4流入情報を取得する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  ep.value.int_value AS ga_session_id,
  e.user_pseudo_id,
  e.event_date,
  cts.manual_medium AS medium,
  cts.manual_source AS source,
  ep2.value.string_value AS review_text
FROM
  `${PROJECT}.${DATASET}.events_*` AS e,
  UNNEST(e.event_params) AS ep,
  UNNEST(e.event_params) AS ep2
LEFT JOIN
  UNNEST([e.collected_traffic_source]) AS cts
WHERE
  e.event_name = 'review_submit'
  AND ep.key = 'ga_session_id'
  AND ep2.key = 'review_body'
  AND _TABLE_SUFFIX BETWEEN '20250101' AND '20250731'
