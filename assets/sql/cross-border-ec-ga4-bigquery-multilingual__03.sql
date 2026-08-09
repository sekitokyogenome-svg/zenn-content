-- 出典: 越境ECのGA4多言語計測をBigQueryで国別に正確に集計する方法
-- 記事: articles/cross-border-ec-ga4-bigquery-multilingual.md（多言語サイトにおける注意点とデータ品質の改善方法）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  geo.country AS country,
  REGEXP_EXTRACT(
    (SELECT ep.value.string_value FROM UNNEST(event_params) AS ep WHERE ep.key = 'page_location'),
    r'https?://[^/]+/([a-z]{2})(?:-[a-z]{2})?/'
  ) AS lang_path,
  device.language AS browser_language,
  COUNT(*) AS event_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250731'
  AND event_name = 'page_view'
GROUP BY
  country,
  lang_path,
  browser_language
ORDER BY
  event_count DESC;
