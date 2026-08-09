-- Gemini in BigQueryの料金体系を完全解説【思わぬ課金を防ぐ設定】
-- 用途: データを絞り込んでからモデルに渡す
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH session_data AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    COUNT(*) AS event_count
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240701' AND '20240731'
    AND event_name IN ('session_start', 'page_view')
  GROUP BY
    1, 2, 3, 4
)
SELECT
  user_pseudo_id,
  ga_session_id,
  medium,
  source
FROM
  session_data
WHERE
  event_count = 1  -- セッション内イベントが1件のみ（直帰の近似）
LIMIT 500;
