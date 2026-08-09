-- 出典: LINE広告×GA4×BigQueryでCPA・ROASを正確に計測する設定と集計SQL
-- 記事: articles/line-ads-ga4-bigquery-cpa-roas.md（BIgQueryでLINE広告の流入セッションを抽出するSQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- LINE広告経由のセッション一覧を取得
SELECT
  user_pseudo_id,
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_id'
  ) AS ga_session_id,
  collected_traffic_source.manual_source     AS traffic_source,
  collected_traffic_source.manual_medium     AS traffic_medium,
  collected_traffic_source.manual_campaign_name AS campaign_name,
  MIN(event_timestamp) AS session_start_ts
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
  AND collected_traffic_source.manual_medium = 'cpc'
  AND collected_traffic_source.manual_source = 'line'
  AND event_name = 'session_start'
GROUP BY
  1, 2, 3, 4, 5
