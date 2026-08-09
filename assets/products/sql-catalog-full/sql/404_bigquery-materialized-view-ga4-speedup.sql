-- 404. BigQueryのマテリアライズドビューでGA4集計クエリを高速化した（GA4のBigQueryエクスポートテーブル構造を理解する） その1
-- 用途: GA4のBigQueryエクスポートテーブル構造を理解する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  event_date,
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
