-- BigQueryでSQLテストを書く方法―データマートの品質を担保する仕組み
-- 用途: 流入元データの整合性チェック
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH allowed_mediums AS (
  SELECT medium FROM UNNEST(['organic', 'cpc', 'email', 'social', 'referral', '(none)']) AS medium
),
actual_mediums AS (
  SELECT DISTINCT
    collected_traffic_source.manual_medium AS medium
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    AND event_name = 'session_start'
    AND collected_traffic_source.manual_medium IS NOT NULL
)
SELECT
  a.medium AS unexpected_medium
FROM
  actual_mediums a
LEFT JOIN
  allowed_mediums al ON a.medium = al.medium
WHERE
  al.medium IS NULL
;
