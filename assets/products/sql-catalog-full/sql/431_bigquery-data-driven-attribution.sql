-- 431. BigQueryで広告の貢献度をデータドリブンアトリビューションで再計算する（BigQueryでコンバージョン経路を抽出するSQL）
-- 用途: BigQueryでコンバージョン経路を抽出するSQL
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH session_base AS (
  SELECT
    user_pseudo_id,
    -- ga_session_id は event_params から取得
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS ga_session_id,
    event_name,
    event_timestamp,
    -- 流入元は collected_traffic_source から参照
    collected_traffic_source.manual_source   AS source,
    collected_traffic_source.manual_medium  AS medium
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250731'
    AND event_name IN ('session_start', 'purchase')
),

-- セッション単位に流入元を集約
session_source AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    MAX(source)  AS source,
    MAX(medium)  AS medium,
    MAX(event_timestamp) AS session_ts,
    MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) AS is_converted
  FROM session_base
  GROUP BY 1, 2
),

-- ユーザーごとにセッションを時系列で並べてコンバージョン経路を構築
conversion_path AS (
  SELECT
    user_pseudo_id,
    STRING_AGG(
      CONCAT(COALESCE(source, '(direct)'), ' / ', COALESCE(medium, '(none)')),
      ' > '
      ORDER BY session_ts
    ) AS path,
    MAX(is_converted) AS converted
  FROM session_source
  GROUP BY user_pseudo_id
)

SELECT
  path,
  COUNT(*)                                        AS total_users,
  SUM(converted)                                  AS conversions,
  ROUND(SUM(converted) / COUNT(*) * 100, 2)       AS conversion_rate_pct
FROM conversion_path
GROUP BY path
ORDER BY conversions DESC
LIMIT 30;
