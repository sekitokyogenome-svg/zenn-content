-- 07. Claude Codeで競合ECサイトのSEO戦略をGA4×Search Consoleデータから逆算する（GA4 BigQueryデータで流入セッションとコンバージョンを紐づけるSQL）
-- 用途: GA4 BigQueryデータで流入セッションとコンバージョンを紐づけるSQL
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH session_params AS (
  SELECT
    user_pseudo_id,
    -- ga_session_id は event_params を UNNEST して取得
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')              AS session_id,
    collected_traffic_source.manual_medium     AS medium,
    collected_traffic_source.manual_source     AS source,
    event_name
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
                      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
),
session_summary AS (
  SELECT
    user_pseudo_id,
    session_id,
    medium,
    source,
    COUNTIF(event_name = 'purchase') AS purchase_count
  FROM session_params
  WHERE medium = 'organic'   -- オーガニック検索のみ
  GROUP BY 1, 2, 3, 4
)
SELECT
  source,
  COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(session_id AS STRING))) AS sessions,
  SUM(purchase_count)                                                  AS purchases,
  ROUND(SUM(purchase_count) /
        COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(session_id AS STRING))) * 100, 2) AS cvr_pct
FROM session_summary
GROUP BY source
ORDER BY sessions DESC;
