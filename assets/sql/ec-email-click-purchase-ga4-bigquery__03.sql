-- 出典: ECメルマガのクリック→購入をGA4×BigQueryで追跡してセグメント別効果を測定する
-- 記事: articles/ec-email-click-purchase-ga4-bigquery.md（リピーター・新規ユーザー別に効果を分ける）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 新規・リピート別のメルマガ効果比較
WITH email_sessions AS (
  SELECT
    user_pseudo_id,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS session_id,
    collected_traffic_source.manual_campaign_name AS utm_campaign,
    event_name,
    -- user_first_touch_timestamp はマイクロ秒単位
    TIMESTAMP_MICROS(user_first_touch_timestamp) AS first_touch_ts,
    TIMESTAMP_MICROS(event_timestamp) AS event_ts
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
    AND collected_traffic_source.manual_medium = 'email'
),

session_agg AS (
  SELECT
    user_pseudo_id,
    session_id,
    utm_campaign,
    MIN(first_touch_ts) AS first_touch_ts,
    MIN(event_ts)        AS session_start_ts,
    COUNTIF(event_name = 'purchase') AS purchased
  FROM email_sessions
  GROUP BY user_pseudo_id, session_id, utm_campaign
)

SELECT
  utm_campaign,
  CASE
    WHEN TIMESTAMP_DIFF(session_start_ts, first_touch_ts, DAY) < 30
      THEN '新規（初回接触30日以内）'
    ELSE 'リピーター'
  END AS user_segment,
  COUNT(*) AS sessions,
  COUNTIF(purchased > 0) AS conversions,
  ROUND(SAFE_DIVIDE(COUNTIF(purchased > 0), COUNT(*)) * 100, 2) AS cvr_pct
FROM session_agg
GROUP BY utm_campaign, user_segment
ORDER BY utm_campaign, user_segment;
