-- 出典: GTMでGA4のスクロール率・動画再生をイベント計測する方法
-- 記事: articles/gtm-ga4-scroll-video-event-tracking.md（BigQueryでのスクロールデータ分析例）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  (SELECT value.string_value
   FROM UNNEST(event_params) WHERE key = 'page_path') AS page_path,
  (SELECT value.string_value
   FROM UNNEST(event_params) WHERE key = 'scroll_percentage') AS scroll_pct,
  COUNT(DISTINCT user_pseudo_id) AS users
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  event_name = 'scroll_depth'
  AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
GROUP BY
  page_path, scroll_pct
ORDER BY
  page_path, CAST(scroll_pct AS INT64)
