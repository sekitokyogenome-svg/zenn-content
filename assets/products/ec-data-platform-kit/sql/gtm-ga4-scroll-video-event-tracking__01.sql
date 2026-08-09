-- GTMでGA4のスクロール率・動画再生をイベント計測する方法
-- 用途: BigQueryでのスクロールデータ分析例
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
