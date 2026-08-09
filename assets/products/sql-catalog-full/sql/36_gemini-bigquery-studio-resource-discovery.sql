-- 36. Gemini in BigQuery Studioのリソース検出機能でマルチプロジェクト分析を効率化する（シナリオ: 2ブランドのコンバージョンを横断集計したい）
-- 用途: シナリオ: 2ブランドのコンバージョンを横断集計したい
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  'brand_a' AS brand,
  COUNT(DISTINCT
    (SELECT ep.value.string_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases
FROM
  `project-brand-a.analytics_XXXXXXXXX.events_*`
WHERE
  event_name IN ('session_start', 'purchase')
  AND _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH))
    AND FORMAT_DATE('%Y%m%d', LAST_DAY(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)))

UNION ALL

-- ブランドB: 先月の購入件数
SELECT
  'brand_b' AS brand,
  COUNT(DISTINCT
    (SELECT ep.value.string_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases
FROM
  `project-brand-b.analytics_YYYYYYYYY.events_*`
WHERE
  event_name IN ('session_start', 'purchase')
  AND _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH))
    AND FORMAT_DATE('%Y%m%d', LAST_DAY(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)));
