-- Claude Codeに競合サイトの施策をGA4データから推測させた話
-- 用途: Step 3：購入率の変動も加える
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH purchase_sessions AS (
  SELECT
    DATE_TRUNC(
      PARSE_DATE('%Y%m%d', event_date), WEEK
    ) AS week_start,
    (SELECT value.string_value FROM UNNEST(event_params)
     WHERE key = 'page_location') AS page_location,
    (SELECT value.int_value FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id,
    user_pseudo_id,
    event_name
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
    AND event_name IN ('page_view', 'purchase')
)
SELECT
  week_start,
  COUNT(DISTINCT CASE WHEN event_name = 'purchase'
    THEN CONCAT(user_pseudo_id, CAST(session_id AS STRING))
  END) AS purchase_sessions,
  COUNT(DISTINCT
    CONCAT(user_pseudo_id, CAST(session_id AS STRING))
  ) AS total_sessions,
  SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN event_name = 'purchase'
      THEN CONCAT(user_pseudo_id, CAST(session_id AS STRING))
    END),
    COUNT(DISTINCT
      CONCAT(user_pseudo_id, CAST(session_id AS STRING))
    )
  ) AS cvr
FROM purchase_sessions
GROUP BY week_start
ORDER BY week_start DESC;
