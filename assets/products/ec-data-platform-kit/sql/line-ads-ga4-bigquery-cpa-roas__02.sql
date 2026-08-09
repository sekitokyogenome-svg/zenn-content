-- LINE広告×GA4×BigQueryでCPA・ROASを正確に計測する設定と集計SQL
-- 用途: CPA・ROASをSQLで集計する
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH line_sessions AS (
  -- LINE広告経由のセッションを特定
  SELECT
    user_pseudo_id,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
    AND event_name = 'session_start'
    AND collected_traffic_source.manual_medium = 'cpc'
    AND collected_traffic_source.manual_source = 'line'
),

purchases AS (
  -- 購入イベントとセッションIDを紐付け
  SELECT
    e.user_pseudo_id,
    (
      SELECT value.int_value
      FROM UNNEST(e.event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,
    (
      SELECT value.double_value
      FROM UNNEST(e.event_params)
      WHERE key = 'value'
    ) AS purchase_revenue
  FROM
    `${PROJECT}.${DATASET}.events_*` AS e
  WHERE
    _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
    AND e.event_name = 'purchase'
)

SELECT
  COUNT(DISTINCT p.user_pseudo_id || CAST(p.ga_session_id AS STRING)) AS conversions,
  SUM(p.purchase_revenue)                                              AS total_revenue,
  -- 広告費は手動で入力（例: 50000円）
  50000                                                                AS ad_spend,
  ROUND(50000 / NULLIF(COUNT(DISTINCT p.user_pseudo_id || CAST(p.ga_session_id AS STRING)), 0), 0) AS cpa,
  ROUND(SUM(p.purchase_revenue) / NULLIF(50000, 0), 2)                AS roas
FROM
  purchases AS p
INNER JOIN
  line_sessions AS ls
  ON p.user_pseudo_id = ls.user_pseudo_id
  AND p.ga_session_id  = ls.ga_session_id
