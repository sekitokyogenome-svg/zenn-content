-- GA4×BigQueryでセッションIDを正しく定義する方法
-- 用途: セッションごとのPV数
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
    event_name
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
)
SELECT
  session_id,
  COUNTIF(event_name = 'page_view') AS page_views
FROM sessions
GROUP BY session_id
ORDER BY page_views DESC
LIMIT 20
