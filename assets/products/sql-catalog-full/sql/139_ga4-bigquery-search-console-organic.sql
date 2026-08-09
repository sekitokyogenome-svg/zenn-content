-- 139. GA4×BigQueryでSearch Consoleデータを結合してオーガニック分析する（URLの正規化）
-- 用途: URLの正規化
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  REGEXP_EXTRACT(
    'https://example.com/blog/post-1?utm_source=twitter',
    r'^(https?://[^?#]+)'
  ) AS ga4_clean_url,
  REGEXP_EXTRACT(
    'https://example.com/blog/post-1',
    r'^(https?://[^?#]+)'
  ) AS search_console_clean_url
