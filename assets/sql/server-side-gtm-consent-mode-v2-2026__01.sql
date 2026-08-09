-- 出典: サーバーサイドGTM × Consent Mode v2で広告計測精度を維持する【2026年版】
-- 記事: articles/server-side-gtm-consent-mode-v2-2026.md（GA4 × BigQueryで同意率を可視化する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo') AS event_date,
  (
    SELECT value.string_value
    FROM UNNEST(event_params)
    WHERE key = 'analytics_storage'
  ) AS analytics_storage,
  (
    SELECT value.string_value
    FROM UNNEST(event_params)
    WHERE key = 'ad_storage'
  ) AS ad_storage,
  (
    SELECT value.string_value
    FROM UNNEST(event_params)
    WHERE key = 'ad_user_data'
  ) AS ad_user_data,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(*) AS event_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE('Asia/Tokyo'))
  AND event_name = 'consent_update'
GROUP BY
  1, 2, 3, 4, 5, 6
ORDER BY
  event_date DESC
