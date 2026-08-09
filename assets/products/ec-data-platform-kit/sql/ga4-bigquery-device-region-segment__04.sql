-- GA4×BigQueryでデバイス別・地域別セグメント分析をする
-- 用途: 国別セッション数（海外展開サイト向け）
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  geo.country AS country,
  geo.continent AS continent,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    )
  ) AS sessions,
  COUNT(DISTINCT user_pseudo_id) AS users
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'session_start'
GROUP BY country, continent
ORDER BY sessions DESC
LIMIT 30
