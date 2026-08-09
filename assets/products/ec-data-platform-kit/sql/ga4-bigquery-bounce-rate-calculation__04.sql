-- BigQueryでGA4の直帰率を正確に計算する方法（GA4に直帰率はない問題）
-- 用途: ページ別の直帰率を計算する
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH session_landing AS (
  SELECT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    (SELECT value.string_value
     FROM UNNEST(event_params)
     WHERE key = 'page_location') AS landing_page,
    MAX(
      (SELECT value.string_value
       FROM UNNEST(event_params)
       WHERE key = 'session_engaged')
    ) AS session_engaged
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
    AND event_name = 'session_start'
  GROUP BY session_id, landing_page
)
SELECT
  landing_page,
  COUNT(*) AS sessions,
  COUNTIF(session_engaged != '1' OR session_engaged IS NULL) AS bounced,
  ROUND(
    COUNTIF(session_engaged != '1' OR session_engaged IS NULL)
    / COUNT(*) * 100, 2
  ) AS bounce_rate_percent
FROM session_landing
GROUP BY landing_page
HAVING sessions >= 10
ORDER BY bounce_rate_percent DESC
LIMIT 20
