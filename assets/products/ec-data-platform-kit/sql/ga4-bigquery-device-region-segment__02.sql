-- GA4×BigQueryでデバイス別・地域別セグメント分析をする
-- 用途: デバイス別×チャネル別のクロス集計
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH sessions AS (
  SELECT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    device.category AS device_category,
    collected_traffic_source.manual_medium AS medium
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
    AND event_name = 'session_start'
)
SELECT
  device_category,
  IFNULL(medium, '(none)') AS medium,
  COUNT(DISTINCT session_id) AS sessions
FROM sessions
GROUP BY device_category, medium
ORDER BY device_category, sessions DESC
