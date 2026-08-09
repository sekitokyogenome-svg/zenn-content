-- 出典: GA4×BigQueryでSearch Consoleデータを結合してオーガニック分析する
-- 記事: articles/ga4-bigquery-search-console-organic.md（URLの正規化）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- GA4側のURL正規化
REGEXP_EXTRACT(page_location, r'^(https?://[^?#]+)') AS clean_url

-- Search Console側のURL正規化
REGEXP_EXTRACT(url, r'^(https?://[^?#]+)') AS clean_url
