-- BigQueryで広告の貢献度をデータドリブンアトリビューションで再計算する
-- 用途: チャネルごとの貢献度を線形モデルで計算する
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH session_source AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS ga_session_id,
    event_name,
    event_timestamp,
    collected_traffic_source.manual_source  AS source,
    collected_traffic_source.manual_medium  AS medium
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250731'
    AND event_name IN ('session_start', 'purchase')
),

session_agg AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    MAX(source)        AS source,
    MAX(medium)        AS medium,
    MAX(event_timestamp) AS session_ts,
    MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) AS is_converted
  FROM session_source
  GROUP BY 1, 2
),

-- コンバージョンしたユーザーの経路のみ対象
converted_users AS (
  SELECT user_pseudo_id
  FROM session_agg
  GROUP BY 1
  HAVING MAX(is_converted) = 1
),

-- ユーザーあたりのタッチポイント数を算出
user_touch AS (
  SELECT
    s.user_pseudo_id,
    s.ga_session_id,
    CONCAT(COALESCE(s.source,'(direct)'), ' / ', COALESCE(s.medium,'(none)')) AS channel,
    COUNT(*) OVER (PARTITION BY s.user_pseudo_id) AS touch_count
  FROM session_agg s
  INNER JOIN converted_users c USING (user_pseudo_id)
)

-- チャネルごとに線形配分の合計を集計
SELECT
  channel,
  ROUND(SUM(1.0 / touch_count), 2) AS linear_attribution_score,
  COUNT(*)                          AS total_touchpoints
FROM user_touch
GROUP BY channel
ORDER BY linear_attribution_score DESC;
