-- 出典: Google広告データをBigQuery Data Transfer Serviceで自動連携する完全手順
-- 記事: articles/google-ads-bigquery-dts-setup-guide.md（GA4データと掛け合わせて流入経路を確認するSQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH google_ads_sessions AS (
  SELECT
    -- ga_session_idはevent_paramsのUNNESTで取得する
    (
      SELECT value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id,
    user_pseudo_id,
    -- 流入元はcollected_traffic_sourceから取得
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    COUNT(*) AS event_count
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250731'
    AND collected_traffic_source.manual_medium = 'cpc'
  GROUP BY
    ga_session_id,
    user_pseudo_id,
    medium,
    source
)

SELECT
  source,
  medium,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNT(DISTINCT ga_session_id) AS sessions,
  SUM(event_count) AS total_events
FROM
  google_ads_sessions
GROUP BY
  source,
  medium
ORDER BY
  sessions DESC;
