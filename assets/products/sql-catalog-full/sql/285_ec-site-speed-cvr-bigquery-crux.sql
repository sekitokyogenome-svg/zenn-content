-- 285. ECサイトのサイト速度がCVRに与える影響をBigQueryのCrUXデータで検証する（GA4のBigQueryエクスポートでCVRを算出するSQL）
-- 用途: GA4のBigQueryエクスポートでCVRを算出するSQL
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH sessions AS (
  SELECT
    -- ga_session_idはUNNEST経由で取得
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id,
    user_pseudo_id,
    -- 流入元はcollected_traffic_sourceから取得
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source  AS source,
    -- 購入フラグ（purchaseイベントが存在するセッションを1とする）
    MAX(IF(event_name = 'purchase', 1, 0)) AS is_converted,
    COUNT(DISTINCT event_name)             AS event_count
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240701' AND '20240731'
  GROUP BY
    session_id,
    user_pseudo_id,
    medium,
    source
),

cvr_by_channel AS (
  SELECT
    medium,
    source,
    COUNT(*)                                  AS total_sessions,
    SUM(is_converted)                         AS converted_sessions,
    ROUND(SUM(is_converted) / COUNT(*), 4)    AS cvr
  FROM sessions
  WHERE session_id IS NOT NULL
  GROUP BY medium, source
  ORDER BY total_sessions DESC
)

SELECT * FROM cvr_by_channel;
