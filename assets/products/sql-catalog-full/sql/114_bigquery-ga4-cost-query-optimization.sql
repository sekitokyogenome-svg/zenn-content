-- 114. BigQueryでGA4データのコスト管理・クエリ最適化入門（テクニック2：必要なカラムだけSELECTする）
-- 用途: テクニック2：必要なカラムだけSELECTする
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  event_date,
  user_pseudo_id,
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_id') AS ga_session_id
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX = '20260330'
