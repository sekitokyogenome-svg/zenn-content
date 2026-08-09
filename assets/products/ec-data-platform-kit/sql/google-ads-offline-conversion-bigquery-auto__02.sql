-- Google広告のオフラインコンバージョンをBigQuery経由で自動化する
-- 用途: CRMデータと結合してコンバージョンテーブルを作る
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH gclid_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.string_value
     FROM UNNEST(event_params)
     WHERE key = 'gclid') AS gclid,
    DATE(TIMESTAMP_MICROS(event_timestamp)) AS click_date
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
    AND event_name = 'session_start'
    AND collected_traffic_source.manual_medium = 'cpc'
),
conversions AS (
  SELECT
    user_email,
    contract_date,
    contract_value,
    crm_user_id
  FROM
    `your_project.crm_dataset.contracts`
  WHERE
    contract_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
)
SELECT
  g.gclid,
  c.contract_date AS conversion_time,
  'Offline_Contract' AS conversion_name,
  c.contract_value AS conversion_value,
  'JPY' AS currency_code
FROM
  gclid_sessions g
  INNER JOIN `your_project.crm_dataset.users` u
    ON g.user_pseudo_id = u.ga_user_pseudo_id
  INNER JOIN conversions c
    ON u.user_email = c.user_email
WHERE
  g.gclid IS NOT NULL
