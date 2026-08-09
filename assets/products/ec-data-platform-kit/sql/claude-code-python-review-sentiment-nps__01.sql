-- Claude Code × Pythonで顧客レビューを感情分析してNPS予測に使う
-- 用途: BigQueryからレビューデータとGA4流入情報を取得する
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
