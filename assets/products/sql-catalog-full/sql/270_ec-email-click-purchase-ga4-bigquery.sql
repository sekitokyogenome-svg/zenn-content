-- 270. ECメルマガのクリック→購入をGA4×BigQueryで追跡してセグメント別効果を測定する（メルマガ経由セッションを抽出するSQL）
-- 用途: メルマガ経由セッションを抽出するSQL
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH email_sessions AS (
  SELECT
    user_pseudo_id,
    -- ga_session_id は event_params をUNNESTして取得する
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS session_id,
    collected_traffic_source.manual_medium AS utm_medium,
    collected_traffic_source.manual_source AS utm_source,
    collected_traffic_source.manual_campaign_name AS utm_campaign,
    event_name,
    event_timestamp
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
    AND collected_traffic_source.manual_medium = 'email'
),

-- セッション単位で最初のイベントと購入有無を集計
session_summary AS (
  SELECT
    user_pseudo_id,
    session_id,
    utm_source,
    utm_campaign,
    COUNTIF(event_name = 'purchase') AS purchase_count,
    MIN(event_timestamp) AS session_start_ts
  FROM email_sessions
  GROUP BY
    user_pseudo_id,
    session_id,
    utm_source,
    utm_campaign
)

SELECT
  utm_campaign,
  COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(session_id AS STRING))) AS total_sessions,
  COUNTIF(purchase_count > 0) AS purchase_sessions,
  ROUND(
    SAFE_DIVIDE(COUNTIF(purchase_count > 0), COUNT(*)) * 100, 2
  ) AS conversion_rate_pct
FROM session_summary
GROUP BY utm_campaign
ORDER BY conversion_rate_pct DESC;
