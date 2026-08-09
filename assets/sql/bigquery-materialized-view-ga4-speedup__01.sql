-- 出典: BigQueryのマテリアライズドビューでGA4集計クエリを高速化した
-- 記事: articles/bigquery-materialized-view-ga4-speedup.md（GA4のBigQueryエクスポートテーブル構造を理解する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- ga_session_id の取得方法（UNNEST経由）
SELECT
  event_date,
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
