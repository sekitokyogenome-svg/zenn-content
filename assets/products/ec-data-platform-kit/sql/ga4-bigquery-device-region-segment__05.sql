-- GA4×BigQueryでデバイス別・地域別セグメント分析をする
-- 用途: PIVOT的なデバイス別集計（日別×デバイス）
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH daily_device AS (
  SELECT
    event_date,
    device.category AS device_category,
    COUNT(DISTINCT
      CONCAT(
        user_pseudo_id, '.',
        CAST(
          (SELECT value.int_value
           FROM UNNEST(event_params)
           WHERE key = 'ga_session_id') AS STRING)
      )
    ) AS sessions
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
    AND event_name = 'session_start'
  GROUP BY event_date, device_category
)
SELECT
  event_date,
  SUM(CASE WHEN device_category = 'desktop' THEN sessions ELSE 0 END) AS desktop,
  SUM(CASE WHEN device_category = 'mobile' THEN sessions ELSE 0 END) AS mobile,
  SUM(CASE WHEN device_category = 'tablet' THEN sessions ELSE 0 END) AS tablet,
  SUM(sessions) AS total
FROM daily_device
GROUP BY event_date
ORDER BY event_date
