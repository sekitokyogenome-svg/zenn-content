-- 228. GA4×BigQueryでSNS流入の質を測定してInstagramとTikTokを比較した（セッション単位でSNS流入を集計するSQL）
-- 用途: セッション単位でSNS流入を集計するSQL
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH session_base AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium,
    event_name,
    event_timestamp,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'engagement_time_msec') AS engagement_time_msec
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND collected_traffic_source.manual_medium = 'social'
),

session_metrics AS (
  SELECT
    user_pseudo_id,
    session_id,
    source,
    -- セッション内のエンゲージメント時間合計（秒）
    SUM(engagement_time_msec) / 1000 AS engagement_sec,
    -- セッション内のページビュー数
    COUNTIF(event_name = 'page_view') AS page_views,
    -- 購入の有無
    MAX(IF(event_name = 'purchase', 1, 0)) AS has_purchase,
    -- セッション開始・終了タイムスタンプ
    MIN(event_timestamp) AS session_start,
    MAX(event_timestamp) AS session_end
  FROM session_base
  GROUP BY user_pseudo_id, session_id, source
)

SELECT
  source,
  COUNT(*) AS sessions,
  ROUND(AVG(engagement_sec), 1) AS avg_engagement_sec,
  ROUND(AVG(page_views), 1) AS avg_page_views,
  -- 直帰率（ページビュー1以下のセッション割合）
  ROUND(COUNTIF(page_views <= 1) / COUNT(*) * 100, 1) AS bounce_rate,
  -- CV率
  ROUND(SUM(has_purchase) / COUNT(*) * 100, 2) AS cvr
FROM session_metrics
GROUP BY source
ORDER BY sessions DESC
