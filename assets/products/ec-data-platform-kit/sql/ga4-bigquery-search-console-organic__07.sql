-- GA4×BigQueryでSearch Consoleデータを結合してオーガニック分析する
-- 用途: URLの正規化
-- 必要テーブル: (なし)
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
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
