-- 288. 定期購入ECの解約予兆をGA4行動ログから検知するBigQueryモデル（解約予兆シグナルとなる行動パターンを定義する）
-- 用途: 解約予兆シグナルとなる行動パターンを定義する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH raw_events AS (
  SELECT
    user_pseudo_id,
    (SELECT value.string_value
     FROM UNNEST(event_params)
     WHERE key = 'page_location') AS page_location,
    event_name,
    event_date
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY))
      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
    AND event_name = 'page_view'
)

SELECT
  user_pseudo_id,
  COUNTIF(page_location LIKE '%/cancel%' OR page_location LIKE '%/unsubscribe%')
    AS cancel_page_views,
  COUNTIF(page_location LIKE '%/mypage%')
    AS mypage_views,
  COUNTIF(page_location LIKE '%/help%' OR page_location LIKE '%/faq%')
    AS help_page_views,
  COUNT(DISTINCT event_date) AS active_days
FROM raw_events
GROUP BY user_pseudo_id
