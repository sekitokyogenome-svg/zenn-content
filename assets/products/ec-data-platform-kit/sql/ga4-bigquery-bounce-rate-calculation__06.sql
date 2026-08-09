-- BigQueryでGA4の直帰率を正確に計算する方法（GA4に直帰率はない問題）
-- 用途: UAの直帰率定義をBigQueryで再現する
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH session_pages AS (
  SELECT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    COUNTIF(event_name = 'page_view') AS page_views
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  GROUP BY session_id
)
SELECT
  COUNT(*) AS total_sessions,
  COUNTIF(page_views <= 1) AS single_page_sessions,
  ROUND(
    COUNTIF(page_views <= 1) / COUNT(*) * 100, 2
  ) AS ua_style_bounce_rate_percent
FROM session_pages
