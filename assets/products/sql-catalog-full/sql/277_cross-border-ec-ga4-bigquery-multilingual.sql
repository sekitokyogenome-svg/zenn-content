-- 277. 越境ECのGA4多言語計測をBigQueryで国別に正確に集計する方法（国別・言語別のセッション数をBigQueryで集計する）
-- 用途: 国別・言語別のセッション数をBigQueryで集計する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH session_base AS (
  SELECT
    user_pseudo_id,
    geo.country AS country,
    device.language AS browser_language,
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250731'
    AND event_name = 'session_start'
)

SELECT
  country,
  browser_language,
  COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING))) AS session_count
FROM
  session_base
GROUP BY
  country,
  browser_language
ORDER BY
  session_count DESC
LIMIT 50;
