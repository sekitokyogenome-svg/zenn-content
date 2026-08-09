-- 出典: GA4×BigQueryでSearch Consoleデータを結合してオーガニック分析する
-- 記事: articles/ga4-bigquery-search-console-organic.md（URLの正規化）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  REGEXP_EXTRACT(
    'https://example.com/blog/post-1?utm_source=twitter',
    r'^(https?://[^?#]+)'
  ) AS ga4_clean_url,
  REGEXP_EXTRACT(
    'https://example.com/blog/post-1',
    r'^(https?://[^?#]+)'
  ) AS search_console_clean_url
